from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from iso_ne_250bus_case_related.isone_nodal_ni import (
    DEFAULT_DEMAND_POWER,
    DEFAULT_DISTANCE_FLOOR_MILES,
    DEFAULT_DISTANCE_POWER,
    DEFAULT_INTERFACE_CLUSTER_SPECS,
    DEFAULT_LOCALIZED_NI_SHARE,
    TIME_COLS,
    build_cluster_weights,
    build_interface_df,
    build_nodal_ni,
    calibrate_interface_df,
)


def main() -> None:
    parser = argparse.ArgumentParser(description="Prepare flexible nodal NI target/cap files for the ISO-NE 250-bus case.")
    parser.add_argument("--case-dir", type=Path, default=Path("ModelCases") / "ISONE_PCM_250bus_case")
    parser.add_argument("--raw-dir", type=Path, default=Path("tools") / "iso_ne_250bus_case_related" / "raw_sources")
    parser.add_argument("--localized-ni-share", type=float, default=None)
    parser.add_argument("--demand-power", type=float, default=None)
    parser.add_argument("--distance-power", type=float, default=None)
    parser.add_argument("--distance-floor-miles", type=float, default=None)
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[2]
    case_dir = (root / args.case_dir).resolve() if not args.case_dir.is_absolute() else args.case_dir.resolve()
    raw_dir = (root / args.raw_dir).resolve() if not args.raw_dir.is_absolute() else args.raw_dir.resolve()
    data_dir = case_dir / "Data_ISONE_PCM_250bus"

    config_path = raw_dir / "ni_interface_generation_config.json"
    if config_path.exists():
        config = json.loads(config_path.read_text(encoding="utf-8"))
    else:
        config = {}

    localized_ni_share = float(args.localized_ni_share if args.localized_ni_share is not None else config.get("localized_ni_share", DEFAULT_LOCALIZED_NI_SHARE))
    demand_power = float(args.demand_power if args.demand_power is not None else config.get("demand_power", DEFAULT_DEMAND_POWER))
    distance_power = float(args.distance_power if args.distance_power is not None else config.get("distance_power", DEFAULT_DISTANCE_POWER))
    distance_floor_miles = float(args.distance_floor_miles if args.distance_floor_miles is not None else config.get("distance_floor_miles", DEFAULT_DISTANCE_FLOOR_MILES))
    interface_cluster_specs = config.get("interface_cluster_specs", DEFAULT_INTERFACE_CLUSTER_SPECS)

    regional_load_path = data_dir / "load_timeseries_regional.csv"
    nodal_load_path = data_dir / "load_timeseries_nodal.csv"
    busdata_path = data_dir / "busdata.csv"
    workbook_path = raw_dir / "smd_interchange_2024.xlsx"

    regional_df = pd.read_csv(regional_load_path)
    interface_df = build_interface_df(workbook_path, regional_load_path)
    official_target = interface_df["ISO_NE_CA_NetInt_MWh"].astype(float)
    live_cap_target = regional_df["NI"].astype(float)
    cluster_weights, _ = build_cluster_weights(
        busdata_path,
        interface_cluster_specs,
        demand_power=demand_power,
        distance_power=distance_power,
        distance_floor_miles=distance_floor_miles,
    )
    calibrated_interface_df = calibrate_interface_df(interface_df, official_target)
    target_df = build_nodal_ni(
        calibrated_interface_df,
        nodal_load_path,
        cluster_weights,
        localized_ni_share=localized_ni_share,
    )
    cap_interface_df = calibrate_interface_df(interface_df, live_cap_target)
    cap_df = build_nodal_ni(
        cap_interface_df,
        nodal_load_path,
        cluster_weights,
        localized_ni_share=localized_ni_share,
    )

    target_bus_cols = [col for col in target_df.columns if col not in TIME_COLS]
    cap_bus_cols = [col for col in cap_df.columns if col not in TIME_COLS]
    if target_bus_cols != cap_bus_cols:
        raise ValueError("Target/cap nodal NI bus columns do not match.")
    target_values = target_df[target_bus_cols].to_numpy(dtype=float)
    cap_values = cap_df[cap_bus_cols].to_numpy(dtype=float)
    same_sign = (np.sign(target_values) == np.sign(cap_values)) | (np.abs(target_values) <= 1.0e-9) | (np.abs(cap_values) <= 1.0e-9)
    cap_covers_target = same_sign & (np.abs(cap_values) + 1.0e-6 >= np.abs(target_values))
    replaced_cells = int(np.size(cap_values) - int(cap_covers_target.sum()))
    if not np.all(cap_covers_target):
        cap_values = np.where(cap_covers_target, cap_values, target_values)
        cap_df[target_bus_cols] = cap_values

    target_path = data_dir / "ni_timeseries_nodal_target.csv"
    cap_out_path = data_dir / "ni_timeseries_nodal_cap.csv"
    target_df.to_csv(target_path, index=False)
    cap_df.to_csv(cap_out_path, index=False)

    target_sum = target_df[target_bus_cols].sum(axis=1).to_numpy(dtype=float)
    cap_sum = cap_df[cap_bus_cols].sum(axis=1).to_numpy(dtype=float)
    cap_gap = np.abs(target_values) - np.abs(cap_values)
    if np.any(cap_gap > 1.0e-6):
        raise ValueError("Some nodal NI targets exceed the existing case NI cap in absolute value.")

    summary = {
        "target_path": str(target_path),
        "cap_path": str(cap_out_path),
        "avg_target_ni_mw": float(target_sum.mean()),
        "avg_cap_ni_mw": float(cap_sum.mean()),
        "max_target_cap_abs_gap_mw": float(np.max(np.abs(np.abs(target_values) - np.abs(cap_values)))),
        "cap_cells_replaced_with_target": replaced_cells,
        "localized_ni_share": localized_ni_share,
        "demand_power": demand_power,
        "distance_power": distance_power,
        "distance_floor_miles": distance_floor_miles,
    }
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
