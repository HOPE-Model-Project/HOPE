from __future__ import annotations

from collections import Counter, deque
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Dict, Iterable, List, Sequence

import csv
import json
import math
import re
import struct
import zlib

import numpy as np
import pandas as pd

from isone_nodal_ni import generate_nodal_ni_case_data
from isone_osm_seams import (
    apply_seam_capacity_tuning,
    build_seam_scorecard,
    summarize_supported_seams,
)
from isone_topology_rewire import apply_topology_rewires, build_long_branch_audit


ROOT = Path(__file__).resolve().parents[2]
RAW_MATPOWER = ROOT / "tools" / "iso_ne_250bus_case_related" / "raw_sources" / "tamu_ne_250bus" / "matpower" / "Summer90Tight.m"
TOOLS_DIR = ROOT / "tools" / "iso_ne_250bus_case_related"
REF_DIR = TOOLS_DIR / "references"
CASE_DIR = ROOT / "ModelCases" / "ISONE_PCM_250bus_case"
DATA_DIR = CASE_DIR / "Data_ISONE_PCM_250bus"
RAW_EIA860_DIR = TOOLS_DIR / "raw_sources" / "eia860_2024"
RAW_EIA860_PLANT = RAW_EIA860_DIR / "2___Plant_Y2024.xlsx"
RAW_EIA860_GENERATOR = RAW_EIA860_DIR / "3_1_Generator_Y2024.xlsx"
RAW_EIA860_WIND = RAW_EIA860_DIR / "3_2_Wind_Y2024.xlsx"
RAW_EIA860_SOLAR = RAW_EIA860_DIR / "3_3_Solar_Y2024.xlsx"
RAW_EIA860_STORAGE = RAW_EIA860_DIR / "3_4_Energy_Storage_Y2024.xlsx"
RAW_ISONE_HOURLY_LOAD = TOOLS_DIR / "raw_sources" / "hourlysystemdemand_202407.csv"
RAW_EIA_BA = TOOLS_DIR / "raw_sources" / "EBA.zip"
OSM_SUBSTATIONS_CSV = REF_DIR / "osm_substations.csv"
OSM_CORRIDOR_POINTS_CSV = REF_DIR / "osm_corridor_points.csv"
OSM_SEAM_SCORECARD_CSV = REF_DIR / "osm_synthetic_seam_scorecard.csv"
LONG_BRANCH_AUDIT_CSV = REF_DIR / "long_branch_topology_audit.csv"
TOPOLOGY_REWIRE_PLAN_CSV = REF_DIR / "topology_rewire_plan.csv"
CASE_YEAR = 2024
CASE_MONTH = 7

ZONE_NAMES = ["Maine", "NNE", "ROP", "SENE"]
# For the nodal PCM case, state policy accounting is bus-based, so the direct
# zonedata.State value is now only a nominal tag for the zone itself.
ZONE_STATE = {"Maine": "ME", "NNE": "NH", "ROP": "CT", "SENE": "MA"}
LOAD_ZONE_CONFIG = {
    "Maine": [("ME", "ME", 44.3072, -69.7817)],
    "NNE": [("VT", "VT", 44.2601, -72.5754), ("NH", "NH", 43.2081, -71.5376)],
    "ROP": [("CT", "CT", 41.7658, -72.6734), ("WCMA", "MA", 42.1015, -72.5898)],
    "SENE": [
        ("RI", "RI", 41.8240, -71.4128),
        ("SEMA", "MA", 41.6362, -70.9342),
        ("NEMA/Boston", "MA", 42.3601, -71.0589),
    ],
}
LOAD_ZONE_GEOMETRY = {
    "ME": {"lat": 44.80, "lon": -69.20, "width": 2.30, "height": 1.90, "angle": -18.0},
    "VT": {"lat": 44.15, "lon": -72.65, "width": 0.70, "height": 1.55, "angle": -10.0},
    "NH": {"lat": 43.55, "lon": -71.45, "width": 0.80, "height": 1.55, "angle": -16.0},
    "CT": {"lat": 41.62, "lon": -72.65, "width": 0.75, "height": 0.65, "angle": 8.0},
    "WCMA": {"lat": 42.23, "lon": -72.28, "width": 0.55, "height": 0.85, "angle": -8.0},
    "RI": {"lat": 41.73, "lon": -71.52, "width": 0.38, "height": 0.42, "angle": 12.0},
    "SEMA": {"lat": 41.82, "lon": -70.95, "width": 0.60, "height": 0.42, "angle": 16.0},
    "NEMA/Boston": {"lat": 42.34, "lon": -71.02, "width": 0.82, "height": 0.55, "angle": 6.0},
}
LOAD_ZONE_PUBLIC_ANCHORS = {
    "ME": [
        {"name": "Portland", "lat": 43.6591, "lon": -70.2568, "weight": 1.5},
        {"name": "Augusta", "lat": 44.3106, "lon": -69.7795, "weight": 1.2},
        {"name": "Bangor", "lat": 44.8012, "lon": -68.7778, "weight": 1.2},
        {"name": "Presque Isle", "lat": 46.6811, "lon": -68.0159, "weight": 0.8},
    ],
    "VT": [
        {"name": "Burlington", "lat": 44.4759, "lon": -73.2121, "weight": 1.4},
        {"name": "Montpelier", "lat": 44.2601, "lon": -72.5754, "weight": 1.0},
        {"name": "Rutland", "lat": 43.6106, "lon": -72.9726, "weight": 1.0},
        {"name": "St Johnsbury", "lat": 44.4190, "lon": -72.0151, "weight": 0.8},
    ],
    "NH": [
        {"name": "Manchester", "lat": 42.9956, "lon": -71.4548, "weight": 1.4},
        {"name": "Concord", "lat": 43.2081, "lon": -71.5376, "weight": 1.1},
        {"name": "Portsmouth", "lat": 43.0718, "lon": -70.7626, "weight": 1.0},
        {"name": "Berlin", "lat": 44.4687, "lon": -71.1851, "weight": 0.7},
    ],
    "CT": [
        {"name": "Hartford", "lat": 41.7658, "lon": -72.6734, "weight": 1.5},
        {"name": "New Haven", "lat": 41.3083, "lon": -72.9279, "weight": 1.3},
        {"name": "Bridgeport", "lat": 41.1792, "lon": -73.1894, "weight": 1.2},
        {"name": "New London", "lat": 41.3557, "lon": -72.0995, "weight": 1.0},
    ],
    "WCMA": [
        {"name": "Springfield", "lat": 42.1015, "lon": -72.5898, "weight": 1.3},
        {"name": "Pittsfield", "lat": 42.4501, "lon": -73.2454, "weight": 1.0},
        {"name": "Greenfield", "lat": 42.5870, "lon": -72.5995, "weight": 0.8},
    ],
    "RI": [
        {"name": "Providence", "lat": 41.8240, "lon": -71.4128, "weight": 1.6},
        {"name": "Warwick", "lat": 41.7001, "lon": -71.4162, "weight": 1.1},
        {"name": "Newport", "lat": 41.4901, "lon": -71.3128, "weight": 0.8},
    ],
    "SEMA": [
        {"name": "New Bedford", "lat": 41.6362, "lon": -70.9342, "weight": 1.3},
        {"name": "Fall River", "lat": 41.7015, "lon": -71.1550, "weight": 1.2},
        {"name": "Plymouth", "lat": 41.9584, "lon": -70.6673, "weight": 1.0},
        {"name": "Hyannis", "lat": 41.6525, "lon": -70.2881, "weight": 0.9},
    ],
    "NEMA/Boston": [
        {"name": "Boston", "lat": 42.3601, "lon": -71.0589, "weight": 1.8},
        {"name": "Woburn", "lat": 42.4793, "lon": -71.1523, "weight": 1.0},
        {"name": "Salem", "lat": 42.5195, "lon": -70.8967, "weight": 0.9},
        {"name": "Lowell", "lat": 42.6334, "lon": -71.3162, "weight": 0.9},
    ],
}
LOAD_ZONE_CORRIDORS = {
    "ME": [
        [(43.6591, -70.2568), (44.3106, -69.7795), (44.8012, -68.7778), (45.6586, -68.5981)],
        [(43.9145, -69.9653), (44.1037, -70.2312), (44.3072, -69.7817)],
        [(43.7508, -70.1567), (43.7240, -70.3280), (44.4090, -69.5350), (44.8242, -68.7094)],
        [(43.6575, -70.3750), (43.9145, -69.9653), (44.7280, -68.7910)],
        [(43.6591, -70.2568), (43.7050, -70.4830), (43.7986, -70.2157)],
    ],
    "VT": [
        [(44.4759, -73.2121), (44.2601, -72.5754), (43.6106, -72.9726)],
        [(44.4190, -72.0151), (44.2601, -72.5754), (43.6268, -72.5173)],
    ],
    "NH": [
        [(43.0718, -70.7626), (42.9956, -71.4548), (43.2081, -71.5376), (43.6423, -72.2518)],
        [(44.4687, -71.1851), (43.2081, -71.5376), (43.0718, -70.7626)],
        [(42.8992, -70.8489), (43.1047, -70.8061), (42.9956, -71.4548)],
        [(42.9042, -71.4261), (43.1411, -71.4692), (43.2081, -71.5376)],
        [(43.0718, -70.7626), (43.1047, -70.8061), (43.0514, -70.9664)],
    ],
    "CT": [
        [(41.1792, -73.1894), (41.3083, -72.9279), (41.7658, -72.6734), (41.3557, -72.0995)],
        [(41.1792, -73.1894), (41.7658, -72.6734)],
    ],
    "WCMA": [
        [(42.4501, -73.2454), (42.1015, -72.5898), (42.2626, -71.8023)],
        [(42.5870, -72.5995), (42.1015, -72.5898), (41.9584, -70.6673)],
    ],
    "RI": [
        [(41.8240, -71.4128), (41.7001, -71.4162), (41.4901, -71.3128)],
    ],
    "SEMA": [
        [(41.7015, -71.1550), (41.6362, -70.9342), (41.9584, -70.6673), (41.6525, -70.2881)],
    ],
    "NEMA/Boston": [
        [(42.3601, -71.0589), (42.4793, -71.1523), (42.6334, -71.3162)],
        [(42.3601, -71.0589), (42.5195, -70.8967)],
    ],
}
LOAD_ZONE_GRID_ANCHORS = {
    "ME": [
        {"name": "Surowiec", "lat": 43.7240, "lon": -70.3280, "weight": 1.2},
        {"name": "South Gorham", "lat": 43.7050, "lon": -70.4830, "weight": 1.0},
        {"name": "Orrington", "lat": 44.7280, "lon": -68.7910, "weight": 1.1},
        {"name": "Kittery Interface", "lat": 43.1133, "lon": -70.7362, "weight": 0.8},
        {"name": "Westbrook", "lat": 43.6575, "lon": -70.3750, "weight": 1.0},
        {"name": "Wyman", "lat": 43.7508, "lon": -70.1567, "weight": 1.0},
        {"name": "Coopers Mills", "lat": 44.4090, "lon": -69.5350, "weight": 0.95},
        {"name": "Maine Independence", "lat": 44.8242, "lon": -68.7094, "weight": 1.0},
        {"name": "Aroostook Backbone", "lat": 46.8600, "lon": -68.0100, "weight": 0.8},
    ],
    "VT": [
        {"name": "Coolidge", "lat": 43.6268, "lon": -72.5173, "weight": 0.9},
        {"name": "Burlington Backbone", "lat": 44.4759, "lon": -73.2121, "weight": 1.0},
    ],
    "NH": [
        {"name": "Scobie Pond", "lat": 42.8810, "lon": -71.3310, "weight": 1.2},
        {"name": "Seabrook Corridor", "lat": 42.8992, "lon": -70.8489, "weight": 1.1},
        {"name": "Portsmouth Interface", "lat": 43.0718, "lon": -70.7626, "weight": 1.0},
        {"name": "North Country Backbone", "lat": 44.4687, "lon": -71.1851, "weight": 0.8},
        {"name": "Newington", "lat": 43.1047, "lon": -70.8061, "weight": 1.0},
        {"name": "Granite Ridge", "lat": 42.9042, "lon": -71.4261, "weight": 1.0},
        {"name": "Merrimack", "lat": 43.1411, "lon": -71.4692, "weight": 0.95},
        {"name": "Schiller", "lat": 43.0635, "lon": -70.7572, "weight": 0.9},
        {"name": "Deerfield Backbone", "lat": 43.1380, "lon": -71.2490, "weight": 0.9},
    ],
    "CT": [
        {"name": "North Bloomfield", "lat": 41.8790, "lon": -72.7340, "weight": 1.1},
        {"name": "Lake Road", "lat": 41.8720, "lon": -71.8960, "weight": 1.1},
        {"name": "Montville", "lat": 41.4540, "lon": -72.1120, "weight": 1.0},
        {"name": "Bridgeport", "lat": 41.1792, "lon": -73.1894, "weight": 1.0},
        {"name": "Middletown", "lat": 41.5549, "lon": -72.5791, "weight": 1.0},
        {"name": "New Haven Harbor", "lat": 41.2840, "lon": -72.9043, "weight": 0.95},
        {"name": "Milford", "lat": 41.2244, "lon": -73.0997, "weight": 0.95},
        {"name": "Towantic", "lat": 41.4812, "lon": -73.1231, "weight": 0.95},
    ],
    "WCMA": [
        {"name": "Northfield", "lat": 42.6107, "lon": -72.4716, "weight": 1.3},
        {"name": "Bear Swamp", "lat": 42.6839, "lon": -72.9599, "weight": 1.1},
        {"name": "Worcester Backbone", "lat": 42.2626, "lon": -71.8023, "weight": 0.9},
    ],
    "RI": [
        {"name": "West Farnum", "lat": 41.9550, "lon": -71.5960, "weight": 1.2},
        {"name": "Manchester Street", "lat": 41.8120, "lon": -71.4040, "weight": 1.0},
    ],
    "SEMA": [
        {"name": "Canal", "lat": 41.7694, "lon": -70.5097, "weight": 1.4},
        {"name": "Stoughton", "lat": 42.1250, "lon": -71.1020, "weight": 0.9},
        {"name": "Carver", "lat": 41.8880, "lon": -70.7600, "weight": 0.9},
        {"name": "Bellingham", "lat": 42.1106, "lon": -71.4535, "weight": 0.95},
    ],
    "NEMA/Boston": [
        {"name": "Mystic", "lat": 42.3910, "lon": -71.0460, "weight": 1.4},
        {"name": "Woburn", "lat": 42.4793, "lon": -71.1523, "weight": 1.1},
        {"name": "North Cambridge", "lat": 42.3910, "lon": -71.1470, "weight": 1.0},
        {"name": "Fore River", "lat": 42.2422, "lon": -70.9661, "weight": 1.0},
        {"name": "Salem Harbor", "lat": 42.5255, "lon": -70.8782, "weight": 1.0},
        {"name": "Blackstone", "lat": 42.0599, "lon": -71.5158, "weight": 0.9},
    ],
}
MAJOR_PLANT_PLACEMENT_HINTS = {
    "Millstone": {"lat": 41.3107, "lon": -72.1677, "weight": 1.0},
    "Canal": {"lat": 41.7694, "lon": -70.5097, "weight": 1.0},
    "Seabrook": {"lat": 42.899167, "lon": -70.848889, "weight": 1.0},
    "Lake Road Generating Plant": {"lat": 41.872043, "lon": -71.895799, "weight": 1.0},
    "William F Wyman Hybrid": {"lat": 43.7508, "lon": -70.1567, "weight": 0.95},
    "CPV Towantic Energy Center": {"lat": 41.481243, "lon": -73.123108, "weight": 0.95},
    "Fore River Generating Station": {"lat": 42.2422, "lon": -70.9661, "weight": 0.95},
    "Salem Harbor Power Development LP": {"lat": 42.525486, "lon": -70.878239, "weight": 0.95},
    "Granite Ridge": {"lat": 42.9042, "lon": -71.4261, "weight": 0.95},
    "Newington Energy Center": {"lat": 43.1047, "lon": -70.8061, "weight": 0.95},
    "Westbrook Energy Center Power Plant": {"lat": 43.6575, "lon": -70.3750, "weight": 0.95},
    "Maine Independence Station": {"lat": 44.8242, "lon": -68.7094, "weight": 0.95},
    "ANP Bellingham Energy Project": {"lat": 42.110577, "lon": -71.453468, "weight": 0.9},
    "ANP Blackstone Energy Project": {"lat": 42.059876, "lon": -71.515811, "weight": 0.9},
    "Bridgeport Energy Project": {"lat": 41.1692, "lon": -73.1844, "weight": 0.9},
    "New Haven Harbor": {"lat": 41.283997, "lon": -72.904323, "weight": 0.9},
    "Northfield Mountain": {"lat": 42.610683, "lon": -72.471643, "weight": 0.95},
    "Bear Swamp": {"lat": 42.6839, "lon": -72.9599, "weight": 0.95},
    "Rocky River (CT)": {"lat": 41.5826, "lon": -73.4349, "weight": 0.9},
}
PLANT_BUS_OVERRIDES = {
    "Seabrook": 135,
    "Newington Energy Center": 128,
    "Newington": 128,
    "Schiller": 128,
    "UNH 7.9 MW Plant": 128,
    "Westbrook Energy Center Power Plant": 145,
    "William F Wyman Hybrid": 63,
    "Lake Road Generating Plant": 97,
    "Northfield Mountain": 146,
    "Bear Swamp": 98,
    "Rocky River (CT)": 112,
}
PLANT_BUS_CLUSTER_OVERRIDES = {
    "Millstone": [136, 230, 115, 99, 19],
    "Newington Energy Center": [135, 151, 128, 153, 21],
    "Newington": [135, 151, 128, 153, 21],
    "Schiller": [135, 151, 128, 153, 21],
    "UNH 7.9 MW Plant": [135, 151, 128, 153, 21],
    "ANP Bellingham Energy Project": [220, 203, 120, 204, 246],
    "Bellingham Cogeneration Facility": [220, 203, 120, 204, 246],
    "Milford Power LP": [220, 203, 120, 204, 246],
    "Bridgeport Energy Project": [103, 107, 227, 111, 119],
    "Milford Power Project": [103, 107, 227, 111, 119],
    "Bridgeport Station": [107, 103, 227, 111, 119],
    "Lake Road Generating Plant": [97, 115, 230, 19, 99],
}
BRANCH_CAPACITY_TARGETS_MW = {
    (19, 110): 350.0,
    (28, 77): 250.0,
    (28, 203): 250.0,
    (28, 204): 250.0,
    (77, 217): 250.0,
    (102, 114): 250.0,
    (114, 136): 250.0,
    (117, 164): 250.0,
    (131, 152): 250.0,
    (217, 218): 250.0,
}
GENERATOR_MAX_BUS_UTILIZATION = 0.92
GENERATOR_SPLIT_MIN_SITE_MW = 900.0
GENERATOR_SPLIT_MAX_BUSES = 4
GENERATOR_SPLIT_MIN_SEGMENT_MW = 175.0
GENERATOR_SPLIT_NEARBY_RADIUS_MILES = 35.0
GENERATOR_SPLIT_NEARBY_MARGIN_MILES = 15.0
LOAD_ZONE_TO_CAPACITY_ZONE = {
    load_zone: zone_name
    for zone_name, defs in LOAD_ZONE_CONFIG.items()
    for load_zone, _, _, _ in defs
}
LOAD_ZONE_TO_STATE = {
    load_zone: state
    for defs in LOAD_ZONE_CONFIG.values()
    for load_zone, state, _, _ in defs
}
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
EBA_ISONE_GEN_SERIES = [
    "EBA.ISNE-ALL.NG.COL.H",
    "EBA.ISNE-ALL.NG.NG.H",
    "EBA.ISNE-ALL.NG.NUC.H",
    "EBA.ISNE-ALL.NG.OIL.H",
    "EBA.ISNE-ALL.NG.OTH.H",
    "EBA.ISNE-ALL.NG.SUN.H",
    "EBA.ISNE-ALL.NG.WAT.H",
    "EBA.ISNE-ALL.NG.WND.H",
]
NEW_ENGLAND_STATES = {"CT", "ME", "MA", "NH", "RI", "VT"}
LOAD_ZONE_DEMAND_PROXY = {
    "ME": 1.35,
    "VT": 0.65,
    "NH": 1.40,
    "CT": 3.60,
    "WCMA": 0.85,
    "RI": 1.10,
    "SEMA": 1.45,
    "NEMA/Boston": 4.10,
}

TECH_SPECS = {
    "NuC": {"thermal": 1, "vre": 0, "ret": 0, "mustrun": 0, "cost": 12.0, "ef": 0.0, "cc": 0.95, "af": 0.95, "for": 0.06, "rm": 0.10, "ru": 0.12, "rd": 0.12, "uc": 1, "min_down": 24, "min_up": 24, "startup": 4.0},
    "NGCC": {"thermal": 1, "vre": 0, "ret": 0, "mustrun": 0, "cost": 34.0, "ef": 0.40, "cc": 0.92, "af": 1.0, "for": 0.06, "rm": 0.10, "ru": 0.50, "rd": 0.50, "uc": 1, "min_down": 4, "min_up": 4, "startup": 6.0},
    "NGCT": {"thermal": 1, "vre": 0, "ret": 0, "mustrun": 0, "cost": 58.0, "ef": 0.59, "cc": 0.86, "af": 1.0, "for": 0.08, "rm": 0.12, "ru": 1.00, "rd": 1.00, "uc": 1, "min_down": 1, "min_up": 1, "startup": 8.0},
    "Oil": {"thermal": 1, "vre": 0, "ret": 0, "mustrun": 0, "cost": 92.0, "ef": 0.82, "cc": 0.88, "af": 1.0, "for": 0.10, "rm": 0.08, "ru": 1.00, "rd": 1.00, "uc": 1, "min_down": 1, "min_up": 1, "startup": 10.0},
    "Coal": {"thermal": 1, "vre": 0, "ret": 0, "mustrun": 0, "cost": 48.0, "ef": 0.95, "cc": 0.90, "af": 0.92, "for": 0.08, "rm": 0.08, "ru": 0.25, "rd": 0.25, "uc": 1, "min_down": 8, "min_up": 8, "startup": 9.0},
    "Hydro": {"thermal": 0, "vre": 0, "ret": 1, "mustrun": 0, "cost": 7.5, "ef": 0.0, "cc": 0.70, "af": 0.65, "for": 0.04, "rm": 0.00, "ru": 1.00, "rd": 1.00, "uc": 0, "min_down": 0, "min_up": 0, "startup": 0.0},
    "WindOn": {"thermal": 0, "vre": 1, "ret": 1, "mustrun": 0, "cost": 3.0, "ef": 0.0, "cc": 0.18, "af": 1.0, "for": 0.05, "rm": 0.00, "ru": 1.00, "rd": 1.00, "uc": 0, "min_down": 1, "min_up": 1, "startup": 0.0},
    "SolarPV": {"thermal": 0, "vre": 1, "ret": 1, "mustrun": 0, "cost": 2.0, "ef": 0.0, "cc": 0.26, "af": 1.0, "for": 0.03, "rm": 0.00, "ru": 1.00, "rd": 1.00, "uc": 0, "min_down": 1, "min_up": 1, "startup": 0.0},
    "Bio": {"thermal": 1, "vre": 0, "ret": 1, "mustrun": 0, "cost": 39.0, "ef": 0.10, "cc": 0.90, "af": 0.90, "for": 0.08, "rm": 0.06, "ru": 0.40, "rd": 0.40, "uc": 1, "min_down": 6, "min_up": 6, "startup": 6.0},
    "MSW": {"thermal": 1, "vre": 0, "ret": 1, "mustrun": 0, "cost": 32.0, "ef": 0.08, "cc": 0.90, "af": 0.92, "for": 0.08, "rm": 0.06, "ru": 0.35, "rd": 0.35, "uc": 1, "min_down": 6, "min_up": 6, "startup": 5.0},
}

ZONE_TECH_TARGETS = {
    "Maine": {"WindOn": 0.16, "Hydro": 0.14, "Bio": 0.04, "Oil": 0.05, "NGCT": 0.12, "NGCC": 0.49},
    "NNE": {"WindOn": 0.12, "Hydro": 0.16, "NuC": 0.20, "Oil": 0.05, "NGCT": 0.15, "NGCC": 0.32},
    "ROP": {"SolarPV": 0.08, "Hydro": 0.04, "MSW": 0.04, "NuC": 0.24, "Oil": 0.05, "NGCT": 0.15, "NGCC": 0.40},
    "SENE": {"SolarPV": 0.10, "WindOn": 0.03, "Hydro": 0.04, "MSW": 0.04, "Oil": 0.10, "NGCT": 0.17, "NGCC": 0.52},
}
EIA_TECH_TO_HOPE = {
    "Nuclear": "NuC",
    "Natural Gas Fired Combined Cycle": "NGCC",
    "Natural Gas Fired Combustion Turbine": "NGCT",
    "Other Natural Gas": "NGCT",
    "Natural Gas Internal Combustion Engine": "NGCT",
    "Natural Gas Steam Turbine": "NGCT",
    "Petroleum Liquids": "Oil",
    "Conventional Steam Coal": "Coal",
    "Conventional Hydroelectric": "Hydro",
    "Hydroelectric Pumped Storage": "Hydro",
    "Onshore Wind Turbine": "WindOn",
    "Offshore Wind Turbine": "WindOn",
    "Solar Photovoltaic": "SolarPV",
    "Wood/Wood Waste Biomass": "Bio",
    "Other Waste Biomass": "Bio",
    "Landfill Gas": "Bio",
    "Municipal Solid Waste": "MSW",
}


def _parse_month_year_columns(frame: pd.DataFrame, month_col: str, year_col: str) -> tuple[pd.Series, pd.Series]:
    month = pd.to_numeric(frame[month_col], errors="coerce")
    year = pd.to_numeric(frame[year_col], errors="coerce")
    return month, year


def _available_during_case_month(
    frame: pd.DataFrame,
    *,
    op_month_col: str,
    op_year_col: str,
    retirement_month_col: str | None = None,
    retirement_year_col: str | None = None,
) -> pd.Series:
    op_month, op_year = _parse_month_year_columns(frame, op_month_col, op_year_col)
    started = op_year.notna() & (
        (op_year < CASE_YEAR) | ((op_year == CASE_YEAR) & (op_month.fillna(1) <= CASE_MONTH))
    )
    if retirement_month_col is None or retirement_year_col is None:
        return started

    ret_month, ret_year = _parse_month_year_columns(frame, retirement_month_col, retirement_year_col)
    not_retired = ret_year.isna() | (ret_year > CASE_YEAR) | (
        (ret_year == CASE_YEAR) & (ret_month.fillna(12) >= CASE_MONTH)
    )
    return started & not_retired
PMIN_FRACTION = {
    "NuC": 0.68,
    "NGCC": 0.42,
    "NGCT": 0.28,
    "Oil": 0.24,
    "Coal": 0.40,
    "Hydro": 0.0,
    "WindOn": 0.0,
    "SolarPV": 0.0,
    "Bio": 0.48,
    "MSW": 0.50,
}

STORAGE_SPECS = {
    "BES": {
        "charging_efficiency": 0.90,
        "discharging_efficiency": 0.90,
        "cost": 1.0,
        "ef": 0.0,
        "cc": 0.95,
        "charging_rate": 1.0,
        "discharging_rate": 1.0,
    },
    "PHS": {
        "charging_efficiency": 0.82,
        "discharging_efficiency": 0.82,
        "cost": 0.5,
        "ef": 0.0,
        "cc": 0.95,
        "charging_rate": 1.0,
        "discharging_rate": 1.0,
    },
}

PHS_ASSUMPTIONS = {
    539: {
        "duration_hours": 8.0,
        "charge_efficiency": 0.85,
        "discharge_efficiency": 0.85,
        "source_note": "EIA-860 Rocky River pumped-storage plant with generic 8-hour long-duration fallback; public plant-specific duration not found.",
    },
    547: {
        "duration_hours": 7.5,
        "charge_efficiency": 0.88,
        "discharge_efficiency": 0.88,
        "source_note": "FirstLight public page states Northfield Mountain can power for up to 7.5 hours each day; round-trip efficiency approximated at about 77%.",
    },
    8005: {
        "duration_hours": None,
        "energy_mwh": 3028.0,
        "charge_efficiency": 0.84,
        "discharge_efficiency": 0.84,
        "source_note": "FERC/Brookfield public relicensing materials cite about 3,028 MWh generation storage and about 4,286 MWh pumping energy for Bear Swamp.",
    },
}

BUS_COLS = [
    "BUS_I",
    "BUS_TYPE",
    "PD",
    "QD",
    "GS",
    "BS",
    "BUS_AREA",
    "VM",
    "VA",
    "BASE_KV",
    "ZONE",
    "VMAX",
    "VMIN",
    "LAM_P",
    "LAM_Q",
    "MU_VMAX",
    "MU_VMIN",
]

GEN_COLS = [
    "GEN_BUS",
    "PG",
    "QG",
    "QMAX",
    "QMIN",
    "VG",
    "MBASE",
    "GEN_STATUS",
    "PMAX",
    "PMIN",
    "PC1",
    "PC2",
    "QC1MIN",
    "QC1MAX",
    "QC2MIN",
    "QC2MAX",
    "RAMP_AGC",
    "RAMP_10",
    "RAMP_30",
    "RAMP_Q",
    "APF",
]

BRANCH_COLS = [
    "F_BUS",
    "T_BUS",
    "BR_R",
    "BR_X",
    "BR_B",
    "RATE_A",
    "RATE_B",
    "RATE_C",
    "TAP",
    "SHIFT",
    "BR_STATUS",
    "ANGMIN",
    "ANGMAX",
    "PF",
    "QF",
    "PT",
    "QT",
    "MU_SF",
    "MU_ST",
    "MU_ANGMIN",
    "MU_ANGMAX",
]


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="ignore")


def parse_matrix(text: str, marker: str) -> List[List[float]]:
    start_token = f"{marker} = ["
    start = text.find(start_token)
    if start < 0:
        raise ValueError(f"Could not find marker {marker}")
    start = start + len(start_token)
    end = text.find("];", start)
    if end < 0:
        raise ValueError(f"Could not find end of matrix for {marker}")
    block = text[start:end]
    rows: List[List[float]] = []
    for raw_line in block.splitlines():
        line = raw_line.split("%", 1)[0].strip()
        if not line:
            continue
        line = line.rstrip(";")
        parts = line.split()
        rows.append([float(p) for p in parts])
    return rows


def rows_to_frame(rows: List[List[float]], columns: Sequence[str]) -> pd.DataFrame:
    normalized = []
    width = len(columns)
    for row in rows:
        if len(row) < width:
            row = row + [0.0] * (width - len(row))
        elif len(row) > width:
            row = row[:width]
        normalized.append(row)
    return pd.DataFrame(normalized, columns=list(columns))


def ensure_parent(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)


def read_isone_hourly_system_load(path: Path, hours_total: int = 744) -> np.ndarray | None:
    if not path.exists():
        return None
    rows: list[dict[str, object]] = []
    with path.open("r", encoding="utf-8", errors="ignore") as f:
        for raw_line in f:
            line = raw_line.strip()
            if not line:
                continue
            if not line.startswith('"D",'):
                continue
            parts = next(csv.reader([line]))
            if len(parts) < 4:
                continue
            date_str = str(parts[1]).strip()
            hour_ending = int(parts[2])
            total_load = float(parts[3])
            ts = pd.to_datetime(date_str, format="%m/%d/%Y") + pd.Timedelta(hours=hour_ending - 1)
            rows.append({"timestamp": ts, "total_load": total_load})
    if not rows:
        return None
    df = pd.DataFrame(rows).sort_values("timestamp").reset_index(drop=True)
    if len(df) != hours_total:
        raise ValueError(
            f"Expected {hours_total} ISO-NE hourly load rows in {path.name}, found {len(df)}"
        )
    values = df["total_load"].to_numpy(dtype=float)
    if values.max() <= 0.0:
        raise ValueError(f"Invalid nonpositive ISO-NE load series in {path.name}")
    return values / values.max()


def _parse_eba_timestamp(ts_raw: str) -> pd.Timestamp:
    if re.fullmatch(r"\d{8}T\d{2}", ts_raw):
        return pd.to_datetime(ts_raw, format="%Y%m%dT%H", utc=True).tz_convert("America/New_York").tz_localize(None)
    if re.fullmatch(r"\d{8}T\d{2}[+-]\d{2}", ts_raw):
        signed = f"{ts_raw}00"
        return pd.to_datetime(signed, format="%Y%m%dT%H%z", utc=True).tz_convert("America/New_York").tz_localize(None)
    raise ValueError(f"Unsupported EBA timestamp format: {ts_raw}")


@lru_cache(maxsize=1)
def _read_eba_series_map() -> dict[str, pd.Series]:
    if not RAW_EIA_BA.exists():
        return {}
    raw = RAW_EIA_BA.read_bytes()
    if len(raw) < 30 or raw[:4] != b"PK\x03\x04":
        return {}

    _, _, method, _, _, _, _, _, fname_len, extra_len = struct.unpack("<HHHHHIIIHH", raw[4:30])
    if method != 8:
        return {}
    start = 30 + fname_len + extra_len
    decompressed = zlib.decompressobj(-15).decompress(raw[start:])

    series_ids = [f"EBA.ISNE-{report_id}.D.H" for report_id in LOAD_ZONE_REPORT_ID.values()] + EBA_ISONE_GEN_SERIES
    series_map: dict[str, pd.Series] = {}
    for series_id in series_ids:
        pattern = re.compile(rb'\{"series_id":"' + re.escape(series_id.encode("utf-8")) + rb'".*?"data":\[(.*?)\]\}', re.S)
        match = pattern.search(decompressed)
        if match is None:
            continue
        payload = json.loads(b"[" + match.group(1) + b"]")
        values = []
        for ts_raw, val_raw in payload:
            ts = _parse_eba_timestamp(str(ts_raw))
            try:
                val = float(val_raw)
            except (TypeError, ValueError):
                continue
            values.append((ts, val))
        if values:
            series = pd.Series({ts: val for ts, val in values}).sort_index()
            series_map[series_id] = series
    return series_map


def _select_local_july_2024(series: pd.Series, hours_total: int = 744) -> np.ndarray | None:
    if series is None or series.empty:
        return None
    start = pd.Timestamp("2024-07-01 00:00:00")
    end = pd.Timestamp("2024-07-31 23:00:00")
    work = series.sort_index()
    work = work[(work.index >= start) & (work.index <= end)]
    if len(work) != hours_total:
        return None
    return work.to_numpy(dtype=float)


def read_isone_eia_zone_load(load_zone: str, hours_total: int = 744) -> np.ndarray | None:
    report_id = LOAD_ZONE_REPORT_ID.get(load_zone)
    if report_id is None:
        return None
    series_id = f"EBA.ISNE-{report_id}.D.H"
    return _select_local_july_2024(_read_eba_series_map().get(series_id), hours_total=hours_total)


def build_isone_system_net_imports(hours_total: int = 744) -> np.ndarray | None:
    series_map = _read_eba_series_map()
    zone_arrays = [read_isone_eia_zone_load(load_zone, hours_total=hours_total) for load_zone in LOAD_ZONE_REPORT_ID]
    if any(arr is None for arr in zone_arrays):
        return None
    demand = np.sum(np.vstack(zone_arrays), axis=0)
    gen_arrays = [_select_local_july_2024(series_map.get(series_id), hours_total=hours_total) for series_id in EBA_ISONE_GEN_SERIES]
    gen_arrays = [arr for arr in gen_arrays if arr is not None]
    if not gen_arrays:
        return None
    generation = np.sum(np.vstack(gen_arrays), axis=0)
    return demand - generation


def read_isone_public_vre_profile(resource: str, hours_total: int = 744) -> np.ndarray | None:
    series_id_map = {
        "solar": "EBA.ISNE-ALL.NG.SUN.H",
        "wind": "EBA.ISNE-ALL.NG.WND.H",
    }
    series_id = series_id_map.get(str(resource).lower())
    if series_id is None:
        return None
    arr = _select_local_july_2024(_read_eba_series_map().get(series_id), hours_total=hours_total)
    if arr is None:
        return None
    arr = np.maximum(arr.astype(float), 0.0)
    max_val = float(arr.max())
    if max_val <= 0.0:
        return None
    return arr / max_val


def read_isone_nodal_load_weight_distribution(load_zone: str) -> np.ndarray | None:
    report_id = LOAD_ZONE_REPORT_ID.get(load_zone)
    if report_id is None:
        return None
    path = TOOLS_DIR / "raw_sources" / f"nodalloadweights_{report_id}_202407.csv"
    if not path.exists():
        return None
    by_location: dict[str, list[float]] = {}
    with path.open("r", encoding="utf-8", errors="ignore") as f:
        reader = csv.reader(f)
        for row in reader:
            if not row or row[0] != "D" or len(row) < 6:
                continue
            location_id = str(row[3]).strip()
            mw_factor = float(row[5])
            by_location.setdefault(location_id, []).append(mw_factor)
    if not by_location:
        return None
    avg_weights = np.array([float(np.mean(vals)) for vals in by_location.values()], dtype=float)
    avg_weights = avg_weights[avg_weights > 0.0]
    if avg_weights.size == 0:
        return None
    avg_weights.sort()
    avg_weights = avg_weights[::-1]
    return avg_weights / avg_weights.sum()


def compress_public_weight_distribution(avg_weights: np.ndarray, n_buses: int) -> np.ndarray | None:
    if avg_weights is None or n_buses <= 0:
        return None
    if avg_weights.size == 0:
        return None
    bins = np.array_split(avg_weights, n_buses)
    compressed = np.array([float(chunk.sum()) for chunk in bins], dtype=float)
    total = compressed.sum()
    if total <= 0.0:
        return None
    return compressed / total


def read_isone_nodal_load_timeseries(load_zone: str, hours_total: int = 744) -> pd.DataFrame | None:
    report_id = LOAD_ZONE_REPORT_ID.get(load_zone)
    if report_id is None:
        return None
    path = TOOLS_DIR / "raw_sources" / f"nodalloadweights_{report_id}_202407.csv"
    if not path.exists():
        return None
    rows: list[dict[str, object]] = []
    with path.open("r", encoding="utf-8", errors="ignore") as f:
        reader = csv.reader(f)
        for row in reader:
            if not row or row[0] != "D" or len(row) < 6:
                continue
            ts = pd.to_datetime(str(row[1]).strip(), format="%Y-%m-%d") + pd.Timedelta(hours=int(row[2]) - 1)
            rows.append(
                {
                    "timestamp": ts,
                    "location_id": str(row[3]).strip(),
                    "mw_factor": float(row[5]),
                }
            )
    if not rows:
        return None
    df = pd.DataFrame(rows)
    pivot = (
        df.pivot_table(index="timestamp", columns="location_id", values="mw_factor", aggfunc="sum")
        .sort_index()
        .fillna(0.0)
    )
    if len(pivot) != hours_total:
        raise ValueError(
            f"Expected {hours_total} hourly rows in nodal load file for {load_zone}, found {len(pivot)}"
        )
    return pivot


def compress_public_load_timeseries(public_ts: pd.DataFrame, n_buses: int) -> np.ndarray | None:
    if public_ts is None or n_buses <= 0 or public_ts.empty:
        return None
    avg = public_ts.mean(axis=0).sort_values(ascending=False)
    ordered = public_ts.loc[:, avg.index]
    bins = np.array_split(np.arange(ordered.shape[1]), n_buses)
    compressed = np.column_stack(
        [
            ordered.iloc[:, list(bin_idx)].sum(axis=1).to_numpy(dtype=float) if len(bin_idx) > 0 else np.zeros(len(ordered))
            for bin_idx in bins
        ]
    )
    return compressed


def build_adj(branch_df: pd.DataFrame, buses: Sequence[int]) -> Dict[int, set[int]]:
    adj = {int(bus): set() for bus in buses}
    for row in branch_df.itertuples(index=False):
        if int(row.BR_STATUS) <= 0:
            continue
        f = int(row.F_BUS)
        t = int(row.T_BUS)
        adj[f].add(t)
        adj[t].add(f)
    return adj


def bfs_distances(adj: Dict[int, set[int]], seed: int) -> Dict[int, int]:
    dist = {seed: 0}
    q = deque([seed])
    while q:
        node = q.popleft()
        for nbr in adj[node]:
            if nbr not in dist:
                dist[nbr] = dist[node] + 1
                q.append(nbr)
    max_d = max(dist.values()) if dist else 0
    for node in adj:
        if node not in dist:
            dist[node] = max_d + 10_000
    return dist


def choose_seeds(bus_df: pd.DataFrame, adj: Dict[int, set[int]], n_seeds: int = 4) -> List[int]:
    buses = [int(b) for b in bus_df["BUS_I"]]
    first_seed = int(bus_df.sort_values(["PD", "BUS_I"], ascending=[False, True]).iloc[0]["BUS_I"])
    seeds = [first_seed]
    dist_cache = {first_seed: bfs_distances(adj, first_seed)}
    while len(seeds) < n_seeds:
        best_bus = None
        best_score = -1
        for bus in buses:
            score = min(dist_cache[s][bus] for s in seeds)
            if score > best_score:
                best_score = score
                best_bus = bus
        assert best_bus is not None
        seeds.append(int(best_bus))
        dist_cache[int(best_bus)] = bfs_distances(adj, int(best_bus))
    return seeds


def assign_voronoi_zones(adj: Dict[int, set[int]], seeds: Sequence[int]) -> Dict[int, int]:
    dist_cache = {int(seed): bfs_distances(adj, int(seed)) for seed in seeds}
    assignment: Dict[int, int] = {}
    for bus in adj:
        best_seed_idx = min(
            range(len(seeds)),
            key=lambda idx: (dist_cache[int(seeds[idx])][bus], idx),
        )
        assignment[int(bus)] = int(best_seed_idx)
    return assignment


def connected_components(nodes: Iterable[int], adj: Dict[int, set[int]]) -> List[List[int]]:
    remaining = set(nodes)
    components = []
    while remaining:
        start = next(iter(remaining))
        q = deque([start])
        comp = []
        remaining.remove(start)
        while q:
            node = q.popleft()
            comp.append(node)
            for nbr in adj[node]:
                if nbr in remaining:
                    remaining.remove(nbr)
                    q.append(nbr)
        components.append(sorted(comp))
    return components


def repair_connectivity(assignment: Dict[int, int], adj: Dict[int, set[int]]) -> Dict[int, int]:
    changed = True
    while changed:
        changed = False
        for zone_idx in sorted(set(assignment.values())):
            zone_nodes = [bus for bus, z in assignment.items() if z == zone_idx]
            comps = connected_components(zone_nodes, adj)
            if len(comps) <= 1:
                continue
            comps = sorted(comps, key=len, reverse=True)
            for comp in comps[1:]:
                neighbor_zone_counter: Counter[int] = Counter()
                for bus in comp:
                    for nbr in adj[bus]:
                        nbr_zone = assignment[nbr]
                        if nbr_zone != zone_idx:
                            neighbor_zone_counter[nbr_zone] += 1
                if neighbor_zone_counter:
                    target_zone = neighbor_zone_counter.most_common(1)[0][0]
                else:
                    target_zone = min(z for z in set(assignment.values()) if z != zone_idx)
                for bus in comp:
                    assignment[bus] = target_zone
                changed = True
    return assignment


def build_zone_name_map(assignment: Dict[int, int]) -> Dict[int, str]:
    zone_means = []
    for z in sorted(set(assignment.values())):
        members = [bus for bus, zone in assignment.items() if zone == z]
        zone_means.append((z, float(np.mean(members))))
    zone_means.sort(key=lambda item: item[1])
    return {zone_idx: ZONE_NAMES[idx] for idx, (zone_idx, _) in enumerate(zone_means)}


def restrict_adj(adj: Dict[int, set[int]], nodes: Sequence[int]) -> Dict[int, set[int]]:
    node_set = set(int(n) for n in nodes)
    return {int(node): {nbr for nbr in adj[int(node)] if nbr in node_set} for node in node_set}


def assign_load_zones(
    bus_df: pd.DataFrame,
    adj: Dict[int, set[int]],
    bus_zone: Dict[int, str],
) -> Dict[int, tuple[str, str]]:
    bus_to_loadzone: Dict[int, tuple[str, str]] = {}
    bus_lookup = bus_df[["BUS_I", "PD"]].copy()

    for zone_name in ZONE_NAMES:
        members = sorted(bus for bus, zone in bus_zone.items() if zone == zone_name)
        load_zone_defs = LOAD_ZONE_CONFIG[zone_name]
        if not members:
            continue
        if len(load_zone_defs) == 1:
            load_zone, state, _, _ = load_zone_defs[0]
            for bus in members:
                bus_to_loadzone[int(bus)] = (load_zone, state)
            continue

        zone_adj = restrict_adj(adj, members)
        zone_bus_df = bus_lookup.loc[bus_lookup["BUS_I"].isin(members)].copy()
        seeds = choose_seeds(zone_bus_df, zone_adj, n_seeds=len(load_zone_defs))
        local_assignment = repair_connectivity(assign_voronoi_zones(zone_adj, seeds), zone_adj)

        cluster_means = []
        for cluster_idx in sorted(set(local_assignment.values())):
            cluster_members = [bus for bus, idx in local_assignment.items() if idx == cluster_idx]
            cluster_means.append((cluster_idx, float(np.mean(cluster_members))))
        cluster_means.sort(key=lambda item: item[1])

        ordered_load_zones = load_zone_defs[:]
        if zone_name == "NNE":
            ordered_load_zones = sorted(load_zone_defs, key=lambda item: item[3])  # VT west, NH east
        elif zone_name == "ROP":
            ordered_load_zones = sorted(load_zone_defs, key=lambda item: item[2])  # CT south, WCMA north
        elif zone_name == "SENE":
            ordered_load_zones = sorted(load_zone_defs, key=lambda item: (item[2], item[3]))

        cluster_to_loadzone = {
            cluster_idx: ordered_load_zones[pos]
            for pos, (cluster_idx, _) in enumerate(cluster_means)
        }
        for bus, cluster_idx in local_assignment.items():
            load_zone, state, _, _ = cluster_to_loadzone[cluster_idx]
            bus_to_loadzone[int(bus)] = (load_zone, state)

    return bus_to_loadzone


def _sunflower_points(n_points: int) -> np.ndarray:
    if n_points <= 0:
        return np.zeros((0, 2), dtype=float)
    golden_angle = math.pi * (3.0 - math.sqrt(5.0))
    pts = np.zeros((n_points, 2), dtype=float)
    for idx in range(n_points):
        radius = math.sqrt((idx + 0.5) / n_points)
        angle = idx * golden_angle
        pts[idx, 0] = radius * math.cos(angle)
        pts[idx, 1] = radius * math.sin(angle)
    return pts


def _compute_external_pull(
    bus: int,
    load_zone: str,
    adj: Dict[int, set[int]],
    bus_to_loadzone: Dict[int, tuple[str, str]],
) -> np.ndarray:
    geom = LOAD_ZONE_GEOMETRY[load_zone]
    anchor = np.array([geom["lon"], geom["lat"]], dtype=float)
    vectors: list[np.ndarray] = []
    for nbr in adj[bus]:
        nbr_load_zone = bus_to_loadzone.get(int(nbr), (load_zone, ""))[0]
        if nbr_load_zone == load_zone or nbr_load_zone not in LOAD_ZONE_GEOMETRY:
            continue
        nbr_geom = LOAD_ZONE_GEOMETRY[nbr_load_zone]
        vec = np.array([nbr_geom["lon"], nbr_geom["lat"]], dtype=float) - anchor
        norm = float(np.linalg.norm(vec))
        if norm > 1e-9:
            vectors.append(vec / norm)
    if not vectors:
        return np.zeros(2, dtype=float)
    pull = np.mean(np.vstack(vectors), axis=0)
    norm = float(np.linalg.norm(pull))
    return pull / norm if norm > 1e-9 else np.zeros(2, dtype=float)


def _force_layout_points(
    buses: Sequence[int],
    adj: Dict[int, set[int]],
    bus_to_loadzone: Dict[int, tuple[str, str]],
    load_zone: str,
) -> Dict[int, tuple[float, float]]:
    if not buses:
        return {}
    buses = [int(b) for b in buses]
    if len(buses) == 1:
        return {buses[0]: (0.0, 0.0)}

    idx_of = {bus: idx for idx, bus in enumerate(buses)}
    local_adj = restrict_adj(adj, buses)
    edge_pairs = []
    for bus in buses:
        for nbr in local_adj[bus]:
            if bus < nbr:
                edge_pairs.append((idx_of[bus], idx_of[nbr]))

    pos = _sunflower_points(len(buses)) * 0.55
    ext_pull = np.vstack([_compute_external_pull(bus, load_zone, adj, bus_to_loadzone) for bus in buses])

    degrees = np.array([len(local_adj[bus]) for bus in buses], dtype=float)
    if degrees.max() > 0:
        degrees = degrees / degrees.max()

    for iteration in range(180):
        disp = np.zeros_like(pos)
        # Repulsive force.
        for i in range(len(buses)):
            delta = pos[i] - pos
            dist_sq = np.sum(delta * delta, axis=1) + 1e-4
            mask = np.arange(len(buses)) != i
            rep = (delta[mask].T / dist_sq[mask]).T
            disp[i] += rep.sum(axis=0) * 0.018

        # Spring force along branches.
        for i, j in edge_pairs:
            delta = pos[j] - pos[i]
            dist = max(float(np.linalg.norm(delta)), 1e-4)
            preferred = 0.16 + 0.10 * abs(degrees[i] - degrees[j])
            force = 0.22 * (dist - preferred)
            vec = delta / dist
            disp[i] += vec * force
            disp[j] -= vec * force

        # Centering and external directional pull for boundary buses.
        disp += (-0.08 * pos)
        disp += (0.04 * ext_pull)

        # Keep points inside a soft unit ellipse.
        radius = np.sqrt(np.sum(pos * pos, axis=1))
        outside = radius > 0.98
        if np.any(outside):
            disp[outside] += (-0.20 * pos[outside].T / radius[outside]).T

        step = 0.22 * (1.0 - 0.55 * iteration / 180.0)
        pos += step * disp
        pos = np.clip(pos, -1.18, 1.18)

    geom = LOAD_ZONE_GEOMETRY[load_zone]
    theta = math.radians(float(geom["angle"]))
    ct = math.cos(theta)
    st = math.sin(theta)
    width = float(geom["width"]) * 0.48
    height = float(geom["height"]) * 0.48
    anchor_lon = float(geom["lon"])
    anchor_lat = float(geom["lat"])

    coords: Dict[int, tuple[float, float]] = {}
    for idx, bus in enumerate(buses):
        x = float(pos[idx, 0] * width)
        y = float(pos[idx, 1] * height)
        lon = anchor_lon + x * ct - y * st
        lat = anchor_lat + x * st + y * ct
        coords[bus] = (lat, lon)
    return coords


def generate_geo_coordinates(
    bus_geo: pd.DataFrame,
    adj: Dict[int, set[int]],
    bus_to_loadzone: Dict[int, tuple[str, str]],
) -> pd.DataFrame:
    bus_geo = bus_geo.copy()
    latitudes: Dict[int, float] = {}
    longitudes: Dict[int, float] = {}

    for load_zone, grp in bus_geo.groupby("LoadZone", sort=False):
        buses = sorted(grp["Bus_id"].astype(int).tolist())
        coords = _force_layout_points(buses, adj, bus_to_loadzone, str(load_zone))
        for bus, (lat, lon) in coords.items():
            latitudes[int(bus)] = float(lat)
            longitudes[int(bus)] = float(lon)

    bus_geo["Latitude"] = bus_geo["Bus_id"].map(latitudes).astype(float)
    bus_geo["Longitude"] = bus_geo["Bus_id"].map(longitudes).astype(float)
    bus_geo = blend_bus_coordinates_with_public_anchors(bus_geo)
    bus_geo = blend_bus_coordinates_with_grid_anchors(bus_geo)
    bus_geo = blend_bus_coordinates_with_osm_substations(bus_geo, adj)
    bus_geo = blend_bus_coordinates_with_corridors(bus_geo, adj)
    return bus_geo


@lru_cache(maxsize=1)
def _load_optional_osm_substations() -> pd.DataFrame | None:
    if not OSM_SUBSTATIONS_CSV.exists():
        return None
    df = pd.read_csv(OSM_SUBSTATIONS_CSV)
    if df.empty:
        return None
    required = {"Latitude", "Longitude"}
    if not required.issubset(df.columns):
        return None
    work = df.copy()
    work["Latitude"] = pd.to_numeric(work["Latitude"], errors="coerce")
    work["Longitude"] = pd.to_numeric(work["Longitude"], errors="coerce")
    if "AnchorWeight" in work.columns:
        work["AnchorWeight"] = pd.to_numeric(work["AnchorWeight"], errors="coerce").fillna(1.0)
    else:
        work["AnchorWeight"] = 1.0
    if "VoltageKV" in work.columns:
        work["VoltageKV"] = pd.to_numeric(work["VoltageKV"], errors="coerce")
    else:
        work["VoltageKV"] = np.nan
    work = work.loc[pd.notna(work["Latitude"]) & pd.notna(work["Longitude"])].copy()
    if "VoltageKV" in work.columns:
        work = work.loc[work["VoltageKV"].fillna(115.0) >= 115.0].copy()
    return work.reset_index(drop=True) if not work.empty else None


@lru_cache(maxsize=1)
def _load_optional_osm_corridor_points() -> list[tuple[float, float]]:
    if not OSM_CORRIDOR_POINTS_CSV.exists():
        return []
    df = pd.read_csv(OSM_CORRIDOR_POINTS_CSV)
    if df.empty or "Latitude" not in df.columns or "Longitude" not in df.columns:
        return []
    work = df.copy()
    work["Latitude"] = pd.to_numeric(work["Latitude"], errors="coerce")
    work["Longitude"] = pd.to_numeric(work["Longitude"], errors="coerce")
    work = work.loc[pd.notna(work["Latitude"]) & pd.notna(work["Longitude"])].copy()
    if "VoltageKV" in work.columns:
        work["VoltageKV"] = pd.to_numeric(work["VoltageKV"], errors="coerce")
        work = work.loc[work["VoltageKV"].fillna(115.0) >= 115.0].copy()
    work = work.drop_duplicates(subset=["Latitude", "Longitude"])
    return [(float(row.Latitude), float(row.Longitude)) for row in work.itertuples(index=False)]


def blend_bus_coordinates_with_osm_substations(
    bus_geo: pd.DataFrame,
    adj: Dict[int, set[int]],
) -> pd.DataFrame:
    substation_df = _load_optional_osm_substations()
    if substation_df is None:
        return bus_geo

    bus_geo = bus_geo.copy()
    degree_map = {int(bus): len(adj.get(int(bus), set())) for bus in bus_geo["Bus_id"].astype(int)}
    max_degree = max(degree_map.values()) if degree_map else 1
    revised_lat: dict[int, float] = {}
    revised_lon: dict[int, float] = {}

    for row in bus_geo.itertuples(index=False):
        lat = float(row.Latitude)
        lon = float(row.Longitude)
        distances = substation_df.apply(
            lambda sub: _coord_distance(lat, lon, float(sub["Latitude"]), float(sub["Longitude"])),
            axis=1,
        )
        nearest_miles = float(distances.min()) if len(distances) else 999.0
        if nearest_miles > 80.0:
            continue
        work = substation_df.copy()
        work["DistanceMiles"] = distances
        work.sort_values("DistanceMiles", inplace=True)
        work = work.head(8).copy()
        work["RawWeight"] = work.apply(
            lambda sub: float(sub["AnchorWeight"]) / (max(float(sub["DistanceMiles"]), 1.5) ** 2),
            axis=1,
        )
        total = float(work["RawWeight"].sum())
        if total <= 0.0:
            continue
        target_lat = float(np.average(work["Latitude"], weights=work["RawWeight"]))
        target_lon = float(np.average(work["Longitude"], weights=work["RawWeight"]))
        degree_norm = float(degree_map.get(int(row.Bus_id), 0)) / max(max_degree, 1)
        nearest_factor = math.exp(-nearest_miles / 26.0)
        blend = min(0.22, 0.06 + 0.08 * degree_norm + 0.10 * nearest_factor)
        revised_lat[int(row.Bus_id)] = (1.0 - blend) * lat + blend * target_lat
        revised_lon[int(row.Bus_id)] = (1.0 - blend) * lon + blend * target_lon

    if revised_lat:
        bus_geo["Latitude"] = bus_geo["Bus_id"].map(lambda b: float(revised_lat.get(int(b), bus_geo.loc[bus_geo["Bus_id"] == b, "Latitude"].iloc[0])))
        bus_geo["Longitude"] = bus_geo["Bus_id"].map(lambda b: float(revised_lon.get(int(b), bus_geo.loc[bus_geo["Bus_id"] == b, "Longitude"].iloc[0])))
    return bus_geo


def blend_bus_coordinates_with_public_anchors(bus_geo: pd.DataFrame) -> pd.DataFrame:
    bus_geo = bus_geo.copy()
    new_lat: dict[int, float] = {}
    new_lon: dict[int, float] = {}

    for load_zone, grp in bus_geo.groupby("LoadZone", sort=False):
        anchors = LOAD_ZONE_PUBLIC_ANCHORS.get(str(load_zone))
        if not anchors:
            continue
        for row in grp.itertuples(index=False):
            lat = float(row.Latitude)
            lon = float(row.Longitude)
            weighted_targets = []
            total_w = 0.0
            for anchor in anchors:
                d = max(_coord_distance(lat, lon, float(anchor["lat"]), float(anchor["lon"])), 1e-3)
                w = float(anchor["weight"]) / (d * d)
                weighted_targets.append((w, float(anchor["lat"]), float(anchor["lon"])))
                total_w += w
            if total_w <= 0.0:
                continue
            target_lat = sum(w * alat for w, alat, _ in weighted_targets) / total_w
            target_lon = sum(w * alon for w, _, alon in weighted_targets) / total_w
            blend = 0.32
            new_lat[int(row.Bus_id)] = (1.0 - blend) * lat + blend * target_lat
            new_lon[int(row.Bus_id)] = (1.0 - blend) * lon + blend * target_lon

    if new_lat:
        bus_geo["Latitude"] = bus_geo["Bus_id"].map(lambda b: float(new_lat.get(int(b), bus_geo.loc[bus_geo["Bus_id"] == b, "Latitude"].iloc[0])))
        bus_geo["Longitude"] = bus_geo["Bus_id"].map(lambda b: float(new_lon.get(int(b), bus_geo.loc[bus_geo["Bus_id"] == b, "Longitude"].iloc[0])))
    return bus_geo


def blend_bus_coordinates_with_grid_anchors(bus_geo: pd.DataFrame) -> pd.DataFrame:
    bus_geo = bus_geo.copy()
    new_lat: dict[int, float] = {}
    new_lon: dict[int, float] = {}

    for load_zone, grp in bus_geo.groupby("LoadZone", sort=False):
        anchors = LOAD_ZONE_GRID_ANCHORS.get(str(load_zone))
        if not anchors:
            continue
        for row in grp.itertuples(index=False):
            lat = float(row.Latitude)
            lon = float(row.Longitude)
            weighted_targets = []
            total_w = 0.0
            for anchor in anchors:
                d = max(_coord_distance(lat, lon, float(anchor["lat"]), float(anchor["lon"])), 1e-3)
                w = float(anchor["weight"]) / (d * d)
                weighted_targets.append((w, float(anchor["lat"]), float(anchor["lon"])))
                total_w += w
            if total_w <= 0.0:
                continue
            target_lat = sum(w * alat for w, alat, _ in weighted_targets) / total_w
            target_lon = sum(w * alon for w, _, alon in weighted_targets) / total_w
            blend = 0.18
            new_lat[int(row.Bus_id)] = (1.0 - blend) * lat + blend * target_lat
            new_lon[int(row.Bus_id)] = (1.0 - blend) * lon + blend * target_lon

    if new_lat:
        bus_geo["Latitude"] = bus_geo["Bus_id"].map(lambda b: float(new_lat.get(int(b), bus_geo.loc[bus_geo["Bus_id"] == b, "Latitude"].iloc[0])))
        bus_geo["Longitude"] = bus_geo["Bus_id"].map(lambda b: float(new_lon.get(int(b), bus_geo.loc[bus_geo["Bus_id"] == b, "Longitude"].iloc[0])))
    return bus_geo


def _sample_polyline(polyline: Sequence[tuple[float, float]], steps_per_segment: int = 12) -> list[tuple[float, float]]:
    if len(polyline) < 2:
        return list(polyline)
    points: list[tuple[float, float]] = []
    for start, end in zip(polyline[:-1], polyline[1:]):
        for t in np.linspace(0.0, 1.0, steps_per_segment, endpoint=False):
            lat = (1.0 - float(t)) * float(start[0]) + float(t) * float(end[0])
            lon = (1.0 - float(t)) * float(start[1]) + float(t) * float(end[1])
            points.append((lat, lon))
    points.append((float(polyline[-1][0]), float(polyline[-1][1])))
    return points


def _nearest_distance_to_points(lat: float, lon: float, points: Sequence[tuple[float, float]]) -> float:
    if not points:
        return 999.0
    return min(_coord_distance(lat, lon, plat, plon) for plat, plon in points)


def blend_bus_coordinates_with_corridors(
    bus_geo: pd.DataFrame,
    adj: Dict[int, set[int]],
) -> pd.DataFrame:
    bus_geo = bus_geo.copy()
    degree_map = {int(bus): len(adj.get(int(bus), set())) for bus in bus_geo["Bus_id"].astype(int)}
    max_degree = max(degree_map.values()) if degree_map else 1
    bus_geo["Degree"] = bus_geo["Bus_id"].map(lambda b: float(degree_map.get(int(b), 0)))

    revised_lat: dict[int, float] = {}
    revised_lon: dict[int, float] = {}

    for load_zone, grp in bus_geo.groupby("LoadZone", sort=False):
        polylines = LOAD_ZONE_CORRIDORS.get(str(load_zone), [])
        sample_points: list[tuple[float, float]] = []
        for polyline in polylines:
            sample_points.extend(_sample_polyline(polyline))
        sample_points.extend(_load_optional_osm_corridor_points())
        if not sample_points:
            continue

        for row in grp.itertuples(index=False):
            lat = float(row.Latitude)
            lon = float(row.Longitude)
            nearest = min(sample_points, key=lambda pt: _coord_distance(lat, lon, pt[0], pt[1]))
            min_dist = _nearest_distance_to_points(lat, lon, sample_points)
            degree_norm = float(getattr(row, "Degree")) / max(max_degree, 1)
            corridor_proximity = max(0.0, min(1.0, math.exp(-min_dist / 18.0)))
            blend = min(0.34, 0.10 + 0.18 * degree_norm + 0.10 * corridor_proximity)
            revised_lat[int(row.Bus_id)] = (1.0 - blend) * lat + blend * float(nearest[0])
            revised_lon[int(row.Bus_id)] = (1.0 - blend) * lon + blend * float(nearest[1])

    if revised_lat:
        bus_geo["Latitude"] = bus_geo["Bus_id"].map(lambda b: float(revised_lat.get(int(b), bus_geo.loc[bus_geo["Bus_id"] == b, "Latitude"].iloc[0])))
        bus_geo["Longitude"] = bus_geo["Bus_id"].map(lambda b: float(revised_lon.get(int(b), bus_geo.loc[bus_geo["Bus_id"] == b, "Longitude"].iloc[0])))
    return bus_geo.drop(columns=["Degree"])


def _coord_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    lat_scale = 69.0
    lon_scale = 52.0
    dlat = (lat1 - lat2) * lat_scale
    dlon = (lon1 - lon2) * lon_scale
    return math.sqrt(dlat * dlat + dlon * dlon)


def assign_load_zone_from_coord(latitude: float | None, longitude: float | None, state: str) -> str:
    state = str(state).strip().upper()
    candidates = [load_zone for load_zone, load_state in LOAD_ZONE_TO_STATE.items() if load_state == state]
    if not candidates:
        candidates = list(LOAD_ZONE_GEOMETRY.keys())
    if latitude is None or longitude is None or math.isnan(latitude) or math.isnan(longitude):
        return candidates[0]
    best = min(
        candidates,
        key=lambda load_zone: _coord_distance(
            float(latitude),
            float(longitude),
            float(LOAD_ZONE_GEOMETRY[load_zone]["lat"]),
            float(LOAD_ZONE_GEOMETRY[load_zone]["lon"]),
        ),
    )
    return str(best)


def _weighted_mean(series: pd.Series, weights: pd.Series, default: float | None = None) -> float | None:
    mask = pd.notna(series) & pd.notna(weights)
    if not mask.any():
        return default
    vals = pd.to_numeric(series[mask], errors="coerce")
    wts = pd.to_numeric(weights[mask], errors="coerce")
    mask2 = pd.notna(vals) & pd.notna(wts) & (wts > 0)
    if not mask2.any():
        return default
    vals = vals[mask2]
    wts = wts[mask2]
    return float(np.average(vals, weights=wts))


def _weighted_yes_fraction(series: pd.Series, weights: pd.Series) -> float:
    norm = series.fillna("").astype(str).str.strip().str.upper().eq("Y").astype(float)
    wts = pd.to_numeric(weights, errors="coerce").fillna(0.0)
    denom = float(wts.sum())
    if denom <= 0:
        return 0.0
    return float((norm * wts).sum() / denom)


def load_eia860_vre_attributes() -> pd.DataFrame:
    pieces: list[pd.DataFrame] = []

    if RAW_EIA860_WIND.exists():
        wind = pd.read_excel(RAW_EIA860_WIND, header=1)
        wind = wind[wind["State"].isin(NEW_ENGLAND_STATES)].copy()
        wind["Nameplate Capacity (MW)"] = pd.to_numeric(wind["Nameplate Capacity (MW)"], errors="coerce").fillna(0.0)
        wind = wind[wind["Technology"].isin(["Onshore Wind Turbine", "Offshore Wind Turbine"])].copy()
        if not wind.empty:
            wind_rows = []
            for plant_code, grp in wind.groupby("Plant Code", sort=False):
                cap = grp["Nameplate Capacity (MW)"]
                wind_rows.append(
                    {
                        "Plant Code": int(plant_code),
                        "WindDesignSpeedMph": _weighted_mean(grp["Design Wind Speed (mph)"], cap),
                        "WindQualityClass": _weighted_mean(grp["Wind Quality Class"], cap),
                        "WindHubHeightFt": _weighted_mean(grp["Turbine Hub Height (Feet)"], cap),
                    }
                )
            pieces.append(pd.DataFrame(wind_rows))

    if RAW_EIA860_SOLAR.exists():
        solar = pd.read_excel(RAW_EIA860_SOLAR, header=1)
        solar = solar[solar["State"].isin(NEW_ENGLAND_STATES)].copy()
        solar["Nameplate Capacity (MW)"] = pd.to_numeric(solar["Nameplate Capacity (MW)"], errors="coerce").fillna(0.0)
        solar["DC Net Capacity (MW)"] = pd.to_numeric(solar["DC Net Capacity (MW)"], errors="coerce")
        solar = solar[solar["Technology"] == "Solar Photovoltaic"].copy()
        if not solar.empty:
            solar_rows = []
            for plant_code, grp in solar.groupby("Plant Code", sort=False):
                cap = grp["Nameplate Capacity (MW)"]
                dcac = pd.to_numeric(grp["DC Net Capacity (MW)"], errors="coerce") / cap.replace(0.0, np.nan)
                solar_rows.append(
                    {
                        "Plant Code": int(plant_code),
                        "SolarSingleAxisShare": _weighted_yes_fraction(grp["Single-Axis Tracking?"], cap),
                        "SolarDualAxisShare": _weighted_yes_fraction(grp["Dual-Axis Tracking?"], cap),
                        "SolarFixedTiltShare": _weighted_yes_fraction(grp["Fixed Tilt?"], cap),
                        "SolarEastWestShare": _weighted_yes_fraction(grp["East West Fixed Tilt?"], cap),
                        "SolarBifacialShare": _weighted_yes_fraction(grp["Bifacial?"], cap),
                        "SolarDcAcRatio": _weighted_mean(dcac, cap, default=1.15),
                        "SolarAzimuthAngle": _weighted_mean(grp["Azimuth Angle"], cap),
                        "SolarTiltAngle": _weighted_mean(grp["Tilt Angle"], cap),
                    }
                )
            pieces.append(pd.DataFrame(solar_rows))

    if not pieces:
        return pd.DataFrame()

    attrs = pieces[0]
    for piece in pieces[1:]:
        attrs = attrs.merge(piece, on="Plant Code", how="outer")
    return attrs


def load_eia860_generator_data() -> pd.DataFrame:
    if not RAW_EIA860_PLANT.exists() or not RAW_EIA860_GENERATOR.exists():
        return pd.DataFrame()

    plants = pd.read_excel(RAW_EIA860_PLANT, sheet_name="Plant", header=1)
    gens = pd.read_excel(RAW_EIA860_GENERATOR, sheet_name="Operable", header=1)
    vre_attrs = load_eia860_vre_attributes()

    plants = plants[plants["State"].isin(NEW_ENGLAND_STATES)].copy()
    gens = gens[gens["State"].isin(NEW_ENGLAND_STATES)].copy()
    gens = gens[
        _available_during_case_month(
            gens,
            op_month_col="Operating Month",
            op_year_col="Operating Year",
            retirement_month_col="Planned Retirement Month",
            retirement_year_col="Planned Retirement Year",
        )
    ].copy()

    gens = gens[gens["Technology"] != "Hydroelectric Pumped Storage"].copy()
    gens["HopeType"] = gens["Technology"].map(EIA_TECH_TO_HOPE)
    gens["Summer Capacity (MW)"] = pd.to_numeric(gens["Summer Capacity (MW)"], errors="coerce").fillna(0.0)
    gens = gens[(gens["HopeType"].notna()) & (gens["Summer Capacity (MW)"] >= 5.0)].copy()
    if gens.empty:
        return pd.DataFrame()

    plant_cols = ["Plant Code", "Plant Name", "State", "County", "Latitude", "Longitude"]
    plants = plants[plant_cols].drop_duplicates(subset=["Plant Code"]).copy()
    plants["Latitude"] = pd.to_numeric(plants["Latitude"], errors="coerce")
    plants["Longitude"] = pd.to_numeric(plants["Longitude"], errors="coerce")

    merged = gens.merge(plants, on="Plant Code", how="left", suffixes=("", "_plant"))
    if "State_plant" in merged.columns:
        merged["State"] = merged["State"].fillna(merged["State_plant"])
    if "Latitude_plant" in merged.columns:
        merged["Latitude"] = merged["Latitude"].combine_first(merged["Latitude_plant"])
    if "Longitude_plant" in merged.columns:
        merged["Longitude"] = merged["Longitude"].combine_first(merged["Longitude_plant"])

    grouped = (
        merged.groupby(
            ["Plant Code", "Plant Name", "State", "County", "Latitude", "Longitude", "HopeType", "Technology"],
            dropna=False,
            as_index=False,
        )["Summer Capacity (MW)"]
        .sum()
        .rename(columns={"Summer Capacity (MW)": "Pmax (MW)", "Technology": "EIA Technology"})
    )
    if not vre_attrs.empty:
        grouped = grouped.merge(vre_attrs, on="Plant Code", how="left")

    grouped["LoadZone"] = grouped.apply(
        lambda row: assign_load_zone_from_coord(
            float(row["Latitude"]) if pd.notna(row["Latitude"]) else None,
            float(row["Longitude"]) if pd.notna(row["Longitude"]) else None,
            str(row["State"]),
        ),
        axis=1,
    )
    grouped["Zone"] = grouped["LoadZone"].map(LOAD_ZONE_TO_CAPACITY_ZONE)
    grouped["County"] = grouped["County"].fillna("")
    grouped["Plant Name"] = grouped["Plant Name"].fillna(grouped["Plant Code"].map(lambda v: f"Plant {int(v)}"))
    grouped["DataSource"] = "EIA-860 2024 Operable generators + Plant sheet"
    return grouped


def load_eia860_storage_data() -> pd.DataFrame:
    if not RAW_EIA860_PLANT.exists() or not RAW_EIA860_STORAGE.exists():
        return pd.DataFrame()

    plants = pd.read_excel(RAW_EIA860_PLANT, sheet_name="Plant", header=1)
    storage = pd.read_excel(RAW_EIA860_STORAGE, sheet_name="Operable", header=1)
    generators = pd.read_excel(RAW_EIA860_GENERATOR, sheet_name="Operable", header=1)

    plants = plants[plants["State"].isin(NEW_ENGLAND_STATES)].copy()
    storage = storage[storage["State"].isin(NEW_ENGLAND_STATES)].copy()
    generators = generators[generators["State"].isin(NEW_ENGLAND_STATES)].copy()
    storage = storage[
        _available_during_case_month(
            storage,
            op_month_col="Operating Month",
            op_year_col="Operating Year",
        )
    ].copy()
    generators = generators[
        _available_during_case_month(
            generators,
            op_month_col="Operating Month",
            op_year_col="Operating Year",
            retirement_month_col="Planned Retirement Month",
            retirement_year_col="Planned Retirement Year",
        )
    ].copy()
    storage = storage[storage["Technology"] == "Batteries"].copy()

    storage["Nameplate Capacity (MW)"] = pd.to_numeric(storage["Nameplate Capacity (MW)"], errors="coerce").fillna(0.0)
    storage["Maximum Charge Rate (MW)"] = pd.to_numeric(storage["Maximum Charge Rate (MW)"], errors="coerce")
    storage["Maximum Discharge Rate (MW)"] = pd.to_numeric(storage["Maximum Discharge Rate (MW)"], errors="coerce")
    storage["Nameplate Energy Capacity (MWh)"] = pd.to_numeric(storage["Nameplate Energy Capacity (MWh)"], errors="coerce")
    storage = storage[storage["Nameplate Capacity (MW)"] >= 0.5].copy()

    plant_cols = ["Plant Code", "Plant Name", "State", "County", "Latitude", "Longitude"]
    plants = plants[plant_cols].drop_duplicates(subset=["Plant Code"]).copy()
    plants["Latitude"] = pd.to_numeric(plants["Latitude"], errors="coerce")
    plants["Longitude"] = pd.to_numeric(plants["Longitude"], errors="coerce")

    merged = storage.merge(plants, on="Plant Code", how="left", suffixes=("", "_plant"))
    if "State_plant" in merged.columns:
        merged["State"] = merged["State"].fillna(merged["State_plant"])
    if "Latitude_plant" in merged.columns:
        merged["Latitude"] = merged["Latitude"].combine_first(merged["Latitude_plant"])
    if "Longitude_plant" in merged.columns:
        merged["Longitude"] = merged["Longitude"].combine_first(merged["Longitude_plant"])

    merged["Plant Name"] = merged["Plant Name"].fillna(merged["Plant Code"].map(lambda v: f"Storage Plant {int(v)}"))
    merged["LoadZone"] = merged.apply(
        lambda row: assign_load_zone_from_coord(
            float(row["Latitude"]) if pd.notna(row["Latitude"]) else None,
            float(row["Longitude"]) if pd.notna(row["Longitude"]) else None,
            str(row["State"]),
        ),
        axis=1,
    )
    merged["Zone"] = merged["LoadZone"].map(LOAD_ZONE_TO_CAPACITY_ZONE)
    merged["StorageType"] = "BES"
    merged["EnergyCapacityMWh"] = merged["Nameplate Energy Capacity (MWh)"].fillna(0.0)
    merged.loc[merged["EnergyCapacityMWh"] <= 0.0, "EnergyCapacityMWh"] = 2.0 * merged["Nameplate Capacity (MW)"]
    merged["ChargeMW"] = merged["Maximum Charge Rate (MW)"].fillna(merged["Nameplate Capacity (MW)"])
    merged["DischargeMW"] = merged["Maximum Discharge Rate (MW)"].fillna(merged["Nameplate Capacity (MW)"])
    merged["County"] = merged["County"].fillna("")
    merged["DataSource"] = "EIA-860 2024 Operable energy storage + Plant sheet"
    battery_df = merged[
        [
            "Plant Code",
            "Plant Name",
            "State",
            "County",
            "Latitude",
            "Longitude",
            "LoadZone",
            "Zone",
            "StorageType",
            "Nameplate Capacity (MW)",
            "EnergyCapacityMWh",
            "ChargeMW",
            "DischargeMW",
            "DataSource",
        ]
    ].copy()

    phs = generators[generators["Technology"] == "Hydroelectric Pumped Storage"].copy()
    phs["Summer Capacity (MW)"] = pd.to_numeric(phs["Summer Capacity (MW)"], errors="coerce").fillna(0.0)
    phs = phs[phs["Summer Capacity (MW)"] >= 1.0].copy()
    if not phs.empty:
        phs = phs.merge(plants, on="Plant Code", how="left", suffixes=("", "_plant"))
        if "State_plant" in phs.columns:
            phs["State"] = phs["State"].fillna(phs["State_plant"])
        if "Latitude_plant" in phs.columns:
            phs["Latitude"] = phs["Latitude"].combine_first(phs["Latitude_plant"])
        if "Longitude_plant" in phs.columns:
            phs["Longitude"] = phs["Longitude"].combine_first(phs["Longitude_plant"])
        phs_grouped = (
            phs.groupby(["Plant Code", "Plant Name", "State", "County", "Latitude", "Longitude"], dropna=False, as_index=False)["Summer Capacity (MW)"]
            .sum()
            .rename(columns={"Summer Capacity (MW)": "Nameplate Capacity (MW)"})
        )
        phs_grouped["Plant Name"] = phs_grouped["Plant Name"].fillna(phs_grouped["Plant Code"].map(lambda v: f"Pumped Storage Plant {int(v)}"))
        phs_grouped["LoadZone"] = phs_grouped.apply(
            lambda row: assign_load_zone_from_coord(
                float(row["Latitude"]) if pd.notna(row["Latitude"]) else None,
                float(row["Longitude"]) if pd.notna(row["Longitude"]) else None,
                str(row["State"]),
            ),
            axis=1,
        )
        phs_grouped["Zone"] = phs_grouped["LoadZone"].map(LOAD_ZONE_TO_CAPACITY_ZONE)
        phs_grouped["StorageType"] = "PHS"
        phs_grouped["ChargeMW"] = phs_grouped["Nameplate Capacity (MW)"]
        phs_grouped["DischargeMW"] = phs_grouped["Nameplate Capacity (MW)"]
        phs_grouped["DurationHours"] = phs_grouped["Plant Code"].map(
            lambda pc: float(PHS_ASSUMPTIONS.get(int(pc), {}).get("duration_hours", 8.0))
            if PHS_ASSUMPTIONS.get(int(pc), {}).get("duration_hours") is not None
            else np.nan
        )
        phs_grouped["EnergyCapacityMWh"] = phs_grouped.apply(
            lambda row: float(PHS_ASSUMPTIONS.get(int(row["Plant Code"]), {}).get("energy_mwh", row["Nameplate Capacity (MW)"] * row["DurationHours"])),
            axis=1,
        )
        phs_grouped["ChargeEff"] = phs_grouped["Plant Code"].map(
            lambda pc: float(PHS_ASSUMPTIONS.get(int(pc), {}).get("charge_efficiency", 0.85))
        )
        phs_grouped["DischargeEff"] = phs_grouped["Plant Code"].map(
            lambda pc: float(PHS_ASSUMPTIONS.get(int(pc), {}).get("discharge_efficiency", 0.85))
        )
        phs_grouped["County"] = phs_grouped["County"].fillna("")
        phs_grouped["DataSource"] = phs_grouped["Plant Code"].map(
            lambda pc: str(PHS_ASSUMPTIONS.get(int(pc), {}).get("source_note", "EIA-860 2024 pumped-storage generators + Plant sheet with generic 8-hour storage assumption"))
        )
        phs_df = phs_grouped[
            [
                "Plant Code",
                "Plant Name",
                "State",
                "County",
                "Latitude",
                "Longitude",
                "LoadZone",
                "Zone",
                "StorageType",
                "Nameplate Capacity (MW)",
                "EnergyCapacityMWh",
                "ChargeMW",
                "DischargeMW",
                "ChargeEff",
                "DischargeEff",
                "DataSource",
            ]
        ].copy()
    else:
        phs_df = pd.DataFrame(columns=battery_df.columns)

    combined = pd.concat([battery_df, phs_df], ignore_index=True)
    if combined.empty:
        return pd.DataFrame()
    return combined


def choose_branch_capacity(row: pd.Series) -> float:
    for col in ("RATE_A", "RATE_B", "RATE_C"):
        val = float(row[col])
        if val > 0:
            return val
    return 10_000.0


def apply_branch_capacity_tuning(branch_active: pd.DataFrame) -> pd.DataFrame:
    tuned = branch_active.copy()
    branch_keys = tuned.apply(
        lambda row: tuple(sorted((int(row["from_bus"]), int(row["to_bus"])))),
        axis=1,
    )
    targets = branch_keys.map(lambda key: float(BRANCH_CAPACITY_TARGETS_MW.get(key, 0.0)))
    tuned["Capacity (MW)"] = np.where(
        targets.to_numpy(dtype=float) > 0.0,
        np.maximum(tuned["Capacity (MW)"].to_numpy(dtype=float), targets.to_numpy(dtype=float)),
        tuned["Capacity (MW)"].to_numpy(dtype=float),
    )
    return tuned


def build_bus_strength_metrics(
    bus_geo: pd.DataFrame,
    branch_df: pd.DataFrame,
    adj: Dict[int, set[int]],
) -> pd.DataFrame:
    branch_active = branch_df[branch_df["BR_STATUS"] > 0].copy()
    if branch_active.empty:
        metrics = bus_geo[["Bus_id"]].copy()
        metrics["Degree"] = bus_geo["Bus_id"].map(lambda b: len(adj.get(int(b), set()))).astype(float)
        metrics["IncidentCapacityMW"] = 0.0
        metrics["CrossLoadZoneLinks"] = 0.0
        metrics["StrengthScore"] = 0.0
        metrics["CorridorScore"] = 0.0
        metrics["LoadCenterScore"] = 0.0
        metrics["GridAnchorScore"] = 0.0
        return metrics

    branch_active["CapacityMW"] = branch_active.apply(choose_branch_capacity, axis=1)
    cap_records: list[dict] = []
    bus_lz = bus_geo.set_index("Bus_id")["LoadZone"].to_dict()

    for row in branch_active.itertuples(index=False):
        from_bus = int(row.F_BUS)
        to_bus = int(row.T_BUS)
        cap = float(row.CapacityMW)
        from_lz = str(bus_lz.get(from_bus, ""))
        to_lz = str(bus_lz.get(to_bus, ""))
        cross = 1.0 if from_lz and to_lz and from_lz != to_lz else 0.0
        cap_records.append({"Bus_id": from_bus, "IncidentCapacityMW": cap, "CrossLoadZoneLinks": cross})
        cap_records.append({"Bus_id": to_bus, "IncidentCapacityMW": cap, "CrossLoadZoneLinks": cross})

    metrics = pd.DataFrame(cap_records).groupby("Bus_id", as_index=False).sum()
    metrics = bus_geo[["Bus_id", "LoadZone", "Latitude", "Longitude"]].merge(metrics, on="Bus_id", how="left")
    metrics["Degree"] = metrics["Bus_id"].map(lambda b: len(adj.get(int(b), set()))).astype(float)
    metrics["IncidentCapacityMW"] = metrics["IncidentCapacityMW"].fillna(0.0).astype(float)
    metrics["CrossLoadZoneLinks"] = metrics["CrossLoadZoneLinks"].fillna(0.0).astype(float)

    strength_raw = (
        np.log1p(metrics["IncidentCapacityMW"])
        + 0.18 * metrics["Degree"]
        + 0.35 * metrics["CrossLoadZoneLinks"]
    )
    denom = float(strength_raw.max() - strength_raw.min())
    metrics["StrengthScore"] = 0.0 if denom <= 1e-9 else (strength_raw - strength_raw.min()) / denom

    corridor_scores: list[float] = []
    anchor_scores: list[float] = []
    grid_anchor_scores: list[float] = []
    for row in metrics.itertuples(index=False):
        sample_points: list[tuple[float, float]] = []
        for polyline in LOAD_ZONE_CORRIDORS.get(str(row.LoadZone), []):
            sample_points.extend(_sample_polyline(polyline))
        corridor_dist = _nearest_distance_to_points(float(row.Latitude), float(row.Longitude), sample_points)
        corridor_scores.append(math.exp(-corridor_dist / 18.0))

        anchors = LOAD_ZONE_PUBLIC_ANCHORS.get(str(row.LoadZone), [])
        if not anchors:
            anchor_scores.append(0.0)
        else:
            vals = []
            for anchor in anchors:
                dist = max(_coord_distance(float(row.Latitude), float(row.Longitude), float(anchor["lat"]), float(anchor["lon"])), 0.5)
                vals.append(float(anchor["weight"]) / dist)
            anchor_scores.append(float(sum(vals) / max(len(vals), 1)))

        grid_anchors = LOAD_ZONE_GRID_ANCHORS.get(str(row.LoadZone), [])
        if not grid_anchors:
            grid_anchor_scores.append(0.0)
        else:
            vals = []
            for anchor in grid_anchors:
                dist = max(_coord_distance(float(row.Latitude), float(row.Longitude), float(anchor["lat"]), float(anchor["lon"])), 0.5)
                vals.append(float(anchor["weight"]) / dist)
            grid_anchor_scores.append(float(sum(vals) / max(len(vals), 1)))

    metrics["CorridorScore"] = corridor_scores
    anchor_series = pd.Series(anchor_scores, dtype=float)
    denom = float(anchor_series.max() - anchor_series.min())
    metrics["LoadCenterScore"] = 0.0 if denom <= 1e-9 else (anchor_series - anchor_series.min()) / denom
    grid_series = pd.Series(grid_anchor_scores, dtype=float)
    denom = float(grid_series.max() - grid_series.min())
    metrics["GridAnchorScore"] = 0.0 if denom <= 1e-9 else (grid_series - grid_series.min()) / denom

    return metrics


def _score_candidate_bus(
    candidates: pd.DataFrame,
    plant_lat: float,
    plant_lon: float,
    size_mw: float,
    assigned_capacity_by_bus: dict[int, float],
    prefer_load_center: bool,
    placement_hint: dict[str, float] | None = None,
    preferred_buses: Sequence[int] | None = None,
) -> int:
    work = candidates.copy()
    work["distance"] = work.apply(
        lambda cand: _coord_distance(
            plant_lat,
            plant_lon,
            float(cand["Latitude"]),
            float(cand["Longitude"]),
        ),
        axis=1,
    )
    dist_min = float(work["distance"].min())
    dist_span = float(work["distance"].max() - dist_min)
    if dist_span <= 1e-9:
        work["DistScore"] = 0.0
    else:
        work["DistScore"] = (work["distance"] - dist_min) / dist_span

    size_factor = min(1.0, max(0.0, float(size_mw) / 1000.0))
    occ_scale = max(800.0, float(size_mw) * 1.5)
    work["OccupancyPenalty"] = work["Bus_id"].map(
        lambda b: min(1.0, float(assigned_capacity_by_bus.get(int(b), 0.0)) / occ_scale)
    )
    if "IncidentCapacityMW" not in work.columns:
        work["IncidentCapacityMW"] = 0.0
    work["AssignedCapacityMW"] = work["Bus_id"].map(lambda b: float(assigned_capacity_by_bus.get(int(b), 0.0)))
    work["HeadroomMW"] = np.maximum(
        0.0,
        GENERATOR_MAX_BUS_UTILIZATION * pd.to_numeric(work["IncidentCapacityMW"], errors="coerce").fillna(0.0)
        - work["AssignedCapacityMW"],
    )
    work["HeadroomPenalty"] = 1.0 - np.minimum(1.0, work["HeadroomMW"] / max(float(size_mw), 1e-6))
    if placement_hint:
        hint_lat = float(placement_hint["lat"])
        hint_lon = float(placement_hint["lon"])
        hint_weight = float(placement_hint.get("weight", 1.0))
        work["hint_distance"] = work.apply(
            lambda cand: _coord_distance(
                hint_lat,
                hint_lon,
                float(cand["Latitude"]),
                float(cand["Longitude"]),
            ),
            axis=1,
        )
        hint_min = float(work["hint_distance"].min())
        hint_span = float(work["hint_distance"].max() - hint_min)
        if hint_span <= 1e-9:
            work["HintScore"] = 0.0
        else:
            work["HintScore"] = (work["hint_distance"] - hint_min) / hint_span
    else:
        hint_weight = 0.0
        work["HintScore"] = 0.0
    preferred_set = {int(b) for b in preferred_buses or []}
    work["PreferredPenalty"] = work["Bus_id"].map(lambda b: 0.0 if int(b) in preferred_set else 1.0)
    w_dist = 0.58 - 0.18 * size_factor
    w_strength = 0.15 + 0.18 * size_factor
    w_corridor = 0.10 + 0.06 * size_factor
    w_load = 0.05 if prefer_load_center else 0.0
    w_grid = 0.08 + 0.06 * size_factor
    w_occ = 0.04
    w_headroom = 0.12 + 0.40 * size_factor
    w_hint = 0.12 * min(1.0, hint_weight) * max(0.5, size_factor)
    w_pref = 0.08 if preferred_set else 0.0
    work["PlacementScore"] = (
        w_dist * work["DistScore"]
        + w_strength * (1.0 - work["StrengthScore"])
        + w_corridor * (1.0 - work["CorridorScore"])
        + w_load * (1.0 - work["LoadCenterScore"])
        + w_grid * (1.0 - work["GridAnchorScore"])
        + w_hint * work["HintScore"]
        + w_occ * work["OccupancyPenalty"]
        + w_headroom * work["HeadroomPenalty"]
        + w_pref * work["PreferredPenalty"]
    )
    work = work.sort_values(
        ["PlacementScore", "HeadroomPenalty", "distance", "Bus_id"],
        ascending=[True, True, True, True],
    )
    return int(work.iloc[0]["Bus_id"])


def _build_generator_bus_plan(
    candidates: pd.DataFrame,
    plant_lat: float,
    plant_lon: float,
    total_site_mw: float,
    assigned_capacity_by_bus: dict[int, float],
    prefer_load_center: bool,
    placement_hint: dict[str, float] | None = None,
    preferred_buses: Sequence[int] | None = None,
    force_bus: int | None = None,
) -> list[tuple[int, float]]:
    if candidates.empty:
        return []

    valid_candidates = candidates.copy()
    if force_bus is not None and int(force_bus) in set(valid_candidates["Bus_id"].astype(int)):
        if "IncidentCapacityMW" in valid_candidates.columns:
            incident_series = pd.to_numeric(valid_candidates["IncidentCapacityMW"], errors="coerce").fillna(0.0)
            valid_candidates = valid_candidates.assign(IncidentCapacityMW=incident_series)
            force_rows = valid_candidates[valid_candidates["Bus_id"].astype(int) == int(force_bus)]
            if not force_rows.empty:
                force_incident = float(force_rows.iloc[0]["IncidentCapacityMW"])
                if force_incident > 0.0 and total_site_mw <= GENERATOR_MAX_BUS_UTILIZATION * force_incident:
                    return [(int(force_bus), 1.0)]

    primary_bus = _score_candidate_bus(
        valid_candidates,
        plant_lat,
        plant_lon,
        total_site_mw,
        assigned_capacity_by_bus,
        prefer_load_center=prefer_load_center,
        placement_hint=placement_hint,
        preferred_buses=preferred_buses,
    )
    if total_site_mw < GENERATOR_SPLIT_MIN_SITE_MW:
        return [(primary_bus, 1.0)]

    ranked = valid_candidates.copy()
    ranked["distance"] = ranked.apply(
        lambda cand: _coord_distance(
            plant_lat,
            plant_lon,
            float(cand["Latitude"]),
            float(cand["Longitude"]),
        ),
        axis=1,
    )
    ranked["IncidentCapacityMW"] = pd.to_numeric(ranked.get("IncidentCapacityMW", 0.0), errors="coerce").fillna(0.0)
    ranked["AssignedCapacityMW"] = ranked["Bus_id"].map(lambda b: float(assigned_capacity_by_bus.get(int(b), 0.0)))
    ranked["HeadroomMW"] = np.maximum(
        0.0,
        GENERATOR_MAX_BUS_UTILIZATION * ranked["IncidentCapacityMW"] - ranked["AssignedCapacityMW"],
    )
    ranked["PreferredFlag"] = ranked["Bus_id"].map(
        lambda b: 1 if int(b) in {int(x) for x in preferred_buses or []} else 0
    )
    ranked["PrimaryFlag"] = ranked["Bus_id"].map(lambda b: 1 if int(b) == int(primary_bus) else 0)
    ranked = ranked.sort_values(
        ["PrimaryFlag", "PreferredFlag", "HeadroomMW", "IncidentCapacityMW", "distance", "Bus_id"],
        ascending=[False, False, False, False, True, True],
    )

    nearby_radius = max(
        GENERATOR_SPLIT_NEARBY_RADIUS_MILES,
        float(ranked["distance"].min()) + GENERATOR_SPLIT_NEARBY_MARGIN_MILES,
    )
    shortlist = ranked[ranked["distance"] <= nearby_radius].copy()
    if shortlist.empty:
        shortlist = ranked.copy()

    selected_rows: list[pd.Series] = []
    selected_ids: set[int] = set()
    min_segment = min(GENERATOR_SPLIT_MIN_SEGMENT_MW, total_site_mw)
    coverage = 0.0
    for _, cand in shortlist.iterrows():
        bus_id = int(cand["Bus_id"])
        if bus_id in selected_ids:
            continue
        headroom = float(cand["HeadroomMW"])
        if not selected_rows:
            selected_rows.append(cand)
            selected_ids.add(bus_id)
            coverage += max(headroom, min_segment)
            continue
        if headroom >= 0.75 * min_segment or coverage < 0.9 * total_site_mw:
            selected_rows.append(cand)
            selected_ids.add(bus_id)
            coverage += max(headroom, 0.0)
        if len(selected_rows) >= GENERATOR_SPLIT_MAX_BUSES and coverage >= 0.9 * total_site_mw:
            break

    if len(selected_rows) == 1 and float(selected_rows[0]["HeadroomMW"]) + 1e-6 < 0.8 * total_site_mw:
        for _, cand in ranked.iterrows():
            bus_id = int(cand["Bus_id"])
            if bus_id in selected_ids:
                continue
            selected_rows.append(cand)
            selected_ids.add(bus_id)
            coverage += max(float(cand["HeadroomMW"]), 0.0)
            if len(selected_rows) >= GENERATOR_SPLIT_MAX_BUSES or coverage >= 0.9 * total_site_mw:
                break

    if len(selected_rows) == 1:
        return [(int(selected_rows[0]["Bus_id"]), 1.0)]

    weights = np.array(
        [
            max(
                float(cand["HeadroomMW"]),
                0.35 * max(float(cand["IncidentCapacityMW"]), 0.0),
                min_segment,
            )
            for cand in selected_rows
        ],
        dtype=float,
    )
    if float(weights.sum()) <= 1e-9:
        return [(int(selected_rows[0]["Bus_id"]), 1.0)]

    shares = weights / float(weights.sum())
    allocations = [
        (int(cand["Bus_id"]), float(share))
        for cand, share in zip(selected_rows, shares)
        if share * total_site_mw >= min_segment or len(selected_rows) == 1
    ]
    if not allocations:
        return [(int(selected_rows[0]["Bus_id"]), 1.0)]

    share_sum = sum(share for _, share in allocations)
    if share_sum <= 1e-9:
        return [(int(selected_rows[0]["Bus_id"]), 1.0)]
    return [(bus_id, share / share_sum) for bus_id, share in allocations]


def build_eia860_generator_fleet(
    bus_geo: pd.DataFrame,
    branch_df: pd.DataFrame,
    adj: Dict[int, set[int]],
) -> tuple[pd.DataFrame, pd.DataFrame] | None:
    eia = load_eia860_generator_data()
    if eia.empty:
        return None

    work = bus_geo[["Bus_id", "CapacityZone", "LoadZone", "State", "Latitude", "Longitude"]].copy()
    work["Bus_id"] = work["Bus_id"].astype(int)
    work["Latitude"] = pd.to_numeric(work["Latitude"], errors="coerce")
    work["Longitude"] = pd.to_numeric(work["Longitude"], errors="coerce")
    metrics = build_bus_strength_metrics(bus_geo, branch_df, adj)
    work = work.merge(
        metrics[
            [
                "Bus_id",
                "IncidentCapacityMW",
                "StrengthScore",
                "CorridorScore",
                "LoadCenterScore",
                "GridAnchorScore",
            ]
        ],
        on="Bus_id",
        how="left",
    )
    assigned_capacity_by_bus: dict[int, float] = {}
    plant_plan_cache: dict[int, list[tuple[int, float]]] = {}
    plant_total_capacity = (
        eia.groupby("Plant Code", sort=False)["Pmax (MW)"].sum().astype(float).to_dict()
        if not eia.empty
        else {}
    )

    gen_rows: list[dict] = []
    mapping_rows: list[dict] = []

    sort_order = ["Pmax (MW)", "Zone", "State", "Plant Code", "HopeType"]
    for idx, row in eia.sort_values(sort_order, ascending=[False, True, True, True, True]).reset_index(drop=True).iterrows():
        load_zone = str(row["LoadZone"])
        zone = str(row["Zone"])
        state = str(row["State"])
        candidates = work[work["LoadZone"] == load_zone]
        if candidates.empty:
            candidates = work[work["State"] == state]
        if candidates.empty:
            candidates = work[work["CapacityZone"] == zone]
        if candidates.empty:
            candidates = work

        plant_lat = float(row["Latitude"]) if pd.notna(row["Latitude"]) else float(candidates["Latitude"].mean())
        plant_lon = float(row["Longitude"]) if pd.notna(row["Longitude"]) else float(candidates["Longitude"].mean())
        spec = TECH_SPECS[str(row["HopeType"])]
        pmax = float(row["Pmax (MW)"])
        plant_code = int(row["Plant Code"])
        total_site_mw = float(plant_total_capacity.get(plant_code, pmax))
        if plant_code in plant_plan_cache:
            bus_plan = plant_plan_cache[plant_code]
        else:
            placement_hint = MAJOR_PLANT_PLACEMENT_HINTS.get(str(row["Plant Name"]))
            override_bus = PLANT_BUS_OVERRIDES.get(str(row["Plant Name"]))
            preferred_buses = PLANT_BUS_CLUSTER_OVERRIDES.get(str(row["Plant Name"]))
            bus_plan = _build_generator_bus_plan(
                candidates,
                plant_lat,
                plant_lon,
                total_site_mw,
                assigned_capacity_by_bus,
                prefer_load_center=bool(spec["thermal"]),
                placement_hint=placement_hint,
                preferred_buses=preferred_buses,
                force_bus=override_bus,
            )
            plant_plan_cache[plant_code] = bus_plan
        pmin = 0.0
        reserve = float(spec["rm"]) if spec["thermal"] else 0.0
        for split_idx, (assigned_bus, share) in enumerate(bus_plan, start=1):
            pmax_segment = round(pmax * float(share), 6)
            if pmax_segment <= 1e-6:
                continue
            gen_id = f"G{len(gen_rows) + 1}"
            nearest = candidates[candidates["Bus_id"] == assigned_bus].sort_values(["Bus_id"])
            assigned_capacity_by_bus[assigned_bus] = float(assigned_capacity_by_bus.get(assigned_bus, 0.0) + pmax_segment)

            gen_rows.append(
                {
                    "PlantCode": plant_code,
                    "PlantName": str(row["Plant Name"]),
                    "SourceTechnology": str(row["EIA Technology"]),
                    "State": state,
                    "LoadZone": load_zone,
                    "Latitude": round(plant_lat, 6),
                    "Longitude": round(plant_lon, 6),
                    "Pmax (MW)": round(pmax_segment, 3),
                    "Pmin (MW)": round(pmin * float(share), 3),
                    "Zone": zone,
                    "Bus_id": assigned_bus,
                    "Type": str(row["HopeType"]),
                    "Flag_thermal": int(spec["thermal"]),
                    "Flag_RET": int(spec["ret"]),
                    "Flag_VRE": int(spec["vre"]),
                    "Flag_mustrun": int(spec["mustrun"]),
                    "Cost ($/MWh)": round(float(spec["cost"]), 3),
                    "EF": float(spec["ef"]),
                    "CC": float(spec["cc"]),
                    "AF": float(spec["af"]),
                    "FOR": float(spec["for"]),
                    "RM_SPIN": reserve,
                    "RU": float(spec["ru"]),
                    "RD": float(spec["rd"]),
                    "Flag_UC": int(spec["uc"]),
                    "Min_down_time": int(spec["min_down"]),
                    "Min_up_time": int(spec["min_up"]),
                    "Start_up_cost ($/MW)": float(spec["startup"]),
                    "RM_REG_UP": round(reserve * 0.5, 4),
                    "RM_REG_DN": round(reserve * 0.5, 4),
                    "RM_NSPIN": round(reserve * 0.75, 4),
                    "WindDesignSpeedMph": row.get("WindDesignSpeedMph"),
                    "WindQualityClass": row.get("WindQualityClass"),
                    "WindHubHeightFt": row.get("WindHubHeightFt"),
                    "SolarSingleAxisShare": row.get("SolarSingleAxisShare"),
                    "SolarDualAxisShare": row.get("SolarDualAxisShare"),
                    "SolarFixedTiltShare": row.get("SolarFixedTiltShare"),
                    "SolarEastWestShare": row.get("SolarEastWestShare"),
                    "SolarBifacialShare": row.get("SolarBifacialShare"),
                    "SolarDcAcRatio": row.get("SolarDcAcRatio"),
                    "SolarAzimuthAngle": row.get("SolarAzimuthAngle"),
                    "SolarTiltAngle": row.get("SolarTiltAngle"),
                }
            )
            mapping_rows.append(
                {
                    "GenId": gen_id,
                    "PlantCode": int(row["Plant Code"]),
                    "PlantName": str(row["Plant Name"]),
                    "HopeType": str(row["HopeType"]),
                    "EIA Technology": str(row["EIA Technology"]),
                    "State": state,
                    "County": str(row["County"]),
                    "LoadZone": load_zone,
                    "Zone": zone,
                    "Pmax (MW)": round(pmax_segment, 3),
                    "AssignedBus": assigned_bus,
                    "SplitIndex": split_idx,
                    "SplitShare": round(float(share), 6),
                    "PlantLatitude": round(plant_lat, 6),
                    "PlantLongitude": round(plant_lon, 6),
                    "AssignedBusLatitude": round(float(nearest.iloc[0]["Latitude"]), 6),
                    "AssignedBusLongitude": round(float(nearest.iloc[0]["Longitude"]), 6),
                    "MappingMethod": "Scored HOPE bus selection in same load zone using plant coordinates, grid strength, corridor proximity, occupancy penalty, and incident transmission headroom; oversized plants may be split across nearby strong buses",
                    "DataSource": "EIA-860 2024 Operable generators + Plant sheet",
                }
            )

    return pd.DataFrame(gen_rows), pd.DataFrame(mapping_rows)


def build_eia860_storage_fleet(
    bus_geo: pd.DataFrame,
    branch_df: pd.DataFrame,
    adj: Dict[int, set[int]],
) -> tuple[pd.DataFrame, pd.DataFrame] | None:
    eia = load_eia860_storage_data()
    if eia.empty:
        return None

    work = bus_geo[["Bus_id", "CapacityZone", "LoadZone", "State", "Latitude", "Longitude"]].copy()
    work["Bus_id"] = work["Bus_id"].astype(int)
    work["Latitude"] = pd.to_numeric(work["Latitude"], errors="coerce")
    work["Longitude"] = pd.to_numeric(work["Longitude"], errors="coerce")
    metrics = build_bus_strength_metrics(bus_geo, branch_df, adj)
    work = work.merge(metrics[["Bus_id", "StrengthScore", "CorridorScore", "LoadCenterScore", "GridAnchorScore"]], on="Bus_id", how="left")
    assigned_power_by_bus: dict[int, float] = {}
    plant_bus_cache: dict[int, int] = {}

    storage_rows: list[dict] = []
    mapping_rows: list[dict] = []

    for idx, row in eia.sort_values(["DischargeMW", "Zone", "State", "Plant Code"], ascending=[False, True, True, True]).reset_index(drop=True).iterrows():
        load_zone = str(row["LoadZone"])
        zone = str(row["Zone"])
        state = str(row["State"])
        candidates = work[work["LoadZone"] == load_zone]
        if candidates.empty:
            candidates = work[work["State"] == state]
        if candidates.empty:
            candidates = work[work["CapacityZone"] == zone]
        if candidates.empty:
            candidates = work

        plant_lat = float(row["Latitude"]) if pd.notna(row["Latitude"]) else float(candidates["Latitude"].mean())
        plant_lon = float(row["Longitude"]) if pd.notna(row["Longitude"]) else float(candidates["Longitude"].mean())
        spec = STORAGE_SPECS[str(row["StorageType"])]
        power_mw = float(row["DischargeMW"]) if pd.notna(row["DischargeMW"]) else float(row["Nameplate Capacity (MW)"])
        energy_mwh = float(row["EnergyCapacityMWh"])
        charge_mw = float(row["ChargeMW"]) if pd.notna(row["ChargeMW"]) else power_mw
        plant_code = int(row["Plant Code"])
        if plant_code in plant_bus_cache:
            assigned_bus = int(plant_bus_cache[plant_code])
        else:
            placement_hint = MAJOR_PLANT_PLACEMENT_HINTS.get(str(row["Plant Name"]))
            override_bus = PLANT_BUS_OVERRIDES.get(str(row["Plant Name"]))
            if override_bus is not None and int(override_bus) in set(candidates["Bus_id"].astype(int)):
                assigned_bus = int(override_bus)
            else:
                assigned_bus = _score_candidate_bus(
                    candidates,
                    plant_lat,
                    plant_lon,
                    power_mw,
                    assigned_power_by_bus,
                    prefer_load_center=str(row["StorageType"]) == "BES",
                    placement_hint=placement_hint,
                )
            plant_bus_cache[plant_code] = assigned_bus
        nearest = candidates[candidates["Bus_id"] == assigned_bus].sort_values(["Bus_id"])
        assigned_power_by_bus[assigned_bus] = float(assigned_power_by_bus.get(assigned_bus, 0.0) + power_mw)

        storage_rows.append(
            {
                "Zone": zone,
                "Bus_id": assigned_bus,
                "Type": str(row["StorageType"]),
                "Capacity (MWh)": round(energy_mwh, 3),
                "Max Power (MW)": round(power_mw, 3),
                "Charging efficiency": float(row["ChargeEff"]) if "ChargeEff" in row and pd.notna(row["ChargeEff"]) else float(spec["charging_efficiency"]),
                "Discharging efficiency": float(row["DischargeEff"]) if "DischargeEff" in row and pd.notna(row["DischargeEff"]) else float(spec["discharging_efficiency"]),
                "Cost ($/MWh)": float(spec["cost"]),
                "EF": float(spec["ef"]),
                "CC": float(spec["cc"]),
                "Charging Rate": round(charge_mw / max(power_mw, 1e-6), 4),
                "Discharging Rate": float(spec["discharging_rate"]),
            }
        )
        mapping_rows.append(
            {
                "StorageId": f"S{idx + 1}",
                "PlantCode": int(row["Plant Code"]),
                "PlantName": str(row["Plant Name"]),
                "StorageType": str(row["StorageType"]),
                "State": state,
                "County": str(row["County"]),
                "LoadZone": load_zone,
                "Zone": zone,
                "PowerMW": round(power_mw, 3),
                "EnergyMWh": round(energy_mwh, 3),
                "AssignedBus": assigned_bus,
                "PlantLatitude": round(plant_lat, 6),
                "PlantLongitude": round(plant_lon, 6),
                "AssignedBusLatitude": round(float(nearest.iloc[0]["Latitude"]), 6),
                "AssignedBusLongitude": round(float(nearest.iloc[0]["Longitude"]), 6),
                "MappingMethod": "Scored HOPE bus selection in same load zone using storage plant coordinates, grid strength, corridor proximity, and occupancy penalty",
                "DataSource": str(row["DataSource"]),
            }
        )

    return pd.DataFrame(storage_rows), pd.DataFrame(mapping_rows)


def blend_bus_coordinates_with_plants(bus_geo: pd.DataFrame, generator_map: pd.DataFrame) -> pd.DataFrame:
    if generator_map.empty or "AssignedBus" not in generator_map.columns:
        return bus_geo

    grouped = (
        generator_map.groupby("AssignedBus", as_index=False)
        .apply(
            lambda grp: pd.Series(
                {
                    "PlantAnchorLat": np.average(grp["PlantLatitude"], weights=grp["Pmax (MW)"]),
                    "PlantAnchorLon": np.average(grp["PlantLongitude"], weights=grp["Pmax (MW)"]),
                    "PlantCapacityMW": float(grp["Pmax (MW)"].sum()),
                }
            )
        )
        .reset_index(drop=True)
        .rename(columns={"AssignedBus": "Bus_id"})
    )
    merged = bus_geo.merge(grouped, on="Bus_id", how="left")
    has_anchor = merged["PlantAnchorLat"].notna() & merged["PlantAnchorLon"].notna()
    weights = np.minimum(0.55, 0.18 + merged["PlantCapacityMW"].fillna(0.0) / 10000.0)
    merged.loc[has_anchor, "Latitude"] = (
        (1.0 - weights[has_anchor]) * merged.loc[has_anchor, "Latitude"]
        + weights[has_anchor] * merged.loc[has_anchor, "PlantAnchorLat"]
    )
    merged.loc[has_anchor, "Longitude"] = (
        (1.0 - weights[has_anchor]) * merged.loc[has_anchor, "Longitude"]
        + weights[has_anchor] * merged.loc[has_anchor, "PlantAnchorLon"]
    )
    return merged[bus_geo.columns]


def build_zone_peak_targets(gen_out: pd.DataFrame) -> dict[str, float]:
    capacity_by_zone = gen_out.groupby("Zone")["Pmax (MW)"].sum().reindex(ZONE_NAMES).fillna(0.0)
    total_capacity = float(capacity_by_zone.sum())
    if total_capacity <= 0.0:
        return {zone: 0.0 for zone in ZONE_NAMES}

    capacity_share = capacity_by_zone / total_capacity
    demand_proxy_by_zone = pd.Series(
        {
            zone: float(sum(LOAD_ZONE_DEMAND_PROXY[load_zone] for load_zone, _, _, _ in LOAD_ZONE_CONFIG[zone]))
            for zone in ZONE_NAMES
        }
    )
    demand_share = demand_proxy_by_zone / float(demand_proxy_by_zone.sum())

    blended_share = 0.70 * capacity_share + 0.30 * demand_share
    system_peak_target = 0.78 * total_capacity
    return {zone: float(system_peak_target * blended_share[zone]) for zone in ZONE_NAMES}


def _normalized_weights(series: pd.Series) -> pd.Series:
    total = float(series.sum())
    if total <= 0.0:
        return pd.Series(np.full(len(series), 1.0 / max(len(series), 1)), index=series.index, dtype=float)
    return series / total


def build_bus_load_shares(
    bus_df: pd.DataFrame,
    bus_geo: pd.DataFrame,
    gen_out: pd.DataFrame,
    adj: Dict[int, set[int]],
) -> pd.DataFrame:
    bus_meta = bus_geo[["Bus_id", "CapacityZone", "LoadZone", "State"]].copy()
    bus_meta["BasePD"] = bus_df["PD"].astype(float).to_numpy()
    bus_meta["Degree"] = bus_meta["Bus_id"].map(lambda b: len(adj.get(int(b), set()))).astype(float)
    gen_by_bus = gen_out.groupby("Bus_id")["Pmax (MW)"].sum().to_dict() if not gen_out.empty else {}
    bus_meta["GenMW"] = bus_meta["Bus_id"].map(lambda b: float(gen_by_bus.get(int(b), 0.0)))
    bus_meta["NeighborGenMW"] = bus_meta["Bus_id"].map(
        lambda b: float(sum(gen_by_bus.get(int(nbr), 0.0) for nbr in adj.get(int(b), set())))
    )
    bus_meta["GenAccessMW"] = bus_meta["GenMW"] + 0.45 * bus_meta["NeighborGenMW"]

    rows: list[pd.DataFrame] = []
    zone_loadzone_targets = {
        zone: {
            load_zone: float(LOAD_ZONE_DEMAND_PROXY[load_zone])
            for load_zone, _, _, _ in LOAD_ZONE_CONFIG[zone]
        }
        for zone in ZONE_NAMES
    }

    for zone in ZONE_NAMES:
        zone_df = bus_meta[bus_meta["CapacityZone"] == zone].copy()
        if zone_df.empty:
            continue

        present_lz = set(zone_df["LoadZone"])
        load_zone_targets = {
            load_zone: target
            for load_zone, target in zone_loadzone_targets[zone].items()
            if load_zone in present_lz
        }
        for load_zone in sorted(present_lz):
            if load_zone not in load_zone_targets:
                load_zone_targets[str(load_zone)] = float(LOAD_ZONE_DEMAND_PROXY.get(str(load_zone), 1.0))
        total_lz_target = float(sum(load_zone_targets.values()))
        if total_lz_target <= 0.0:
            load_zone_targets = {str(lz): 1.0 for lz in sorted(present_lz)}
            total_lz_target = float(sum(load_zone_targets.values()))

        for load_zone, lz_target in load_zone_targets.items():
            lz_df = zone_df[zone_df["LoadZone"] == load_zone].copy()
            if lz_df.empty:
                continue

            pd_w = _normalized_weights(np.sqrt(lz_df["BasePD"].clip(lower=0.0) + 1.0))
            degree_w = _normalized_weights(lz_df["Degree"] + 1.0)
            gen_w = _normalized_weights(np.sqrt(lz_df["GenAccessMW"].clip(lower=0.0) + 1.0))
            uniform_w = pd.Series(np.full(len(lz_df), 1.0 / len(lz_df)), index=lz_df.index, dtype=float)

            combined = (
                0.30 * pd_w
                + 0.15 * degree_w
                + 0.35 * gen_w
                + 0.20 * uniform_w
            )
            combined = _normalized_weights(combined)
            public_dist = compress_public_weight_distribution(
                read_isone_nodal_load_weight_distribution(load_zone),
                len(lz_df),
            )
            if public_dist is not None:
                lz_df = lz_df.sort_values(
                    by=["GenAccessMW", "BasePD", "Degree", "Bus_id"],
                    ascending=[False, False, False, True],
                ).copy()
                lz_df["PublicWeight"] = public_dist
                final_weights = _normalized_weights(
                    0.70 * lz_df["PublicWeight"].astype(float)
                    + 0.30 * combined.loc[lz_df.index].astype(float)
                )
            else:
                final_weights = combined
            lz_df["Load_share"] = final_weights * (lz_target / total_lz_target)
            rows.append(lz_df)

    bus_shares = pd.concat(rows, ignore_index=True)
    bus_shares["Load_share"] = bus_shares["Load_share"].astype(float)
    return bus_shares[["Bus_id", "CapacityZone", "LoadZone", "State", "Load_share"]]


def build_nodal_load_timeseries(
    bus_shares: pd.DataFrame,
    hours_total: int = 744,
) -> tuple[pd.DataFrame, pd.DataFrame, dict[int, float], dict[str, float]]:
    date_index = pd.date_range("2024-07-01 00:00:00", periods=hours_total, freq="h")
    nodal_ts = pd.DataFrame(
        {
            "Time Period": 1,
            "Month": date_index.month,
            "Day": date_index.day,
            "Hours": np.arange(1, hours_total + 1),
        }
    )
    zone_hourly_mw: dict[str, np.ndarray] = {zone: np.zeros(hours_total, dtype=float) for zone in ZONE_NAMES}
    bus_peak_basis: dict[int, float] = {}
    load_zone_hourly_mw: dict[str, np.ndarray] = {}

    for load_zone in sorted(bus_shares["LoadZone"].unique()):
        zone_df = (
            bus_shares[bus_shares["LoadZone"] == load_zone]
            .sort_values(["Load_share", "Bus_id"], ascending=[False, True])
            .reset_index(drop=True)
        )
        zone_mw = read_isone_eia_zone_load(str(load_zone), hours_total=hours_total)
        public_ts = read_isone_nodal_load_timeseries(str(load_zone), hours_total=hours_total)
        if public_ts is None:
            fallback = build_hourly_profile(hours_total)
            lz_target = float(zone_df["Load_share"].sum())
            public_hourly = np.outer(fallback * lz_target, np.ones(len(zone_df), dtype=float))
        else:
            compressed = compress_public_load_timeseries(public_ts, len(zone_df))
            if compressed is None:
                fallback = build_hourly_profile(hours_total)
                lz_target = float(zone_df["Load_share"].sum())
                public_hourly = np.outer(fallback * lz_target, np.ones(len(zone_df), dtype=float))
            else:
                col_peaks = compressed.max(axis=0)
                order = np.argsort(-col_peaks)
                public_hourly = compressed[:, order]
                if zone_mw is not None:
                    row_sum = public_hourly.sum(axis=1)
                    row_sum[row_sum <= 0.0] = 1.0
                    public_hourly = (public_hourly / row_sum[:, None]) * zone_mw[:, None]

        load_zone_hourly_mw[str(load_zone)] = public_hourly.sum(axis=1)

        for idx, row in zone_df.iterrows():
            bus_id = int(row["Bus_id"])
            series = public_hourly[:, idx].astype(float)
            peak = float(series.max())
            if peak <= 0.0:
                peak = 1.0
                multiplier = np.zeros(hours_total, dtype=float)
            else:
                multiplier = series / peak
            bus_peak_basis[bus_id] = peak
            nodal_ts[str(bus_id)] = np.round(multiplier, 6)
            zone_hourly_mw[str(row["CapacityZone"])] += series

    zone_peak_basis = {zone: float(sum(bus_peak_basis[int(b)] for b in bus_shares[bus_shares["CapacityZone"] == zone]["Bus_id"])) for zone in ZONE_NAMES}
    zonal_ts = pd.DataFrame(
        {
            "Time Period": 1,
            "Month": date_index.month,
            "Day": date_index.day,
            "Hours": np.arange(1, hours_total + 1),
        }
    )
    for zone in ZONE_NAMES:
        denom = max(zone_peak_basis.get(zone, 0.0), 1e-9)
        zonal_ts[zone] = np.round(zone_hourly_mw[zone] / denom, 6)
    system_ni = build_isone_system_net_imports(hours_total=hours_total)
    zonal_ts["NI"] = np.round(system_ni, 6) if system_ni is not None else np.zeros(hours_total, dtype=float)

    return nodal_ts, zonal_ts, bus_peak_basis, zone_peak_basis


def _tech_score(row: pd.Series, tech: str, state: str, load_zone: str) -> float:
    pmax = float(row["PMAX"])
    pmin = max(0.0, float(row["PMIN"]))
    mc = float(row["MarginalCost"])
    ratio = pmin / max(pmax, 1.0)

    if tech == "NuC":
        return 4.0 * (pmax / 1200.0) - 0.03 * max(mc - 24.0, 0.0) + 1.5 * ratio
    if tech == "Hydro":
        state_bonus = 0.4 if state in {"ME", "VT", "NH"} else 0.0
        return 1.3 - 0.0016 * pmax - 0.02 * mc + state_bonus
    if tech == "WindOn":
        state_bonus = 0.45 if state in {"ME", "VT", "NH"} else -0.2
        return 1.0 - 0.0012 * pmax - 0.01 * mc + state_bonus
    if tech == "SolarPV":
        state_bonus = 0.35 if state in {"MA", "RI", "CT"} else -0.15
        load_zone_bonus = 0.18 if load_zone in {"SEMA", "NEMA/Boston", "CT", "RI"} else 0.0
        return 1.0 - 0.0013 * pmax - 0.01 * mc + state_bonus + load_zone_bonus
    if tech == "Bio":
        return 0.9 - 0.0015 * pmax - 0.012 * abs(mc - 35.0)
    if tech == "MSW":
        state_bonus = 0.3 if state in {"MA", "RI", "CT"} else -0.2
        return 0.9 - 0.0014 * pmax - 0.012 * abs(mc - 32.0) + state_bonus
    if tech == "Oil":
        return 0.03 * mc - 0.0006 * pmax + 0.4 * (1.0 - ratio)
    if tech == "NGCT":
        return 0.012 * mc - 0.0004 * pmax + 0.25 * (1.0 - ratio)
    if tech == "NGCC":
        return 1.2 + 0.0010 * pmax - 0.015 * abs(mc - 30.0) + 0.25 * ratio
    return 0.0


def build_proxy_generator_fleet(
    active_gen: pd.DataFrame,
    bus_zone: Dict[int, str],
    bus_load_zone: Dict[int, tuple[str, str]],
    gencost_rows: Sequence[Sequence[float]],
) -> tuple[pd.DataFrame, pd.DataFrame]:
    work = active_gen.copy().reset_index(drop=True)
    work["Bus_id"] = work["GEN_BUS"].astype(int)
    work["Zone"] = work["Bus_id"].map(bus_zone)
    work["LoadZone"] = work["Bus_id"].map(lambda b: bus_load_zone[int(b)][0])
    work["State"] = work["Bus_id"].map(lambda b: bus_load_zone[int(b)][1])
    work["Pmax"] = work["PMAX"].astype(float)
    work["Pmin"] = work["PMIN"].clip(lower=0.0).astype(float)
    work["MarginalCost"] = [
        marginal_cost_from_gencost(gencost_rows[idx], float(work.loc[idx, "Pmin"]), float(work.loc[idx, "Pmax"]))
        for idx in range(len(work))
    ]

    assignments: Dict[int, str] = {}
    mapping_rows: list[dict] = []
    priority_order = ["NuC", "Hydro", "WindOn", "SolarPV", "Bio", "MSW", "Oil", "NGCT", "NGCC"]

    for zone, grp in work.groupby("Zone", sort=False):
        zone_indices = grp.index.tolist()
        total_mw = float(grp["Pmax"].sum())
        targets = {tech: share * total_mw for tech, share in ZONE_TECH_TARGETS[zone].items()}
        unassigned = set(zone_indices)

        for tech in priority_order[:-1]:
            target = float(targets.get(tech, 0.0))
            if target <= 0.0:
                continue
            accumulated = 0.0
            while unassigned and accumulated < 0.86 * target:
                ranked = sorted(
                    unassigned,
                    key=lambda idx: (
                        _tech_score(work.loc[idx], tech, str(work.loc[idx, "State"]), str(work.loc[idx, "LoadZone"])),
                        -abs(float(work.loc[idx, "Pmax"]) - max(50.0, target - accumulated)),
                    ),
                    reverse=True,
                )
                candidate = ranked[0]
                score = _tech_score(work.loc[candidate], tech, str(work.loc[candidate, "State"]), str(work.loc[candidate, "LoadZone"]))
                if score < 0.05:
                    break
                assignments[candidate] = tech
                accumulated += float(work.loc[candidate, "Pmax"])
                unassigned.remove(candidate)

        # Bulk gas assignment after specialty resources.
        remaining = sorted(unassigned, key=lambda idx: float(work.loc[idx, "MarginalCost"]), reverse=True)
        oil_target = float(targets.get("Oil", 0.0))
        ngct_target = float(targets.get("NGCT", 0.0))
        oil_mw = 0.0
        ngct_mw = 0.0
        for idx in remaining:
            if oil_mw < 0.90 * oil_target and _tech_score(work.loc[idx], "Oil", str(work.loc[idx, "State"]), str(work.loc[idx, "LoadZone"])) > 0.25:
                assignments[idx] = "Oil"
                oil_mw += float(work.loc[idx, "Pmax"])
        remaining = [idx for idx in unassigned if idx not in assignments]
        remaining = sorted(remaining, key=lambda idx: _tech_score(work.loc[idx], "NGCT", str(work.loc[idx, "State"]), str(work.loc[idx, "LoadZone"])), reverse=True)
        for idx in remaining:
            if ngct_mw < 0.90 * ngct_target and _tech_score(work.loc[idx], "NGCT", str(work.loc[idx, "State"]), str(work.loc[idx, "LoadZone"])) > 0.18:
                assignments[idx] = "NGCT"
                ngct_mw += float(work.loc[idx, "Pmax"])

        for idx in zone_indices:
            assignments.setdefault(idx, "NGCC")

        actual_by_tech = Counter(assignments[idx] for idx in zone_indices)
        for idx in zone_indices:
            mapping_rows.append(
                {
                    "ProxyGenId": f"G{idx + 1}",
                    "Bus_id": int(work.loc[idx, "Bus_id"]),
                    "Zone": zone,
                    "LoadZone": str(work.loc[idx, "LoadZone"]),
                    "State": str(work.loc[idx, "State"]),
                    "Pmax (MW)": round(float(work.loc[idx, "Pmax"]), 3),
                    "Pmin (MW)": round(float(work.loc[idx, "Pmin"]), 3),
                    "TAMU_MarginalCost": round(float(work.loc[idx, "MarginalCost"]), 3),
                    "AssignedType": assignments[idx],
                    "AssignmentBasis": "Zone-level proxy tech-share heuristic using TAMU unit sizes/costs and New England-style fuel mix assumptions",
                    "ZoneTargetShare": round(float(ZONE_TECH_TARGETS[zone].get(assignments[idx], 0.0)), 4),
                    "ZoneAssignedCount": actual_by_tech[assignments[idx]],
                }
            )

    gen_rows = []
    for idx, row in work.iterrows():
        tech = assignments[idx]
        spec = TECH_SPECS[tech]
        pmax = float(row["Pmax"])
        pmin = float(row["Pmin"]) if spec["thermal"] else 0.0
        reserve = float(spec["rm"]) if spec["thermal"] else 0.0
        gen_rows.append(
            {
                "Pmax (MW)": round(pmax, 3),
                "Pmin (MW)": round(pmin, 3),
                "Zone": str(row["Zone"]),
                "Bus_id": int(row["Bus_id"]),
                "Type": tech,
                "Flag_thermal": int(spec["thermal"]),
                "Flag_RET": int(spec["ret"]),
                "Flag_VRE": int(spec["vre"]),
                "Flag_mustrun": int(spec["mustrun"]),
                "Cost ($/MWh)": round(float(spec["cost"]), 3),
                "EF": float(spec["ef"]),
                "CC": float(spec["cc"]),
                "AF": float(spec["af"]),
                "FOR": float(spec["for"]),
                "RM_SPIN": reserve,
                "RU": float(spec["ru"]),
                "RD": float(spec["rd"]),
                "Flag_UC": int(spec["uc"]),
                "Min_down_time": int(spec["min_down"]),
                "Min_up_time": int(spec["min_up"]),
                "Start_up_cost ($/MW)": float(spec["startup"]),
                "RM_REG_UP": round(reserve * 0.5, 4),
                "RM_REG_DN": round(reserve * 0.5, 4),
                "RM_NSPIN": round(reserve * 0.75, 4),
            }
        )

    return pd.DataFrame(gen_rows), pd.DataFrame(mapping_rows)


def marginal_cost_from_gencost(row: Sequence[float], pmin: float, pmax: float) -> float:
    model = int(row[0])
    ncost = int(row[3])
    coeffs = list(row[4 : 4 + ncost])
    anchor = max(pmin, 0.5 * pmax)
    if model == 2:
        if ncost >= 3:
            c2, c1 = coeffs[-3], coeffs[-2]
            return max(0.0, c1 + 2.0 * c2 * anchor)
        if ncost == 2:
            return max(0.0, coeffs[-2])
        if ncost == 1:
            return max(0.0, coeffs[0])
    if model == 1:
        points = coeffs
        if len(points) >= 4:
            slopes = []
            for idx in range(0, len(points) - 2, 2):
                x1, y1 = points[idx], points[idx + 1]
                x2, y2 = points[idx + 2], points[idx + 3]
                if x2 != x1:
                    slopes.append((y2 - y1) / (x2 - x1))
            if slopes:
                return max(0.0, float(np.mean(slopes)))
    return 25.0


def build_hourly_profile(hours_total: int = 744) -> np.ndarray:
    public_series = read_isone_hourly_system_load(RAW_ISONE_HOURLY_LOAD, hours_total=hours_total)
    if public_series is not None:
        return public_series
    hourly_shape = np.array([
        0.78, 0.75, 0.73, 0.72, 0.72, 0.74, 0.80, 0.86, 0.90, 0.93, 0.96, 0.98,
        1.00, 0.99, 0.98, 0.97, 0.98, 1.00, 1.00, 0.97, 0.93, 0.89, 0.84, 0.80,
    ])
    values = []
    date_index = pd.date_range("2024-07-01 00:00:00", periods=hours_total, freq="h")
    for ts in date_index:
        v = hourly_shape[ts.hour]
        weekday = ts.weekday()
        if weekday == 4:
            v *= 0.98
        elif weekday == 5:
            v *= 0.92
        elif weekday == 6:
            v *= 0.90
        week_mod = 1.0 + 0.025 * math.sin(2 * math.pi * (ts.day - 1) / 31.0)
        values.append(v * week_mod)
    values = np.array(values, dtype=float)
    return values / values.max()


def build_solar_profile(date_index: pd.DatetimeIndex, load_zone: str) -> np.ndarray:
    zone_scale = {
        "ME": 0.92,
        "VT": 0.95,
        "NH": 0.96,
        "CT": 1.03,
        "WCMA": 1.00,
        "RI": 1.02,
        "SEMA": 1.05,
        "NEMA/Boston": 1.01,
    }
    base = read_isone_public_vre_profile("solar", hours_total=len(date_index))
    if base is None:
        vals = []
        for ts in date_index:
            sunrise = 5.0
            sunset = 20.4
            if ts.hour < sunrise or ts.hour > sunset:
                vals.append(0.0)
                continue
            day_frac = (ts.hour - sunrise) / max(sunset - sunrise, 1e-6)
            curve = math.sin(math.pi * day_frac) ** 1.55
            cloud = 0.87 + 0.13 * math.sin(2.0 * math.pi * (ts.day - 1) / 9.0 + 0.4)
            vals.append(max(0.0, min(1.0, zone_scale.get(load_zone, 0.98) * curve * cloud)))
        return np.array(vals, dtype=float)
    return np.clip(base * zone_scale.get(load_zone, 0.98), 0.0, 1.0)


def build_solar_profile_plant(
    date_index: pd.DatetimeIndex,
    load_zone: str,
    latitude: float | None,
    single_axis_share: float,
    dual_axis_share: float,
    east_west_share: float,
    bifacial_share: float,
    dcac_ratio: float | None,
    azimuth_angle: float | None,
    tilt_angle: float | None,
) -> np.ndarray:
    lat = float(latitude) if latitude is not None and not math.isnan(latitude) else float(LOAD_ZONE_GEOMETRY[load_zone]["lat"])
    day_length = max(14.3, min(15.7, 15.0 + 0.22 * (lat - 43.0)))
    sunrise = 12.0 - day_length / 2.0
    sunset = 12.0 + day_length / 2.0
    zone_base = build_solar_profile(date_index, load_zone)
    vals = []
    dcac = float(dcac_ratio) if dcac_ratio is not None and not math.isnan(dcac_ratio) else 1.15
    az = float(azimuth_angle) if azimuth_angle is not None and not math.isnan(azimuth_angle) else 180.0
    tilt = float(tilt_angle) if tilt_angle is not None and not math.isnan(tilt_angle) else max(10.0, min(35.0, lat - 20.0))
    az_factor = max(0.94, 1.0 - abs(az - 180.0) / 500.0)
    tilt_factor = max(0.95, 1.0 - abs(tilt - max(15.0, min(35.0, lat - 18.0))) / 120.0)
    dcac_factor = max(0.96, min(1.08, 0.98 + 0.12 * (dcac - 1.0)))
    bifacial_factor = 1.0 + 0.035 * max(0.0, min(1.0, bifacial_share))
    tracking_midday = 1.0 + 0.04 * max(0.0, min(1.0, single_axis_share)) + 0.08 * max(0.0, min(1.0, dual_axis_share))
    for idx, ts in enumerate(date_index):
        hour = ts.hour + 0.5
        if hour < sunrise or hour > sunset:
            vals.append(0.0)
            continue
        frac = (hour - sunrise) / max(sunset - sunrise, 1e-6)
        shape = math.sin(math.pi * frac) ** (1.55 - 0.20 * single_axis_share - 0.35 * dual_axis_share)
        shoulder = 1.0 + 0.10 * single_axis_share * math.cos(math.pi * (frac - 0.5)) ** 2
        if east_west_share > 0:
            flatter = math.sin(math.pi * frac) ** 0.95
            shape = (1.0 - 0.35 * east_west_share) * shape + 0.35 * east_west_share * flatter
        value = zone_base[idx] * (shape / max(math.sin(math.pi * frac) ** 1.55, 1e-6)) * shoulder
        value *= az_factor * tilt_factor * dcac_factor * bifacial_factor * tracking_midday
        vals.append(max(0.0, min(1.0, value)))
    return np.array(vals, dtype=float)


def build_wind_profile(date_index: pd.DatetimeIndex, load_zone: str) -> np.ndarray:
    zone_scale = {
        "ME": 1.20,
        "VT": 1.02,
        "NH": 0.98,
        "CT": 0.72,
        "WCMA": 0.80,
        "RI": 0.90,
        "SEMA": 0.84,
        "NEMA/Boston": 0.82,
    }
    base = read_isone_public_vre_profile("wind", hours_total=len(date_index))
    if base is None:
        zone_mean = {
            "ME": 0.43,
            "VT": 0.33,
            "NH": 0.31,
            "CT": 0.18,
            "WCMA": 0.22,
            "RI": 0.27,
            "SEMA": 0.24,
            "NEMA/Boston": 0.23,
        }
        phase = {
            "ME": 0.4,
            "VT": 1.1,
            "NH": 1.6,
            "CT": 2.3,
            "WCMA": 1.9,
            "RI": 0.8,
            "SEMA": 1.4,
            "NEMA/Boston": 1.0,
        }
        vals = []
        for ts in date_index:
            diurnal = 0.05 * math.sin(2.0 * math.pi * (ts.hour + 3) / 24.0 + phase.get(load_zone, 0.0))
            synoptic = 0.10 * math.sin(2.0 * math.pi * ((ts.day - 1) * 24 + ts.hour) / 120.0 + phase.get(load_zone, 0.0))
            weekly = 0.04 * math.cos(2.0 * math.pi * (ts.day - 1) / 7.0 + phase.get(load_zone, 0.0))
            vals.append(max(0.03, min(0.78, zone_mean.get(load_zone, 0.25) + diurnal + synoptic + weekly)))
        return np.array(vals, dtype=float)
    return np.clip(base * zone_scale.get(load_zone, 0.85), 0.0, 0.92)


def build_wind_profile_plant(
    date_index: pd.DatetimeIndex,
    load_zone: str,
    latitude: float | None,
    longitude: float | None,
    design_speed_mph: float | None,
    hub_height_ft: float | None,
) -> np.ndarray:
    base = build_wind_profile(date_index, load_zone)
    lat = float(latitude) if latitude is not None and not math.isnan(latitude) else float(LOAD_ZONE_GEOMETRY[load_zone]["lat"])
    lon = float(longitude) if longitude is not None and not math.isnan(longitude) else float(LOAD_ZONE_GEOMETRY[load_zone]["lon"])
    design = float(design_speed_mph) if design_speed_mph is not None and not math.isnan(design_speed_mph) else 17.5
    hub = float(hub_height_ft) if hub_height_ft is not None and not math.isnan(hub_height_ft) else 240.0
    speed_factor = max(0.85, min(1.18, 0.82 + design / 50.0))
    hub_factor = max(0.92, min(1.08, 0.92 + hub / 1500.0))
    coast_factor = 1.04 if lon > -70.8 else 1.0
    north_factor = 1.03 if lat > 44.7 else 1.0
    vals = []
    for idx, ts in enumerate(date_index):
        diurnal_bias = 1.0 + 0.04 * math.sin(2.0 * math.pi * (ts.hour + (lat - 42.0)) / 24.0)
        synoptic_bias = 1.0 + 0.03 * math.cos(2.0 * math.pi * ((ts.day - 1) / 5.5) + lon / 15.0)
        value = base[idx] * speed_factor * hub_factor * coast_factor * north_factor * diurnal_bias * synoptic_bias
        vals.append(max(0.02, min(0.88, value)))
    return np.array(vals, dtype=float)


def build_generator_availability(
    gen_out: pd.DataFrame,
    bus_load_zone: Dict[int, tuple[str, str]],
    hours_total: int = 744,
) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    date_index = pd.date_range("2024-07-01 00:00:00", periods=hours_total, freq="h")
    zone_profiles: dict[str, dict[str, np.ndarray]] = {}
    for load_zone in sorted({load_zone for load_zone, _ in bus_load_zone.values()}):
        zone_profiles[load_zone] = {
            "solar": build_solar_profile(date_index, load_zone),
            "wind": build_wind_profile(date_index, load_zone),
        }

    availability = pd.DataFrame(
        {
            "Time Period": 1,
            "Month": date_index.month,
            "Day": date_index.day,
            "Hours": np.arange(1, hours_total + 1),
        }
    )

    zone_load_zone = {}
    for zone, grp in gen_out.groupby("Zone", sort=False):
        mode_lz = pd.Series([bus_load_zone[int(bus)][0] for bus in grp["Bus_id"]]).mode()
        zone_load_zone[str(zone)] = str(mode_lz.iloc[0]) if not mode_lz.empty else "ME"

    zone_wind_weighted = {zone: np.zeros(hours_total, dtype=float) for zone in ZONE_NAMES}
    zone_solar_weighted = {zone: np.zeros(hours_total, dtype=float) for zone in ZONE_NAMES}
    zone_wind_cap = {zone: 0.0 for zone in ZONE_NAMES}
    zone_solar_cap = {zone: 0.0 for zone in ZONE_NAMES}

    for idx, row in gen_out.reset_index(drop=True).iterrows():
        gen_id = f"G{idx + 1}"
        load_zone = bus_load_zone[int(row["Bus_id"])][0]
        if row["Type"] == "WindOn":
            af = build_wind_profile_plant(
                date_index,
                load_zone,
                float(row["Latitude"]) if pd.notna(row.get("Latitude")) else None,
                float(row["Longitude"]) if pd.notna(row.get("Longitude")) else None,
                float(row["WindDesignSpeedMph"]) if pd.notna(row.get("WindDesignSpeedMph")) else None,
                float(row["WindHubHeightFt"]) if pd.notna(row.get("WindHubHeightFt")) else None,
            )
            zone_wind_weighted[str(row["Zone"])] += af * float(row["Pmax (MW)"])
            zone_wind_cap[str(row["Zone"])] += float(row["Pmax (MW)"])
        elif row["Type"] == "SolarPV":
            af = build_solar_profile_plant(
                date_index,
                load_zone,
                float(row["Latitude"]) if pd.notna(row.get("Latitude")) else None,
                float(row.get("SolarSingleAxisShare", 0.0) or 0.0),
                float(row.get("SolarDualAxisShare", 0.0) or 0.0),
                float(row.get("SolarEastWestShare", 0.0) or 0.0),
                float(row.get("SolarBifacialShare", 0.0) or 0.0),
                float(row["SolarDcAcRatio"]) if pd.notna(row.get("SolarDcAcRatio")) else None,
                float(row["SolarAzimuthAngle"]) if pd.notna(row.get("SolarAzimuthAngle")) else None,
                float(row["SolarTiltAngle"]) if pd.notna(row.get("SolarTiltAngle")) else None,
            )
            zone_solar_weighted[str(row["Zone"])] += af * float(row["Pmax (MW)"])
            zone_solar_cap[str(row["Zone"])] += float(row["Pmax (MW)"])
        else:
            af = np.full(hours_total, float(row["AF"]), dtype=float)
        availability[gen_id] = np.round(np.clip(af, 0.0, 1.0), 6)

    wind_ts = availability[["Time Period", "Month", "Day", "Hours"]].copy()
    solar_ts = availability[["Time Period", "Month", "Day", "Hours"]].copy()
    for zone in ZONE_NAMES:
        load_zone = zone_load_zone.get(zone, "ME")
        if zone_wind_cap[zone] > 0:
            wind_ts[zone] = np.round(zone_wind_weighted[zone] / zone_wind_cap[zone], 6)
        else:
            wind_ts[zone] = np.round(zone_profiles[load_zone]["wind"], 6)
        if zone_solar_cap[zone] > 0:
            solar_ts[zone] = np.round(zone_solar_weighted[zone] / zone_solar_cap[zone], 6)
        else:
            solar_ts[zone] = np.round(zone_profiles[load_zone]["solar"], 6)

    return availability, wind_ts, solar_ts


def aggregate_interzonal_linedata(branch_out: pd.DataFrame) -> pd.DataFrame:
    inter = branch_out[branch_out["From_zone"] != branch_out["To_zone"]].copy()
    if inter.empty:
        return pd.DataFrame(columns=["From_zone", "To_zone", "X", "Capacity (MW)", "Loss (%)"])
    key_df = inter.assign(
        key=inter.apply(lambda r: tuple(sorted((r["From_zone"], r["To_zone"]))), axis=1)
    )
    rows = []
    for key, grp in key_df.groupby("key"):
        rows.append(
            {
                "From_zone": key[0],
                "To_zone": key[1],
                "X": round(float(grp["X"].abs().mean()), 5),
                "Capacity (MW)": round(float(grp["Capacity (MW)"].sum()), 2),
                "Loss (%)": 0.0,
            }
        )
    return pd.DataFrame(rows).sort_values(["From_zone", "To_zone"]).reset_index(drop=True)


def write_case_files() -> None:
    text = read_text(RAW_MATPOWER)
    bus_df = rows_to_frame(parse_matrix(text, "mpc.bus"), BUS_COLS)
    gen_df = rows_to_frame(parse_matrix(text, "mpc.gen"), GEN_COLS)
    branch_df = rows_to_frame(parse_matrix(text, "mpc.branch"), BRANCH_COLS)
    gencost_rows = parse_matrix(text, "mpc.gencost")

    buses = [int(v) for v in bus_df["BUS_I"]]
    adj = build_adj(branch_df, buses)
    assignment = repair_connectivity(assign_voronoi_zones(adj, choose_seeds(bus_df, adj)), adj)
    zone_name_map = build_zone_name_map(assignment)
    bus_zone_initial = {bus: zone_name_map[z] for bus, z in assignment.items()}
    bus_load_zone = assign_load_zones(bus_df, adj, bus_zone_initial)

    bus_df["Bus_id"] = bus_df["BUS_I"].astype(int)
    bus_df["Zone_id"] = bus_df["Bus_id"].map(bus_zone_initial)

    bus_out = bus_df[["Bus_id", "Zone_id", "PD"]].copy()
    bus_out.rename(columns={"PD": "Demand (MW)"}, inplace=True)
    bus_geo = bus_out[["Bus_id", "Zone_id"]].copy().rename(columns={"Zone_id": "CapacityZone"})
    bus_geo["LoadZone"] = bus_geo["Bus_id"].map(lambda b: bus_load_zone[int(b)][0])
    bus_geo["State"] = bus_geo["Bus_id"].map(lambda b: bus_load_zone[int(b)][1])
    bus_geo["Source"] = "Synthetic electrical partition of TAMU Summer90Tight with ISO-NE load-zone/state subpartition"
    mapping_method = "Capacity-zone graph partition, then within-zone force-layout embedding around real New England load-zone anchors"
    if OSM_SUBSTATIONS_CSV.exists() or OSM_CORRIDOR_POINTS_CSV.exists():
        mapping_method += ", blended with optional OSM transmission substations/corridor priors"
    mapping_method += "; not official bus geography"
    bus_geo["MappingMethod"] = mapping_method
    bus_geo = generate_geo_coordinates(bus_geo, adj, bus_load_zone)
    bus_zone = dict(bus_zone_initial)
    bus_df["Zone_id"] = bus_df["Bus_id"].map(bus_zone)
    bus_out["Zone_id"] = bus_out["Bus_id"].map(bus_zone)
    bus_geo["CapacityZone"] = bus_geo["Bus_id"].map(bus_zone)

    real_fleet = build_eia860_generator_fleet(bus_geo, branch_df, adj)
    if real_fleet is not None:
        gen_out, generator_map = real_fleet
        bus_geo = blend_bus_coordinates_with_plants(bus_geo, generator_map)
        remapped_fleet = build_eia860_generator_fleet(bus_geo, branch_df, adj)
        if remapped_fleet is not None:
            gen_out, generator_map = remapped_fleet
            bus_geo = blend_bus_coordinates_with_plants(bus_geo, generator_map)
    else:
        active_gen = gen_df[gen_df["GEN_STATUS"] > 0].copy().reset_index(drop=True)
        if len(gencost_rows) >= len(gen_df) * 2:
            gencost_rows = gencost_rows[: len(gen_df)]
        if len(gencost_rows) < len(gen_df):
            raise ValueError("Not enough gencost rows to map generators.")
        gen_out, generator_map = build_proxy_generator_fleet(active_gen, bus_zone, bus_load_zone, gencost_rows[: len(active_gen)])

    bus_load_shares = build_bus_load_shares(bus_df, bus_geo, gen_out, adj)
    nodal_load_ts, zonal_load_ts, bus_peak_basis, zone_peak_basis = build_nodal_load_timeseries(bus_load_shares, 744)
    bus_out = bus_out.drop(columns=["Demand (MW)"]).merge(
        bus_load_shares.rename(columns={"CapacityZone": "Zone_id"}),
        on=["Bus_id", "Zone_id"],
        how="left",
    )
    bus_out["Demand (MW)"] = bus_out["Bus_id"].map(lambda b: float(bus_peak_basis.get(int(b), 0.0)))

    bus_out["Latitude"] = bus_out["Bus_id"].map(bus_geo.set_index("Bus_id")["Latitude"])
    bus_out["Longitude"] = bus_out["Bus_id"].map(bus_geo.set_index("Bus_id")["Longitude"])
    bus_out = bus_out[["Bus_id", "Zone_id", "LoadZone", "State", "Latitude", "Longitude", "Load_share", "Demand (MW)"]]

    branch_active = branch_df[branch_df["BR_STATUS"] > 0].copy()
    branch_active["from_bus"] = branch_active["F_BUS"].astype(int)
    branch_active["to_bus"] = branch_active["T_BUS"].astype(int)
    branch_active["From_zone"] = branch_active["from_bus"].map(bus_zone)
    branch_active["To_zone"] = branch_active["to_bus"].map(bus_zone)
    branch_active["X"] = branch_active["BR_X"].abs().replace(0.0, 1e-4)

    branch_active["Capacity (MW)"] = branch_active.apply(choose_branch_capacity, axis=1)
    branch_active = apply_branch_capacity_tuning(branch_active)
    seam_scorecard = pd.DataFrame()
    rewire_plan = pd.DataFrame()
    if OSM_CORRIDOR_POINTS_CSV.exists():
        seam_scorecard = build_seam_scorecard(
            bus_out.rename(columns={"Zone_id": "Zone_id"})[["Bus_id", "Zone_id", "Latitude", "Longitude"]],
            branch_active[["From_zone", "To_zone", "from_bus", "to_bus", "X", "Capacity (MW)"]].copy(),
            OSM_CORRIDOR_POINTS_CSV,
        )
        branch_active = apply_seam_capacity_tuning(branch_active, seam_scorecard)
    branch_active, rewire_plan = apply_topology_rewires(bus_out, branch_active)
    long_branch_audit = build_long_branch_audit(bus_out, branch_active)
    branch_active["Loss (%)"] = 0.0
    branch_out = branch_active[
        ["From_zone", "To_zone", "from_bus", "to_bus", "X", "Capacity (MW)", "Loss (%)"]
    ].copy()
    branch_out.sort_values(["from_bus", "to_bus"], inplace=True)

    linedata_out = aggregate_interzonal_linedata(branch_out)

    zonedata_out = pd.DataFrame(
        {
            "Zone_id": ZONE_NAMES,
            "Demand (MW)": [round(float(zone_peak_basis[z]), 3) for z in ZONE_NAMES],
            "State": [ZONE_STATE[z] for z in ZONE_NAMES],
            "Area": ["ISO-NE"] * len(ZONE_NAMES),
        }
    )
    gen_af, wind_ts, solar_ts = build_generator_availability(gen_out, bus_load_zone, 744)

    storagedata_cols = [
        "Zone",
        "Bus_id",
        "Type",
        "Capacity (MWh)",
        "Max Power (MW)",
        "Charging efficiency",
        "Discharging efficiency",
        "Cost ($/MWh)",
        "EF",
        "CC",
        "Charging Rate",
        "Discharging Rate",
    ]
    real_storage = build_eia860_storage_fleet(bus_geo, branch_df, adj)
    if real_storage is not None:
        storage_out, storage_map = real_storage
        storage_out = storage_out[storagedata_cols].copy()
    else:
        storage_out = pd.DataFrame(columns=storagedata_cols)
        storage_map = pd.DataFrame(
            columns=[
                "StorageId",
                "PlantCode",
                "PlantName",
                "StorageType",
                "State",
                "County",
                "LoadZone",
                "Zone",
                "PowerMW",
                "EnergyMWh",
                "AssignedBus",
                "PlantLatitude",
                "PlantLongitude",
                "AssignedBusLatitude",
                "AssignedBusLongitude",
                "MappingMethod",
                "DataSource",
            ]
        )

    gendata_cols = [
        "PlantCode",
        "PlantName",
        "SourceTechnology",
        "State",
        "LoadZone",
        "Latitude",
        "Longitude",
        "Pmax (MW)",
        "Pmin (MW)",
        "Zone",
        "Bus_id",
        "Type",
        "Flag_thermal",
        "Flag_RET",
        "Flag_VRE",
        "Flag_mustrun",
        "Cost ($/MWh)",
        "EF",
        "CC",
        "AF",
        "FOR",
        "RM_SPIN",
        "RU",
        "RD",
        "Flag_UC",
        "Min_down_time",
        "Min_up_time",
        "Start_up_cost ($/MW)",
        "RM_REG_UP",
        "RM_REG_DN",
        "RM_NSPIN",
    ]

    files = {
        DATA_DIR / "busdata.csv": bus_out,
        DATA_DIR / "branchdata.csv": branch_out,
        DATA_DIR / "linedata.csv": linedata_out,
        DATA_DIR / "gendata.csv": gen_out[gendata_cols].copy(),
        DATA_DIR / "gen_availability_timeseries.csv": gen_af,
        DATA_DIR / "storagedata.csv": storage_out,
        DATA_DIR / "zonedata.csv": zonedata_out,
        DATA_DIR / "load_timeseries_regional.csv": zonal_load_ts,
        DATA_DIR / "load_timeseries_nodal.csv": nodal_load_ts,
        DATA_DIR / "wind_timeseries_regional.csv": wind_ts,
        DATA_DIR / "solar_timeseries_regional.csv": solar_ts,
        REF_DIR / "bus_geography_map.csv": bus_geo.rename(columns={"CapacityZone": "Zone_id"}),
        REF_DIR / "generator_mapping.csv": generator_map,
        REF_DIR / "storage_mapping.csv": storage_map,
    }
    if not seam_scorecard.empty:
        files[OSM_SEAM_SCORECARD_CSV] = seam_scorecard
    files[LONG_BRANCH_AUDIT_CSV] = long_branch_audit
    if not rewire_plan.empty:
        files[TOPOLOGY_REWIRE_PLAN_CSV] = rewire_plan

    for path, df in files.items():
        ensure_parent(path)
        df.to_csv(path, index=False)

    if not seam_scorecard.empty:
        print("Applied OSM seam capacity tuning: " + summarize_supported_seams(seam_scorecard))
    if not rewire_plan.empty:
        print(f"Applied topology rewires for {len(rewire_plan)} long synthetic shortcuts.")

    ni_config = generate_nodal_ni_case_data(CASE_DIR, TOOLS_DIR / "raw_sources")
    print(
        "Generated nodal NI inputs with "
        f"localized_ni_share={ni_config['localized_ni_share']}, "
        f"max_target_gap_mw={ni_config['max_target_gap_mw']:.6g}, "
        f"max_nodal_gap_mw={ni_config['max_nodal_gap_mw']:.6g}"
    )


if __name__ == "__main__":
    write_case_files()
