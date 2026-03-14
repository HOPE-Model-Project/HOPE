from __future__ import annotations

import re
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Tuple

import pandas as pd


@dataclass
class CaseData:
    case_path: Path
    output_path: Path
    analysis_path: Path
    busdata: pd.DataFrame
    line_hourly: pd.DataFrame
    node_driver_hourly: pd.DataFrame
    system_hourly: pd.DataFrame
    nodal_price: pd.DataFrame
    zone_colors: Dict[str, str]
    bus_xy: Dict[str, Tuple[float, float]]
    zone_rect: Dict[str, Tuple[float, float, float, float]]


_CACHE: Dict[str, CaseData] = {}


def _parse_datacase(case_path: Path) -> str:
    settings = case_path / "Settings" / "HOPE_model_settings.yml"
    text = settings.read_text(encoding="utf-8")
    m = re.search(r"^\s*DataCase\s*:\s*([^\n#]+)", text, flags=re.MULTILINE)
    if not m:
        raise ValueError(f"Could not find DataCase in: {settings}")
    return m.group(1).strip().strip("\"'").strip()


def _default_zone_colors(zones: list[str]) -> Dict[str, str]:
    palette = [
        "#e6f4ea",
        "#e8f0fe",
        "#fff4db",
        "#f5ecff",
        "#fce8e6",
        "#e6f7ff",
        "#f0f4c3",
        "#ffe0b2",
    ]
    return {z: palette[i % len(palette)] for i, z in enumerate(sorted(zones))}


def _build_layout(busdata: pd.DataFrame) -> tuple[Dict[str, Tuple[float, float]], Dict[str, Tuple[float, float, float, float]]]:
    zones = sorted(busdata["Zone_id"].astype(str).unique().tolist())
    zone_anchor = {
        "Z1": (-6.0, 4.5),
        "Z2": (6.0, 4.5),
        "Z3": (6.0, -4.5),
        "Z4": (-6.0, -4.5),
    }
    default_anchor = [(-10.0, 8.0), (0.0, 8.0), (10.0, 8.0), (-10.0, 0.0), (0.0, 0.0), (10.0, 0.0), (-10.0, -8.0), (0.0, -8.0), (10.0, -8.0)]
    slots = [(-2.1, 1.2), (0.0, 2.0), (2.1, 1.2), (2.1, -1.2), (0.0, -2.0), (-2.1, -1.2)]

    bus_xy: Dict[str, Tuple[float, float]] = {}
    zone_rect: Dict[str, Tuple[float, float, float, float]] = {}

    for idx, z in enumerate(zones):
        zx, zy = zone_anchor.get(z, default_anchor[idx % len(default_anchor)])
        zone_rect[z] = (zx - 3.3, zy - 2.8, zx + 3.3, zy + 2.8)
        buses = sorted(busdata.loc[busdata["Zone_id"].astype(str) == z, "Bus_id"].astype(str).tolist(), key=lambda x: int(x) if x.isdigit() else x)
        if len(buses) <= len(slots):
            for i, b in enumerate(buses):
                dx, dy = slots[i]
                bus_xy[b] = (zx + dx, zy + dy)
        else:
            for i, b in enumerate(buses):
                theta = 2.0 * 3.141592653589793 * i / max(1, len(buses))
                bus_xy[b] = (zx + 2.5 * math.cos(theta), zy + 2.1 * math.sin(theta))
    return bus_xy, zone_rect


def load_case(case_path: str, refresh: bool = False) -> CaseData:
    key = str(Path(case_path).resolve())
    if not refresh and key in _CACHE:
        return _CACHE[key]

    case_dir = Path(case_path).resolve()
    if not case_dir.exists():
        raise FileNotFoundError(f"Case path not found: {case_dir}")

    datacase = _parse_datacase(case_dir).rstrip("/\\")
    data_dir = case_dir / datacase
    output_dir = case_dir / "output"
    analysis_dir = output_dir / "Analysis"

    busdata_path = data_dir / "busdata.csv"
    nodal_price_path = output_dir / "power_price_decomposition_nodal.csv"
    line_hourly_path = analysis_dir / "Summary_Congestion_Line_Hourly.csv"
    node_driver_path = analysis_dir / "Summary_Congestion_Driver_Node_Hourly.csv"
    system_hourly_path = analysis_dir / "Summary_System_Hourly.csv"

    if not busdata_path.exists():
        raise FileNotFoundError(f"Missing busdata for nodal dashboard: {busdata_path}")
    if not nodal_price_path.exists():
        raise FileNotFoundError(f"Missing nodal LMP file: {nodal_price_path}. Re-run case with nodal model and dual outputs.")
    if not line_hourly_path.exists():
        raise FileNotFoundError(f"Missing congestion summary file: {line_hourly_path}. Set summary_table: 1 and rerun.")
    if not node_driver_path.exists():
        raise FileNotFoundError(f"Missing congestion driver file: {node_driver_path}. Set summary_table: 1 and rerun.")

    busdata = pd.read_csv(busdata_path)
    nodal_price = pd.read_csv(nodal_price_path)
    line_hourly = pd.read_csv(line_hourly_path)
    node_driver_hourly = pd.read_csv(node_driver_path)
    system_hourly = pd.read_csv(system_hourly_path) if system_hourly_path.exists() else pd.DataFrame()

    # Normalize common types for joins/filtering.
    busdata["Bus_id"] = busdata["Bus_id"].astype(str)
    busdata["Zone_id"] = busdata["Zone_id"].astype(str)
    nodal_price["Bus"] = nodal_price["Bus"].astype(str)
    nodal_price["Zone"] = nodal_price["Zone"].astype(str)
    nodal_price["Hour"] = nodal_price["Hour"].astype(int)
    if "Loss" not in nodal_price.columns:
        nodal_price["Loss"] = 0.0
    line_hourly["From_bus"] = line_hourly["From_bus"].astype(str)
    line_hourly["To_bus"] = line_hourly["To_bus"].astype(str)
    line_hourly["From_zone"] = line_hourly["From_zone"].astype(str)
    line_hourly["To_zone"] = line_hourly["To_zone"].astype(str)
    line_hourly["Hour"] = line_hourly["Hour"].astype(int)
    if "LineLoss_MW" not in line_hourly.columns:
        line_hourly["LineLoss_MW"] = 0.0
    node_driver_hourly["Bus"] = node_driver_hourly["Bus"].astype(str)
    node_driver_hourly["Zone"] = node_driver_hourly["Zone"].astype(str)
    node_driver_hourly["Hour"] = node_driver_hourly["Hour"].astype(int)
    node_driver_hourly["Line"] = node_driver_hourly["Line"].astype(int)
    node_driver_hourly["From_bus"] = node_driver_hourly["From_bus"].astype(str)
    node_driver_hourly["To_bus"] = node_driver_hourly["To_bus"].astype(str)

    if not system_hourly.empty:
        system_hourly["Hour"] = system_hourly["Hour"].astype(int)
        if "TransmissionLoss_MW" not in system_hourly.columns:
            system_hourly["TransmissionLoss_MW"] = 0.0
    else:
        system_hourly = (
            line_hourly.groupby("Hour", as_index=False)["LineLoss_MW"]
            .sum()
            .rename(columns={"LineLoss_MW": "TransmissionLoss_MW"})
        )

    bus_xy, zone_rect = _build_layout(busdata)
    zone_colors = _default_zone_colors(busdata["Zone_id"].astype(str).unique().tolist())

    result = CaseData(
        case_path=case_dir,
        output_path=output_dir,
        analysis_path=analysis_dir,
        busdata=busdata,
        line_hourly=line_hourly,
        node_driver_hourly=node_driver_hourly,
        system_hourly=system_hourly,
        nodal_price=nodal_price,
        zone_colors=zone_colors,
        bus_xy=bus_xy,
        zone_rect=zone_rect,
    )
    _CACHE[key] = result
    return result
