from __future__ import annotations

# Fallback generator when the official ISO-NE historical interchange workbook
# is unavailable. For the current preferred workflow, use
# generate_isone_nodal_ni_from_workbook.jl.

import csv
from pathlib import Path


TIME_COLS = {"Time Period", "Month", "Day", "Hours", "Period", "Hour"}

# Summer 2024 signed interface template (MW), built from official ISO-NE summary values:
# - NY North: +544 MW
# - Cross Sound: -315 MW
# - Northport-Norwalk: -44 MW
# - New Brunswick: -14 MW
# - Canadian interfaces total: +890 MW, so Highgate + Phase II = +904 MW
# - Split Highgate / Phase II by transfer capability 225 MW / 2000 MW
INTERFACE_TEMPLATE_MW = {
    "highgate": 904.0 * 225.0 / (225.0 + 2000.0),
    "phase_ii": 904.0 * 2000.0 / (225.0 + 2000.0),
    "new_brunswick": -14.0,
    "ny_north": 544.0,
    "northport_norwalk": -44.0,
    "cross_sound": -315.0,
}

PORTAL_BUS_WEIGHTS = {
    "highgate": {"3": 0.456, "18": 0.284, "181": 0.260},
    "phase_ii": {"120": 0.419, "123": 0.294, "116": 0.287},
    "new_brunswick": {"182": 0.616, "190": 0.218, "58": 0.166},
    "cross_sound": {"118": 0.603, "224": 0.199, "33": 0.198},
    "northport_norwalk": {"107": 0.383, "103": 0.324, "227": 0.293},
    "ny_north": {"98": 0.411, "146": 0.308, "249": 0.280},
}


def read_csv_rows(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    with path.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        rows = list(reader)
        if reader.fieldnames is None:
            raise ValueError(f"Missing header in {path}")
        return reader.fieldnames, rows


def validate_time_alignment(load_rows: list[dict[str, str]], nodal_rows: list[dict[str, str]]) -> None:
    if len(load_rows) != len(nodal_rows):
        raise ValueError("Regional load and nodal load row counts do not match.")
    for idx, (load_row, nodal_row) in enumerate(zip(load_rows, nodal_rows), start=1):
        for col in ("Time Period", "Month", "Day", "Hours"):
            if col in load_row and col in nodal_row and load_row[col] != nodal_row[col]:
                raise ValueError(f"Time mismatch at row {idx} for column {col}.")


def main() -> None:
    repo_root = Path(__file__).resolve().parents[2]
    case_dir = repo_root / "ModelCases" / "ISONE_PCM_250bus_case" / "Data_ISONE_PCM_250bus"
    regional_load_path = case_dir / "load_timeseries_regional.csv"
    nodal_load_path = case_dir / "load_timeseries_nodal.csv"
    output_path = case_dir / "ni_timeseries_nodal.csv"

    _, regional_rows = read_csv_rows(regional_load_path)
    nodal_header, nodal_rows = read_csv_rows(nodal_load_path)
    validate_time_alignment(regional_rows, nodal_rows)

    bus_cols = [col for col in nodal_header if col not in TIME_COLS]
    bus_col_set = set(bus_cols)
    missing_portal_buses = sorted(
        {
            bus
            for weights in PORTAL_BUS_WEIGHTS.values()
            for bus in weights
            if bus not in bus_col_set
        }
    )
    if missing_portal_buses:
        raise ValueError(f"Portal buses missing from nodal load header: {missing_portal_buses}")

    template_total = sum(INTERFACE_TEMPLATE_MW.values())
    if abs(template_total) <= 1.0e-9:
        raise ValueError("Invalid interface template: net total is zero.")

    with output_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=nodal_header)
        writer.writeheader()

        for load_row, nodal_row in zip(regional_rows, nodal_rows):
            system_ni = float(load_row["NI"])
            out_row: dict[str, str] = {col: nodal_row[col] for col in nodal_header if col in TIME_COLS}
            bus_values = {bus: 0.0 for bus in bus_cols}

            for interface, template_value in INTERFACE_TEMPLATE_MW.items():
                interface_ni = system_ni * template_value / template_total
                weight_sum = sum(PORTAL_BUS_WEIGHTS[interface].values())
                for bus, weight in PORTAL_BUS_WEIGHTS[interface].items():
                    bus_values[bus] += interface_ni * weight / weight_sum

            for bus in bus_cols:
                out_row[bus] = f"{bus_values[bus]:.6f}"

            writer.writerow(out_row)

    print(f"Wrote {output_path}")


if __name__ == "__main__":
    main()
