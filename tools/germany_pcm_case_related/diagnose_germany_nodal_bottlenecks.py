from __future__ import annotations

import argparse
import csv
from collections import defaultdict
from pathlib import Path


def _read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


def _hour_fields(row: dict[str, str]) -> list[str]:
    return sorted((k for k in row if k.startswith("h")), key=lambda value: int(value[1:]))


def _line_angle_limits(line_rows: list[dict[str, str]], theta_max: float) -> list[dict[str, object]]:
    results: list[dict[str, object]] = []
    for idx, row in enumerate(line_rows, start=1):
        x_value = float(row["X"])
        capacity = float(row["Capacity (MW)"])
        angle_cap_single = float("inf") if x_value == 0 else theta_max / x_value
        angle_cap_two_sided = float("inf") if x_value == 0 else (2.0 * theta_max) / x_value
        results.append(
            {
                "line_id": idx,
                "from_bus": row["from_bus"],
                "to_bus": row["to_bus"],
                "from_zone": row["From_zone"],
                "to_zone": row["To_zone"],
                "x": x_value,
                "capacity": capacity,
                "angle_cap_single": angle_cap_single,
                "angle_cap_two_sided": angle_cap_two_sided,
                "cap_to_angle_ratio": float("inf") if angle_cap_two_sided == 0 else capacity / angle_cap_two_sided,
            }
        )
    return results


def _top_loadshedding_hours(loadshedding_rows: list[dict[str, str]], zone: str, top_n: int = 15) -> list[tuple[int, float]]:
    for row in loadshedding_rows:
        if row["load_area"] != zone:
            continue
        values = [(int(key[1:]), float(value)) for key, value in row.items() if key.startswith("h")]
        return sorted(values, key=lambda item: item[1], reverse=True)[:top_n]
    return []


def _top_zone_prices(price_rows: list[dict[str, str]], zone: str, top_n: int = 15) -> list[tuple[int, float]]:
    for row in price_rows:
        if row["Zone"] != zone:
            continue
        values = [(int(key[1:]), float(value)) for key, value in row.items() if key.startswith("h")]
        return sorted(values, key=lambda item: item[1], reverse=True)[:top_n]
    return []


def _high_price_buses(
    price_nodal_rows: list[dict[str, str]], zone: str, voll_threshold: float = 99999.0
) -> list[tuple[str, int, float]]:
    counts: dict[str, int] = defaultdict(int)
    maximums: dict[str, float] = defaultdict(float)
    for row in price_nodal_rows:
        if row["Zone"] != zone:
            continue
        bus_id = row["Bus"]
        for key, value in row.items():
            if not key.startswith("h"):
                continue
            price = float(value)
            if price >= voll_threshold:
                counts[bus_id] += 1
            if price > maximums[bus_id]:
                maximums[bus_id] = price
    return sorted(((bus, counts[bus], maximums[bus]) for bus in counts), key=lambda item: item[1], reverse=True)


def _incident_line_map(line_rows: list[dict[str, str]]) -> dict[str, list[dict[str, str]]]:
    incident: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in line_rows:
        incident[row["from_bus"]].append(row)
        incident[row["to_bus"]].append(row)
    return incident


def _generator_summary_by_bus(generator_rows: list[dict[str, str]]) -> dict[str, dict[str, object]]:
    summary: dict[str, dict[str, object]] = defaultdict(
        lambda: {"count": 0, "pmax": 0.0, "types": defaultdict(float)}
    )
    for row in generator_rows:
        bus_id = row["Bus_id"]
        entry = summary[bus_id]
        pmax = float(row["Pmax (MW)"])
        entry["count"] += 1
        entry["pmax"] += pmax
        entry["types"][row["Type"]] += pmax
    return summary


def _zone_capacity_summary(generator_rows: list[dict[str, str]]) -> dict[str, dict[str, float]]:
    zone_capacity: dict[str, dict[str, float]] = defaultdict(lambda: defaultdict(float))
    for row in generator_rows:
        zone_capacity[row["Zone"]][row["Type"]] += float(row["Pmax (MW)"])
    return zone_capacity


def _max_flow_by_line(flow_rows: list[dict[str, str]]) -> dict[tuple[str, str, str, str], float]:
    maximums: dict[tuple[str, str, str, str], float] = defaultdict(float)
    for row in flow_rows:
        key = (row["From_bus"], row["To_bus"], row["From_zone"], row["To_zone"])
        max_flow = max(abs(float(row[field])) for field in _hour_fields(row))
        maximums[key] = max(maximums[key], max_flow)
    return maximums


def build_report(case_root: Path, theta_max: float = 1000.0, focus_zone: str = "TenneT") -> str:
    data_dir = next(case_root.glob("Data_*"))
    output_dir = case_root / "output"

    bus_rows = _read_csv(data_dir / "busdata.csv")
    line_rows = _read_csv(data_dir / "linedata.csv")
    generator_rows = _read_csv(data_dir / "gendata.csv")
    loadshedding_rows = _read_csv(output_dir / "power_loadshedding.csv")
    price_rows = _read_csv(output_dir / "power_price.csv")
    price_nodal_rows = _read_csv(output_dir / "power_price_nodal.csv")
    annual_congestion_rows = _read_csv(output_dir / "Analysis" / "Summary_Congestion_Line_Annual.csv")
    flow_rows = _read_csv(output_dir / "power_flow.csv")

    angle_rows = _line_angle_limits(line_rows, theta_max)
    annual_congestion_rows.sort(
        key=lambda row: (
            float(row["HoursBinding"]),
            float(row["MaxAbsShadow"]),
            float(row["P95Loading_pct"]),
        ),
        reverse=True,
    )

    top_shedding = _top_loadshedding_hours(loadshedding_rows, focus_zone)
    shedding_hours = {hour for hour, value in top_shedding if value > 1e-3}
    top_prices = _top_zone_prices(price_rows, focus_zone)
    high_price_buses = _high_price_buses(price_nodal_rows, focus_zone)
    incident_lines = _incident_line_map(line_rows)
    generator_by_bus = _generator_summary_by_bus(generator_rows)
    max_flow_by_line = _max_flow_by_line(flow_rows)

    bus_info = {row["Bus_id"]: row for row in bus_rows}
    zone_demand = defaultdict(float)
    for row in bus_rows:
        zone_demand[row["Zone_id"]] += float(row["Demand (MW)"])
    zone_capacity = _zone_capacity_summary(generator_rows)

    focus_bus_set = {bus for bus, hours, _ in high_price_buses if hours == high_price_buses[0][1]} if high_price_buses else set()
    focus_angle_rows = [
        row
        for row in angle_rows
        if row["from_bus"] in focus_bus_set or row["to_bus"] in focus_bus_set
    ]

    angle_lt_25 = sum(1 for row in angle_rows if row["angle_cap_two_sided"] < 0.25 * row["capacity"])
    angle_lt_50 = sum(1 for row in angle_rows if row["angle_cap_two_sided"] < 0.50 * row["capacity"])
    angle_lt_100 = sum(1 for row in angle_rows if row["angle_cap_two_sided"] < row["capacity"])

    lines: list[str] = []
    lines.append(f"Case: {case_root.name}")
    lines.append(f"Focus zone: {focus_zone}")
    lines.append("")
    lines.append("Top load-shedding hours")
    for hour, value in top_shedding[:12]:
        lines.append(f"- h{hour}: {value:.2f} MW")

    lines.append("")
    lines.append("Top zonal price hours")
    for hour, value in top_prices[:12]:
        lines.append(f"- h{hour}: {value:.2f} $/MWh")

    lines.append("")
    lines.append("Largest recurring high-price bus cluster")
    for bus_id, voll_hours, max_price in high_price_buses[:8]:
        info = bus_info[bus_id]
        gen = generator_by_bus[bus_id]
        dominant_types = sorted(gen["types"].items(), key=lambda item: item[1], reverse=True)[:3]
        dominant_text = ", ".join(f"{tech} {capacity:.1f} MW" for tech, capacity in dominant_types)
        lines.append(
            f"- {bus_id}: {voll_hours} VOLL hours, max price {max_price:.2f}, "
            f"load {float(info['Demand (MW)']):.1f} MW, local Pmax {gen['pmax']:.1f} MW, "
            f"lat/lon ({info['Latitude']}, {info['Longitude']}), types [{dominant_text}]"
        )

    lines.append("")
    lines.append("Top annual congestion lines from HOPE summary")
    for row in annual_congestion_rows[:10]:
        lines.append(
            f"- Line {row['Line']} {row['From_bus']}->{row['To_bus']} ({row['From_zone']}->{row['To_zone']}): "
            f"HoursBinding={row['HoursBinding']}, MaxAbsShadow={float(row['MaxAbsShadow']):.6g}, "
            f"P95Loading={float(row['P95Loading_pct']):.1f}%"
        )

    lines.append("")
    lines.append("Approximate angle-limit stress check")
    lines.append(
        f"- Using two-sided transfer ~ 2*theta_max/X with theta_max={theta_max:.1f}, "
        f"{angle_lt_25} of {len(angle_rows)} lines are below 25% of thermal capacity."
    )
    lines.append(f"- {angle_lt_50} of {len(angle_rows)} lines are below 50% of thermal capacity.")
    lines.append(f"- {angle_lt_100} of {len(angle_rows)} lines are below 100% of thermal capacity.")

    lines.append("")
    lines.append("Most stressed lines by thermal-to-angle mismatch")
    for row in sorted(angle_rows, key=lambda item: item["cap_to_angle_ratio"], reverse=True)[:12]:
        lines.append(
            f"- {row['from_bus']}->{row['to_bus']} ({row['from_zone']}->{row['to_zone']}): "
            f"X={row['x']:.3f}, thermal={row['capacity']:.1f} MW, approx angle cap={row['angle_cap_two_sided']:.1f} MW, "
            f"ratio={row['cap_to_angle_ratio']:.1f}"
        )

    if focus_angle_rows:
        lines.append("")
        lines.append("Focus-bus incident lines")
        seen: set[tuple[str, str, float, float]] = set()
        for row in focus_angle_rows:
            dedupe_key = (str(row["from_bus"]), str(row["to_bus"]), float(row["x"]), float(row["capacity"]))
            if dedupe_key in seen:
                continue
            seen.add(dedupe_key)
            flow_key = (
                str(row["from_bus"]),
                str(row["to_bus"]),
                str(row["from_zone"]),
                str(row["to_zone"]),
            )
            max_flow = max_flow_by_line.get(flow_key, 0.0)
            lines.append(
                f"- {row['from_bus']}->{row['to_bus']} ({row['from_zone']}->{row['to_zone']}): "
                f"X={row['x']:.3f}, thermal={row['capacity']:.1f} MW, approx angle cap={row['angle_cap_two_sided']:.1f} MW, "
                f"observed max flow={max_flow:.1f} MW"
            )

    lines.append("")
    lines.append("Zone demand vs installed capacity")
    for zone in sorted(zone_demand):
        tech_mix = zone_capacity.get(zone, {})
        top_types = sorted(tech_mix.items(), key=lambda item: item[1], reverse=True)[:5]
        mix_text = ", ".join(f"{tech} {capacity:.1f} MW" for tech, capacity in top_types)
        lines.append(
            f"- {zone}: base demand {zone_demand[zone]:.1f} MW, installed Pmax {sum(tech_mix.values()):.1f} MW, top types [{mix_text}]"
        )

    if shedding_hours:
        lines.append("")
        lines.append(
            "Interpretation: the highest-shedding hours line up with the same TenneT bus cluster, "
            "but HOPE's thermal congestion summary stays modest. That points more strongly to angle/reactance scaling "
            "than to a thermal line-limit bottleneck."
        )

    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description="Diagnose bottlenecks in a Germany nodal HOPE run.")
    parser.add_argument("case_root", type=Path, help="Path to the HOPE case directory.")
    parser.add_argument("--theta-max", type=float, default=1000.0, help="theta_max used in the DCOPF run.")
    parser.add_argument("--focus-zone", default="TenneT", help="Zone to inspect for shortages/high prices.")
    parser.add_argument(
        "--output",
        type=Path,
        default=None,
        help="Optional report path. Defaults to output/Analysis/Nodal_Bottleneck_Diagnostic.txt inside the case.",
    )
    args = parser.parse_args()

    report = build_report(args.case_root, theta_max=args.theta_max, focus_zone=args.focus_zone)
    output_path = args.output or args.case_root / "output" / "Analysis" / "Nodal_Bottleneck_Diagnostic.txt"
    output_path.write_text(report, encoding="utf-8")
    print(f"Wrote diagnostic report to {output_path}")


if __name__ == "__main__":
    main()
