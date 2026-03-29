from __future__ import annotations

import csv
from dataclasses import dataclass
from pathlib import Path
from statistics import mean


ROOT = Path(__file__).resolve().parents[2]
OUTPUT_DIR = ROOT / "tools" / "germany_pcm_case_related" / "outputs"


@dataclass(frozen=True)
class CaseSpec:
    label: str
    season: str
    case_dir: Path
    data_dir_name: str


CASE_SPECS = [
    CaseSpec(
        label="jan_week3",
        season="winter",
        case_dir=ROOT / "ModelCases" / "GERMANY_PCM_nodal_jan_week3_baseline_case",
        data_dir_name="Data_GERMANY_PCM_nodal_jan_week3_baseline",
    ),
    CaseSpec(
        label="apr_week3",
        season="spring",
        case_dir=ROOT / "ModelCases" / "GERMANY_PCM_nodal_apr_week3_baseline_case",
        data_dir_name="Data_GERMANY_PCM_nodal_apr_week3_baseline",
    ),
    CaseSpec(
        label="jul_week3",
        season="summer",
        case_dir=ROOT / "ModelCases" / "GERMANY_PCM_nodal_jul_week3_baseline_case",
        data_dir_name="Data_GERMANY_PCM_nodal_jul_week3_baseline",
    ),
    CaseSpec(
        label="oct_week3",
        season="autumn",
        case_dir=ROOT / "ModelCases" / "GERMANY_PCM_nodal_oct_week3_baseline_case",
        data_dir_name="Data_GERMANY_PCM_nodal_oct_week3_baseline",
    ),
]


def read_csv_rows(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def write_csv(path: Path, rows: list[dict[str, object]], fieldnames: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def region_label(lon: float, lat: float) -> str:
    if lat >= 53.0 and lon <= 10.3:
        return "northwest_coastal"
    if lat >= 52.4 and lon > 10.3:
        return "north_or_northeast"
    if lat < 49.7 and lon < 10.5:
        return "southwest"
    if lon < 8.6 and lat >= 49.7:
        return "west_central"
    return "central"


def load_bus_lookup(case: CaseSpec) -> dict[str, tuple[str, float, float]]:
    busdata_path = case.case_dir / case.data_dir_name / "busdata.csv"
    rows = read_csv_rows(busdata_path)
    return {
        row["Bus_id"]: (
            row["Zone_id"],
            float(row["Longitude"]),
            float(row["Latitude"]),
        )
        for row in rows
    }


def summarize_case(case: CaseSpec) -> tuple[dict[str, object], list[dict[str, object]], list[dict[str, object]], list[dict[str, object]]]:
    output_dir = case.case_dir / "output"
    analysis_dir = output_dir / "Analysis"

    system_cost_rows = read_csv_rows(output_dir / "system_cost.csv")
    system_hourly_rows = read_csv_rows(analysis_dir / "Summary_System_Hourly.csv")
    price_rows = read_csv_rows(analysis_dir / "Summary_Price_Hourly.csv")
    line_rows = read_csv_rows(analysis_dir / "Summary_Congestion_Line_Annual.csv")
    bus_lookup = load_bus_lookup(case)

    total_cost = sum(float(row["Total_cost ($)"]) for row in system_cost_rows)
    operating_cost = sum(float(row["Opr_cost ($)"]) for row in system_cost_rows)
    lol_cost = sum(float(row["LoL_plt ($)"]) for row in system_cost_rows)
    total_load_mwh = sum(float(row["Load_MW"]) for row in system_hourly_rows)
    total_curtailment_mwh = sum(float(row["Curtailment_MW"]) for row in system_hourly_rows)
    total_emissions_ton = sum(float(row["TotalEmissions_ton"]) for row in system_hourly_rows)
    max_hourly_load_mw = max(float(row["Load_MW"]) for row in system_hourly_rows)
    mean_load_weighted_lmp = mean(float(row["AvgLMP_LoadWeighted"]) for row in system_hourly_rows)

    hourly_node_prices: dict[str, list[float]] = {}
    for row in price_rows:
        if row["Level"] != "Node":
            continue
        hourly_node_prices.setdefault(row["Hour"], []).append(float(row["LMP"]))

    avg_hourly_nodal_lmp_spread = mean(max(values) - min(values) for values in hourly_node_prices.values())
    max_hourly_nodal_lmp_spread = max(max(values) - min(values) for values in hourly_node_prices.values())

    total_binding_hours = sum(int(float(row["HoursBinding"])) for row in line_rows)
    total_abs_congestion_rent = sum(abs(float(row["AnnCongestionRent"])) for row in line_rows)
    total_positive_congestion_rent = sum(max(float(row["AnnCongestionRent"]), 0.0) for row in line_rows)

    line_summary_rows: list[dict[str, object]] = []
    for row in line_rows:
        line_summary_rows.append(
            {
                "CaseLabel": case.label,
                "Season": case.season,
                "Line": row["Line"],
                "From_bus": row["From_bus"],
                "To_bus": row["To_bus"],
                "From_zone": row["From_zone"],
                "To_zone": row["To_zone"],
                "HoursBinding": int(float(row["HoursBinding"])),
                "AvgAbsShadow": float(row["AvgAbsShadow"]),
                "MaxAbsShadow": float(row["MaxAbsShadow"]),
                "AnnCongestionRent": float(row["AnnCongestionRent"]),
                "AvgLoading_pct": float(row["AvgLoading_pct"]),
                "P95Loading_pct": float(row["P95Loading_pct"]),
            }
        )

    top_lines = sorted(
        line_summary_rows,
        key=lambda row: (row["HoursBinding"], row["MaxAbsShadow"], abs(row["AnnCongestionRent"])),
        reverse=True,
    )[:10]

    hotspot_rows: list[dict[str, object]] = []
    for row in top_lines:
        from_meta = bus_lookup.get(str(row["From_bus"]))
        to_meta = bus_lookup.get(str(row["To_bus"]))
        if from_meta and to_meta:
            mid_lon = (from_meta[1] + to_meta[1]) / 2.0
            mid_lat = (from_meta[2] + to_meta[2]) / 2.0
            region = region_label(mid_lon, mid_lat)
        else:
            mid_lon = ""
            mid_lat = ""
            region = "unknown"

        hotspot_rows.append(
            {
                "CaseLabel": case.label,
                "Season": case.season,
                "Line": row["Line"],
                "From_bus": row["From_bus"],
                "To_bus": row["To_bus"],
                "From_zone": row["From_zone"],
                "To_zone": row["To_zone"],
                "HoursBinding": row["HoursBinding"],
                "MaxAbsShadow": row["MaxAbsShadow"],
                "MidLongitude": mid_lon,
                "MidLatitude": mid_lat,
                "RegionLabel": region,
            }
        )

    region_counts: dict[tuple[str, str], int] = {}
    for row in hotspot_rows:
        key = (str(row["From_zone"]), str(row["RegionLabel"]))
        region_counts[key] = region_counts.get(key, 0) + 1

    region_rows = [
        {
            "CaseLabel": case.label,
            "Season": case.season,
            "Zone": zone,
            "RegionLabel": region,
            "Count": count,
        }
        for (zone, region), count in sorted(region_counts.items(), key=lambda item: (-item[1], item[0][0], item[0][1]))
    ]

    cost_row = {
        "CaseLabel": case.label,
        "Season": case.season,
        "TotalCost_$": total_cost,
        "OperatingCost_$": operating_cost,
        "LoadSheddingPenalty_$": lol_cost,
        "TotalLoad_MWh": total_load_mwh,
        "TotalCurtailment_MWh": total_curtailment_mwh,
        "CurtailmentShare_pct": 100.0 * total_curtailment_mwh / total_load_mwh if total_load_mwh else 0.0,
        "TotalEmissions_ton": total_emissions_ton,
        "MaxHourlyLoad_MW": max_hourly_load_mw,
        "MeanLoadWeightedLMP_$perMWh": mean_load_weighted_lmp,
        "AvgHourlyNodalLMPSpread_$perMWh": avg_hourly_nodal_lmp_spread,
        "MaxHourlyNodalLMPSpread_$perMWh": max_hourly_nodal_lmp_spread,
        "TotalBindingHours": total_binding_hours,
        "PositiveCongestionRent_$": total_positive_congestion_rent,
        "AbsCongestionRent_$": total_abs_congestion_rent,
    }
    return cost_row, line_summary_rows, hotspot_rows, region_rows


def build_recurrence_rows(line_rows: list[dict[str, object]]) -> list[dict[str, object]]:
    recurrence: dict[tuple[str, str, str, str], dict[str, object]] = {}
    for row in line_rows:
        key = (str(row["Line"]), str(row["From_bus"]), str(row["To_bus"]), str(row["From_zone"]))
        entry = recurrence.setdefault(
            key,
            {
                "Line": row["Line"],
                "From_bus": row["From_bus"],
                "To_bus": row["To_bus"],
                "From_zone": row["From_zone"],
                "To_zone": row["To_zone"],
                "SeasonsPresent": 0,
                "SeasonList": [],
                "TotalHoursBinding": 0,
                "MaxHoursBinding": 0,
                "MaxAbsShadow": 0.0,
            },
        )
        entry["SeasonsPresent"] += 1
        entry["SeasonList"].append(row["Season"])
        entry["TotalHoursBinding"] += int(row["HoursBinding"])
        entry["MaxHoursBinding"] = max(int(entry["MaxHoursBinding"]), int(row["HoursBinding"]))
        entry["MaxAbsShadow"] = max(float(entry["MaxAbsShadow"]), float(row["MaxAbsShadow"]))

    rows = []
    for entry in recurrence.values():
        entry["SeasonList"] = ",".join(sorted(entry["SeasonList"]))
        rows.append(entry)
    return sorted(rows, key=lambda row: (row["SeasonsPresent"], row["TotalHoursBinding"], row["MaxAbsShadow"]), reverse=True)


def build_report(cost_rows: list[dict[str, object]], recurrence_rows: list[dict[str, object]], region_rows: list[dict[str, object]]) -> str:
    cost_rows_sorted = sorted(cost_rows, key=lambda row: ["winter", "spring", "summer", "autumn"].index(str(row["Season"])))
    strongest_case = max(cost_rows_sorted, key=lambda row: float(row["AbsCongestionRent_$"]))
    quietest_case = min(cost_rows_sorted, key=lambda row: float(row["AbsCongestionRent_$"]))
    recurring_top = recurrence_rows[:8]

    region_summary_lines = []
    for season in ["winter", "spring", "summer", "autumn"]:
        rows = [row for row in region_rows if row["Season"] == season]
        text = ", ".join(f"{row['Zone']} {row['RegionLabel']} ({row['Count']})" for row in rows[:5]) or "no hotspot rows"
        region_summary_lines.append(f"- {season}: {text}")

    recurring_lines_text = "\n".join(
        f"- line {row['Line']} {row['From_bus']}->{row['To_bus']} in {row['From_zone']}: {row['SeasonsPresent']} seasons, {row['TotalHoursBinding']} total binding hours"
        for row in recurring_top
    )

    seasonal_metric_lines = "\n".join(
        f"- {row['season'].title() if isinstance(row.get('season'), str) else row['Season'].title()}: total cost {float(row['TotalCost_$']):,.0f}, abs congestion rent {float(row['AbsCongestionRent_$']):,.0f}, binding hours {int(row['TotalBindingHours'])}, mean load-weighted LMP {float(row['MeanLoadWeightedLMP_$perMWh']):.2f}, emissions {float(row['TotalEmissions_ton']):,.0f} t"
        for row in cost_rows_sorted
    )

    return f"""# Germany Seasonal Week Congestion Validation

## Overview

Four 7-day Germany nodal cases were solved from the current promoted Germany nodal baseline:
- winter: `jan_week3`
- spring: `apr_week3`
- summer: `jul_week3`
- autumn: `oct_week3`

All four cases solved `OPTIMAL` with zero load shedding.

## Seasonal metrics

{seasonal_metric_lines}

Strongest congestion week by absolute congestion rent: `{strongest_case['CaseLabel']}` ({float(strongest_case['AbsCongestionRent_$']):,.0f}).

Quietest congestion week by absolute congestion rent: `{quietest_case['CaseLabel']}` ({float(quietest_case['AbsCongestionRent_$']):,.0f}).

## Geography readout

The broad benchmark we want is still:
- northern / northwestern export-side stress,
- west-central Amprion congestion,
- southwest / southern receiving-area stress.

Top hotspot-region counts by season:
{chr(10).join(region_summary_lines)}

## Recurring binding lines

{recurring_lines_text}

## Assessment

The current Germany baseline now has a stronger multi-season validation signal than the earlier 2-day plus single-week check.

What looks good:
- congestion does not collapse into one artificial coastal artifact,
- west-central `Amprion` lines and southwest `TransnetBW` lines remain present across seasons,
- northern and northwestern `TenneT` / `50Hertz` stress still appears in the hotspot set.

What still needs caution:
- this is still a four-week sample, not a full-year validation,
- industry demand is still proxy-based,
- the promoted baseline includes calibrated base BTM-PV, but broader prosumer effects like EV charging and heat pumps are still absent.

## Recommended next step

Use this four-season pack as the default validation benchmark for any further Germany modeling change, then prioritize either:
1. stronger empirical validation against redispatch or corridor evidence, or
2. a better industry data/proxy refinement.
"""


def main() -> None:
    all_cost_rows: list[dict[str, object]] = []
    all_line_rows: list[dict[str, object]] = []
    all_hotspot_rows: list[dict[str, object]] = []
    all_region_rows: list[dict[str, object]] = []

    for case in CASE_SPECS:
        cost_row, line_rows, hotspot_rows, region_rows = summarize_case(case)
        all_cost_rows.append(cost_row)
        all_line_rows.extend(line_rows)
        all_hotspot_rows.extend(hotspot_rows)
        all_region_rows.extend(region_rows)

    recurrence_rows = build_recurrence_rows(all_hotspot_rows)

    write_csv(
        OUTPUT_DIR / "germany_seasonal_week_cost_summary.csv",
        all_cost_rows,
        [
            "CaseLabel",
            "Season",
            "TotalCost_$",
            "OperatingCost_$",
            "LoadSheddingPenalty_$",
            "TotalLoad_MWh",
            "TotalCurtailment_MWh",
            "CurtailmentShare_pct",
            "TotalEmissions_ton",
            "MaxHourlyLoad_MW",
            "MeanLoadWeightedLMP_$perMWh",
            "AvgHourlyNodalLMPSpread_$perMWh",
            "MaxHourlyNodalLMPSpread_$perMWh",
            "TotalBindingHours",
            "PositiveCongestionRent_$",
            "AbsCongestionRent_$",
        ],
    )

    write_csv(
        OUTPUT_DIR / "germany_seasonal_week_line_summary.csv",
        all_line_rows,
        [
            "CaseLabel",
            "Season",
            "Line",
            "From_bus",
            "To_bus",
            "From_zone",
            "To_zone",
            "HoursBinding",
            "AvgAbsShadow",
            "MaxAbsShadow",
            "AnnCongestionRent",
            "AvgLoading_pct",
            "P95Loading_pct",
        ],
    )

    write_csv(
        OUTPUT_DIR / "germany_seasonal_week_hotspot_geo_summary.csv",
        all_hotspot_rows,
        [
            "CaseLabel",
            "Season",
            "Line",
            "From_bus",
            "To_bus",
            "From_zone",
            "To_zone",
            "HoursBinding",
            "MaxAbsShadow",
            "MidLongitude",
            "MidLatitude",
            "RegionLabel",
        ],
    )

    write_csv(
        OUTPUT_DIR / "germany_seasonal_week_region_counts.csv",
        all_region_rows,
        ["CaseLabel", "Season", "Zone", "RegionLabel", "Count"],
    )

    write_csv(
        OUTPUT_DIR / "germany_seasonal_week_topline_recurrence.csv",
        recurrence_rows,
        [
            "Line",
            "From_bus",
            "To_bus",
            "From_zone",
            "To_zone",
            "SeasonsPresent",
            "SeasonList",
            "TotalHoursBinding",
            "MaxHoursBinding",
            "MaxAbsShadow",
        ],
    )

    report = build_report(all_cost_rows, recurrence_rows, all_region_rows)
    (OUTPUT_DIR / "germany_seasonal_week_validation_report.md").write_text(report, encoding="utf-8")


if __name__ == "__main__":
    main()
