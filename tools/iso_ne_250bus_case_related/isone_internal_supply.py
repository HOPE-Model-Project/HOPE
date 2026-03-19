from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

import pandas as pd


CALIBRATION_PREFIX = "Calibration "
TIME_COLS = ["Time Period", "Month", "Day", "Hours"]


def _load_case_tables(case_dir: Path) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    data_dir = case_dir / "Data_ISONE_PCM_250bus"
    gendata = pd.read_csv(data_dir / "gendata.csv")
    availability = pd.read_csv(data_dir / "gen_availability_timeseries.csv")
    busdata = pd.read_csv(data_dir / "busdata.csv")
    return gendata, availability, busdata


def _remove_existing_calibration_units(
    gendata: pd.DataFrame,
    availability: pd.DataFrame,
) -> tuple[pd.DataFrame, pd.DataFrame, int]:
    keep_mask = ~gendata["PlantName"].astype(str).str.startswith(CALIBRATION_PREFIX)
    removed = int((~keep_mask).sum())
    if removed == 0:
        return gendata.copy(), availability.copy(), 0

    kept_gendata = gendata.loc[keep_mask].reset_index(drop=True)
    kept_columns = TIME_COLS + [f"G{i + 1}" for i, keep in enumerate(keep_mask) if keep]
    kept_availability = availability.loc[:, kept_columns].copy()
    rename_map = {old: f"G{i + 1}" for i, old in enumerate(col for col in kept_availability.columns if col not in TIME_COLS)}
    kept_availability.rename(columns=rename_map, inplace=True)
    return kept_gendata, kept_availability, removed


def apply_internal_supply_adders(
    case_dir: Path,
    spec_path: Path,
    *,
    replace_existing: bool = True,
) -> dict[str, Any]:
    gendata, availability, busdata = _load_case_tables(case_dir)
    if replace_existing:
        gendata, availability, removed_count = _remove_existing_calibration_units(gendata, availability)
    else:
        removed_count = 0

    spec_df = pd.read_csv(spec_path)
    required_cols = {"PlantCode", "PlantName", "DonorPlantName", "Bus_id", "Pmax_MW"}
    missing_cols = sorted(required_cols - set(spec_df.columns))
    if missing_cols:
        raise ValueError(f"Supply calibration spec is missing columns: {missing_cols}")

    donor_map = {str(name): idx for idx, name in enumerate(gendata["PlantName"].astype(str))}
    bus_map = {int(row["Bus_id"]): row for _, row in busdata.iterrows()}

    appended_rows: list[pd.Series] = []
    appended_availability: dict[str, pd.Series] = {}
    next_col_idx = len(gendata) + 1
    summary_rows: list[dict[str, Any]] = []

    for _, spec in spec_df.iterrows():
        plant_name = str(spec["PlantName"]).strip()
        if not plant_name.startswith(CALIBRATION_PREFIX):
            raise ValueError(f"Calibration plant name must start with '{CALIBRATION_PREFIX}': {plant_name}")
        donor_name = str(spec["DonorPlantName"]).strip()
        if donor_name not in donor_map:
            raise ValueError(f"Donor plant '{donor_name}' was not found in gendata.csv.")
        bus_id = int(spec["Bus_id"])
        if bus_id not in bus_map:
            raise ValueError(f"Bus {bus_id} from supply calibration spec was not found in busdata.csv.")

        donor_idx = donor_map[donor_name]
        donor_row = gendata.iloc[donor_idx].copy()
        bus_row = bus_map[bus_id]
        new_row = donor_row.copy()
        new_row["PlantCode"] = int(spec["PlantCode"])
        new_row["PlantName"] = plant_name
        new_row["SourceTechnology"] = f"{donor_row['SourceTechnology']} Calibration"
        new_row["State"] = bus_row["State"]
        new_row["LoadZone"] = bus_row["LoadZone"]
        new_row["Latitude"] = float(bus_row["Latitude"])
        new_row["Longitude"] = float(bus_row["Longitude"])
        new_row["Zone"] = bus_row["Zone_id"]
        new_row["Bus_id"] = bus_id
        new_row["Pmax (MW)"] = float(spec["Pmax_MW"])

        if "Pmin_MW" in spec_df.columns and pd.notna(spec["Pmin_MW"]):
            new_row["Pmin (MW)"] = float(spec["Pmin_MW"])
        elif float(donor_row["Pmax (MW)"]) > 0.0:
            new_row["Pmin (MW)"] = float(donor_row["Pmin (MW)"]) * float(spec["Pmax_MW"]) / float(donor_row["Pmax (MW)"])
        else:
            new_row["Pmin (MW)"] = 0.0

        if "Cost_per_MWh" in spec_df.columns and pd.notna(spec["Cost_per_MWh"]):
            new_row["Cost ($/MWh)"] = float(spec["Cost_per_MWh"])

        appended_rows.append(new_row)
        new_col = f"G{next_col_idx}"
        availability_profile = str(spec.get("AvailabilityProfile", "donor")).strip().lower()
        if availability_profile == "constant":
            availability_value = float(spec.get("AvailabilityValue", 1.0))
            appended_availability[new_col] = pd.Series(availability_value, index=availability.index, dtype=float)
        else:
            donor_col = f"G{donor_idx + 1}"
            appended_availability[new_col] = availability[donor_col].copy()
        next_col_idx += 1

        summary_rows.append(
            {
                "PlantName": plant_name,
                "Zone": new_row["Zone"],
                "LoadZone": new_row["LoadZone"],
                "Bus_id": bus_id,
                "Pmax_MW": float(new_row["Pmax (MW)"]),
                "DonorPlantName": donor_name,
                "AvailabilityProfile": availability_profile,
            }
        )

    if appended_rows:
        gendata = pd.concat([gendata, pd.DataFrame(appended_rows)], ignore_index=True)
        for col_name, col_values in appended_availability.items():
            availability[col_name] = col_values.to_numpy()

    data_dir = case_dir / "Data_ISONE_PCM_250bus"
    gendata.to_csv(data_dir / "gendata.csv", index=False)
    availability.to_csv(data_dir / "gen_availability_timeseries.csv", index=False)

    return {
        "removed_existing_calibration_units": removed_count,
        "added_calibration_units": len(appended_rows),
        "added_capacity_mw": float(sum(row["Pmax_MW"] for row in summary_rows)),
        "spec_path": str(spec_path),
        "units": summary_rows,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Apply internal supply calibration adders to the ISO-NE 250-bus case.")
    parser.add_argument("--case-dir", type=Path, default=Path(__file__).resolve().parents[2] / "ModelCases" / "ISONE_PCM_250bus_case")
    parser.add_argument(
        "--spec-path",
        type=Path,
        default=Path(__file__).resolve().parent / "raw_sources" / "internal_supply_adders_live_case.csv",
    )
    parser.add_argument("--keep-existing", action="store_true", help="Do not remove existing calibration units before appending new ones.")
    args = parser.parse_args()

    result = apply_internal_supply_adders(
        args.case_dir,
        args.spec_path,
        replace_existing=not args.keep_existing,
    )
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
