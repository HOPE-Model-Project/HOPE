from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd


SHEET_TO_INTERFACE: list[tuple[str, str]] = [
    ("SALBRYNB", "SALBRYNB"),
    ("ROSETON", "ROSETON"),
    ("HQ_P1_P2", "HQ_P1_P2"),
    ("HQHIGATE", "HQHIGATE"),
    ("SHOREHAM", "SHOREHAM"),
    ("NORTHPORT", "NORTHPORT"),
]

DEFAULT_INTERFACE_CLUSTER_SPECS: dict[str, dict[str, Any]] = {
    "SALBRYNB": {"anchor_buses": ["182", "190", "58"], "states": [], "loadzones": [], "max_buses": None, "lat_min": None, "lat_max": None, "lon_min": None, "lon_max": None},
    "ROSETON": {"anchor_buses": ["98", "146", "249"], "states": [], "loadzones": [], "max_buses": None, "lat_min": None, "lat_max": None, "lon_min": None, "lon_max": None},
    "HQ_P1_P2": {"anchor_buses": ["120", "123", "116"], "states": [], "loadzones": [], "max_buses": None, "lat_min": None, "lat_max": None, "lon_min": None, "lon_max": None},
    "HQHIGATE": {"anchor_buses": ["3", "18", "181"], "states": [], "loadzones": [], "max_buses": None, "lat_min": None, "lat_max": None, "lon_min": None, "lon_max": None},
    "SHOREHAM": {"anchor_buses": ["118", "224", "33"], "states": [], "loadzones": [], "max_buses": None, "lat_min": None, "lat_max": None, "lon_min": None, "lon_max": None},
    "NORTHPORT": {"anchor_buses": ["107", "103", "227"], "states": [], "loadzones": [], "max_buses": None, "lat_min": None, "lat_max": None, "lon_min": None, "lon_max": None},
}

TIME_COLS = ["Time Period", "Month", "Day", "Hours"]
DEFAULT_LOCALIZED_NI_SHARE = 0.70
DEFAULT_DEMAND_POWER = 0.5
DEFAULT_DISTANCE_POWER = 0.75
DEFAULT_DISTANCE_FLOOR_MILES = 5.0


def _normalize_bus_label(value: Any) -> str:
    if pd.isna(value):
        raise ValueError("Encountered missing bus identifier while building nodal NI.")
    try:
        return str(int(value))
    except Exception:
        return str(value).strip()


def _bus_distance_miles(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    dy = 69.0 * (float(lat1) - float(lat2))
    dx = 53.0 * (float(lon1) - float(lon2))
    return float(np.hypot(dx, dy))


def _bus_allowed(row: pd.Series, spec: dict[str, Any]) -> bool:
    state_ok = not spec["states"] or str(row["State"]) in spec["states"]
    zone_ok = not spec["loadzones"] or str(row["LoadZone"]) in spec["loadzones"]
    lat = float(row["Latitude"])
    lon = float(row["Longitude"])
    lat_min_ok = spec["lat_min"] is None or lat >= float(spec["lat_min"])
    lat_max_ok = spec["lat_max"] is None or lat <= float(spec["lat_max"])
    lon_min_ok = spec["lon_min"] is None or lon >= float(spec["lon_min"])
    lon_max_ok = spec["lon_max"] is None or lon <= float(spec["lon_max"])
    return state_ok and zone_ok and lat_min_ok and lat_max_ok and lon_min_ok and lon_max_ok


def _apply_optional_osm_interface_windows(raw_dir: Path, interface_cluster_specs: dict[str, dict[str, Any]]) -> dict[str, dict[str, Any]]:
    summary_path = raw_dir.parent / "references" / "osm_interface_portal_summary.csv"
    if not summary_path.exists():
        return interface_cluster_specs
    summary_df = pd.read_csv(summary_path)
    if summary_df.empty or "Interface" not in summary_df.columns:
        return interface_cluster_specs

    adjusted = {name: dict(spec) for name, spec in interface_cluster_specs.items()}
    for row in summary_df.itertuples(index=False):
        interface = str(row.Interface)
        if interface not in adjusted:
            continue
        spec = adjusted[interface]
        for key, attr in (
            ("lat_min", "LatMin"),
            ("lat_max", "LatMax"),
            ("lon_min", "LonMin"),
            ("lon_max", "LonMax"),
        ):
            if spec.get(key) is None:
                spec[key] = float(getattr(row, attr))
    return adjusted


def july_sheet(path: Path, sheet: str, *, year: int = 2024, month: int = 7) -> pd.DataFrame:
    df = pd.read_excel(path, sheet_name=sheet)
    dates = pd.to_datetime(df["Date"])
    mask = (dates.dt.year == year) & (dates.dt.month == month)
    out = df.loc[mask].copy()
    out["Date"] = dates.loc[mask]
    out["Hr_End"] = out["Hr_End"].astype(int)
    return out.reset_index(drop=True)


def build_interface_df(workbook_path: Path, regional_load_path: Path) -> pd.DataFrame:
    reg = pd.read_csv(regional_load_path)
    interface_df = reg[TIME_COLS].copy()

    ca = july_sheet(workbook_path, "ISO NE CA")
    if len(ca) != len(reg):
        raise ValueError(f"ISO NE CA July row count {len(ca)} does not match regional load row count {len(reg)}.")

    for sheet_name, column_name in SHEET_TO_INTERFACE:
        df = july_sheet(workbook_path, sheet_name)
        if len(df) != len(reg):
            raise ValueError(f"Sheet {sheet_name} July row count {len(df)} does not match regional load row count {len(reg)}.")
        interface_df[column_name] = df["NetInt_MWh"].astype(float).to_numpy()

    interface_df["ISO_NE_CA_NetInt_MWh"] = ca["NetInt_MWh"].astype(float).to_numpy()
    interface_df["InterfaceSum_NetInt_MWh"] = interface_df[[col for _, col in SHEET_TO_INTERFACE]].sum(axis=1)
    return interface_df


def build_cluster_weights(
    busdata_path: Path,
    interface_cluster_specs: dict[str, dict[str, Any]],
    *,
    demand_power: float,
    distance_power: float,
    distance_floor_miles: float,
) -> tuple[dict[str, dict[str, float]], pd.DataFrame]:
    bus_df = pd.read_csv(busdata_path).rename(columns={"Demand (MW)": "Demand_MW"}).copy()
    bus_df["Bus_id"] = bus_df["Bus_id"].map(_normalize_bus_label)
    bus_df["Latitude"] = bus_df["Latitude"].astype(float)
    bus_df["Longitude"] = bus_df["Longitude"].astype(float)
    bus_df["Demand_MW"] = bus_df["Demand_MW"].astype(float)

    cluster_weights: dict[str, dict[str, float]] = {}
    summary_rows: list[dict[str, Any]] = []

    for interface_name, spec in interface_cluster_specs.items():
        anchor_buses = {_normalize_bus_label(bus) for bus in spec["anchor_buses"]}
        anchor_df = bus_df.loc[bus_df["Bus_id"].isin(anchor_buses)].copy()
        if anchor_df.empty:
            raise ValueError(f"No anchor buses found for {interface_name}.")
        centroid_lat = float(anchor_df["Latitude"].mean())
        centroid_lon = float(anchor_df["Longitude"].mean())

        candidate_df = bus_df.loc[bus_df.apply(lambda row: _bus_allowed(row, spec), axis=1)].copy()
        if candidate_df.empty and any(spec.get(key) is not None for key in ("lat_min", "lat_max", "lon_min", "lon_max")):
            relaxed_spec = dict(spec)
            relaxed_spec["lat_min"] = None
            relaxed_spec["lat_max"] = None
            relaxed_spec["lon_min"] = None
            relaxed_spec["lon_max"] = None
            candidate_df = bus_df.loc[bus_df.apply(lambda row: _bus_allowed(row, relaxed_spec), axis=1)].copy()
        if candidate_df.empty:
            raise ValueError(f"No candidate buses found for {interface_name}.")
        candidate_df["DistanceMiles"] = candidate_df.apply(
            lambda row: _bus_distance_miles(row["Latitude"], row["Longitude"], centroid_lat, centroid_lon),
            axis=1,
        )
        candidate_df.sort_values("DistanceMiles", inplace=True)
        max_buses = spec["max_buses"]
        if max_buses is not None:
            candidate_df = candidate_df.head(int(max_buses)).copy()

        candidate_df["RawWeight"] = candidate_df.apply(
            lambda row: (max(float(row["Demand_MW"]), 1.0) ** demand_power)
            / (max(float(row["DistanceMiles"]), distance_floor_miles) ** distance_power),
            axis=1,
        )
        weight_sum = float(candidate_df["RawWeight"].sum())
        if weight_sum <= 0.0:
            raise ValueError(f"Cluster weight sum is non-positive for {interface_name}.")
        candidate_df["Weight"] = candidate_df["RawWeight"] / weight_sum
        cluster_weights[interface_name] = dict(zip(candidate_df["Bus_id"], candidate_df["Weight"]))

        for _, row in candidate_df.iterrows():
            summary_rows.append(
                {
                    "Interface": interface_name,
                    "Bus_id": row["Bus_id"],
                    "State": row["State"],
                    "LoadZone": row["LoadZone"],
                    "Latitude": float(row["Latitude"]),
                    "Longitude": float(row["Longitude"]),
                    "Demand_MW": float(row["Demand_MW"]),
                    "DistanceMiles": float(row["DistanceMiles"]),
                    "Weight": float(row["Weight"]),
                    "IsAnchor": row["Bus_id"] in anchor_buses,
                    "CentroidLatitude": centroid_lat,
                    "CentroidLongitude": centroid_lon,
                }
            )

    return cluster_weights, pd.DataFrame(summary_rows)


def calibrate_interface_df(interface_df: pd.DataFrame, target_system_ni: pd.Series) -> pd.DataFrame:
    if len(target_system_ni) != len(interface_df):
        raise ValueError("Target system NI length does not match interface data rows.")

    calibrated_df = interface_df[TIME_COLS].copy()
    calibrated_df["OfficialSystemNI"] = interface_df["ISO_NE_CA_NetInt_MWh"].astype(float)
    calibrated_df["TargetSystemNI"] = target_system_ni.astype(float).to_numpy()
    calibrated_df["PositiveImportScale"] = 0.0

    interface_cols = [col for _, col in SHEET_TO_INTERFACE]
    for col in interface_cols:
        calibrated_df[col] = 0.0

    for idx in range(len(interface_df)):
        official_values = {col: float(interface_df.at[idx, col]) for col in interface_cols}
        positive_total = sum(max(v, 0.0) for v in official_values.values())
        negative_total = sum(min(v, 0.0) for v in official_values.values())
        if positive_total <= 0.0:
            raise ValueError(f"Official interchange has no positive imports at row {idx + 1}; cannot calibrate to target NI.")
        required_positive_total = float(target_system_ni.iloc[idx]) - negative_total
        if required_positive_total < 0.0:
            raise ValueError(
                f"Target NI {float(target_system_ni.iloc[idx])} is inconsistent with retained exports {negative_total} at row {idx + 1}."
            )
        scale = required_positive_total / positive_total
        calibrated_df.at[idx, "PositiveImportScale"] = scale
        for col in interface_cols:
            value = official_values[col]
            calibrated_df.at[idx, col] = value * scale if value > 0.0 else value

    calibrated_df["CalibratedSystemNI"] = calibrated_df[interface_cols].sum(axis=1)
    return calibrated_df


def build_nodal_ni(
    interface_df: pd.DataFrame,
    nodal_load_path: Path,
    cluster_weights: dict[str, dict[str, float]],
    *,
    localized_ni_share: float,
) -> pd.DataFrame:
    nodal_load = pd.read_csv(nodal_load_path)
    if len(nodal_load) != len(interface_df):
        raise ValueError("Nodal load row count does not match interface row count.")

    nodal_df = nodal_load[TIME_COLS].copy()
    bus_cols = [col for col in nodal_load.columns if col not in TIME_COLS]
    for bus in bus_cols:
        nodal_df[bus] = 0.0

    missing_buses = sorted({bus for weights in cluster_weights.values() for bus in weights if bus not in bus_cols})
    if missing_buses:
        raise ValueError(f"Cluster buses missing from nodal load columns: {missing_buses}")

    for interface_name, weights in cluster_weights.items():
        for bus, weight in weights.items():
            nodal_df[bus] += interface_df[interface_name].astype(float) * float(weight)

    if localized_ni_share < 1.0:
        target_col = "TargetSystemNI" if "TargetSystemNI" in interface_df.columns else "CalibratedSystemNI"
        load_values = nodal_load[bus_cols].astype(float).to_numpy()
        load_row_sums = load_values.sum(axis=1, keepdims=True)
        load_weights = np.divide(
            load_values,
            load_row_sums,
            out=np.full_like(load_values, 1.0 / len(bus_cols)),
            where=load_row_sums > 0.0,
        )
        localized_values = nodal_df[bus_cols].astype(float).to_numpy()
        background_values = interface_df[target_col].astype(float).to_numpy()[:, None] * load_weights
        nodal_df[bus_cols] = localized_ni_share * localized_values + (1.0 - localized_ni_share) * background_values

    return nodal_df


def generate_nodal_ni_case_data(
    case_dir: Path,
    raw_dir: Path,
    *,
    localized_ni_share: float = DEFAULT_LOCALIZED_NI_SHARE,
    demand_power: float = DEFAULT_DEMAND_POWER,
    distance_power: float = DEFAULT_DISTANCE_POWER,
    distance_floor_miles: float = DEFAULT_DISTANCE_FLOOR_MILES,
    interface_cluster_specs: dict[str, dict[str, Any]] | None = None,
    target_system_ni: pd.Series | np.ndarray | None = None,
    overwrite_regional_ni: bool = False,
) -> dict[str, Any]:
    data_dir = case_dir / "Data_ISONE_PCM_250bus"
    workbook_path = raw_dir / "smd_interchange_2024.xlsx"
    regional_load_path = data_dir / "load_timeseries_regional.csv"
    nodal_load_path = data_dir / "load_timeseries_nodal.csv"
    busdata_path = data_dir / "busdata.csv"
    official_interface_csv_path = raw_dir / "smd_interchange_2024_07.csv"
    calibrated_interface_csv_path = raw_dir / "smd_interchange_2024_07_calibrated_to_case_ni.csv"
    cluster_csv_path = raw_dir / "ni_interface_bus_clusters.csv"
    config_json_path = raw_dir / "ni_interface_generation_config.json"
    nodal_ni_path = data_dir / "ni_timeseries_nodal.csv"

    if interface_cluster_specs is None:
        interface_cluster_specs = DEFAULT_INTERFACE_CLUSTER_SPECS
    interface_cluster_specs = _apply_optional_osm_interface_windows(raw_dir, interface_cluster_specs)

    regional_df = pd.read_csv(regional_load_path)
    interface_df = build_interface_df(workbook_path, regional_load_path)
    cluster_weights, cluster_summary_df = build_cluster_weights(
        busdata_path,
        interface_cluster_specs,
        demand_power=demand_power,
        distance_power=distance_power,
        distance_floor_miles=distance_floor_miles,
    )
    if target_system_ni is None:
        target_system_ni_series = regional_df["NI"].astype(float)
    else:
        target_system_ni_series = pd.Series(np.asarray(target_system_ni, dtype=float))
        if len(target_system_ni_series) != len(regional_df):
            raise ValueError(
                f"Target system NI length {len(target_system_ni_series)} does not match regional load row count {len(regional_df)}."
            )

    calibrated_interface_df = calibrate_interface_df(interface_df, target_system_ni_series)
    nodal_df = build_nodal_ni(
        calibrated_interface_df,
        nodal_load_path,
        cluster_weights,
        localized_ni_share=localized_ni_share,
    )

    official_interface_csv_path.parent.mkdir(parents=True, exist_ok=True)
    interface_df.to_csv(official_interface_csv_path, index=False)
    calibrated_interface_df.to_csv(calibrated_interface_csv_path, index=False)
    cluster_summary_df.to_csv(cluster_csv_path, index=False)
    nodal_df.to_csv(nodal_ni_path, index=False)

    if overwrite_regional_ni:
        regional_df = regional_df.copy()
        regional_df["NI"] = target_system_ni_series.astype(float).to_numpy()
        regional_df.to_csv(regional_load_path, index=False)

    nodal_sum = nodal_df[[col for col in nodal_df.columns if col not in TIME_COLS]].sum(axis=1)
    config_payload = {
        "localized_ni_share": localized_ni_share,
        "demand_power": demand_power,
        "distance_power": distance_power,
        "distance_floor_miles": distance_floor_miles,
        "overwrite_regional_ni": overwrite_regional_ni,
        "interface_cluster_specs": interface_cluster_specs,
        "target_system_ni_source": "regional_load.NI" if target_system_ni is None else "explicit_target_system_ni",
        "max_official_gap_mw": float(np.max(np.abs(interface_df["ISO_NE_CA_NetInt_MWh"] - interface_df["InterfaceSum_NetInt_MWh"]))),
        "max_target_gap_mw": float(np.max(np.abs(calibrated_interface_df["TargetSystemNI"] - calibrated_interface_df["CalibratedSystemNI"]))),
        "max_nodal_gap_mw": float(np.max(np.abs(target_system_ni_series.astype(float).to_numpy() - nodal_sum))),
    }
    config_json_path.write_text(json.dumps(config_payload, indent=2), encoding="utf-8")
    return config_payload


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate nodal NI inputs for the ISO-NE 250-bus HOPE case.")
    parser.add_argument("--case-dir", type=Path, default=Path(__file__).resolve().parents[2] / "ModelCases" / "ISONE_PCM_250bus_case")
    parser.add_argument("--raw-dir", type=Path, default=Path(__file__).resolve().parent / "raw_sources")
    parser.add_argument("--localized-ni-share", type=float, default=DEFAULT_LOCALIZED_NI_SHARE)
    parser.add_argument("--demand-power", type=float, default=DEFAULT_DEMAND_POWER)
    parser.add_argument("--distance-power", type=float, default=DEFAULT_DISTANCE_POWER)
    parser.add_argument("--distance-floor-miles", type=float, default=DEFAULT_DISTANCE_FLOOR_MILES)
    parser.add_argument("--overwrite-regional-ni", action="store_true")
    args = parser.parse_args()

    result = generate_nodal_ni_case_data(
        args.case_dir,
        args.raw_dir,
        localized_ni_share=args.localized_ni_share,
        demand_power=args.demand_power,
        distance_power=args.distance_power,
        distance_floor_miles=args.distance_floor_miles,
        overwrite_regional_ni=args.overwrite_regional_ni,
    )
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
