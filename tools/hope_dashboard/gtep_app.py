"""
HOPE GTEP Dashboard — Generation & Transmission Expansion Planning viewer.

Separate Dash application (default port 8051).  Run via run_gtep_dashboard.py.
"""
from __future__ import annotations

import json
import math
import os
import re
from dataclasses import dataclass, field
from functools import lru_cache
from pathlib import Path

import numpy as np
import pandas as pd
import plotly.graph_objects as go
from dash import ALL, Dash, Input, Output, State, ctx, dcc, html, no_update

# ─────────────────────────────────────────────────────────────────────────────
# Global constants
# ─────────────────────────────────────────────────────────────────────────────

APP_FONT = (
    "'Segoe UI Variable', 'Avenir Next', 'Segoe UI', 'Helvetica Neue', Arial, sans-serif"
)
DEFAULT_GTEP_CASE = "ModelCases/MD_GTEP_clean_case"
_mc_env = os.environ.get("HOPE_MODELCASES_PATH")
_REPO_ROOT = Path(_mc_env).parent if _mc_env else Path(__file__).resolve().parents[2]

# Technology display order + colours
TECH_COLOR: dict[str, str] = {
    # Nuclear — orange (baseload, cleanest carbon-free)
    "NuC":               "#f97316",
    "Nuc":               "#f97316",
    "Nuclear":           "#f97316",
    # Solid fuels — baseload thermal
    "Coal":              "#1c1917",
    # Natural gas — grey family (cleanest CCS → dirtiest peaker)
    "NGCC_CCS":          "#374151",
    "NGCC":              "#6b7280",
    "NGCT_CCS":          "#78716c",
    "NGCT":              "#9ca3af",
    # Other fossil / generic thermal — brown
    "Oil":               "#57534e",
    "MSW":               "#6366f1",
    "Thermal":           "#92400e",   # dark amber/brown
    "Other":             "#92400e",   # brown (same family as Thermal)
    # Biomass / landfill gas
    "Bio":               "#84cc16",
    "Landfill_NG":       "#a3e635",
    # Renewables — blues for water/wind, bright yellow for solar
    "Hydro":             "#1d4ed8",   # medium-dark blue (was WindOn)
    "PHS":               "#5b21b6",   # dark purple (pumped hydro storage)
    "WindOff":           "#38bdf8",   # sky blue (lighter, offshore)
    "WindOn":            "#60a5fa",   # light blue (onshore)
    "SolarPV":           "#facc15",   # bright yellow
    # Storage — purples (discharge = deep, charge = light)
    "Battery":           "#7c3aed",   # deep purple
    "Battery_discharge": "#7c3aed",
    "Battery_charge":    "#c4b5fd",   # light purple
    "ES":                "#6d28d9",   # deeper purple
    "ES_discharge":      "#6d28d9",
    "ES_charge":         "#ddd6fe",   # very light purple
    # Demand response — purple family
    "Loadshifting":      "#a855f7",
    "Loadshift":         "#a855f7",
    "DR":                "#a855f7",
}

# Zone centroids (lat, lon) — covers MD utility zones, PJM utility zones, and USA-64 zones.
# USA-64 entries are approximate EPA IPM v6 region centres; refine with actual shapefile if needed.
_ZONE_CENTROIDS: dict[str, tuple[float, float]] = {
    # ── Maryland utility sub-zones ───────────────────────────────────────────
    "BGE":     (39.30, -76.60),
    "PEPCO":   (38.95, -77.00),
    "APS_MD":  (39.65, -79.00),
    "DPL_MD":  (38.75, -75.60),
    # ── PJM utility zones (35 zones — PJM_MD100_GTEP_case) ──────────────────
    "AE_NJ":   (39.45, -74.65),   # Atlantic City Electric, southern NJ
    "AEP_IN":  (40.60, -86.35),   # AEP Indiana
    "AEP_KY":  (38.15, -82.90),   # AEP Kentucky
    "AEP_MI":  (41.85, -84.30),   # AEP Michigan
    "AEP_OH":  (39.90, -82.40),   # AEP Ohio
    "AEP_TN":  (36.10, -82.00),   # AEP Tennessee
    "AEP_VA":  (37.30, -81.30),   # AEP Appalachian Power, SW Virginia
    "AEP_WV":  (38.65, -80.65),   # AEP West Virginia
    "AP_MD":   (39.75, -78.85),   # Allegheny Power, western MD
    "AP_PA":   (40.25, -78.85),   # Allegheny Power, PA
    "AP_VA":   (37.85, -79.85),   # Allegheny Power, VA
    "AP_WV":   (38.80, -79.60),   # Allegheny Power, WV
    "ATSI_OH": (41.10, -81.20),   # AEP/ATSI, northeast Ohio
    "ATSI_PA": (40.85, -80.30),   # AEP/ATSI, PA
    "BC_MD":   (39.35, -76.65),   # Baltimore City area
    "CE_IL":   (41.85, -88.10),   # ComEd, northern Illinois
    "DAY_OH":  (39.75, -84.20),   # Dayton Power & Light, OH
    "DEOK_KY": (38.50, -84.50),   # Duke Energy, KY
    "DEOK_OH": (39.10, -84.10),   # Duke Energy, OH (Cincinnati)
    "DOM_NC":  (35.80, -78.70),   # Dominion North Carolina
    "DOM_VA":  (37.50, -77.80),   # Dominion Virginia
    "DPL_DE":  (38.90, -75.55),   # Delmarva Power, Delaware
    "DPL_VA":  (37.60, -75.90),   # Delmarva Power, VA Eastern Shore
    "DUQ_PA":  (40.45, -79.85),   # Duquesne Light, Pittsburgh
    "EKPC_KY": (37.70, -83.90),   # East KY Power Cooperative
    "JC_NJ":   (40.15, -74.45),   # Jersey Central P&L, central NJ
    "ME_PA":   (40.25, -76.10),   # Metropolitan Edison, PA (Reading)
    "OVEC_OH": (38.60, -82.60),   # Ohio Valley Electric, southern OH
    "PE_PA":   (40.00, -75.35),   # PECO Energy, Philadelphia
    "PEP_MD":  (38.95, -77.00),   # PEPCO Maryland
    "PL_PA":   (41.05, -80.25),   # Penn Power / FirstEnergy, NW PA
    "PN_PA":   (40.75, -76.20),   # PPL (Penn Power & Light), central PA
    "PS_NJ":   (40.50, -74.30),   # PSE&G, northern NJ
    "RECO_NJ": (41.10, -74.20),   # Rockland Electric, NJ/NY border
    # ── USA 64-zone EPA IPM v6 regions — centroids from PowerGenome GeoJSON ──
    # Zone mapping from tools/64_zone_US_case_related/USA_64zone/Parameter_527/Generators_data.csv
    "z1":  (27.9194, -96.9597),   # ERC_REST  — ERCOT main (central/south TX)
    "z2":  (31.1299, -101.9836),  # ERC_WEST  — ERCOT west Texas
    "z3":  (34.5857, -101.2766),  # ERC_PHDL  — ERCOT panhandle
    "z4":  (27.2869, -81.8869),   # FRCC      — Florida
    "z5":  (47.5591, -101.6115),  # MIS_MAPP  — MISO north (ND/SD)
    "z6":  (38.7071, -89.0844),   # MIS_IL    — MISO Illinois
    "z7":  (38.4545, -86.8675),   # MIS_INKY  — MISO Indiana/Kentucky
    "z8":  (42.2309, -92.4967),   # MIS_IA    — MISO Iowa
    "z9":  (42.0039, -94.3900),   # MIS_MIDA  — MISO upper Midwest
    "z10": (43.5044, -83.6007),   # MIS_LMI   — MISO Michigan
    "z11": (38.8621, -91.6182),   # MIS_MO    — MISO Missouri
    "z12": (46.2249, -86.3573),   # MIS_WUMS  — MISO upper Michigan/Wisconsin
    "z13": (47.2175, -92.9203),   # MIS_MNWI  — MISO Minnesota/Wisconsin
    "z14": (30.4088, -93.5840),   # MIS_WOTA  — MISO west TX/OK/AR border
    "z15": (29.2794, -89.5521),   # MIS_AMSO  — MISO AR/MS/south
    "z16": (34.8231, -91.3149),   # MIS_AR    — MISO Arkansas
    "z17": (32.5938, -90.5201),   # MIS_D_MS  — MISO delta Mississippi
    "z18": (30.5265, -91.9885),   # MIS_LA    — MISO Louisiana
    "z19": (41.2121, -72.8270),   # NENG_CT   — New England Connecticut
    "z20": (42.0966, -70.8529),   # NENGREST  — New England (MA/RI)
    "z21": (44.1788, -68.8407),   # NENG_ME   — New England Maine
    "z22": (44.0329, -76.0507),   # NY_Z_C&E  — NY zones C & E
    "z23": (43.3881, -73.8046),   # NY_Z_F    — NY zone F
    "z24": (41.1834, -74.0075),   # NY_Z_G-I  — NY zones G-I
    "z25": (40.6840, -73.8753),   # NY_Z_J    — NY zone J (NYC)
    "z26": (40.7436, -73.1673),   # NY_Z_K    — NY zone K (Long Island)
    "z27": (42.9149, -78.8922),   # NY_Z_A    — NY zone A (western NY)
    "z28": (43.0971, -77.3830),   # NY_Z_B    — NY zone B (Rochester)
    "z29": (44.5303, -75.3559),   # NY_Z_D    — NY zone D (north NY)
    "z30": (40.8791, -76.3868),   # PJM_WMAC  — PJM West Maryland/central PA
    "z31": (38.4153, -75.4760),   # PJM_EMAC  — PJM East Maryland/DE
    "z32": (38.8258, -76.6463),   # PJM_SMAC  — PJM South Maryland/DC
    "z33": (38.2274, -83.0528),   # PJM_West  — PJM western (KY/OH/WV)
    "z34": (39.4738, -79.0474),   # PJM_AP    — PJM Allegheny Power
    "z35": (41.5695, -89.3719),   # PJM_COMD  — PJM ComEd (northern IL)
    "z36": (41.1767, -82.4517),   # PJM_ATSI  — PJM AEP/ATSI (NE Ohio)
    "z37": (36.8351, -76.3144),   # PJM_Dom   — PJM Dominion (Virginia)
    "z38": (40.9829, -78.7641),   # PJM_PENE  — PJM Pennsylvania east
    "z39": (34.0655, -78.2943),   # S_VACA    — Southeast VA/Carolinas
    "z40": (37.8583, -84.3525),   # S_C_KY    — Southeast Kentucky
    "z41": (37.9156, -91.4490),   # S_D_AECI  — Assoc. Electric Cooperative (MO)
    "z42": (35.6945, -86.0384),   # S_C_TVA   — TVA Tennessee
    "z43": (31.1479, -84.7685),   # S_SOU     — Southeast south (AL/GA/MS)
    "z44": (41.5850, -96.7112),   # SPP_NEBR  — SPP Nebraska
    "z45": (38.9515, -94.1559),   # SPP_N     — SPP north (KS/MO)
    "z46": (34.2666, -94.3900),   # SPP_WEST  — SPP west (OK/AR)
    "z47": (34.5470, -103.0454),  # SPP_SPS   — SPP southwest (TX/NM panhandle)
    "z48": (45.8916, -100.5464),  # SPP_WAUE  — SPP northern (ND/SD)
    "z49": (39.5253, -122.4407),  # WEC_CALN  — CA north (PG&E north)
    "z50": (34.8060, -118.5733),  # WEC_LADW  — LA/Kern County
    "z51": (32.8628, -117.2123),  # WEC_SDGE  — San Diego
    "z52": (34.4436, -118.8904),  # WECC_SCE  — Southern CA Edison
    "z53": (46.2929, -111.6774),  # WECC_MT   — Montana
    "z54": (39.4446, -121.9205),  # WEC_BANC  — Sacramento/northern CA
    "z55": (45.2146, -114.4575),  # WECC_ID   — Idaho
    "z56": (38.9761, -115.9052),  # WECC_NNV  — Northern Nevada
    "z57": (35.9251, -114.6590),  # WECC_SNV  — Southern Nevada
    "z58": (39.6751, -111.0104),  # WECC_UT   — Utah
    "z59": (46.7724, -123.0277),  # WECC_PNW  — Pacific Northwest (WA/OR)
    "z60": (38.9107, -106.4404),  # WECC_CO   — Colorado
    "z61": (44.0361, -103.6599),  # WECC_WY   — Wyoming
    "z62": (34.3892, -114.3665),  # WECC_AZ   — Arizona
    "z63": (32.1718, -105.3246),  # WECC_NM   — New Mexico
    "z64": (33.0472, -114.7465),  # WECC_IID  — Imperial Irrigation District
}
_ZONE_COLORS: dict[str, str] = {
    "BGE":    "#0077b6",
    "PEPCO":  "#d4500a",
    "APS_MD": "#2d7a2d",
    "DPL_MD": "#7c3aed",
}


# ─────────────────────────────────────────────────────────────────────────────
# Data model
# ─────────────────────────────────────────────────────────────────────────────

@dataclass
class GTEPCaseData:
    case_path:           Path
    capacity:            pd.DataFrame = field(default_factory=pd.DataFrame)
    line_results:        pd.DataFrame = field(default_factory=pd.DataFrame)
    system_cost:         pd.DataFrame = field(default_factory=pd.DataFrame)
    power:               pd.DataFrame = field(default_factory=pd.DataFrame)
    power_flow:          pd.DataFrame = field(default_factory=pd.DataFrame)
    es_capacity:         pd.DataFrame = field(default_factory=pd.DataFrame)
    es_charge:           pd.DataFrame = field(default_factory=pd.DataFrame)
    es_discharge:        pd.DataFrame = field(default_factory=pd.DataFrame)
    curtailment:         pd.DataFrame = field(default_factory=pd.DataFrame)
    dr_power:            pd.DataFrame = field(default_factory=pd.DataFrame)
    zonedata:            pd.DataFrame = field(default_factory=pd.DataFrame)
    linedata:            pd.DataFrame = field(default_factory=pd.DataFrame)
    linedata_candidate:  pd.DataFrame = field(default_factory=pd.DataFrame)


def _read_csv(path: Path) -> pd.DataFrame:
    return pd.read_csv(path) if path.exists() else pd.DataFrame()


def load_gtep_case(case_dir_str: str) -> GTEPCaseData:
    case_dir = (_REPO_ROOT / case_dir_str).resolve()
    output_dir = case_dir / "output"

    # Locate input data folder via Settings/HOPE_model_settings.yml
    data_case_dir = case_dir
    settings = case_dir / "Settings" / "HOPE_model_settings.yml"
    if settings.exists():
        try:
            m = re.search(
                r"^\s*DataCase\s*:\s*([^\n#]+)",
                settings.read_text(encoding="utf-8"),
                flags=re.MULTILINE,
            )
            if m:
                candidate = case_dir / m.group(1).strip().strip("\"'")
                if candidate.is_dir():
                    data_case_dir = candidate
        except Exception:
            pass

    return GTEPCaseData(
        case_path          = case_dir,
        capacity           = _read_csv(output_dir / "capacity.csv"),
        line_results       = _read_csv(output_dir / "line.csv"),
        system_cost        = _read_csv(output_dir / "system_cost.csv"),
        power              = _read_csv(output_dir / "power.csv"),
        power_flow         = _read_csv(output_dir / "power_flow.csv"),
        es_capacity        = _read_csv(output_dir / "es_capacity.csv"),
        es_charge          = _read_csv(output_dir / "es_power_charge.csv"),
        es_discharge       = _read_csv(output_dir / "es_power_discharge.csv"),
        curtailment        = _read_csv(output_dir / "power_renewable_curtailment.csv"),
        dr_power           = _read_csv(output_dir / "dr_power.csv"),
        zonedata           = _read_csv(data_case_dir / "zonedata.csv"),
        linedata           = _read_csv(data_case_dir / "linedata.csv"),
        linedata_candidate = _read_csv(data_case_dir / "linedata_candidate.csv"),
    )


def _discover_gtep_cases() -> list[dict]:
    root = _REPO_ROOT / "ModelCases"
    gtep_re = re.compile(
        r"^\s*model_mode\s*:\s*['\"]?GTEP['\"]?(?:\s+#.*)?\s*$",
        re.IGNORECASE | re.MULTILINE,
    )
    options: list[dict] = []
    for case_dir in sorted(root.iterdir(), key=lambda p: p.name.lower()):
        if not case_dir.is_dir():
            continue
        settings = case_dir / "Settings" / "HOPE_model_settings.yml"
        if not settings.exists():
            continue
        if not (case_dir / "output" / "capacity.csv").exists():
            continue
        try:
            if gtep_re.search(settings.read_text(encoding="utf-8", errors="ignore")):
                rel = str(case_dir.relative_to(_REPO_ROOT)).replace("\\", "/")
                options.append({"label": case_dir.name, "value": rel})
        except Exception:
            pass
    return options


AVAILABLE_GTEP_CASES = _discover_gtep_cases()
if not any(opt["value"] == DEFAULT_GTEP_CASE for opt in AVAILABLE_GTEP_CASES):
    AVAILABLE_GTEP_CASES.insert(
        0, {"label": Path(DEFAULT_GTEP_CASE).name, "value": DEFAULT_GTEP_CASE}
    )


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

def _theme_palette(theme: str) -> dict:
    if theme == "dark":
        return {
            "bg":    "#0b1220", "card": "#121a2b", "plot": "#0f1726",
            "text":  "#e5edf7", "muted": "#9fb1c7","grid": "#243146",
        }
    return {
        "bg":    "#eef3f8", "card": "#ffffff",  "plot": "#f8fafc",
        "text":  "#0f172a", "muted": "#475569", "grid": "#d9e2ec",
    }


def _hex_to_rgba(color: str, alpha: float) -> str:
    color = (color or "").strip().lstrip("#")
    if len(color) != 6:
        return f"rgba(148, 163, 184, {alpha:.3f})"
    r, g, b = int(color[:2], 16), int(color[2:4], 16), int(color[4:], 16)
    return f"rgba({r}, {g}, {b}, {alpha:.3f})"


def _fmt_cost(val_dollars: float) -> str:
    if abs(val_dollars) >= 1e9:
        return f"${val_dollars / 1e9:.2f}B"
    if abs(val_dollars) >= 1e6:
        return f"${val_dollars / 1e6:.1f}M"
    return f"${val_dollars:,.0f}"


def _fmt_mw(mw: float) -> str:
    if mw >= 1000:
        return f"{mw / 1000:.1f} GW"
    return f"{mw:.0f} MW"


def _tech_color(tech: str) -> str:
    return TECH_COLOR.get(str(tech), "#94a3b8")


def _ordered_techs(df: pd.DataFrame, tech_col: str = "Technology") -> list[str]:
    """Return technologies in display order (baseload first, VRE last)."""
    techs_in_data = set(df[tech_col].astype(str).unique())
    ordered = [t for t in TECH_COLOR if t in techs_in_data]
    rest = sorted(techs_in_data - set(ordered))
    return ordered + rest


def _filter_zone(df: pd.DataFrame, zone: str, zone_col: str = "Zone") -> pd.DataFrame:
    if zone and zone != "All":
        return df[df[zone_col].astype(str) == zone]
    return df


def _md_zones(data: GTEPCaseData) -> list[str]:
    """Return all zones from zonedata (no centroid filter).  Falls back to centroids dict."""
    if data.zonedata.empty or "Zone_id" not in data.zonedata.columns:
        return list(_ZONE_CENTROIDS.keys())
    return data.zonedata["Zone_id"].astype(str).tolist()


def _detect_n_periods(data: GTEPCaseData) -> int:
    """Infer number of representative periods from power.csv column names."""
    if data.power.empty:
        return 4
    tcol_re = re.compile(r'^t(\d+)h\d+$')
    period_nums = [int(tcol_re.match(c).group(1)) for c in data.power.columns if tcol_re.match(c)]
    return max(period_nums) if period_nums else 4


# ─────────────────────────────────────────────────────────────────────────────
# KPI strip (toolbar)
# ─────────────────────────────────────────────────────────────────────────────

def _gtep_kpi_strip(data: GTEPCaseData) -> html.Div:
    total_cost, new_tx_mw, total_cap_fin, renewable_pct = 0.0, 0.0, 0.0, 0.0

    if not data.system_cost.empty and "Total_cost ($)" in data.system_cost.columns:
        total_cost = float(data.system_cost["Total_cost ($)"].sum())

    if not data.line_results.empty:
        nb = data.line_results[data.line_results.get("New_Build", pd.Series([0])).astype(int) == 1]
        if "Capacity (MW)" in nb.columns:
            new_tx_mw = float(nb["Capacity (MW)"].sum())

    ren_techs = {"SolarPV", "WindOn", "WindOff", "Hydro", "Bio", "Landfill_NG"}
    if not data.capacity.empty and "Capacity_FIN (MW)" in data.capacity.columns:
        cap = data.capacity.copy()
        total_cap_fin = float(cap["Capacity_FIN (MW)"].sum())

    if not data.power.empty and "AnnSum" in data.power.columns:
        total_ann = float(data.power["AnnSum"].sum())
        ren_ann   = float(data.power[data.power["Technology"].isin(ren_techs)]["AnnSum"].sum())
        if total_ann > 0:
            renewable_pct = ren_ann / total_ann * 100.0

    pills = [
        html.Span(f"Total Cost {_fmt_cost(total_cost)}", className="kpi-pill kpi-pill-hour"),
        html.Span(f"New Transmission {_fmt_mw(new_tx_mw)}", className="kpi-pill"),
        html.Span(f"Total Capacity {_fmt_mw(total_cap_fin)}", className="kpi-pill"),
        html.Span(f"Renewable {renewable_pct:.1f}%", className="kpi-pill"),
    ]
    return html.Div(pills, className="kpi-strip")


# ─────────────────────────────────────────────────────────────────────────────
# IPM zone → region mapping (from Generators_data.csv, USA_64zone case)
# ─────────────────────────────────────────────────────────────────────────────

_IPM_ZONE_MAP: dict[str, str] = {
    "z1":  "ERC_REST",  "z2":  "ERC_WEST",  "z3":  "ERC_PHDL",  "z4":  "FRCC",
    "z5":  "MIS_MAPP",  "z6":  "MIS_IL",    "z7":  "MIS_INKY",  "z8":  "MIS_IA",
    "z9":  "MIS_MIDA",  "z10": "MIS_LMI",  "z11": "MIS_MO",   "z12": "MIS_WUMS",
    "z13": "MIS_MNWI", "z14": "MIS_WOTA", "z15": "MIS_AMSO", "z16": "MIS_AR",
    "z17": "MIS_D_MS", "z18": "MIS_LA",   "z19": "NENG_CT",  "z20": "NENGREST",
    "z21": "NENG_ME",  "z22": "NY_Z_C&E", "z23": "NY_Z_F",   "z24": "NY_Z_G-I",
    "z25": "NY_Z_J",   "z26": "NY_Z_K",   "z27": "NY_Z_A",   "z28": "NY_Z_B",
    "z29": "NY_Z_D",   "z30": "PJM_WMAC", "z31": "PJM_EMAC", "z32": "PJM_SMAC",
    "z33": "PJM_West", "z34": "PJM_AP",   "z35": "PJM_COMD", "z36": "PJM_ATSI",
    "z37": "PJM_Dom",  "z38": "PJM_PENE", "z39": "S_VACA",   "z40": "S_C_KY",
    "z41": "S_D_AECI", "z42": "S_C_TVA",  "z43": "S_SOU",    "z44": "SPP_NEBR",
    "z45": "SPP_N",    "z46": "SPP_WEST", "z47": "SPP_SPS",  "z48": "SPP_WAUE",
    "z49": "WEC_CALN", "z50": "WEC_LADW", "z51": "WEC_SDGE", "z52": "WECC_SCE",
    "z53": "WECC_MT",  "z54": "WEC_BANC", "z55": "WECC_ID",  "z56": "WECC_NNV",
    "z57": "WECC_SNV", "z58": "WECC_UT",  "z59": "WECC_PNW", "z60": "WECC_CO",
    "z61": "WECC_WY",  "z62": "WECC_AZ",  "z63": "WECC_NM",  "z64": "WECC_IID",
}
_IPM_REGION_TO_ZONE: dict[str, str] = {v: k for k, v in _IPM_ZONE_MAP.items()}

# ─────────────────────────────────────────────────────────────────────────────
# IPM region boundary data — pre-converted to WGS84 (no pyproj needed at runtime)
# ─────────────────────────────────────────────────────────────────────────────

# Pre-converted WGS84 file bundled with the dashboard (coordinates already lon/lat)
_GEOJSON_WGS84 = Path(__file__).with_name("data") / "ipm_regions_wgs84.geojson"


@lru_cache(maxsize=1)
def _load_ipm_boundaries() -> dict[str, list[tuple[list[float], list[float]]]]:
    """Return {IPM_Region: [(lats, lons), ...]} in WGS84, one ring tuple per polygon ring.

    Reads from the pre-converted ipm_regions_wgs84.geojson (coordinates already in WGS84).
    Falls back to empty dict if the file is missing or malformed.
    """
    if not _GEOJSON_WGS84.exists():
        return {}
    try:
        with open(_GEOJSON_WGS84) as f:
            data = json.load(f)
    except Exception:
        return {}

    result: dict[str, list[tuple[list[float], list[float]]]] = {}
    for feat in data.get("features", []):
        name = feat["properties"].get("IPM_Region", "")
        geom = feat.get("geometry", {})
        rings_out: list[tuple[list[float], list[float]]] = []
        if geom.get("type") == "Polygon":
            ring_groups = geom["coordinates"]
        elif geom.get("type") == "MultiPolygon":
            ring_groups = [ring for poly in geom["coordinates"] for ring in poly]
        else:
            continue
        for ring in ring_groups:
            lons_r = [c[0] for c in ring]
            lats_r = [c[1] for c in ring]
            rings_out.append((lats_r, lons_r))
        if rings_out:
            result[name] = rings_out
    return result


def _geo_boundary_traces(
    zones: list[str],
    theme: str = "light",
) -> list[go.Scattergeo]:
    """Return one filled Scattergeo trace per zone polygon boundary.

    Each zone maps to an EPA IPM v6 region via _IPM_ZONE_MAP.
    MultiPolygon rings are concatenated with None separators (Plotly convention).
    """
    boundaries = _load_ipm_boundaries()
    if not boundaries:
        return []

    is_dark = theme == "dark"
    line_color = "rgba(0,0,0,0.45)" if not is_dark else "rgba(220,220,220,0.55)"

    # Which IPM regions are active for the current zone set
    active_ipm = {_IPM_ZONE_MAP[z] for z in zones if z in _IPM_ZONE_MAP}

    traces: list[go.Scattergeo] = []
    for ipm, rings in boundaries.items():
        if ipm not in active_ipm:
            continue
        # Concatenate rings with None separator (Plotly multi-ring)
        all_lats: list[float | None] = []
        all_lons: list[float | None] = []
        for lats, lons in rings:
            if all_lats:   # not the first ring
                all_lats.append(None)
                all_lons.append(None)
            all_lats.extend(lats)
            all_lons.extend(lons)
        zone_label = _IPM_REGION_TO_ZONE.get(ipm, ipm)
        traces.append(go.Scattergeo(
            lat=all_lats,
            lon=all_lons,
            mode="lines",
            line=dict(width=1.2, color=line_color),
            hoverinfo="text",
            text=f"{zone_label} ({ipm})",
            showlegend=False,
        ))
    return traces


# ── PJM utility zone boundaries ───────────────────────────────────────────────
_PJM_GEOJSON_PATH = Path(__file__).with_name("data") / "pjm_zones_simplified.geojson"


@lru_cache(maxsize=1)
def _load_pjm_boundaries() -> dict[str, list[tuple[list[float], list[float]]]]:
    """Return {zone_id: [(lats, lons), ...]} from the simplified PJM GeoJSON.

    Already in WGS84 (EPSG:4326). Each entry is the outer ring of one sub-polygon.
    Returns empty dict if the file is missing or malformed.
    """
    try:
        with open(_PJM_GEOJSON_PATH) as f:
            fc = json.load(f)
    except Exception:
        return {}

    result: dict[str, list[tuple[list[float], list[float]]]] = {}
    for feat in fc.get("features", []):
        zone = (feat.get("properties") or {}).get("zone_id")
        geom = feat.get("geometry") or {}
        if not zone or not geom:
            continue
        gtype = geom.get("type")
        coords = geom.get("coordinates", [])
        if gtype == "Polygon":
            outer_rings = [coords[0]] if coords else []
        elif gtype == "MultiPolygon":
            # Each sub-polygon is stored as [[outer_ring]] after simplification
            outer_rings = [poly[0] for poly in coords if poly]
        else:
            continue
        rings_out: list[tuple[list[float], list[float]]] = []
        for ring in outer_rings:
            lons_r = [c[0] for c in ring]
            lats_r = [c[1] for c in ring]
            rings_out.append((lats_r, lons_r))
        if rings_out:
            result.setdefault(zone, []).extend(rings_out)
    return result


def _geo_pjm_boundary_traces(
    zones: list[str],
    theme: str = "light",
) -> list[go.Scattergeo]:
    """Return Scattergeo boundary traces for active PJM utility zones.

    Uses the same fill='toself' + None-separator approach as _geo_boundary_traces
    for IPM zones — which is known to render correctly.
    """
    boundaries = _load_pjm_boundaries()
    if not boundaries:
        return []

    is_dark = theme == "dark"
    line_color = "rgba(0,0,0,0.45)" if not is_dark else "rgba(220,220,220,0.55)"

    active_zones = set(zones) & set(boundaries)
    traces: list[go.Scattergeo] = []
    for zone in sorted(active_zones):
        rings = boundaries[zone]
        if not rings:
            continue
        all_lats: list[float | None] = []
        all_lons: list[float | None] = []
        for lats, lons in rings:
            if len(lats) < 4:
                continue
            if all_lats:
                all_lats.append(None)
                all_lons.append(None)
            all_lats.extend(lats)
            all_lons.extend(lons)
        if not all_lats:
            continue
        traces.append(go.Scattergeo(
            lat=all_lats,
            lon=all_lons,
            mode="lines",
            line=dict(width=1.2, color=line_color),
            hoverinfo="text",
            text=zone,
            showlegend=False,
        ))
    return traces


# ─────────────────────────────────────────────────────────────────────────────
# Geo pie-chart helpers
# ─────────────────────────────────────────────────────────────────────────────

def _arc_polygon(
    center_lat: float,
    center_lon: float,
    radius_deg: float,
    start_angle: float,
    end_angle: float,
    n_points: int = 24,
) -> tuple[list[float], list[float]]:
    """Return (lats, lons) for a closed pie-slice polygon.

    Angles are measured clockwise from north (0 = top/north, π/2 = east).
    The polygon goes: center → arc from start to end → back to center.
    lon offsets are divided by cos(lat) so the slice looks circular on the map.
    """
    cos_lat = max(math.cos(math.radians(center_lat)), 0.15)
    lats = [center_lat]
    lons = [center_lon]
    for i in range(n_points + 1):
        theta = start_angle + (end_angle - start_angle) * i / n_points
        lats.append(center_lat + radius_deg * math.cos(theta))
        lons.append(center_lon + radius_deg * math.sin(theta) / cos_lat)
    lats.append(center_lat)
    lons.append(center_lon)
    return lats, lons


def _geo_pie_traces(
    cap_df: pd.DataFrame,
    zones: list[str],
    hidden: set[str],
    new_only: bool,
    theme: str,
    pie_scale: float = 1.0,
) -> list[go.Scattergeo]:
    """Build one Scattergeo pie-slice trace per (zone, tech) for the expansion map.

    Radius scales with sqrt(zone_total / system_max) so large zones get bigger pies.
    """
    if cap_df.empty or pie_scale == 0:
        return []

    work = cap_df.copy()
    work["Technology"] = work["Technology"].astype(str)
    work["Zone"] = work["Zone"].astype(str)
    work["Capacity_FIN (MW)"] = pd.to_numeric(work["Capacity_FIN (MW)"], errors="coerce").fillna(0.0)
    if new_only:
        work = work[work["New_Build"].astype(int) == 1]
    work = work[work["Capacity_FIN (MW)"] > 0.01]

    cap_by_zone: dict[str, float] = work.groupby("Zone")["Capacity_FIN (MW)"].sum().to_dict()
    visible_zones = [z for z in zones if z not in hidden and z in _ZONE_CENTROIDS]
    visible_caps = [cap_by_zone.get(z, 0.0) for z in visible_zones]
    max_cap = max(visible_caps, default=1.0)
    max_cap = max(max_cap, 1.0)
    n_visible = max(len(visible_zones), 1)
    # Scale max radius down as zone count grows so pies don't overlap
    max_radius = max(0.25, min(0.8, 4.5 / math.sqrt(n_visible))) * max(0.1, pie_scale)

    traces: list[go.Scattergeo] = []
    seen_techs: set[str] = set()

    for z in zones:
        if z in hidden or z not in _ZONE_CENTROIDS:
            continue
        total = cap_by_zone.get(z, 0.0)
        if total < 1.0:
            continue

        center_lat, center_lon = _ZONE_CENTROIDS[z]
        radius = max(0.12, max_radius * math.sqrt(total / max_cap))

        zone_cap = (
            work[work["Zone"] == z]
            .groupby("Technology")["Capacity_FIN (MW)"]
            .sum()
        )
        zone_cap = zone_cap[zone_cap > 0.01]
        if zone_cap.empty:
            continue
        zone_total = float(zone_cap.sum())

        # Order techs consistently (baseload first, VRE last; unknown alphabetical at end)
        techs_ordered = [t for t in TECH_COLOR if t in zone_cap.index]
        techs_ordered += sorted(t for t in zone_cap.index if t not in TECH_COLOR)

        cum_angle = 0.0   # start at north (12 o'clock), clockwise
        for tech in techs_ordered:
            mw = float(zone_cap[tech])
            frac = mw / zone_total
            end_angle = cum_angle + frac * 2.0 * math.pi

            lats, lons = _arc_polygon(center_lat, center_lon, radius, cum_angle, end_angle)
            color = _tech_color(tech)
            is_first = tech not in seen_techs
            if is_first:
                seen_techs.add(tech)

            traces.append(go.Scattergeo(
                lat=lats,
                lon=lons,
                fill="toself",
                fillcolor=color,
                mode="lines",
                line=dict(width=0.5, color="rgba(255,255,255,0.7)"),
                name=tech,
                legendgroup=tech,
                showlegend=is_first,
                hoverinfo="text",
                text=(
                    f"<b>{z}</b> — {tech}<br>"
                    f"{mw:.0f} MW ({frac * 100:.1f}%)<br>"
                    f"Zone total: {zone_total:.0f} MW"
                ),
            ))
            cum_angle = end_angle

    return traces


# ─────────────────────────────────────────────────────────────────────────────
# Panel A — Expansion Map
# ─────────────────────────────────────────────────────────────────────────────

def _map_figure(
    data: GTEPCaseData,
    overlay: str = "total_cap",
    hidden_zones: list[str] | None = None,
    theme: str = "light",
    show_lines: list[str] | None = None,
    pie_scale: float = 1.0,
    show_boundaries: bool = True,
) -> go.Figure:
    palette  = _theme_palette(theme)
    hidden   = set(hidden_zones or [])
    _show_lines = set(show_lines if show_lines is not None else ["existing", "new"])
    fig      = go.Figure()

    zones    = _md_zones(data)

    # ── IPM zone background fills (drawn first, behind everything) ─────────────
    if show_boundaries:
        for t in _geo_boundary_traces(zones, theme):
            fig.add_trace(t)
        # PJM utility zone boundaries (drawn right after IPM — behind pies)
        for t in _geo_pjm_boundary_traces(zones, theme):
            fig.add_trace(t)

    cap_by_zone: dict[str, float] = {}
    if not data.capacity.empty and "Capacity_FIN (MW)" in data.capacity.columns:
        for z, grp in data.capacity.groupby("Zone"):
            cap_by_zone[str(z)] = float(grp["Capacity_FIN (MW)"].sum())

    inv_by_zone: dict[str, float] = {}
    if not data.system_cost.empty and "Inv_cost ($)" in data.system_cost.columns:
        for _, row in data.system_cost.iterrows():
            inv_by_zone[str(row["Zone"])] = float(row["Inv_cost ($)"])

    new_cap_by_zone: dict[str, float] = {}
    if not data.capacity.empty and "Capacity_FIN (MW)" in data.capacity.columns:
        nb = data.capacity[data.capacity.get("New_Build", pd.Series([0])).astype(int) == 1]
        for z, grp in nb.groupby("Zone"):
            new_cap_by_zone[str(z)] = float(grp["Capacity_FIN (MW)"].sum())

    total_cost_by_zone: dict[str, float] = {}
    if not data.system_cost.empty and "Total_cost ($)" in data.system_cost.columns:
        for _, row in data.system_cost.iterrows():
            total_cost_by_zone[str(row["Zone"])] = float(row["Total_cost ($)"])

    # ── Existing transmission lines ───────────────────────────────────────────
    existing_lines_drawn: set[tuple] = set()
    if "existing" in _show_lines and not data.linedata.empty:
        for _, row in data.linedata.iterrows():
            fz, tz = str(row.get("From_zone", "")), str(row.get("To_zone", ""))
            if fz not in _ZONE_CENTROIDS or tz not in _ZONE_CENTROIDS:
                continue
            key = tuple(sorted([fz, tz]))
            if key in existing_lines_drawn:
                continue
            existing_lines_drawn.add(key)
            lat_f, lon_f = _ZONE_CENTROIDS[fz]
            lat_t, lon_t = _ZONE_CENTROIDS[tz]
            cap = float(row.get("Capacity (MW)", 0))
            fig.add_trace(go.Scattergeo(
                lat=[lat_f, lat_t, None],
                lon=[lon_f, lon_t, None],
                mode="lines",
                line=dict(width=1.8, color="#94a3b8"),
                hoverinfo="text",
                text=f"{fz}→{tz}<br>Existing: {cap:.0f} MW",
                legendgroup="existing_line",
                showlegend=False,
            ))

    # ── New transmission lines (results) ─────────────────────────────────────
    if "new" in _show_lines and not data.line_results.empty:
        new_lines = data.line_results[
            data.line_results.get("New_Build", pd.Series([0])).astype(int) == 1
        ]
        for _, row in new_lines.iterrows():
            fz = str(row.get("From_zone", ""))
            tz = str(row.get("To_zone", ""))
            if fz not in _ZONE_CENTROIDS or tz not in _ZONE_CENTROIDS:
                continue
            cap = float(row.get("Capacity (MW)", 0))
            if cap < 1.0:
                continue
            lat_f, lon_f = _ZONE_CENTROIDS[fz]
            lat_t, lon_t = _ZONE_CENTROIDS[tz]
            fig.add_trace(go.Scattergeo(
                lat=[lat_f, lat_t, None],
                lon=[lon_f, lon_t, None],
                mode="lines",
                line=dict(width=1.8, color="#f97316"),
                hoverinfo="text",
                text=f"NEW: {fz}→{tz}<br>{cap:.0f} MW",
                legendgroup="new_line",
                showlegend=False,
            ))
            # Label at midpoint
            mid_lat = (lat_f + lat_t) / 2.0
            mid_lon = (lon_f + lon_t) / 2.0
            fig.add_trace(go.Scattergeo(
                lat=[mid_lat],
                lon=[mid_lon],
                mode="text",
                text=[f"+{cap:.0f} MW"],
                textfont=dict(size=10, color="#f97316"),
                hoverinfo="skip",
                legendgroup="new_line",
                showlegend=False,
            ))

    # ── Zone visualization — pie charts (capacity) or bubbles (cost) ─────────
    if overlay in ("total_cap", "new_cap"):
        pie_traces = _geo_pie_traces(
            data.capacity,
            zones,
            hidden,
            new_only=(overlay == "new_cap"),
            theme=theme,
            pie_scale=pie_scale,
        )
        for t in pie_traces:
            fig.add_trace(t)

        # Zone labels at each centroid
        label_lat, label_lon, label_ids = [], [], []
        for z in zones:
            if z in hidden or z not in _ZONE_CENTROIDS:
                continue
            lat, lon = _ZONE_CENTROIDS[z]
            label_lat.append(lat)
            label_lon.append(lon)
            label_ids.append(z)
        if label_lat:
            fig.add_trace(go.Scattergeo(
                lat=label_lat,
                lon=label_lon,
                mode="text",
                text=label_ids,
                textfont=dict(size=10, color=palette["text"]),
                textposition="top center",
                hoverinfo="skip",
                showlegend=False,
            ))
    else:
        # ── Bubble visualization for cost overlays ────────────────────────────
        bubble_lat, bubble_lon, bubble_size, bubble_color = [], [], [], []
        bubble_text, bubble_ids = [], []

        for z in zones:
            if z in hidden or z not in _ZONE_CENTROIDS:
                continue
            lat, lon = _ZONE_CENTROIDS[z]

            if overlay == "total_cost":
                raw_val = total_cost_by_zone.get(z, 0.0) / 1e6
            else:  # inv_cost
                raw_val = inv_by_zone.get(z, 0.0) / 1e6

            size = max(12.0, min(60.0, (cap_by_zone.get(z, 1000.0) / 1000.0) * 14.0))
            bubble_lat.append(lat)
            bubble_lon.append(lon)
            bubble_size.append(size)
            bubble_color.append(raw_val)
            bubble_ids.append(z)

            total = cap_by_zone.get(z, 0.0)
            new   = new_cap_by_zone.get(z, 0.0)
            cost  = total_cost_by_zone.get(z, 0.0)
            inv   = inv_by_zone.get(z, 0.0)
            bubble_text.append(
                f"<b>{z}</b><br>"
                f"Total capacity: {_fmt_mw(total)}<br>"
                f"New capacity: {_fmt_mw(new)}<br>"
                f"Total cost: {_fmt_cost(cost)}<br>"
                f"Investment: {_fmt_cost(inv)}"
            )

        overlay_label = {
            "total_cost": "Total Cost ($M)",
            "inv_cost":   "Inv Cost ($M)",
        }.get(overlay, "")

        if bubble_lat:
            arr = np.array(bubble_color, dtype=float)
            cmin, cmax = float(arr.min()), float(arr.max())
            if cmin == cmax:
                cmax = cmin + 1.0
            fig.add_trace(go.Scattergeo(
                lat=bubble_lat,
                lon=bubble_lon,
                mode="markers",
                marker=dict(
                    size=bubble_size,
                    color=bubble_color,
                    colorscale="Oranges",
                    cmin=cmin,
                    cmax=cmax,
                    colorbar=dict(
                        title=overlay_label,
                        thickness=10,
                        len=0.55,
                        y=0.5,
                        x=1.0,
                        xanchor="left",
                        outlinewidth=0,
                    ),
                    line=dict(width=1.5, color="rgba(255,255,255,0.8)"),
                ),
                hoverinfo="text",
                hovertext=bubble_text,
                showlegend=False,
            ))
            fig.add_trace(go.Scattergeo(
                lat=bubble_lat,
                lon=bubble_lon,
                mode="text",
                text=bubble_ids,
                textfont=dict(size=10, color=palette["text"]),
                textposition="top center",
                hoverinfo="skip",
                showlegend=False,
            ))

    # ── Line legend markers (grouped with real traces so legend-click toggles all) ─
    if "new" in _show_lines:
        fig.add_trace(go.Scattergeo(
            lat=[None], lon=[None], mode="lines",
            line=dict(width=4, color="#f97316"),
            name="New transmission",
            legendgroup="new_line",
            showlegend=True,
        ))
    if "existing" in _show_lines:
        fig.add_trace(go.Scattergeo(
            lat=[None], lon=[None], mode="lines",
            line=dict(width=1.8, color="#94a3b8"),
            name="Existing line",
            legendgroup="existing_line",
            showlegend=True,
        ))

    fig.update_layout(
        autosize=True,
        margin=dict(l=2, r=56, t=2, b=2),
        paper_bgcolor=palette["card"],
        font=dict(family=APP_FONT, size=12, color=palette["text"]),
        legend=dict(
            orientation="h", yanchor="bottom", y=0.02,
            xanchor="left", x=0.02,
            bgcolor="rgba(255,255,255,0.7)", borderwidth=0,
        ),
        uirevision=f"{overlay}:{theme}",
        geo=dict(
            projection_type="albers usa",
            bgcolor=palette["card"],
            showframe=False,
            showland=True,
            landcolor="#e6ebf2" if theme != "dark" else "#131b2b",
            showlakes=True,
            lakecolor="#c8dff0" if theme != "dark" else "#1a2a40",
            showcountries=False,
            showcoastlines=True,
            coastlinecolor="#8fa7bf" if theme != "dark" else "#2d4a66",
            showsubunits=True,
            subunitcolor="#8fa7bf" if theme != "dark" else "#2d4a66",
            subunitwidth=1.2,
        ),
    )
    return fig


# ─────────────────────────────────────────────────────────────────────────────
# Panel B — Capacity Mix
# ─────────────────────────────────────────────────────────────────────────────

def _capacity_figure(
    data: GTEPCaseData,
    zone_filter: str = "All",
    show_new_only: bool = False,
    theme: str = "light",
) -> go.Figure:
    palette = _theme_palette(theme)
    if data.capacity.empty:
        return go.Figure()

    cap = data.capacity.copy()
    cap["Technology"]       = cap["Technology"].astype(str)
    cap["Zone"]             = cap["Zone"].astype(str)

    if zone_filter and zone_filter != "All":
        cap = cap[cap["Zone"] == zone_filter]

    # Only keep rows with some final capacity
    cap = cap[cap["Capacity_FIN (MW)"] > 0.01]

    zones = sorted(cap["Zone"].unique())
    techs = _ordered_techs(cap)

    fig = go.Figure()

    for tech in techs:
        t_data = cap[cap["Technology"] == tech]
        if t_data.empty:
            continue
        color = _tech_color(tech)

        # Existing (New_Build=0)
        ex = t_data[t_data["New_Build"].astype(int) == 0]
        ex_y = [float(ex[ex["Zone"] == z]["Capacity_FIN (MW)"].sum()) for z in zones]
        if any(v > 0 for v in ex_y) and not show_new_only:
            fig.add_trace(go.Bar(
                name=tech,
                x=zones,
                y=ex_y,
                marker_color=color,
                legendgroup=tech,
                showlegend=True,
                hovertemplate=f"<b>{tech}</b> (existing)<br>%{{x}}: %{{y:.1f}} MW<extra></extra>",
            ))

        # New build (New_Build=1)
        nb = t_data[t_data["New_Build"].astype(int) == 1]
        nb_y = [float(nb[nb["Zone"] == z]["Capacity_FIN (MW)"].sum()) for z in zones]
        if any(v > 0 for v in nb_y):
            fig.add_trace(go.Bar(
                name=f"{tech} (new)",
                x=zones,
                y=nb_y,
                marker=dict(
                    color=color,
                    opacity=0.55,
                    line=dict(color=color, width=2),
                    pattern=dict(shape="/", fgcolor=color, bgcolor="rgba(255,255,255,0.4)"),
                ),
                legendgroup=tech,
                showlegend=False,
                hovertemplate=f"<b>{tech} (NEW BUILD)</b><br>%{{x}}: %{{y:.1f}} MW<extra></extra>",
            ))

    fig.update_layout(
        barmode="stack",
        autosize=True,
        margin=dict(l=40, r=16, t=28, b=60),
        paper_bgcolor=palette["card"],
        plot_bgcolor=palette["plot"],
        font=dict(family=APP_FONT, size=12, color=palette["text"]),
        legend=dict(
            orientation="v",
            yanchor="top", y=1.0,
            xanchor="left", x=1.02,
            font=dict(size=10),
        ),
        xaxis=dict(
            title="Zone",
            gridcolor=palette["grid"],
            tickfont=dict(size=11),
        ),
        yaxis=dict(
            title="Capacity (MW)",
            gridcolor=palette["grid"],
            zerolinecolor=palette["grid"],
        ),
        title=dict(
            text="Final Installed Capacity by Zone",
            font=dict(size=13),
            x=0.0,
            xanchor="left",
        ),
    )
    return fig


# ─────────────────────────────────────────────────────────────────────────────
# Panel C — Dispatch Profile (stacked area, charge on –y)
# ─────────────────────────────────────────────────────────────────────────────

def _dispatch_figure(
    data: GTEPCaseData,
    zone_filter: str = "All",
    period_filter: str = "All",
    theme: str = "light",
) -> go.Figure:
    palette = _theme_palette(theme)
    fig     = go.Figure()

    # ── Detect time-step columns dynamically ─────────────────────────────────
    _tcol_re = re.compile(r'^t(\d+)h(\d+)$')
    if not data.power.empty:
        power_tcols = sorted(
            [c for c in data.power.columns if _tcol_re.match(c)],
            key=lambda c: (int(_tcol_re.match(c).group(1)), int(_tcol_re.match(c).group(2))),
        )
    else:
        power_tcols = []
    n_steps   = len(power_tcols)
    n_periods = n_steps // 24 if n_steps >= 24 else max(1, n_steps)

    # ── Period slicing ────────────────────────────────────────────────────────
    pnum_m = re.match(r'^P(\d+)$', period_filter or "All")
    if pnum_m:
        pnum             = int(pnum_m.group(1))
        sel_power_tcols  = [c for c in power_tcols if _tcol_re.match(c).group(1) == str(pnum)]
        x_slice          = list(range((pnum - 1) * 24 + 1, pnum * 24 + 1))
    else:
        sel_power_tcols  = power_tcols
        x_slice          = list(range(1, n_steps + 1))

    # Derive storage/DR column lists from selected power tcols
    sel_dischr_tcols = [f"dc_{c}" for c in sel_power_tcols]
    sel_charge_tcols = [f"c_{c}"  for c in sel_power_tcols]
    sel_dr_tcols     = [f"dr_{c}" for c in sel_power_tcols]

    # ── Positive: generation ──────────────────────────────────────────────────
    if not data.power.empty:
        for tech in _ordered_techs(data.power):
            t_rows = data.power[data.power["Technology"].astype(str) == tech]
            if zone_filter != "All":
                t_rows = t_rows[t_rows["Zone"].astype(str) == zone_filter]
            available = [c for c in sel_power_tcols if c in t_rows.columns]
            if t_rows.empty or not available:
                continue
            y = t_rows[available].fillna(0.0).sum(axis=0).to_numpy(dtype=float)
            if y.sum() < 1.0:
                continue
            color = _tech_color(tech)
            fig.add_trace(go.Scatter(
                x=x_slice[:len(y)],
                y=y,
                mode="lines",
                stackgroup="positive",
                name=tech,
                legendgroup=tech,
                line=dict(width=0.5, color=color),
                fillcolor=_hex_to_rgba(color, 0.85),
                hovertemplate=f"<b>{tech}</b><br>Step %{{x}}: %{{y:.1f}} MW<extra></extra>",
            ))

    # ── Positive: storage discharge ───────────────────────────────────────────
    if not data.es_discharge.empty:
        for tech in data.es_discharge["Technology"].astype(str).unique():
            t_rows = data.es_discharge[data.es_discharge["Technology"].astype(str) == tech]
            if zone_filter != "All":
                t_rows = t_rows[t_rows["Zone"].astype(str) == zone_filter]
            available = [c for c in sel_dischr_tcols if c in t_rows.columns]
            if t_rows.empty or not available:
                continue
            y = t_rows[available].fillna(0.0).sum(axis=0).to_numpy(dtype=float)
            if y.sum() < 0.1:
                continue
            label = f"{tech} (discharge)"
            color = _tech_color(tech)
            fig.add_trace(go.Scatter(
                x=x_slice[:len(y)],
                y=y,
                mode="lines",
                stackgroup="positive",
                name=label,
                legendgroup=tech,
                showlegend=False,
                line=dict(width=0.5, color=color),
                fillcolor=_hex_to_rgba(color, 0.5),
                hovertemplate=f"<b>{label}</b><br>Step %{{x}}: %{{y:.1f}} MW<extra></extra>",
            ))

    # ── Positive: demand response ─────────────────────────────────────────────
    if not data.dr_power.empty:
        dr_col = "Zone" if "Zone" in data.dr_power.columns else (
            "Zone_id" if "Zone_id" in data.dr_power.columns else None
        )
        for tech in data.dr_power["Technology"].astype(str).unique():
            t_rows = data.dr_power[data.dr_power["Technology"].astype(str) == tech]
            if zone_filter != "All" and dr_col:
                t_rows = t_rows[t_rows[dr_col].astype(str) == zone_filter]
            available = [c for c in sel_dr_tcols if c in t_rows.columns]
            if t_rows.empty or not available:
                continue
            y = t_rows[available].fillna(0.0).sum(axis=0).to_numpy(dtype=float)
            if y.sum() < 0.1:
                continue
            color = _tech_color(tech)
            fig.add_trace(go.Scatter(
                x=x_slice[:len(y)],
                y=y,
                mode="lines",
                stackgroup="positive",
                name=f"DR: {tech}",
                line=dict(width=0.5, color=color),
                fillcolor=_hex_to_rgba(color, 0.7),
                hovertemplate=f"<b>DR: {tech}</b><br>Step %{{x}}: %{{y:.1f}} MW<extra></extra>",
            ))

    # ── Negative: storage charging ────────────────────────────────────────────
    if not data.es_charge.empty:
        for tech in data.es_charge["Technology"].astype(str).unique():
            t_rows = data.es_charge[data.es_charge["Technology"].astype(str) == tech]
            if zone_filter != "All":
                t_rows = t_rows[t_rows["Zone"].astype(str) == zone_filter]
            available = [c for c in sel_charge_tcols if c in t_rows.columns]
            if t_rows.empty or not available:
                continue
            y = -t_rows[available].fillna(0.0).sum(axis=0).to_numpy(dtype=float)
            if abs(y).sum() < 0.1:
                continue
            color = _tech_color(tech)
            fig.add_trace(go.Scatter(
                x=x_slice[:len(y)],
                y=y,
                mode="lines",
                stackgroup="negative",
                name=f"{tech} (charge)",
                legendgroup=tech,
                showlegend=False,
                line=dict(width=0.5, color=color),
                fillcolor=_hex_to_rgba(color, 0.4),
                hovertemplate=f"<b>{tech} charge</b><br>Step %{{x}}: %{{y:.1f}} MW<extra></extra>",
            ))

    # ── Period separator lines ────────────────────────────────────────────────
    if period_filter == "All":
        for p in range(1, n_periods):
            fig.add_vline(
                x=p * 24 + 0.5,
                line_dash="dash",
                line_color=palette["muted"],
                line_width=1,
                annotation_text=f"P{p + 1}",
                annotation_position="top",
                annotation_font_size=9,
                annotation_font_color=palette["muted"],
            )

    zone_label = "" if zone_filter == "All" else f" — {zone_filter}"
    tickvals = list(range(1, n_steps + 1, 24)) if period_filter == "All" else None
    ticktext = [f"P{p + 1}" for p in range(n_periods)] if period_filter == "All" else None

    fig.update_layout(
        autosize=True,
        margin=dict(l=50, r=16, t=32, b=50),
        paper_bgcolor=palette["card"],
        plot_bgcolor=palette["plot"],
        font=dict(family=APP_FONT, size=12, color=palette["text"]),
        legend=dict(
            orientation="v",
            yanchor="top", y=1.0,
            xanchor="left", x=1.02,
            font=dict(size=10),
        ),
        hovermode="x unified",
        title=dict(
            text=f"Dispatch Profile{zone_label}",
            font=dict(size=13),
            x=0.0, xanchor="left",
        ),
        xaxis=dict(
            title="Representative-period hour",
            gridcolor=palette["grid"],
            tickmode="array" if tickvals else "auto",
            tickvals=tickvals,
            ticktext=ticktext,
        ),
        yaxis=dict(
            title="Power (MW)",
            gridcolor=palette["grid"],
            zerolinecolor=palette["text"],
            zerolinewidth=1.5,
        ),
    )
    return fig


# ─────────────────────────────────────────────────────────────────────────────
# Panel D — System Cost Breakdown
# ─────────────────────────────────────────────────────────────────────────────

def _cost_figure(data: GTEPCaseData, theme: str = "light") -> go.Figure:
    palette = _theme_palette(theme)
    if data.system_cost.empty:
        return go.Figure()

    cost = data.system_cost.copy()
    cost = cost[cost[["Inv_cost ($)", "Opr_cost ($)"]].sum(axis=1) > 0]
    if cost.empty:
        return go.Figure()

    zones  = cost["Zone"].astype(str).tolist()
    inv    = (cost["Inv_cost ($)"].fillna(0.0) / 1e6).tolist()
    opr    = (cost["Opr_cost ($)"].fillna(0.0) / 1e6).tolist()
    lol    = (cost["LoL_plt ($)"].fillna(0.0)  / 1e6).tolist() if "LoL_plt ($)" in cost.columns else [0.0] * len(zones)

    fig = go.Figure()
    fig.add_trace(go.Bar(
        name="Investment",
        y=zones, x=inv,
        orientation="h",
        marker_color="#2563eb",
        hovertemplate="<b>Inv</b> %{y}: $%{x:.1f}M<extra></extra>",
    ))
    fig.add_trace(go.Bar(
        name="Operation",
        y=zones, x=opr,
        orientation="h",
        marker_color="#f59e0b",
        hovertemplate="<b>Opr</b> %{y}: $%{x:.1f}M<extra></extra>",
    ))
    if any(v > 0 for v in lol):
        fig.add_trace(go.Bar(
            name="Loss of Load",
            y=zones, x=lol,
            orientation="h",
            marker_color="#ef4444",
            hovertemplate="<b>LoL</b> %{y}: $%{x:.1f}M<extra></extra>",
        ))

    total = sum(inv) + sum(opr) + sum(lol)
    fig.update_layout(
        barmode="stack",
        autosize=True,
        margin=dict(l=70, r=16, t=32, b=50),
        paper_bgcolor=palette["card"],
        plot_bgcolor=palette["plot"],
        font=dict(family=APP_FONT, size=12, color=palette["text"]),
        legend=dict(orientation="h", yanchor="bottom", y=-0.25, xanchor="left", x=0.0, font=dict(size=11)),
        title=dict(
            text=f"System Cost by Zone  (Total: {_fmt_cost(total * 1e6)})",
            font=dict(size=13),
            x=0.0, xanchor="left",
        ),
        xaxis=dict(
            title="Cost ($M)",
            gridcolor=palette["grid"],
            zerolinecolor=palette["grid"],
        ),
        yaxis=dict(
            gridcolor=palette["grid"],
        ),
    )
    return fig


# ─────────────────────────────────────────────────────────────────────────────
# Chrome sidebar content
# ─────────────────────────────────────────────────────────────────────────────

def _chrome_section(label: str, *children) -> html.Div:
    return html.Div(
        [html.Span(label, className="map-ctrl-section-label"), *children],
        className="map-ctrl-section",
    )


def _chrome_sidebar(zones: list[str], n_periods: int = 4) -> html.Div:
    zone_options = [{"label": "All Zones", "value": "All"}] + [
        {"label": z, "value": z} for z in zones
    ]
    overlay_opts = [
        {"label": "Total Capacity (MW)",     "value": "total_cap"},
        {"label": "New Capacity Added (MW)", "value": "new_cap"},
        {"label": "System Cost ($M)",        "value": "total_cost"},
        {"label": "Investment Cost ($M)",    "value": "inv_cost"},
    ]
    period_opts = [{"label": "All periods", "value": "All"}] + [
        {"label": f"Period {i}", "value": f"P{i}"} for i in range(1, n_periods + 1)
    ]
    return html.Div(
        [
            _chrome_section(
                "Map Overlay",
                dcc.RadioItems(
                    id="gtep-map-overlay",
                    options=overlay_opts,
                    value="total_cap",
                    className="toolbar-checklist",
                    inputClassName="toolbar-checklist-input",
                    labelClassName="toolbar-checklist-label",
                ),
            ),
            html.Hr(style={"borderColor": "var(--hope-border)", "margin": "8px 0"}),
            _chrome_section(
                "Zone Filter",
                dcc.Dropdown(
                    id="gtep-zone-filter",
                    options=zone_options,
                    value="All",
                    clearable=False,
                    className="map-ctrl-dropdown",
                ),
            ),
            html.Hr(style={"borderColor": "var(--hope-border)", "margin": "8px 0"}),
            _chrome_section(
                "Dispatch Period",
                dcc.Dropdown(
                    id="gtep-period-filter",
                    options=period_opts,
                    value="All",
                    clearable=False,
                    className="map-ctrl-dropdown",
                ),
            ),
            html.Hr(style={"borderColor": "var(--hope-border)", "margin": "8px 0"}),
            _chrome_section(
                "Options",
                dcc.Checklist(
                    id="gtep-options",
                    options=[
                        {"label": "New builds only (capacity)", "value": "new_only"},
                    ],
                    value=[],
                    className="toolbar-checklist",
                    inputClassName="toolbar-checklist-input",
                    labelClassName="toolbar-checklist-label",
                ),
            ),
            html.Hr(style={"borderColor": "var(--hope-border)", "margin": "8px 0"}),
            _chrome_section(
                "Transmission Lines",
                dcc.Checklist(
                    id="gtep-show-lines",
                    options=[
                        {"label": "Existing lines", "value": "existing"},
                        {"label": "New lines", "value": "new"},
                        {"label": "Zone boundaries", "value": "boundaries"},
                    ],
                    value=["existing", "new", "boundaries"],
                    className="toolbar-checklist",
                    inputClassName="toolbar-checklist-input",
                    labelClassName="toolbar-checklist-label",
                ),
            ),
            html.Hr(style={"borderColor": "var(--hope-border)", "margin": "8px 0"}),
            _chrome_section(
                "Pie Chart Size",
                dcc.Slider(
                    id="gtep-pie-scale",
                    min=0,
                    max=4.0,
                    step=None,
                    marks={
                        0: "0",
                        0.25: "¼×", 0.5: "½×",
                        1.0: "1×", 1.5: "",
                        2.0: "2×", 2.5: "",
                        3.0: "3×", 3.5: "",
                        4.0: "4×",
                    },
                    value=1.0,
                    tooltip={"placement": "bottom", "always_visible": False},
                ),
            ),
        ],
        className="map-panel-chrome",
        style={"minWidth": "220px", "maxWidth": "260px"},
    )


# ─────────────────────────────────────────────────────────────────────────────
# App
# ─────────────────────────────────────────────────────────────────────────────

app = Dash(
    __name__,
    assets_folder=str(Path(__file__).with_name("assets")),
    title="HOPE Dashboard: GTEP Expansion Planning Results",
)

# Load default case on startup
_default_data = load_gtep_case(DEFAULT_GTEP_CASE)
_default_zones = _md_zones(_default_data)
_default_n_periods = _detect_n_periods(_default_data)

app.layout = html.Div(
    [
        # ── Toolbar ───────────────────────────────────────────────────────────
        html.Div(
            [
                html.Div(
                    [
                        html.Div(
                            [
                                html.H2(
                                    "HOPE Dashboard: GTEP Expansion Planning Results",
                                    style={"margin": "0", "fontWeight": 850, "letterSpacing": "0.1px"},
                                ),
                                html.Div(
                                    "Capacity & transmission expansion planning — zonal capacity mix, dispatch profile, cost breakdown.",
                                    className="dashboard-subtitle",
                                ),
                            ],
                            className="dashboard-header-copy",
                        ),
                    ],
                    className="dashboard-header-row",
                ),
                html.Div(
                    [
                        dcc.Dropdown(
                            id="gtep-case-path",
                            options=AVAILABLE_GTEP_CASES,
                            value=DEFAULT_GTEP_CASE,
                            clearable=False,
                            className="hope-case-dropdown",
                            style={"width": "400px"},
                        ),
                        html.Button(
                            "Load Case",
                            id="gtep-load-case",
                            n_clicks=0,
                            className="hope-button hope-button-primary",
                        ),
                        html.Div(
                            [
                                html.Button(
                                    "+ Case Path",
                                    id="gtep-custom-case-toggle",
                                    n_clicks=0,
                                    className="hope-button hope-button-secondary toolbar-action-button",
                                    title="Add a custom local case directory path",
                                ),
                                html.Button(
                                    "Help",
                                    id="gtep-help-toggle",
                                    n_clicks=0,
                                    className="hope-button hope-button-secondary toolbar-action-button",
                                ),
                                html.Button(
                                    "Dark Mode",
                                    id="gtep-theme-toggle",
                                    n_clicks=0,
                                    className="hope-button hope-button-secondary toolbar-action-button",
                                ),
                            ],
                            className="toolbar-action-stack",
                        ),
                    ],
                    className="toolbar-row toolbar-row-top",
                    style={"paddingRight": "160px"},
                ),
                # KPI strip
                html.Div(id="gtep-kpi-strip", className="kpi-strip"),
            ],
            className="dashboard-toolbar",
            style={"padding": "14px 20px 10px"},
        ),

        # ── Custom case path input panel ──────────────────────────────────────
        html.Div(
            [
                html.Span(
                    "Enter the absolute path to any HOPE GTEP case directory:",
                    style={"fontSize": "13px", "color": "var(--hope-muted)", "marginBottom": "8px", "display": "block"},
                ),
                html.Div(
                    [
                        dcc.Input(
                            id="gtep-custom-case-input",
                            type="text",
                            placeholder="e.g. C:/Users/you/MyCase  or  /home/you/MyCase",
                            debounce=False,
                            className="hope-text-input custom-case-text-input",
                        ),
                        html.Button(
                            "Add Case",
                            id="gtep-add-custom-case",
                            n_clicks=0,
                            className="hope-button hope-button-primary",
                        ),
                    ],
                    className="custom-case-input-row",
                ),
                html.Div(id="gtep-custom-case-status", className="custom-case-status"),
            ],
            id="gtep-custom-case-panel",
            className="custom-case-panel",
            style={"display": "none", "padding": "10px 20px 8px"},
        ),

        # ── Help panel ────────────────────────────────────────────────────────
        html.Div(
            [
                html.P(
                    "Use the GTEP dashboard to explore capacity expansion results: choose an overlay, filter by zone, and compare capacity mix and costs.",
                    className="dashboard-help-intro",
                ),
                html.Ul(
                    [
                        html.Li([html.B("Loading a case: "), "Select a case from the dropdown and click Load Case. To load a case not in the list, click + Case Path and enter its absolute directory path."]),
                        html.Li([html.B("Map Overlay: "), "Switch between Total Capacity, New Capacity Added, System Cost, and Investment Cost bubble overlays."]),
                        html.Li([html.B("Zone Filter: "), "Filter the Capacity Mix and Dispatch charts to a single zone."]),
                        html.Li([html.B("Dispatch Period: "), "Filter the dispatch chart to a specific representative period."]),
                        html.Li([html.B("New builds only: "), "In Capacity Mix, show only newly-built capacity (hides existing generators)."]),
                        html.Li([html.B("Transmission Lines: "), "Toggle existing lines, new build lines, and zone boundary overlays on the map."]),
                        html.Li([html.B("Pie Chart Size: "), "Adjust the scale of capacity pie charts on the expansion map."]),
                        html.Li([html.B("Dark Mode: "), "Toggle dark/light theme using the Dark Mode button."]),
                    ],
                    className="dashboard-help-list",
                ),
            ],
            id="gtep-help-panel",
            className="dashboard-help",
            style={"display": "none", "padding": "10px 20px 8px"},
        ),

        # ── Hidden state stores ───────────────────────────────────────────────
        dcc.Store(id="gtep-case-store",        data=DEFAULT_GTEP_CASE),
        dcc.Store(id="gtep-theme-store",       data="light"),
        dcc.Store(id="gtep-custom-cases-store", data=[]),

        # ── Panel Canvas ──────────────────────────────────────────────────────
        html.Div(
            [
                # Row 1: Map (left 61%) + Capacity Mix (right 37%)
                html.Div(
                    [
                        # Map panel
                        html.Div(
                            [
                                html.Div(
                                    [
                                        html.Span("::", className="panel-handle-glyph"),
                                        html.Span("Expansion Map"),
                                    ],
                                    className="panel-drag-handle",
                                ),
                                html.Div(
                                    [
                                        _chrome_sidebar(_default_zones, _default_n_periods),
                                        html.Div(
                                            dcc.Graph(
                                                id="gtep-map-graph",
                                                figure=_map_figure(_default_data),
                                                config={"displaylogo": False},
                                                style={"width": "100%", "height": "100%"},
                                            ),
                                            className="map-panel-graph",
                                        ),
                                    ],
                                    className="map-panel-body",
                                ),
                            ],
                            className="panel-card panel-card-map",
                            style={
                                "position": "absolute",
                                "top": "12px", "left": "0px",
                                "width": "61%", "height": "660px",
                                "zIndex": 3,
                            },
                        ),
                        # Capacity panel
                        html.Div(
                            [
                                html.Div(
                                    [
                                        html.Span("::", className="panel-handle-glyph"),
                                        html.Span("Capacity Mix"),
                                    ],
                                    className="panel-drag-handle",
                                ),
                                html.Div(
                                    dcc.Graph(
                                        id="gtep-capacity-graph",
                                        figure=_capacity_figure(_default_data),
                                        config={"displaylogo": False},
                                        style={"width": "100%", "height": "100%"},
                                    ),
                                    className="panel-inner",
                                ),
                            ],
                            className="panel-card",
                            style={
                                "position": "absolute",
                                "top": "12px", "left": "63%",
                                "width": "37%", "height": "660px",
                                "zIndex": 2,
                            },
                        ),
                    ],
                ),
                # Row 2: Dispatch (left 50%) + Cost (right 48%)
                html.Div(
                    [
                        # Dispatch panel
                        html.Div(
                            [
                                html.Div(
                                    [
                                        html.Span("::", className="panel-handle-glyph"),
                                        html.Span("Dispatch Profile"),
                                    ],
                                    className="panel-drag-handle",
                                ),
                                html.Div(
                                    dcc.Graph(
                                        id="gtep-dispatch-graph",
                                        figure=_dispatch_figure(_default_data),
                                        config={"displaylogo": False},
                                        style={"width": "100%", "height": "100%"},
                                    ),
                                    className="panel-inner",
                                ),
                            ],
                            className="panel-card",
                            style={
                                "position": "absolute",
                                "top": "696px", "left": "0px",
                                "width": "50%", "height": "360px",
                                "zIndex": 1,
                            },
                        ),
                        # Cost panel
                        html.Div(
                            [
                                html.Div(
                                    [
                                        html.Span("::", className="panel-handle-glyph"),
                                        html.Span("System Cost"),
                                    ],
                                    className="panel-drag-handle",
                                ),
                                html.Div(
                                    dcc.Graph(
                                        id="gtep-cost-graph",
                                        figure=_cost_figure(_default_data),
                                        config={"displaylogo": False},
                                        style={"width": "100%", "height": "100%"},
                                    ),
                                    className="panel-inner",
                                ),
                            ],
                            className="panel-card",
                            style={
                                "position": "absolute",
                                "top": "696px", "left": "52%",
                                "width": "48%", "height": "360px",
                                "zIndex": 1,
                            },
                        ),
                    ],
                ),
            ],
            className="panel-canvas",
            style={"minHeight": "1080px"},
        ),
    ],
    className="hope-dashboard",
    id="gtep-root",
)


# ─────────────────────────────────────────────────────────────────────────────
# Callbacks
# ─────────────────────────────────────────────────────────────────────────────

@app.callback(
    Output("gtep-theme-store", "data"),
    Output("gtep-theme-toggle", "children"),
    Output("gtep-root", "className"),
    Input("gtep-theme-toggle", "n_clicks"),
    State("gtep-theme-store", "data"),
    prevent_initial_call=True,
)
def toggle_theme(n, current):
    if not n:
        return no_update, no_update, no_update
    new_theme = "dark" if current == "light" else "light"
    label = "Light Mode" if new_theme == "dark" else "Dark Mode"
    root_class = "hope-dashboard theme-dark" if new_theme == "dark" else "hope-dashboard"
    return new_theme, label, root_class


@app.callback(
    Output("gtep-case-store", "data"),
    Input("gtep-load-case", "n_clicks"),
    State("gtep-case-path", "value"),
    prevent_initial_call=True,
)
def load_case_click(n, case_path):
    return case_path or DEFAULT_GTEP_CASE


@app.callback(
    Output("gtep-period-filter", "options"),
    Output("gtep-period-filter", "value"),
    Output("gtep-zone-filter",   "options"),
    Output("gtep-zone-filter",   "value"),
    Input("gtep-case-store", "data"),
)
def update_sidebar_options(case_path):
    try:
        data = load_gtep_case(case_path or DEFAULT_GTEP_CASE)
    except Exception:
        data = _default_data

    zones = _md_zones(data)
    zone_options = [{"label": "All Zones", "value": "All"}] + [
        {"label": z, "value": z} for z in zones
    ]

    n_periods = _detect_n_periods(data)
    period_opts = [{"label": "All periods", "value": "All"}] + [
        {"label": f"Period {i}", "value": f"P{i}"} for i in range(1, n_periods + 1)
    ]
    return period_opts, "All", zone_options, "All"


@app.callback(
    Output("gtep-kpi-strip",       "children"),
    Output("gtep-map-graph",        "figure"),
    Output("gtep-capacity-graph",  "figure"),
    Output("gtep-dispatch-graph",  "figure"),
    Output("gtep-cost-graph",      "figure"),
    Input("gtep-case-store",      "data"),
    Input("gtep-map-overlay",     "value"),
    Input("gtep-zone-filter",     "value"),
    Input("gtep-period-filter",   "value"),
    Input("gtep-options",         "value"),
    Input("gtep-theme-store",     "data"),
    Input("gtep-show-lines",      "value"),
    Input("gtep-pie-scale",       "value"),
)
def update_all(case_path, overlay, zone_filter, period_filter, options, theme, show_lines, pie_scale):
    try:
        data = load_gtep_case(case_path or DEFAULT_GTEP_CASE)
    except Exception:
        data = _default_data

    show_new_only = "new_only" in (options or [])
    show_boundaries = "boundaries" in (show_lines or [])

    kpi     = _gtep_kpi_strip(data).children
    map_fig = _map_figure(
        data, overlay or "total_cap",
        theme=theme or "light",
        show_lines=show_lines,
        pie_scale=float(pie_scale) if pie_scale is not None else 1.0,
        show_boundaries=show_boundaries,
    )
    cap_fig = _capacity_figure(data, zone_filter or "All", show_new_only, theme or "light")
    dis_fig = _dispatch_figure(data, zone_filter or "All", period_filter or "All", theme or "light")
    cst_fig = _cost_figure(data, theme or "light")

    return kpi, map_fig, cap_fig, dis_fig, cst_fig


@app.callback(
    Output("gtep-help-panel", "style"),
    Input("gtep-help-toggle", "n_clicks"),
)
def gtep_toggle_help(n_clicks: int):
    if (n_clicks or 0) % 2 == 1:
        return {"display": "block", "padding": "10px 20px 8px"}
    return {"display": "none", "padding": "10px 20px 8px"}


@app.callback(
    Output("gtep-custom-case-panel", "style"),
    Output("gtep-custom-case-toggle", "children"),
    Input("gtep-custom-case-toggle", "n_clicks"),
)
def gtep_toggle_custom_case_panel(n_clicks: int):
    visible = (n_clicks or 0) % 2 == 1
    style = {"display": "block", "padding": "10px 20px 8px"} if visible else {"display": "none", "padding": "10px 20px 8px"}
    label = "Hide Case Input" if visible else "+ Case Path"
    return style, label


@app.callback(
    Output("gtep-case-path", "options"),
    Output("gtep-custom-case-status", "children"),
    Output("gtep-custom-cases-store", "data"),
    Input("gtep-add-custom-case", "n_clicks"),
    State("gtep-custom-case-input", "value"),
    State("gtep-custom-cases-store", "data"),
    prevent_initial_call=True,
)
def gtep_add_custom_case(_n_clicks: int, path_str: str, existing_custom: list):
    from dash import no_update
    if not path_str or not path_str.strip():
        return no_update, "Please enter a case directory path.", no_update
    case_dir = Path(path_str.strip()).resolve()
    if not case_dir.exists():
        return no_update, f"Path not found: {case_dir}", no_update
    if not (case_dir / "Settings" / "HOPE_model_settings.yml").exists():
        return no_update, "Missing Settings/HOPE_model_settings.yml — not a HOPE case directory.", no_update
    if not (case_dir / "output" / "capacity.csv").exists():
        return no_update, "Missing output/capacity.csv — run the GTEP case first.", no_update
    case_str = str(case_dir)
    if any(str(opt.get("value", "")) == case_str for opt in AVAILABLE_GTEP_CASES):
        return no_update, f"Already in list: {case_dir.name}", no_update
    if case_str in (existing_custom or []):
        return no_update, f"Already added: {case_dir.name}", no_update
    new_custom = list(existing_custom or []) + [case_str]
    all_options = AVAILABLE_GTEP_CASES + [
        {"label": f"[Custom] {Path(p).name}", "value": p}
        for p in new_custom
    ]
    return all_options, f"\u2713 Added: {case_dir.name}", new_custom


if __name__ == "__main__":
    _host = os.environ.get("DASH_HOST", "127.0.0.1")
    _port = int(os.environ.get("DASH_PORT", "8051"))
    _debug = os.environ.get("DASH_DEBUG", "true").lower() == "true"
    app.run(debug=_debug, host=_host, port=_port)
