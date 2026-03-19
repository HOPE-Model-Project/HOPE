from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd


TARGET_REWIRE_KEYS = {
    (24, 177): "NNE",
    (27, 202): "NNE",
    (141, 196): "NNE",
    (166, 245): "NNE",
    (174, 250): "NNE",
    (193, 200): "NNE",
    (177, 249): "NNE",
    (26, 202): "NNE",
    (243, 245): "NNE",
}


def _miles(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    return float(np.hypot((lat1 - lat2) * 69.0, (lon1 - lon2) * 53.0))


def build_long_branch_audit(bus_df: pd.DataFrame, branch_df: pd.DataFrame) -> pd.DataFrame:
    bus = bus_df.set_index("Bus_id")
    rows: list[dict[str, object]] = []
    for _, row in branch_df.iterrows():
        from_bus = int(row["from_bus"])
        to_bus = int(row["to_bus"])
        a = bus.loc[from_bus]
        b = bus.loc[to_bus]
        miles = _miles(float(a.Latitude), float(a.Longitude), float(b.Latitude), float(b.Longitude))
        seam = "-".join(sorted((str(row["From_zone"]), str(row["To_zone"]))))
        key = tuple(sorted((from_bus, to_bus)))
        rows.append(
            {
                "from_bus": from_bus,
                "to_bus": to_bus,
                "From_zone": str(row["From_zone"]),
                "To_zone": str(row["To_zone"]),
                "Capacity (MW)": float(row["Capacity (MW)"]),
                "X": float(row["X"]),
                "Miles": miles,
                "Seam": seam,
                "FlagTargetRewire": key in TARGET_REWIRE_KEYS,
                "FromLoadZone": str(a.LoadZone),
                "ToLoadZone": str(b.LoadZone),
            }
        )
    audit = pd.DataFrame(rows).sort_values("Miles", ascending=False).reset_index(drop=True)
    return audit


def choose_bridge_bus(
    bus_df: pd.DataFrame,
    from_bus: int,
    to_bus: int,
    *,
    target_zone: str,
) -> int:
    bus = bus_df.set_index("Bus_id")
    a = bus.loc[int(from_bus)]
    c = bus.loc[int(to_bus)]
    candidates = bus_df.loc[bus_df["Zone_id"] == str(target_zone)].copy()
    if candidates.empty:
        raise ValueError(f"No candidate buses found in target zone {target_zone}.")
    candidates["Score"] = candidates.apply(
        lambda row: _miles(float(a.Latitude), float(a.Longitude), float(row.Latitude), float(row.Longitude))
        + _miles(float(c.Latitude), float(c.Longitude), float(row.Latitude), float(row.Longitude))
        - 0.01 * float(row["Demand (MW)"]),
        axis=1,
    )
    return int(candidates.sort_values(["Score", "Bus_id"]).iloc[0]["Bus_id"])


def apply_topology_rewires(
    bus_df: pd.DataFrame,
    branch_df: pd.DataFrame,
) -> tuple[pd.DataFrame, pd.DataFrame]:
    bus_lookup = bus_df.set_index("Bus_id")
    branch = branch_df.copy()
    rewired_rows: list[dict[str, object]] = []
    kept_rows: list[dict[str, object]] = []

    for _, row in branch.iterrows():
        from_bus = int(row["from_bus"])
        to_bus = int(row["to_bus"])
        key = tuple(sorted((from_bus, to_bus)))
        if key not in TARGET_REWIRE_KEYS:
            kept_rows.append(row.to_dict())
            continue

        target_zone = TARGET_REWIRE_KEYS[key]
        bridge_bus = choose_bridge_bus(bus_df, from_bus, to_bus, target_zone=target_zone)
        a = bus_lookup.loc[from_bus]
        b = bus_lookup.loc[bridge_bus]
        c = bus_lookup.loc[to_bus]
        dab = _miles(float(a.Latitude), float(a.Longitude), float(b.Latitude), float(b.Longitude))
        dbc = _miles(float(b.Latitude), float(b.Longitude), float(c.Latitude), float(c.Longitude))
        total = max(dab + dbc, 1.0)
        x_total = float(row["X"])
        cap = float(row["Capacity (MW)"])

        row_ab = row.to_dict()
        row_ab["to_bus"] = bridge_bus
        row_ab["To_zone"] = str(b.Zone_id)
        row_ab["X"] = max(1e-4, x_total * dab / total)
        kept_rows.append(row_ab)

        row_bc = row.to_dict()
        row_bc["from_bus"] = bridge_bus
        row_bc["From_zone"] = str(b.Zone_id)
        row_bc["X"] = max(1e-4, x_total * dbc / total)
        kept_rows.append(row_bc)

        rewired_rows.append(
            {
                "OriginalFromBus": from_bus,
                "OriginalToBus": to_bus,
                "OriginalFromZone": str(row["From_zone"]),
                "OriginalToZone": str(row["To_zone"]),
                "BridgeBus": bridge_bus,
                "BridgeZone": str(b.Zone_id),
                "Capacity (MW)": cap,
                "OriginalX": x_total,
                "LegAB_X": row_ab["X"],
                "LegBC_X": row_bc["X"],
                "OriginalMiles": _miles(float(a.Latitude), float(a.Longitude), float(c.Latitude), float(c.Longitude)),
                "LegAB_Miles": dab,
                "LegBC_Miles": dbc,
            }
        )

    return pd.DataFrame(kept_rows), pd.DataFrame(rewired_rows)
