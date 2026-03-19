from __future__ import annotations

import argparse
import csv
import json
import re
import struct
import zlib
from pathlib import Path

import numpy as np
import pandas as pd


TIME_COLS = ["Time Period", "Month", "Day", "Hours"]
LOAD_ZONE_REPORT_ID = {
    "ME": 4001,
    "NH": 4002,
    "VT": 4003,
    "CT": 4004,
    "RI": 4005,
    "NEMA/Boston": 4006,
    "SEMA": 4007,
    "WCMA": 4008,
}
SYNTHETIC_ZONE_TO_LOAD_ZONES = {
    "Maine": ["ME"],
    "NNE": ["NH", "VT"],
    "ROP": ["CT", "WCMA"],
    "SENE": ["RI", "SEMA", "NEMA/Boston"],
}
EBA_ISONE_GEN_SERIES = {
    "Coal": "EBA.ISNE-ALL.NG.COL.H",
    "Natural Gas": "EBA.ISNE-ALL.NG.NG.H",
    "Nuclear": "EBA.ISNE-ALL.NG.NUC.H",
    "Oil": "EBA.ISNE-ALL.NG.OIL.H",
    "Other": "EBA.ISNE-ALL.NG.OTH.H",
    "Solar": "EBA.ISNE-ALL.NG.SUN.H",
    "Hydro": "EBA.ISNE-ALL.NG.WAT.H",
    "Wind": "EBA.ISNE-ALL.NG.WND.H",
}


def parse_eba_timestamp(ts_raw: str) -> pd.Timestamp:
    if re.fullmatch(r"\d{8}T\d{2}", ts_raw):
        return pd.to_datetime(ts_raw, format="%Y%m%dT%H", utc=True).tz_convert("America/New_York").tz_localize(None)
    if re.fullmatch(r"\d{8}T\d{2}[+-]\d{2}", ts_raw):
        signed = f"{ts_raw}00"
        return pd.to_datetime(signed, format="%Y%m%dT%H%z", utc=True).tz_convert("America/New_York").tz_localize(None)
    raise ValueError(f"Unsupported EBA timestamp format: {ts_raw}")


def read_eba_series_map(zip_path: Path, series_ids: list[str]) -> dict[str, pd.Series]:
    raw = zip_path.read_bytes()
    if len(raw) < 30 or raw[:4] != b"PK\x03\x04":
        raise ValueError(f"{zip_path} is not a supported EBA zip payload.")

    _, _, method, _, _, _, _, _, fname_len, extra_len = struct.unpack("<HHHHHIIIHH", raw[4:30])
    if method != 8:
        raise ValueError(f"Unsupported EBA compression method {method}.")
    start = 30 + fname_len + extra_len
    decompressed = zlib.decompressobj(-15).decompress(raw[start:])

    series_map: dict[str, pd.Series] = {}
    for series_id in series_ids:
        pattern = re.compile(rb'\{"series_id":"' + re.escape(series_id.encode("utf-8")) + rb'".*?"data":\[(.*?)\]\}', re.S)
        match = pattern.search(decompressed)
        if match is None:
            continue
        payload = json.loads(b"[" + match.group(1) + b"]")
        rows = []
        for ts_raw, val_raw in payload:
            try:
                rows.append((parse_eba_timestamp(str(ts_raw)), float(val_raw)))
            except (TypeError, ValueError):
                continue
        if rows:
            series_map[series_id] = pd.Series({ts: val for ts, val in rows}).sort_index()
    return series_map


def july_2024(series: pd.Series) -> np.ndarray:
    start = pd.Timestamp("2024-07-01 00:00:00")
    end = pd.Timestamp("2024-07-31 23:00:00")
    window = series[(series.index >= start) & (series.index <= end)]
    if len(window) != 744:
        raise ValueError(f"Expected 744 July 2024 hours, found {len(window)}.")
    return window.to_numpy(dtype=float)


def model_major_fuel(technology: str) -> str:
    tech = str(technology)
    if tech in {"NGCC", "NGCT", "NGST", "NGIC"}:
        return "Natural Gas"
    if tech == "NuC":
        return "Nuclear"
    if tech == "Oil":
        return "Oil"
    if tech == "Coal":
        return "Coal"
    if tech == "SolarPV":
        return "Solar"
    if tech in {"WindOn", "WindOff"}:
        return "Wind"
    if tech in {"Hydro", "PHS"}:
        return "Hydro"
    return "Other"


def case_capacity_group(source_technology: str) -> str:
    st = str(source_technology)
    if "Natural Gas" in st:
        return "Natural Gas"
    if st == "Nuclear":
        return "Nuclear"
    if st == "Petroleum Liquids":
        return "Oil"
    if st == "Conventional Steam Coal":
        return "Coal"
    if st == "Conventional Hydroelectric":
        return "Hydro"
    if st in {"Wood/Wood Waste Biomass", "Other Waste Biomass", "Municipal Solid Waste", "Landfill Gas"}:
        return "Other"
    if st in {"Onshore Wind Turbine", "Offshore Wind Turbine"}:
        return "Wind"
    if st == "Solar Photovoltaic":
        return "Solar"
    return "Other"


def iso_capacity_group(fuel: str) -> str:
    mapping = {
        "NG": "Natural Gas",
        "NUC": "Nuclear",
        "DFO": "Oil",
        "KER": "Oil",
        "RFO": "Oil",
        "JF": "Oil",
        "BIT": "Coal",
        "WAT": "Hydro",
        "WDS": "Other",
        "MSW": "Other",
        "LFG": "Other",
        "WND": "Wind",
        "SUN": "Solar",
    }
    return mapping.get(str(fuel), "Other")


def read_hourly_load_csv(path: Path) -> pd.DataFrame:
    rows: list[dict[str, object]] = []
    with path.open("r", encoding="utf-8", errors="ignore") as f:
        for raw_line in f:
            line = raw_line.strip()
            if not line or not line.startswith('"D",'):
                continue
            parts = next(csv.reader([line]))
            if len(parts) < 4:
                continue
            ts = pd.to_datetime(parts[1], format="%m/%d/%Y") + pd.Timedelta(hours=int(parts[2]) - 1)
            rows.append({"timestamp": ts, "total_load_mwh": float(parts[3])})
    if len(rows) != 744:
        raise ValueError(f"Expected 744 July load rows in {path}, found {len(rows)}.")
    return pd.DataFrame(rows)


def hourly_columns(df: pd.DataFrame) -> list[str]:
    return [col for col in df.columns if str(col).startswith("h")]


def compare_capacity(case_data_dir: Path, raw_dir: Path) -> pd.DataFrame:
    gendata = pd.read_csv(case_data_dir / "gendata.csv")
    storagedata = pd.read_csv(case_data_dir / "storagedata.csv")
    scc = pd.read_excel(raw_dir / "scc_july_2024.xlsx", sheet_name="SCC_Report_Current", header=1)
    scc = scc.rename(columns=lambda c: str(c).strip())
    scc = scc[(scc["Generator Status"] == "ACTIVE") & scc["SCC (MW)"].notna()].copy()
    scc["MajorFuel"] = scc["Fuel Type"].map(iso_capacity_group)
    actual = (
        scc.groupby("MajorFuel", as_index=False)["SCC (MW)"]
        .sum()
        .rename(columns={"SCC (MW)": "actual_capacity_mw"})
    )

    case_gen = gendata[["SourceTechnology", "Pmax (MW)"]].copy()
    case_gen["MajorFuel"] = case_gen["SourceTechnology"].map(case_capacity_group)
    model = (
        case_gen.groupby("MajorFuel", as_index=False)["Pmax (MW)"]
        .sum()
        .rename(columns={"Pmax (MW)": "model_capacity_mw"})
    )
    phs_power = float(storagedata.loc[storagedata["Type"] == "PHS", "Max Power (MW)"].sum())
    if phs_power:
        hydro_mask = model["MajorFuel"] == "Hydro"
        if hydro_mask.any():
            model.loc[hydro_mask, "model_capacity_mw"] += phs_power
        else:
            model = pd.concat([model, pd.DataFrame([{"MajorFuel": "Hydro", "model_capacity_mw": phs_power}])], ignore_index=True)

    comp = model.merge(actual, on="MajorFuel", how="outer").fillna(0.0)
    comp["delta_mw"] = comp["model_capacity_mw"] - comp["actual_capacity_mw"]
    comp["delta_pct_vs_actual"] = np.where(
        comp["actual_capacity_mw"] != 0.0,
        comp["delta_mw"] / comp["actual_capacity_mw"],
        np.nan,
    )
    return comp.sort_values("MajorFuel").reset_index(drop=True)


def compare_generation(output_dir: Path, raw_dir: Path) -> pd.DataFrame:
    power = pd.read_csv(output_dir / "power_hourly.csv")
    model = (
        power.assign(MajorFuel=power["Technology"].map(model_major_fuel))
        .groupby("MajorFuel", as_index=False)["AnnSum"]
        .sum()
        .rename(columns={"AnnSum": "model_generation_mwh"})
    )
    series_ids = list(EBA_ISONE_GEN_SERIES.values())
    eba_map = read_eba_series_map(raw_dir / "EBA.zip", series_ids)
    actual_rows = []
    for fuel, series_id in EBA_ISONE_GEN_SERIES.items():
        series = eba_map.get(series_id)
        if series is None:
            continue
        try:
            actual_rows.append({"MajorFuel": fuel, "actual_generation_mwh": float(july_2024(series).sum())})
        except ValueError:
            continue
    actual = pd.DataFrame(actual_rows)
    comp = model.merge(actual, on="MajorFuel", how="outer")
    comp["model_generation_mwh"] = comp["model_generation_mwh"].fillna(0.0)
    comp["delta_mwh"] = comp["model_generation_mwh"] - comp["actual_generation_mwh"]
    comp["delta_pct_vs_actual"] = np.where(
        comp["actual_generation_mwh"].notna() & (comp["actual_generation_mwh"] != 0.0),
        comp["delta_mwh"] / comp["actual_generation_mwh"],
        np.nan,
    )
    return comp.sort_values("MajorFuel").reset_index(drop=True)


def compare_zonal_load(case_data_dir: Path, raw_dir: Path) -> pd.DataFrame:
    zonedata = pd.read_csv(case_data_dir / "zonedata.csv")
    load_regional = pd.read_csv(case_data_dir / "load_timeseries_regional.csv")
    zone_peak = dict(zip(zonedata["Zone_id"], zonedata["Demand (MW)"]))
    model_rows = []
    for zone in zonedata["Zone_id"]:
        hourly = load_regional[zone].astype(float).to_numpy() * float(zone_peak[zone])
        model_rows.append(
            {
                "Zone": zone,
                "model_load_mwh": float(hourly.sum()),
                "model_avg_load_mw": float(hourly.mean()),
            }
        )
    model = pd.DataFrame(model_rows)

    load_series_ids = [f"EBA.ISNE-{rid}.D.H" for rid in LOAD_ZONE_REPORT_ID.values()]
    eba_map = read_eba_series_map(raw_dir / "EBA.zip", load_series_ids)
    actual_rows = []
    for zone, load_zones in SYNTHETIC_ZONE_TO_LOAD_ZONES.items():
        total = np.zeros(744, dtype=float)
        for load_zone in load_zones:
            series_id = f"EBA.ISNE-{LOAD_ZONE_REPORT_ID[load_zone]}.D.H"
            total += july_2024(eba_map[series_id])
        actual_rows.append(
            {
                "Zone": zone,
                "actual_load_mwh": float(total.sum()),
                "actual_avg_load_mw": float(total.mean()),
            }
        )
    actual = pd.DataFrame(actual_rows)
    comp = model.merge(actual, on="Zone", how="outer").fillna(0.0)
    model_total = float(comp["model_load_mwh"].sum())
    actual_total = float(comp["actual_load_mwh"].sum())
    comp["model_load_share"] = np.where(model_total > 0.0, comp["model_load_mwh"] / model_total, np.nan)
    comp["actual_load_share"] = np.where(actual_total > 0.0, comp["actual_load_mwh"] / actual_total, np.nan)
    comp["delta_share_pct_pt"] = 100.0 * (comp["model_load_share"] - comp["actual_load_share"])
    return comp.sort_values("Zone").reset_index(drop=True)


def summarize_seam_capacity(case_data_dir: Path) -> pd.DataFrame:
    branchdata = pd.read_csv(case_data_dir / "branchdata.csv")
    cross = branchdata[branchdata["From_zone"] != branchdata["To_zone"]].copy()
    if cross.empty:
        return pd.DataFrame(columns=["Seam", "TotalCapacityMW", "LineCount"])
    cross["Seam"] = cross.apply(lambda r: " <-> ".join(sorted([str(r["From_zone"]), str(r["To_zone"])])), axis=1)
    seam = (
        cross.groupby("Seam", as_index=False)
        .agg(TotalCapacityMW=("Capacity (MW)", "sum"), LineCount=("Capacity (MW)", "size"))
        .sort_values("TotalCapacityMW", ascending=False)
        .reset_index(drop=True)
    )
    return seam


def summarize_output(output_dir: Path) -> dict[str, float]:
    price_nodal = pd.read_csv(output_dir / "power_price_nodal.csv")
    price_cols = hourly_columns(price_nodal)
    lmp_vals = price_nodal[price_cols].to_numpy(dtype=float).ravel()

    load_shedding = pd.read_csv(output_dir / "power_loadshedding.csv")
    ls_cols = hourly_columns(load_shedding)
    ls_total = float(load_shedding["AnnTol"].astype(float).sum())

    power = pd.read_csv(output_dir / "power_hourly.csv")
    generation_total = float(power["AnnSum"].astype(float).sum())

    return {
        "average_nodal_lmp": float(lmp_vals.mean()),
        "negative_lmp_share": float((lmp_vals < 0.0).mean()),
        "load_shedding_total_mwh": ls_total,
        "generation_total_mwh": generation_total,
    }


def summarize_system(case_data_dir: Path, raw_dir: Path, output_dir: Path) -> dict[str, dict[str, float]]:
    zonedata = pd.read_csv(case_data_dir / "zonedata.csv")
    load_regional = pd.read_csv(case_data_dir / "load_timeseries_regional.csv")
    actual_load = read_hourly_load_csv(raw_dir / "hourlysystemdemand_202407.csv")
    interchange = pd.read_csv(raw_dir / "smd_interchange_2024_07.csv")
    model_output = summarize_output(output_dir)

    zone_peak = dict(zip(zonedata["Zone_id"], zonedata["Demand (MW)"]))
    model_load = sum(load_regional[zone].astype(float).to_numpy() * float(zone_peak[zone]) for zone in zonedata["Zone_id"])
    output_ni_path = output_dir / "power_ni_nodal.csv"
    if output_ni_path.exists():
        ni_nodal = pd.read_csv(output_ni_path)
    else:
        ni_nodal = pd.read_csv(case_data_dir / "ni_timeseries_nodal.csv")
    ni_cols = [col for col in ni_nodal.columns if str(col).startswith("h")]
    model_ni = ni_nodal[ni_cols].sum(axis=0).to_numpy(dtype=float)

    actual_load_total = float(actual_load["total_load_mwh"].sum())
    actual_ni_total = float(interchange["ISO_NE_CA_NetInt_MWh"].sum())
    actual_generation_total = actual_load_total - actual_ni_total

    return {
        "model": {
            "average_load_mw": float(model_load.mean()),
            "total_load_mwh": float(model_load.sum()),
            "average_net_import_mw": float(model_ni.mean()),
            "total_net_import_mwh": float(model_ni.sum()),
            "total_generation_mwh": float(model_output["generation_total_mwh"]),
        },
        "actual": {
            "average_load_mw": float(actual_load["total_load_mwh"].mean()),
            "total_load_mwh": actual_load_total,
            "average_net_import_mw": float(interchange["ISO_NE_CA_NetInt_MWh"].mean()),
            "total_net_import_mwh": actual_ni_total,
            "total_generation_mwh": actual_generation_total,
        },
        "output": model_output,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Build a July 2024 scorecard for the ISO-NE 250-bus PCM example.")
    parser.add_argument("--case-data-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--raw-dir", type=Path, required=True)
    parser.add_argument("--summary-path", type=Path, required=True)
    parser.add_argument("--capacity-csv", type=Path, required=True)
    parser.add_argument("--generation-csv", type=Path, required=True)
    parser.add_argument("--zonal-load-csv", type=Path, required=True)
    parser.add_argument("--seam-csv", type=Path, required=True)
    args = parser.parse_args()

    capacity = compare_capacity(args.case_data_dir, args.raw_dir)
    generation = compare_generation(args.output_dir, args.raw_dir)
    zonal_load = compare_zonal_load(args.case_data_dir, args.raw_dir)
    seam = summarize_seam_capacity(args.case_data_dir)
    system = summarize_system(args.case_data_dir, args.raw_dir, args.output_dir)

    summary = {
        "system": system,
        "capacity_gap_by_fuel_mw": {row["MajorFuel"]: float(row["delta_mw"]) for _, row in capacity.iterrows()},
        "generation_gap_by_fuel_mwh": {
            row["MajorFuel"]: float(row["delta_mwh"])
            for _, row in generation.iterrows()
            if pd.notna(row["actual_generation_mwh"])
        },
        "zonal_load_share_gap_pct_pt": {row["Zone"]: float(row["delta_share_pct_pt"]) for _, row in zonal_load.iterrows()},
        "interzonal_seams_ranked_by_capacity_mw": [
            {"Seam": str(row["Seam"]), "TotalCapacityMW": float(row["TotalCapacityMW"]), "LineCount": int(row["LineCount"])}
            for _, row in seam.iterrows()
        ],
    }

    for path in [args.summary_path, args.capacity_csv, args.generation_csv, args.zonal_load_csv, args.seam_csv]:
        path.parent.mkdir(parents=True, exist_ok=True)

    args.summary_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")
    capacity.to_csv(args.capacity_csv, index=False)
    generation.to_csv(args.generation_csv, index=False)
    zonal_load.to_csv(args.zonal_load_csv, index=False)
    seam.to_csv(args.seam_csv, index=False)
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
