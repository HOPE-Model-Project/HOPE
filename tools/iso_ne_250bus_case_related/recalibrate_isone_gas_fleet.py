from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

import pandas as pd


NGCC_PROXY_PARAMS = {
    "Type": "NGCC",
    "Cost ($/MWh)": 34.0,
    "EF": 0.40,
    "CC": 0.92,
    "AF": 1.0,
    "FOR": 0.06,
    "RM_SPIN": 0.10,
    "RU": 0.50,
    "RD": 0.50,
    "Flag_UC": 1,
    "Min_down_time": 4,
    "Min_up_time": 4,
    "Start_up_cost ($/MW)": 6.0,
    "RM_REG_UP": 0.05,
    "RM_REG_DN": 0.05,
    "RM_NSPIN": 0.075,
}


def apply_gas_fleet_recalibration(case_dir: Path, spec_path: Path) -> dict[str, Any]:
    data_dir = case_dir / "Data_ISONE_PCM_250bus"
    gendata_path = data_dir / "gendata.csv"
    gendata = pd.read_csv(gendata_path)
    spec_df = pd.read_csv(spec_path)

    required_cols = {"PlantName", "TargetType"}
    missing_cols = sorted(required_cols - set(spec_df.columns))
    if missing_cols:
        raise ValueError(f"Gas recalibration spec is missing columns: {missing_cols}")

    updated_rows: list[dict[str, Any]] = []
    for _, spec in spec_df.iterrows():
        plant_name = str(spec["PlantName"]).strip()
        target_type = str(spec["TargetType"]).strip()
        if target_type != "NGCC":
            raise ValueError(f"Unsupported gas recalibration TargetType '{target_type}' for {plant_name}.")

        mask = gendata["PlantName"].astype(str) == plant_name
        if "PlantCode" in spec_df.columns and pd.notna(spec["PlantCode"]):
            mask = mask & (gendata["PlantCode"].astype(int) == int(spec["PlantCode"]))
        if "CurrentType" in spec_df.columns and pd.notna(spec["CurrentType"]):
            mask = mask & (gendata["Type"].astype(str) == str(spec["CurrentType"]).strip())
        if not mask.any():
            raise ValueError(f"Plant '{plant_name}' was not found in gendata.csv.")

        if mask.sum() != 1:
            raise ValueError(f"Plant '{plant_name}' matched {int(mask.sum())} rows; expected exactly one.")

        row_idx = gendata.index[mask][0]
        original_type = str(gendata.at[row_idx, "Type"])
        original_cost = float(gendata.at[row_idx, "Cost ($/MWh)"])

        for col, value in NGCC_PROXY_PARAMS.items():
            gendata.at[row_idx, col] = value

        note = str(spec["SourceTechnologyNote"]).strip() if "SourceTechnologyNote" in spec_df.columns and pd.notna(spec["SourceTechnologyNote"]) else ""
        if note:
            gendata.at[row_idx, "SourceTechnology"] = note

        updated_rows.append(
            {
                "PlantName": plant_name,
                "Zone": str(gendata.at[row_idx, "Zone"]),
                "Bus_id": int(gendata.at[row_idx, "Bus_id"]),
                "Pmax_MW": float(gendata.at[row_idx, "Pmax (MW)"]),
                "OriginalType": original_type,
                "NewType": "NGCC",
                "OriginalCost_per_MWh": original_cost,
                "NewCost_per_MWh": float(gendata.at[row_idx, "Cost ($/MWh)"]),
            }
        )

    gendata.to_csv(gendata_path, index=False)
    return {
        "spec_path": str(spec_path),
        "updated_plants": len(updated_rows),
        "updated_capacity_mw": float(sum(row["Pmax_MW"] for row in updated_rows)),
        "plants": updated_rows,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Apply a gas fleet recalibration preset to the ISO-NE 250-bus case.")
    parser.add_argument("--case-dir", type=Path, default=Path(__file__).resolve().parents[2] / "ModelCases" / "ISONE_PCM_250bus_case")
    parser.add_argument(
        "--spec-path",
        type=Path,
        default=Path(__file__).resolve().parent / "raw_sources" / "gas_fleet_recalibration_v1.csv",
    )
    args = parser.parse_args()

    result = apply_gas_fleet_recalibration(args.case_dir, args.spec_path)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
