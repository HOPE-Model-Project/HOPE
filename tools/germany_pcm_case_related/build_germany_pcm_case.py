from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import numpy as np
import pandas as pd


TOOLS_DIR = Path(__file__).resolve().parent
REPO_ROOT = TOOLS_DIR.parents[1]
CASE_DIR = REPO_ROOT / 'ModelCases' / 'GERMANY_PCM_nodal_case'
DATA_DIR = CASE_DIR / 'Data_GERMANY_PCM_nodal'
RAW_DIR = TOOLS_DIR / 'raw_sources'
REF_DIR = TOOLS_DIR / 'references'
OUT_DIR = TOOLS_DIR / 'outputs'


@dataclass(frozen=True)
class GermanyCaseSpec:
    study_year: int = 2025
    study_month: int = 0
    nodal_bus_target: int = 200
    zones: tuple[str, ...] = ('50Hertz', 'Amprion', 'TenneT', 'TransnetBW')
    network_source: str = 'osm_europe_grid_plus_pypsa_eur'
    generator_source: str = 'powerplantmatching_plus_bnetza_validation'
    chronology_source: str = 'smard_primary'


SPEC = GermanyCaseSpec()


BUS_ZONE_MAP = REF_DIR / 'germany_bus_zone_map.csv'
GENERATOR_BUS_MAP = REF_DIR / 'germany_generator_bus_map.csv'
GENERATOR_FLEET = REF_DIR / 'germany_generator_fleet_clean.csv'
HOURLY_CHRONOLOGY = REF_DIR / 'germany_hourly_chronology_clean.csv'
ZONE_HOURLY_REFERENCE = REF_DIR / 'germany_zone_hourly_load_reference.csv'
NETWORK_BUSES = REF_DIR / 'germany_network_buses_clean.csv'
NETWORK_LINES = REF_DIR / 'germany_network_lines_clean.csv'
NETWORK_TRANSFORMERS = REF_DIR / 'germany_network_transformers_clean.csv'
ASSUMED_TRANSFORMER_X_PU = 0.12

SINGLE_PARAMETER_DEFAULTS = {
    'VOLL': 100000.0,
    'planning_reserve_margin': 0.02,
    'BigM': 1.0e13,
    'PT_RPS': 1.0e10,
    'PT_emis': 1.0e10,
    'PT_NI_DEV': 500.0,
    'Inv_bugt_gen': 1.0e16,
    'Inv_bugt_line': 1.0e16,
    'Inv_bugt_storage': 1.0e16,
    'alpha_storage_anchor': 0.5,
    'reg_up_requirement': 0.01,
    'reg_dn_requirement': 0.01,
    'spin_requirement': 0.03,
    'nspin_requirement': 0.02,
    'delta_reg': 1.0 / 12.0,
    'delta_spin': 1.0 / 6.0,
    'delta_nspin': 0.5,
    'theta_max': 1000.0,
}

GEN_TECH_SPECS = {
    'NuC': {'Flag_thermal': 1, 'Flag_RET': 0, 'Flag_VRE': 0, 'Flag_mustrun': 0, 'Cost ($/MWh)': 12.0, 'EF': 0.0, 'CC': 0.95, 'AF': 0.95, 'FOR': 0.06, 'RM_SPIN': 0.10, 'RU': 0.12, 'RD': 0.12, 'Flag_UC': 1, 'Min_down_time': 24, 'Min_up_time': 24, 'Start_up_cost ($/MW)': 4.0, 'RM_REG_UP': 0.05, 'RM_REG_DN': 0.05, 'RM_NSPIN': 0.075},
    'NGCC': {'Flag_thermal': 1, 'Flag_RET': 0, 'Flag_VRE': 0, 'Flag_mustrun': 0, 'Cost ($/MWh)': 42.0, 'EF': 0.40, 'CC': 0.92, 'AF': 1.0, 'FOR': 0.06, 'RM_SPIN': 0.10, 'RU': 0.50, 'RD': 0.50, 'Flag_UC': 1, 'Min_down_time': 4, 'Min_up_time': 4, 'Start_up_cost ($/MW)': 6.0, 'RM_REG_UP': 0.05, 'RM_REG_DN': 0.05, 'RM_NSPIN': 0.075},
    'NGCT': {'Flag_thermal': 1, 'Flag_RET': 0, 'Flag_VRE': 0, 'Flag_mustrun': 0, 'Cost ($/MWh)': 68.0, 'EF': 0.58, 'CC': 0.86, 'AF': 1.0, 'FOR': 0.08, 'RM_SPIN': 0.12, 'RU': 1.0, 'RD': 1.0, 'Flag_UC': 1, 'Min_down_time': 1, 'Min_up_time': 1, 'Start_up_cost ($/MW)': 8.0, 'RM_REG_UP': 0.08, 'RM_REG_DN': 0.08, 'RM_NSPIN': 0.10},
    'Coal': {'Flag_thermal': 1, 'Flag_RET': 0, 'Flag_VRE': 0, 'Flag_mustrun': 0, 'Cost ($/MWh)': 36.0, 'EF': 0.95, 'CC': 0.90, 'AF': 0.92, 'FOR': 0.08, 'RM_SPIN': 0.08, 'RU': 0.25, 'RD': 0.25, 'Flag_UC': 1, 'Min_down_time': 8, 'Min_up_time': 8, 'Start_up_cost ($/MW)': 9.0, 'RM_REG_UP': 0.04, 'RM_REG_DN': 0.04, 'RM_NSPIN': 0.05},
    'Oil': {'Flag_thermal': 1, 'Flag_RET': 0, 'Flag_VRE': 0, 'Flag_mustrun': 0, 'Cost ($/MWh)': 110.0, 'EF': 0.82, 'CC': 0.88, 'AF': 1.0, 'FOR': 0.10, 'RM_SPIN': 0.08, 'RU': 1.0, 'RD': 1.0, 'Flag_UC': 1, 'Min_down_time': 1, 'Min_up_time': 1, 'Start_up_cost ($/MW)': 10.0, 'RM_REG_UP': 0.06, 'RM_REG_DN': 0.06, 'RM_NSPIN': 0.08},
    'Hydro': {'Flag_thermal': 0, 'Flag_RET': 1, 'Flag_VRE': 0, 'Flag_mustrun': 0, 'Cost ($/MWh)': 7.5, 'EF': 0.0, 'CC': 0.70, 'AF': 0.65, 'FOR': 0.04, 'RM_SPIN': 0.0, 'RU': 1.0, 'RD': 1.0, 'Flag_UC': 0, 'Min_down_time': 0, 'Min_up_time': 0, 'Start_up_cost ($/MW)': 0.0, 'RM_REG_UP': 0.0, 'RM_REG_DN': 0.0, 'RM_NSPIN': 0.0},
    'WindOn': {'Flag_thermal': 0, 'Flag_RET': 1, 'Flag_VRE': 1, 'Flag_mustrun': 0, 'Cost ($/MWh)': 3.0, 'EF': 0.0, 'CC': 0.18, 'AF': 1.0, 'FOR': 0.05, 'RM_SPIN': 0.0, 'RU': 1.0, 'RD': 1.0, 'Flag_UC': 0, 'Min_down_time': 0, 'Min_up_time': 0, 'Start_up_cost ($/MW)': 0.0, 'RM_REG_UP': 0.0, 'RM_REG_DN': 0.0, 'RM_NSPIN': 0.0},
    'WindOff': {'Flag_thermal': 0, 'Flag_RET': 1, 'Flag_VRE': 1, 'Flag_mustrun': 0, 'Cost ($/MWh)': 4.0, 'EF': 0.0, 'CC': 0.25, 'AF': 1.0, 'FOR': 0.05, 'RM_SPIN': 0.0, 'RU': 1.0, 'RD': 1.0, 'Flag_UC': 0, 'Min_down_time': 0, 'Min_up_time': 0, 'Start_up_cost ($/MW)': 0.0, 'RM_REG_UP': 0.0, 'RM_REG_DN': 0.0, 'RM_NSPIN': 0.0},
    'SolarPV': {'Flag_thermal': 0, 'Flag_RET': 1, 'Flag_VRE': 1, 'Flag_mustrun': 0, 'Cost ($/MWh)': 2.0, 'EF': 0.0, 'CC': 0.15, 'AF': 1.0, 'FOR': 0.03, 'RM_SPIN': 0.0, 'RU': 1.0, 'RD': 1.0, 'Flag_UC': 0, 'Min_down_time': 0, 'Min_up_time': 0, 'Start_up_cost ($/MW)': 0.0, 'RM_REG_UP': 0.0, 'RM_REG_DN': 0.0, 'RM_NSPIN': 0.0},
    'Bio': {'Flag_thermal': 1, 'Flag_RET': 1, 'Flag_VRE': 0, 'Flag_mustrun': 0, 'Cost ($/MWh)': 39.0, 'EF': 0.10, 'CC': 0.90, 'AF': 0.90, 'FOR': 0.08, 'RM_SPIN': 0.06, 'RU': 0.40, 'RD': 0.40, 'Flag_UC': 1, 'Min_down_time': 6, 'Min_up_time': 6, 'Start_up_cost ($/MW)': 6.0, 'RM_REG_UP': 0.05, 'RM_REG_DN': 0.05, 'RM_NSPIN': 0.06},
    'MSW': {'Flag_thermal': 1, 'Flag_RET': 1, 'Flag_VRE': 0, 'Flag_mustrun': 0, 'Cost ($/MWh)': 32.0, 'EF': 0.08, 'CC': 0.90, 'AF': 0.92, 'FOR': 0.08, 'RM_SPIN': 0.06, 'RU': 0.35, 'RD': 0.35, 'Flag_UC': 1, 'Min_down_time': 6, 'Min_up_time': 6, 'Start_up_cost ($/MW)': 5.0, 'RM_REG_UP': 0.05, 'RM_REG_DN': 0.05, 'RM_NSPIN': 0.06},
    'Landfill_NG': {'Flag_thermal': 1, 'Flag_RET': 1, 'Flag_VRE': 0, 'Flag_mustrun': 0, 'Cost ($/MWh)': 30.0, 'EF': 0.18, 'CC': 0.85, 'AF': 0.90, 'FOR': 0.08, 'RM_SPIN': 0.05, 'RU': 0.40, 'RD': 0.40, 'Flag_UC': 1, 'Min_down_time': 4, 'Min_up_time': 4, 'Start_up_cost ($/MW)': 4.0, 'RM_REG_UP': 0.04, 'RM_REG_DN': 0.04, 'RM_NSPIN': 0.05},
    'Other': {'Flag_thermal': 1, 'Flag_RET': 0, 'Flag_VRE': 0, 'Flag_mustrun': 0, 'Cost ($/MWh)': 55.0, 'EF': 0.25, 'CC': 0.85, 'AF': 0.90, 'FOR': 0.08, 'RM_SPIN': 0.05, 'RU': 0.40, 'RD': 0.40, 'Flag_UC': 1, 'Min_down_time': 4, 'Min_up_time': 4, 'Start_up_cost ($/MW)': 5.0, 'RM_REG_UP': 0.04, 'RM_REG_DN': 0.04, 'RM_NSPIN': 0.05},
}


STORAGE_DEFAULTS = {
    'PHS': {'Charging efficiency': 0.84, 'Discharging efficiency': 0.84, 'Cost ($/MWh)': 0.5, 'EF': 0.0, 'CC': 0.95, 'Charging Rate': 1.0, 'Discharging Rate': 1.0, 'DefaultDuration': 8.0},
    'BES': {'Charging efficiency': 0.90, 'Discharging efficiency': 0.90, 'Cost ($/MWh)': 1.0, 'EF': 0.0, 'CC': 0.95, 'Charging Rate': 0.5, 'Discharging Rate': 1.0, 'DefaultDuration': 2.0},
}


def ensure_workspace() -> None:
    for path in (CASE_DIR, DATA_DIR, RAW_DIR, REF_DIR, OUT_DIR):
        path.mkdir(parents=True, exist_ok=True)


def required_reference_outputs() -> tuple[Path, ...]:
    return (
        NETWORK_BUSES,
        NETWORK_LINES,
        NETWORK_TRANSFORMERS,
        BUS_ZONE_MAP,
        GENERATOR_FLEET,
        GENERATOR_BUS_MAP,
        HOURLY_CHRONOLOGY,
        ZONE_HOURLY_REFERENCE,
    )


def _require_csv(path: Path) -> pd.DataFrame:
    if not path.exists():
        raise FileNotFoundError(f'Missing required reference file: {path}')
    return pd.read_csv(path)


def _combined_network_edges(lines: pd.DataFrame, transformers: pd.DataFrame) -> pd.DataFrame:
    line_edges = lines[['FromBus', 'ToBus', 'X', 'Capacity_MVA', 'Voltage_kV']].copy()
    line_edges['ElementType'] = 'line'

    xf_edges = transformers[['Bus0', 'Bus1', 'X', 'S_nom_MVA', 'VoltageBus0_kV', 'VoltageBus1_kV']].copy().rename(
        columns={'Bus0': 'FromBus', 'Bus1': 'ToBus', 'S_nom_MVA': 'Capacity_MVA'}
    )
    xf_edges['Voltage_kV'] = xf_edges[['VoltageBus0_kV', 'VoltageBus1_kV']].max(axis=1)
    xf_edges = xf_edges.drop(columns=['VoltageBus0_kV', 'VoltageBus1_kV'])
    xf_edges['ElementType'] = 'transformer'

    network_edges = pd.concat([line_edges, xf_edges], ignore_index=True, sort=False)
    network_edges['FromBus'] = network_edges['FromBus'].astype(str)
    network_edges['ToBus'] = network_edges['ToBus'].astype(str)
    return network_edges


def _edge_x_to_hope_scale(row: pd.Series) -> float:
    raw_x = pd.to_numeric(pd.Series([row.get('X')]), errors='coerce').iloc[0]
    voltage_kv = pd.to_numeric(pd.Series([row.get('Voltage_kV')]), errors='coerce').iloc[0]
    capacity_mva = pd.to_numeric(pd.Series([row.get('Capacity_MVA')]), errors='coerce').iloc[0]
    element_type = str(row.get('ElementType', 'line')).lower()

    if pd.notna(raw_x) and raw_x > 0 and pd.notna(voltage_kv) and voltage_kv > 0:
        # OSM/PyPSA-Europe branch reactance is carried in raw electrical units. HOPE's
        # DCOPF flow equation uses an MW/rad-style coefficient, so we normalize by V^2.
        return float(abs(raw_x) / (float(voltage_kv) ** 2))

    if element_type == 'transformer' and pd.notna(capacity_mva) and capacity_mva > 0:
        # When transformer x is missing, use a conservative default transformer reactance
        # on the transformer's own MVA base, then convert to HOPE's scaled X.
        return float(ASSUMED_TRANSFORMER_X_PU / float(capacity_mva))

    return np.nan


def _largest_connected_bus_set(buses: pd.DataFrame, network_edges: pd.DataFrame) -> set[str]:
    adjacency: dict[str, set[str]] = {}
    for bus_id in buses['Bus_id'].astype(str):
        adjacency[bus_id] = set()
    for _, row in network_edges.iterrows():
        a = str(row['FromBus'])
        b = str(row['ToBus'])
        adjacency.setdefault(a, set()).add(b)
        adjacency.setdefault(b, set()).add(a)

    remaining = set(adjacency)
    largest_component: set[str] = set()
    while remaining:
        start = next(iter(remaining))
        stack = [start]
        component = {start}
        remaining.remove(start)
        while stack:
            node = stack.pop()
            for neighbor in adjacency.get(node, set()):
                if neighbor in remaining:
                    remaining.remove(neighbor)
                    component.add(neighbor)
                    stack.append(neighbor)
        if len(component) > len(largest_component):
            largest_component = component
    return largest_component


def _map_generator_type(fuel: str, tech: str) -> tuple[str | None, str | None]:
    fuel_l = str(fuel).lower()
    tech_l = str(tech).lower()
    combo = f'{fuel_l} {tech_l}'
    if 'battery' in combo or tech_l in {'li', 'pb'}:
        return None, 'BES'
    if 'pumped storage' in combo or ('hydro' in fuel_l and tech_l == 'pumped storage'):
        return None, 'PHS'
    if 'solar' in combo or 'pv' in combo:
        return 'SolarPV', None
    if 'offshore' in combo:
        return 'WindOff', None
    if 'wind' in combo:
        return 'WindOn', None
    if 'nuclear' in combo:
        return 'NuC', None
    if 'hydro' in combo:
        return 'Hydro', None
    if 'lignite' in combo or 'coal' in combo:
        return 'Coal', None
    if 'oil' in combo or 'diesel' in combo or 'petroleum' in combo:
        return 'Oil', None
    if 'waste' in combo or 'municipal' in combo:
        return 'MSW', None
    if 'landfill' in combo or 'mine gas' in combo or 'sewage' in combo:
        return 'Landfill_NG', None
    if 'bio' in combo or 'biomass' in combo or 'wood' in combo:
        return 'Bio', None
    if 'gas' in combo or 'lng' in combo:
        if 'cc' in tech_l or 'combined' in tech_l or 'steam' in tech_l or 'chp' in tech_l:
            return 'NGCC', None
        return 'NGCT', None
    return 'Other', None


def _build_zone_table(bus_zone_map: pd.DataFrame, zonal_hourly: pd.DataFrame, zones: list[str]) -> pd.DataFrame:
    zone_load_cols = {
        '50Hertz': 'Load_50Hertz_MW',
        'Amprion': 'Load_Amprion_MW',
        'TenneT': 'Load_TenneT_MW',
        'TransnetBW': 'Load_TransnetBW_MW',
    }
    rows = []
    for zone in zones:
        col = zone_load_cols[zone]
        peak = float(pd.to_numeric(zonal_hourly[col], errors='coerce').max())
        rows.append({'Zone_id': zone, 'Demand (MW)': peak, 'State': 'DE', 'Area': 'Germany'})
    return pd.DataFrame(rows)


def _build_bus_table(
    buses: pd.DataFrame,
    network_edges: pd.DataFrame,
    bus_zone_map: pd.DataFrame,
    generator_fleet: pd.DataFrame,
    zonedata: pd.DataFrame,
) -> pd.DataFrame:
    degree_counts = pd.concat([network_edges['FromBus'], network_edges['ToBus']]).astype(str).value_counts().rename('Degree')
    gen_capacity = generator_fleet.groupby('Bus_id', as_index=True)['Capacity_MW'].sum().rename('GenCapacityMW') if not generator_fleet.empty else pd.Series(dtype=float)

    work = buses.merge(bus_zone_map[['Bus_id', 'Zone_id']], on='Bus_id', how='left')
    work['Degree'] = work['Bus_id'].map(degree_counts).fillna(0.0)
    work['GenCapacityMW'] = work['Bus_id'].map(gen_capacity).fillna(0.0)
    max_voltage = max(float(pd.to_numeric(work['V_nom_kV'], errors='coerce').max()), 1.0)
    voltage_norm = pd.to_numeric(work['V_nom_kV'], errors='coerce').fillna(max_voltage / 2.0) / max_voltage
    work['LoadProxy'] = 1.0 + 0.15 * work['Degree'] + 0.50 * voltage_norm + 0.0002 * work['GenCapacityMW'].clip(upper=5000.0)
    work['Load_share'] = work.groupby('Zone_id')['LoadProxy'].transform(lambda s: s / s.sum())
    zone_peak = zonedata.set_index('Zone_id')['Demand (MW)'].to_dict()
    work['Demand (MW)'] = work['Zone_id'].map(zone_peak).fillna(0.0) * work['Load_share']
    work['LoadZone'] = work['Zone_id']
    work['State'] = 'DE'
    return work[['Bus_id', 'Zone_id', 'LoadZone', 'State', 'Latitude', 'Longitude', 'Load_share', 'Demand (MW)']].copy()


def _build_line_table(network_edges: pd.DataFrame, bus_zone_map: pd.DataFrame) -> pd.DataFrame:
    zone_lookup = bus_zone_map.set_index('Bus_id')['Zone_id'].astype(str).to_dict()
    work = network_edges.copy()
    work['From_zone'] = work['FromBus'].astype(str).map(zone_lookup)
    work['To_zone'] = work['ToBus'].astype(str).map(zone_lookup)
    work['from_bus'] = work['FromBus'].astype(str)
    work['to_bus'] = work['ToBus'].astype(str)
    work['X_raw'] = pd.to_numeric(work['X'], errors='coerce').abs()
    work['Voltage_kV'] = pd.to_numeric(work.get('Voltage_kV'), errors='coerce')
    work['X'] = work.apply(_edge_x_to_hope_scale, axis=1)
    positive_x = work.loc[work['X'] > 0, 'X']
    fallback_x = float(positive_x.median()) if not positive_x.empty else 1.0e-4
    work['X'] = work['X'].fillna(fallback_x).replace(0, fallback_x)
    work['Capacity (MW)'] = pd.to_numeric(work['Capacity_MVA'], errors='coerce')
    positive_cap = work.loc[work['Capacity (MW)'] > 0, 'Capacity (MW)']
    fallback_cap = float(positive_cap.median()) if not positive_cap.empty else 1000.0
    work['Capacity (MW)'] = work['Capacity (MW)'].fillna(fallback_cap)
    work['Loss (%)'] = 0.0
    work = work.loc[work['from_bus'] != work['to_bus']].copy()
    return work[['From_zone', 'To_zone', 'from_bus', 'to_bus', 'X', 'Capacity (MW)', 'Loss (%)']].reset_index(drop=True)


def _aggregate_generators_and_storage(generator_map: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    gen_rows = []
    storage_rows = []
    for _, row in generator_map.iterrows():
        gen_type, storage_type = _map_generator_type(row['FuelType'], row['Technology'])
        duration = pd.to_numeric(pd.Series([row.get('Duration')]), errors='coerce').iloc[0] if 'Duration' in generator_map.columns else np.nan
        entry = row.to_dict()
        entry['MappedType'] = gen_type
        entry['MappedStorageType'] = storage_type
        entry['DurationHours'] = duration
        if storage_type is not None:
            storage_rows.append(entry)
        elif gen_type is not None:
            gen_rows.append(entry)
    return pd.DataFrame(gen_rows), pd.DataFrame(storage_rows)


def _build_gendata(generator_map: pd.DataFrame) -> pd.DataFrame:
    gen_df, _ = _aggregate_generators_and_storage(generator_map)
    if gen_df.empty:
        return pd.DataFrame(columns=['PlantCode', 'PlantName', 'SourceTechnology', 'State', 'LoadZone', 'Latitude', 'Longitude', 'Pmax (MW)', 'Pmin (MW)', 'Zone', 'Bus_id', 'Type', 'Flag_thermal', 'Flag_RET', 'Flag_VRE', 'Flag_mustrun', 'Cost ($/MWh)', 'EF', 'CC', 'AF', 'FOR', 'RM_SPIN', 'RU', 'RD', 'Flag_UC', 'Min_down_time', 'Min_up_time', 'Start_up_cost ($/MW)', 'RM_REG_UP', 'RM_REG_DN', 'RM_NSPIN'])

    gen_df['WeightLat'] = gen_df['Latitude'] * gen_df['Capacity_MW']
    gen_df['WeightLon'] = gen_df['Longitude'] * gen_df['Capacity_MW']
    grouped = gen_df.groupby(['Zone_id', 'Bus_id', 'MappedType'], as_index=False).agg(
        PlantName=('PlantName', 'first'),
        FuelType=('FuelType', 'first'),
        Technology=('Technology', 'first'),
        CapacityMW=('Capacity_MW', 'sum'),
        WeightLat=('WeightLat', 'sum'),
        WeightLon=('WeightLon', 'sum'),
    )
    grouped['Latitude'] = grouped['WeightLat'] / grouped['CapacityMW']
    grouped['Longitude'] = grouped['WeightLon'] / grouped['CapacityMW']
    rows = []
    for idx, row in grouped.iterrows():
        spec = GEN_TECH_SPECS[row['MappedType']]
        rows.append({
            'PlantCode': idx + 1,
            'PlantName': row['PlantName'],
            'SourceTechnology': f"{row['FuelType']} | {row['Technology']}",
            'State': 'DE',
            'LoadZone': row['Zone_id'],
            'Latitude': row['Latitude'],
            'Longitude': row['Longitude'],
            'Pmax (MW)': row['CapacityMW'],
            'Pmin (MW)': 0.0,
            'Zone': row['Zone_id'],
            'Bus_id': row['Bus_id'],
            'Type': row['MappedType'],
            **spec,
        })
    return pd.DataFrame(rows)


def _build_storagedata(generator_map: pd.DataFrame) -> pd.DataFrame:
    _, storage_df = _aggregate_generators_and_storage(generator_map)
    columns = ['Zone', 'Bus_id', 'Type', 'Capacity (MWh)', 'Max Power (MW)', 'Charging efficiency', 'Discharging efficiency', 'Cost ($/MWh)', 'EF', 'CC', 'Charging Rate', 'Discharging Rate']
    if storage_df.empty:
        return pd.DataFrame(columns=columns)
    storage_df['DurationHours'] = pd.to_numeric(storage_df['DurationHours'], errors='coerce')
    grouped = storage_df.groupby(['Zone_id', 'Bus_id', 'MappedStorageType'], as_index=False).agg(
        CapacityMW=('Capacity_MW', 'sum'),
        MeanDuration=('DurationHours', 'mean'),
    )
    rows = []
    for _, row in grouped.iterrows():
        defaults = STORAGE_DEFAULTS[row['MappedStorageType']]
        duration = float(row['MeanDuration']) if pd.notna(row['MeanDuration']) and row['MeanDuration'] > 0 else defaults['DefaultDuration']
        rows.append({
            'Zone': row['Zone_id'],
            'Bus_id': row['Bus_id'],
            'Type': row['MappedStorageType'],
            'Capacity (MWh)': row['CapacityMW'] * duration,
            'Max Power (MW)': row['CapacityMW'],
            'Charging efficiency': defaults['Charging efficiency'],
            'Discharging efficiency': defaults['Discharging efficiency'],
            'Cost ($/MWh)': defaults['Cost ($/MWh)'],
            'EF': defaults['EF'],
            'CC': defaults['CC'],
            'Charging Rate': defaults['Charging Rate'],
            'Discharging Rate': defaults['Discharging Rate'],
        })
    return pd.DataFrame(rows, columns=columns)


def _time_columns(chronology: pd.DataFrame) -> pd.DataFrame:
    ts = pd.to_datetime(chronology['TimestampUTC'])
    return pd.DataFrame({
        'Time Period': np.ones(len(ts), dtype=int),
        'Month': ts.dt.month,
        'Day': ts.dt.day,
        'Hours': ts.dt.hour + 1,
    })


def _build_regional_load_and_bus_load(
    chronology: pd.DataFrame,
    zonal_reference: pd.DataFrame,
    busdata: pd.DataFrame,
    zonedata: pd.DataFrame,
) -> tuple[pd.DataFrame, pd.DataFrame]:
    time_df = _time_columns(chronology)
    zone_load_cols = {
        '50Hertz': 'Load_50Hertz_MW',
        'Amprion': 'Load_Amprion_MW',
        'TenneT': 'Load_TenneT_MW',
        'TransnetBW': 'Load_TransnetBW_MW',
    }
    zone_peak = zonedata.set_index('Zone_id')['Demand (MW)'].to_dict()
    regional = time_df.copy()
    for zone, col in zone_load_cols.items():
        zone_mw = pd.to_numeric(zonal_reference[col], errors='coerce').fillna(0.0)
        denom = max(zone_peak[zone], 1.0)
        regional[zone] = zone_mw / denom
    regional['NI'] = 0.0

    zone_by_bus = busdata['Zone_id'].astype(str).tolist()
    bus_cols = busdata['Bus_id'].astype(str).tolist()
    zone_matrix = np.column_stack([regional[zone].to_numpy(dtype=float) for zone in zonedata['Zone_id']])
    zone_index = {zone: idx for idx, zone in enumerate(zonedata['Zone_id'])}
    bus_zone_idx = np.array([zone_index[z] for z in zone_by_bus], dtype=int)
    nodal_values = zone_matrix[:, bus_zone_idx]
    nodal = time_df.copy()
    nodal = pd.concat([nodal, pd.DataFrame(nodal_values, columns=bus_cols)], axis=1)
    return regional, nodal


def _build_vre_profiles(chronology: pd.DataFrame, zones: list[str]) -> tuple[pd.DataFrame, pd.DataFrame]:
    time_df = _time_columns(chronology)
    wind = time_df.copy()
    solar = time_df.copy()

    wind_total = (
        pd.to_numeric(chronology['WindOnshore_MW'], errors='coerce').fillna(0.0)
        + pd.to_numeric(chronology['WindOffshore_MW'], errors='coerce').fillna(0.0)
    )
    solar_total = pd.to_numeric(chronology['SolarPV_MW'], errors='coerce').fillna(0.0)

    wind_denom = max(float(wind_total.max()), 1.0)
    solar_denom = max(float(solar_total.max()), 1.0)
    wind_profile = wind_total / wind_denom
    solar_profile = solar_total / solar_denom

    for zone in zones:
        wind[zone] = wind_profile.to_numpy(dtype=float)
        solar[zone] = solar_profile.to_numpy(dtype=float)
    return wind, solar


def _empty_policy_tables() -> tuple[pd.DataFrame, pd.DataFrame]:
    carbon = pd.DataFrame(columns=['State', 'Time Period', 'Allowance (tons)'])
    rps = pd.DataFrame(columns=['From_state', 'To_state', 'RPS'])
    return carbon, rps


def _single_parameter_table() -> pd.DataFrame:
    return pd.DataFrame([SINGLE_PARAMETER_DEFAULTS])


def _write_case_files(tables: dict[str, pd.DataFrame]) -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    for filename, frame in tables.items():
        frame.to_csv(DATA_DIR / filename, index=False)


def build_germany_pcm_case() -> None:
    ensure_workspace()
    missing = [path for path in required_reference_outputs() if not path.exists()]
    if missing:
        missing_text = ', '.join(path.name for path in missing)
        raise FileNotFoundError(f'Missing required Germany reference files: {missing_text}')

    buses = _require_csv(NETWORK_BUSES)
    lines = _require_csv(NETWORK_LINES)
    transformers = _require_csv(NETWORK_TRANSFORMERS)
    bus_zone_map = _require_csv(BUS_ZONE_MAP)
    generator_fleet = _require_csv(GENERATOR_FLEET)
    chronology = _require_csv(HOURLY_CHRONOLOGY)
    zonal_reference = _require_csv(ZONE_HOURLY_REFERENCE)

    network_edges = _combined_network_edges(lines, transformers)
    active_buses = _largest_connected_bus_set(buses, network_edges)
    buses = buses.loc[buses['Bus_id'].astype(str).isin(active_buses)].copy().reset_index(drop=True)
    bus_zone_map = bus_zone_map.loc[bus_zone_map['Bus_id'].astype(str).isin(active_buses)].copy().reset_index(drop=True)
    generator_fleet = generator_fleet.loc[generator_fleet['Bus_id'].astype(str).isin(active_buses)].copy().reset_index(drop=True)
    network_edges = network_edges.loc[
        network_edges['FromBus'].astype(str).isin(active_buses) & network_edges['ToBus'].astype(str).isin(active_buses)
    ].copy().reset_index(drop=True)

    zonedata = _build_zone_table(bus_zone_map, zonal_reference, list(SPEC.zones))
    busdata = _build_bus_table(buses, network_edges, bus_zone_map, generator_fleet, zonedata)
    linedata = _build_line_table(network_edges, bus_zone_map)
    gendata = _build_gendata(generator_fleet)
    storagedata = _build_storagedata(generator_fleet)
    load_regional, load_nodal = _build_regional_load_and_bus_load(chronology, zonal_reference, busdata, zonedata)
    wind_regional, solar_regional = _build_vre_profiles(chronology, list(SPEC.zones))
    carbonpolicies, rpspolicies = _empty_policy_tables()
    single_parameter = _single_parameter_table()

    tables = {
        'zonedata.csv': zonedata,
        'busdata.csv': busdata,
        'linedata.csv': linedata,
        'gendata.csv': gendata,
        'storagedata.csv': storagedata,
        'load_timeseries_regional.csv': load_regional,
        'load_timeseries_nodal.csv': load_nodal,
        'wind_timeseries_regional.csv': wind_regional,
        'solar_timeseries_regional.csv': solar_regional,
        'carbonpolicies.csv': carbonpolicies,
        'rpspolicies.csv': rpspolicies,
        'single_parameter.csv': single_parameter,
    }
    _write_case_files(tables)


if __name__ == '__main__':
    build_germany_pcm_case()
    print(f'Wrote first-pass Germany nodal PCM inputs to {DATA_DIR}')
