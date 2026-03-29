from __future__ import annotations

import argparse
import csv
import io
import zipfile
from pathlib import Path

import numpy as np
import pandas as pd

csv.field_size_limit(2**31 - 1)


TOOLS_DIR = Path(__file__).resolve().parent
PUBLIC_RAW_DIR = TOOLS_DIR / 'raw_sources' / 'public_spatial_load'
EGON_RAW_DIR = TOOLS_DIR / 'raw_sources' / 'egon_data'
REF_DIR = TOOLS_DIR / 'references'

NETWORK_BUSES = REF_DIR / 'germany_network_buses_clean.csv'
BUS_ZONE_MAP = REF_DIR / 'germany_bus_zone_map.csv'
OUT_FILE = REF_DIR / 'germany_spatial_load_shares.csv'

DEFAULT_EGON_ZIP = Path.home() / 'Downloads' / 'german_nodal_data.zip'
DIRECT_DEMAND_WEIGHT = 0.85
INDUSTRY_FALLBACK_WEIGHT = 0.15
EGON_MAPPING_K = 4
MIN_MAPPING_DISTANCE_KM = 2.0
VOLTAGE_MISMATCH_ALPHA = 2.0
LOCAL_EGON_BUS_FILES = (
    EGON_RAW_DIR / 'egon_etrago_bus.csv',
)
LOCAL_EGON_DEMAND_FILES = (
    EGON_RAW_DIR / 'egon_etrago_electricity_households.csv',
    EGON_RAW_DIR / 'egon_etrago_electricity_cts.csv',
    EGON_RAW_DIR / 'egon_etrago_electricity_industry.csv',
)

LAYER_FILES = {
    'population': (
        PUBLIC_RAW_DIR / 'population_grid_1km.csv',
        PUBLIC_RAW_DIR / 'population_grid.csv',
        PUBLIC_RAW_DIR / 'zensus_population_grid.csv',
    ),
    'settlement': (
        PUBLIC_RAW_DIR / 'settlement_centers.csv',
        PUBLIC_RAW_DIR / 'settlement_points.csv',
        PUBLIC_RAW_DIR / 'osm_settlement_points.csv',
    ),
    'industry': (
        PUBLIC_RAW_DIR / 'industrial_sites.csv',
        PUBLIC_RAW_DIR / 'industrial_locations.csv',
        PUBLIC_RAW_DIR / 'osm_industrial_sites.csv',
    ),
}
LEGACY_LAYER_WEIGHTS = {
    'population': 0.70,
    'settlement': 0.15,
    'industry': 0.15,
}


def _first_existing(paths: tuple[Path, ...]) -> Path | None:
    for path in paths:
        if path.exists():
            return path
    return None


def _require_csv(path: Path) -> pd.DataFrame:
    if not path.exists():
        raise FileNotFoundError(f'Missing required file: {path}')
    return pd.read_csv(path)


def _find_column(frame: pd.DataFrame, candidates: tuple[str, ...], required: bool = True) -> str | None:
    lowered = {str(col).strip().lower(): col for col in frame.columns}
    for candidate in candidates:
        found = lowered.get(candidate.lower())
        if found is not None:
            return found
    if required:
        raise KeyError(f'Expected one of columns {candidates}; found {list(frame.columns)}')
    return None


def _sanitize_column_name(name: str) -> str:
    chars = []
    for ch in str(name):
        chars.append(ch if ch.isalnum() else '_')
    cleaned = ''.join(chars).strip('_').lower()
    return cleaned or 'layer'


def _haversine_km(lat1: np.ndarray, lon1: np.ndarray, lat2: np.ndarray, lon2: np.ndarray) -> np.ndarray:
    r = 6371.0
    lat1_r = np.radians(lat1)
    lon1_r = np.radians(lon1)
    lat2_r = np.radians(lat2)
    lon2_r = np.radians(lon2)
    dlat = lat2_r - lat1_r
    dlon = lon2_r - lon1_r
    a = np.sin(dlat / 2.0) ** 2 + np.cos(lat1_r) * np.cos(lat2_r) * np.sin(dlon / 2.0) ** 2
    return 2.0 * r * np.arcsin(np.sqrt(a))


def _nearest_indices(
    src_lon: np.ndarray,
    src_lat: np.ndarray,
    dst_lon: np.ndarray,
    dst_lat: np.ndarray,
) -> tuple[np.ndarray, np.ndarray]:
    idx = np.zeros(len(src_lon), dtype=int)
    dist = np.zeros(len(src_lon), dtype=float)
    for i in range(len(src_lon)):
        d = _haversine_km(
            np.full(len(dst_lat), src_lat[i]),
            np.full(len(dst_lon), src_lon[i]),
            dst_lat,
            dst_lon,
        )
        best = int(np.argmin(d))
        idx[i] = best
        dist[i] = float(d[best])
    return idx, dist


def _prepare_hope_buses() -> pd.DataFrame:
    hope_buses = _require_csv(NETWORK_BUSES).merge(
        _require_csv(BUS_ZONE_MAP)[['Bus_id', 'Zone_id']],
        on='Bus_id',
        how='left',
    )
    hope_buses['Bus_id'] = hope_buses['Bus_id'].astype(str)
    hope_buses['Zone_id'] = hope_buses['Zone_id'].astype(str)
    hope_buses['Longitude'] = pd.to_numeric(hope_buses['Longitude'], errors='coerce')
    hope_buses['Latitude'] = pd.to_numeric(hope_buses['Latitude'], errors='coerce')
    hope_buses['V_nom_kV'] = pd.to_numeric(hope_buses.get('V_nom_kV'), errors='coerce')
    return hope_buses.dropna(subset=['Longitude', 'Latitude', 'Zone_id']).copy()


def _voltage_match_score(src_kv: float | None, dst_kv: np.ndarray) -> np.ndarray:
    if src_kv is None or not np.isfinite(src_kv) or src_kv <= 0:
        return np.ones(len(dst_kv), dtype=float)
    dst = np.where(np.isfinite(dst_kv) & (dst_kv > 0), dst_kv, src_kv)
    mismatch = np.abs(np.log(dst / src_kv))
    return 1.0 / (1.0 + VOLTAGE_MISMATCH_ALPHA * mismatch)


def _load_layer(name: str) -> pd.DataFrame:
    layer_file = _first_existing(LAYER_FILES[name])
    if layer_file is None:
        return pd.DataFrame(columns=['Longitude', 'Latitude', 'raw_weight'])
    frame = pd.read_csv(layer_file)
    lon_col = _find_column(frame, ('x', 'lon', 'longitude', 'Longitude'))
    lat_col = _find_column(frame, ('y', 'lat', 'latitude', 'Latitude'))
    weight_col = _find_column(
        frame,
        (
            'weight',
            'Weight',
            'value',
            'Value',
            'population',
            'Population',
            'pop',
            'people',
            'count',
            'settlement_weight',
            'SettlementWeight',
            'industrial_weight',
            'IndustrialWeight',
            'annual_mwh',
            'Annual_MWh',
            'demand_mwh',
            'Demand_MWh',
        ),
    )
    out = frame[[lon_col, lat_col, weight_col]].copy()
    out.columns = ['Longitude', 'Latitude', 'raw_weight']
    out['Longitude'] = pd.to_numeric(out['Longitude'], errors='coerce')
    out['Latitude'] = pd.to_numeric(out['Latitude'], errors='coerce')
    out['raw_weight'] = pd.to_numeric(out['raw_weight'], errors='coerce').fillna(0.0)
    out = out.dropna(subset=['Longitude', 'Latitude'])
    out = out.loc[out['raw_weight'] > 0].copy()
    out['source_file'] = layer_file.name
    return out


def _map_points_to_hope_buses(
    points: pd.DataFrame,
    hope_buses: pd.DataFrame,
    entity_col: str,
    scenario_col: str | None = None,
) -> pd.DataFrame:
    if points.empty:
        columns = [entity_col, 'Bus_id', 'Zone_id', 'raw_weight', 'MappedDistance_km']
        if scenario_col is not None:
            columns.insert(1, scenario_col)
        return pd.DataFrame(columns=columns)

    coarse_idx, _ = _nearest_indices(
        points['Longitude'].to_numpy(dtype=float),
        points['Latitude'].to_numpy(dtype=float),
        hope_buses['Longitude'].to_numpy(dtype=float),
        hope_buses['Latitude'].to_numpy(dtype=float),
    )
    coarse = hope_buses.iloc[coarse_idx].reset_index(drop=True)
    work = points.copy()
    work['Zone_id'] = coarse['Zone_id'].astype(str).to_numpy()

    mapped_parts: list[pd.DataFrame] = []
    for zone, group in work.groupby('Zone_id', sort=True):
        zone_buses = hope_buses.loc[hope_buses['Zone_id'].astype(str) == str(zone)].reset_index(drop=True)
        if zone_buses.empty:
            continue
        zone_idx, zone_dist = _nearest_indices(
            group['Longitude'].to_numpy(dtype=float),
            group['Latitude'].to_numpy(dtype=float),
            zone_buses['Longitude'].to_numpy(dtype=float),
            zone_buses['Latitude'].to_numpy(dtype=float),
        )
        assigned = group.copy()
        assigned['Bus_id'] = zone_buses.iloc[zone_idx]['Bus_id'].astype(str).to_numpy()
        assigned['MappedDistance_km'] = zone_dist
        mapped_parts.append(assigned)

    if not mapped_parts:
        columns = [entity_col, 'Bus_id', 'Zone_id', 'raw_weight', 'MappedDistance_km']
        if scenario_col is not None:
            columns.insert(1, scenario_col)
        return pd.DataFrame(columns=columns)

    columns = [entity_col, 'Bus_id', 'Zone_id', 'raw_weight', 'MappedDistance_km']
    if scenario_col is not None:
        columns.insert(1, scenario_col)
    return pd.concat(mapped_parts, ignore_index=True)[columns]


def _map_egon_points_to_hope_buses(
    points: pd.DataFrame,
    hope_buses: pd.DataFrame,
    entity_col: str,
    scenario_col: str,
) -> pd.DataFrame:
    if points.empty:
        return pd.DataFrame(columns=[entity_col, scenario_col, 'Bus_id', 'Zone_id', 'raw_weight', 'MappedDistance_km', 'AssignmentWeight'])

    coarse_idx, _ = _nearest_indices(
        points['Longitude'].to_numpy(dtype=float),
        points['Latitude'].to_numpy(dtype=float),
        hope_buses['Longitude'].to_numpy(dtype=float),
        hope_buses['Latitude'].to_numpy(dtype=float),
    )
    coarse = hope_buses.iloc[coarse_idx].reset_index(drop=True)
    work = points.copy()
    work['Zone_id'] = coarse['Zone_id'].astype(str).to_numpy()

    mapped_parts: list[pd.DataFrame] = []
    for zone, group in work.groupby('Zone_id', sort=True):
        zone_buses = hope_buses.loc[hope_buses['Zone_id'].astype(str) == str(zone)].reset_index(drop=True)
        if zone_buses.empty:
            continue
        dst_lon = zone_buses['Longitude'].to_numpy(dtype=float)
        dst_lat = zone_buses['Latitude'].to_numpy(dtype=float)
        dst_kv = zone_buses['V_nom_kV'].to_numpy(dtype=float) if 'V_nom_kV' in zone_buses.columns else np.full(len(zone_buses), np.nan)
        rows: list[pd.DataFrame] = []
        for _, point in group.iterrows():
            distances = _haversine_km(
                np.full(len(dst_lat), float(point['Latitude'])),
                np.full(len(dst_lon), float(point['Longitude'])),
                dst_lat,
                dst_lon,
            )
            order = np.argsort(distances)[: min(EGON_MAPPING_K, len(zone_buses))]
            candidate_buses = zone_buses.iloc[order].reset_index(drop=True)
            candidate_dist = distances[order]
            distance_score = 1.0 / np.maximum(candidate_dist, MIN_MAPPING_DISTANCE_KM) ** 2
            voltage_score = _voltage_match_score(
                float(point['Voltage_kV']) if 'Voltage_kV' in point.index and pd.notna(point['Voltage_kV']) else None,
                dst_kv[order],
            )
            score = distance_score * voltage_score
            score_sum = float(score.sum())
            if score_sum <= 0:
                score = np.full(len(candidate_buses), 1.0 / len(candidate_buses))
            else:
                score = score / score_sum
            assigned = pd.DataFrame({
                entity_col: [point[entity_col]] * len(candidate_buses),
                scenario_col: [point[scenario_col]] * len(candidate_buses),
                'Bus_id': candidate_buses['Bus_id'].astype(str),
                'Zone_id': [str(zone)] * len(candidate_buses),
                'raw_weight': float(point['raw_weight']) * score,
                'MappedDistance_km': candidate_dist,
                'AssignmentWeight': score,
            })
            rows.append(assigned)
        if rows:
            mapped_parts.append(pd.concat(rows, ignore_index=True))

    if not mapped_parts:
        return pd.DataFrame(columns=[entity_col, scenario_col, 'Bus_id', 'Zone_id', 'raw_weight', 'MappedDistance_km', 'AssignmentWeight'])
    return pd.concat(mapped_parts, ignore_index=True)


def _layer_from_point_weights(
    layer_name: str,
    points: pd.DataFrame,
    hope_buses: pd.DataFrame,
) -> pd.DataFrame:
    mapped = _map_points_to_hope_buses(points, hope_buses, entity_col='PointId')
    if mapped.empty:
        return pd.DataFrame(columns=['Bus_id', 'Zone_id', 'layer', 'layer_share'])
    grouped = mapped.groupby(['Bus_id', 'Zone_id'], as_index=False).agg(
        raw_weight=('raw_weight', 'sum'),
        PointCount=('PointId', 'nunique'),
        MeanMappedDistance_km=('MappedDistance_km', 'mean'),
        MaxMappedDistance_km=('MappedDistance_km', 'max'),
    )
    grouped['layer_share'] = grouped['raw_weight'] / grouped.groupby('Zone_id')['raw_weight'].transform('sum')
    grouped['layer'] = layer_name
    return grouped[['Bus_id', 'Zone_id', 'layer', 'layer_share', 'PointCount', 'MeanMappedDistance_km', 'MaxMappedDistance_km']]


def _legacy_public_layers(hope_buses: pd.DataFrame) -> list[pd.DataFrame]:
    layers: list[pd.DataFrame] = []
    for name in ('population', 'settlement', 'industry'):
        frame = _load_layer(name)
        if frame.empty:
            continue
        frame = frame.copy().reset_index(drop=True)
        frame['PointId'] = frame.index.astype(str)
        layers.append(_layer_from_point_weights(name, frame, hope_buses))
    return [layer for layer in layers if not layer.empty]


def _classify_csv_header(header: list[str]) -> str | None:
    lowered = {str(col).strip().lower() for col in header}
    if {'bus_id', 'x', 'y'}.issubset(lowered):
        return 'bus'
    if 'bus_id' in lowered and ('p_set' in lowered or 'annual_mwh' in lowered or 'demand_mwh' in lowered):
        return 'demand'
    return None


def _discover_egon_sources(zip_path: Path) -> tuple[str | None, list[str]]:
    bus_entry: str | None = None
    demand_entries: list[str] = []
    with zipfile.ZipFile(zip_path) as zf:
        for info in zf.infolist():
            if info.is_dir() or not info.filename.lower().endswith('.csv'):
                continue
            with zf.open(info.filename) as handle:
                text = io.TextIOWrapper(handle, encoding='utf-8', newline='')
                reader = csv.reader(text)
                header = next(reader, None)
            if not header:
                continue
            kind = _classify_csv_header(header)
            if kind == 'bus' and bus_entry is None:
                bus_entry = info.filename
            elif kind == 'demand':
                demand_entries.append(info.filename)
    return bus_entry, sorted(demand_entries)


def _discover_local_egon_sources() -> tuple[Path | None, list[Path]]:
    bus_path = _first_existing(LOCAL_EGON_BUS_FILES)
    demand_paths = [path for path in LOCAL_EGON_DEMAND_FILES if path.exists()]
    return bus_path, demand_paths


def _load_egon_bus_coordinates(zip_path: Path, entry_name: str) -> pd.DataFrame:
    with zipfile.ZipFile(zip_path) as zf:
        with zf.open(entry_name) as handle:
            frame = pd.read_csv(handle, usecols=['bus_id', 'x', 'y', 'country', 'v_nom'])
    frame['bus_id'] = frame['bus_id'].astype(str)
    frame['x'] = pd.to_numeric(frame['x'], errors='coerce')
    frame['y'] = pd.to_numeric(frame['y'], errors='coerce')
    frame['country'] = frame['country'].astype(str)
    frame['v_nom'] = pd.to_numeric(frame['v_nom'], errors='coerce')
    frame = frame.loc[frame['country'].str.upper() == 'DE'].dropna(subset=['x', 'y']).copy()
    return frame.groupby('bus_id', as_index=False).agg(Longitude=('x', 'mean'), Latitude=('y', 'mean'), Voltage_kV=('v_nom', 'median'))


def _load_egon_bus_coordinates_from_csv(path: Path) -> pd.DataFrame:
    frame = pd.read_csv(path, usecols=['bus_id', 'x', 'y', 'country', 'v_nom'])
    frame['bus_id'] = frame['bus_id'].astype(str)
    frame['x'] = pd.to_numeric(frame['x'], errors='coerce')
    frame['y'] = pd.to_numeric(frame['y'], errors='coerce')
    frame['country'] = frame['country'].astype(str)
    frame['v_nom'] = pd.to_numeric(frame['v_nom'], errors='coerce')
    frame = frame.loc[frame['country'].str.upper() == 'DE'].dropna(subset=['x', 'y']).copy()
    return frame.groupby('bus_id', as_index=False).agg(Longitude=('x', 'mean'), Latitude=('y', 'mean'), Voltage_kV=('v_nom', 'median'))


def _parse_annual_energy(row: dict[str, str]) -> float:
    for candidate in ('annual_mwh', 'demand_mwh'):
        if candidate in row and row[candidate] not in (None, ''):
            value = pd.to_numeric(pd.Series([row[candidate]]), errors='coerce').iloc[0]
            if pd.notna(value) and value > 0:
                return float(value)
    raw = str(row.get('p_set', '')).strip()
    if not raw:
        return 0.0
    if raw.startswith('[') and raw.endswith(']'):
        raw = raw[1:-1]
    values = np.fromstring(raw, sep=',', dtype=float)
    if values.size == 0:
        return 0.0
    return float(np.nan_to_num(values, nan=0.0).sum())


def _load_egon_demand_weights(zip_path: Path, entry_name: str) -> pd.DataFrame:
    totals: dict[tuple[str, str], float] = {}
    with zipfile.ZipFile(zip_path) as zf:
        with zf.open(entry_name) as handle:
            text = io.TextIOWrapper(handle, encoding='utf-8', newline='')
            reader = csv.DictReader(text)
            for row in reader:
                bus_id = str(row.get('bus_id', '')).strip()
                if not bus_id:
                    continue
                scenario = str(row.get('scn_name', 'unknown')).strip() or 'unknown'
                annual_mwh = _parse_annual_energy(row)
                if annual_mwh <= 0:
                    continue
                key = (bus_id, scenario)
                totals[key] = totals.get(key, 0.0) + annual_mwh
    rows = [
        {'egon_bus_id': bus_id, 'Scenario': scenario, 'raw_weight': value}
        for (bus_id, scenario), value in totals.items()
    ]
    return pd.DataFrame(rows)


def _load_egon_demand_weights_from_csv(path: Path) -> pd.DataFrame:
    totals: dict[tuple[str, str], float] = {}
    with path.open('r', encoding='utf-8', newline='') as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            bus_id = str(row.get('bus_id', '')).strip()
            if not bus_id:
                continue
            scenario = str(row.get('scn_name', 'unknown')).strip() or 'unknown'
            annual_mwh = _parse_annual_energy(row)
            if annual_mwh <= 0:
                continue
            key = (bus_id, scenario)
            totals[key] = totals.get(key, 0.0) + annual_mwh
    rows = [
        {'egon_bus_id': bus_id, 'Scenario': scenario, 'raw_weight': value}
        for (bus_id, scenario), value in totals.items()
    ]
    return pd.DataFrame(rows)


def _layer_from_egon_demand(
    layer_name: str,
    demand_weights: pd.DataFrame,
    egon_buses: pd.DataFrame,
    hope_buses: pd.DataFrame,
) -> pd.DataFrame:
    if demand_weights.empty:
        return pd.DataFrame(columns=['Bus_id', 'Zone_id', 'layer', 'layer_share'])

    points = demand_weights.merge(
        egon_buses.rename(columns={'bus_id': 'egon_bus_id'}),
        on='egon_bus_id',
        how='inner',
    )
    points = points.loc[points['raw_weight'] > 0].copy()
    if points.empty:
        return pd.DataFrame(columns=['Bus_id', 'Zone_id', 'layer', 'layer_share'])

    mapped = _map_egon_points_to_hope_buses(points, hope_buses, entity_col='egon_bus_id', scenario_col='Scenario')
    if mapped.empty:
        return pd.DataFrame(columns=['Bus_id', 'Zone_id', 'layer', 'layer_share'])

    scenario_mapped = mapped.groupby(['Bus_id', 'Zone_id', 'Scenario'], as_index=False)['raw_weight'].sum()
    scenario_totals = scenario_mapped.groupby(['Zone_id', 'Scenario'])['raw_weight'].transform('sum')
    scenario_mapped = scenario_mapped.loc[scenario_totals > 0].copy()
    scenario_mapped['layer_share'] = scenario_mapped['raw_weight'] / scenario_totals.loc[scenario_mapped.index]

    averaged = scenario_mapped.groupby(['Bus_id', 'Zone_id'], as_index=False)['layer_share'].mean()
    diagnostics = mapped.groupby(['Bus_id', 'Zone_id'], as_index=False).agg(
        PointCount=('AssignmentWeight', 'sum'),
        MeanMappedDistance_km=('MappedDistance_km', lambda s: float(np.average(s, weights=mapped.loc[s.index, 'AssignmentWeight']))),
        MaxMappedDistance_km=('MappedDistance_km', 'max'),
    )
    averaged = averaged.merge(diagnostics, on=['Bus_id', 'Zone_id'], how='left')
    averaged['layer'] = layer_name
    return averaged[['Bus_id', 'Zone_id', 'layer', 'layer_share', 'PointCount', 'MeanMappedDistance_km', 'MaxMappedDistance_km']]


def _egon_layers(hope_buses: pd.DataFrame, zip_path: Path | None) -> list[pd.DataFrame]:
    bus_path, demand_paths = _discover_local_egon_sources()
    if bus_path is not None and demand_paths:
        egon_buses = _load_egon_bus_coordinates_from_csv(bus_path)
        layers: list[pd.DataFrame] = []
        for path in demand_paths:
            demand_weights = _load_egon_demand_weights_from_csv(path)
            layer_name = _sanitize_column_name(path.stem)
            layer = _layer_from_egon_demand(layer_name, demand_weights, egon_buses, hope_buses)
            if not layer.empty:
                layers.append(layer)
        if layers:
            return layers

    if zip_path is None or not zip_path.exists():
        return []
    bus_entry, demand_entries = _discover_egon_sources(zip_path)
    if bus_entry is None or not demand_entries:
        return []

    egon_buses = _load_egon_bus_coordinates(zip_path, bus_entry)
    layers: list[pd.DataFrame] = []
    for entry_name in demand_entries:
        demand_weights = _load_egon_demand_weights(zip_path, entry_name)
        layer_name = f'egon_{_sanitize_column_name(Path(entry_name).stem)}'
        layer = _layer_from_egon_demand(layer_name, demand_weights, egon_buses, hope_buses)
        if not layer.empty:
            layers.append(layer)
    return layers


def _combined_layer_weights(layers: list[pd.DataFrame]) -> dict[str, float]:
    layer_names = [str(layer['layer'].iloc[0]) for layer in layers if not layer.empty]
    egon_names = sorted(name for name in layer_names if name.startswith('egon_'))
    weights: dict[str, float] = {}
    if egon_names:
        direct_each = DIRECT_DEMAND_WEIGHT / max(len(egon_names), 1)
        for name in egon_names:
            weights[name] = direct_each
        if 'industry' in layer_names:
            weights['industry'] = INDUSTRY_FALLBACK_WEIGHT
    else:
        weights.update(LEGACY_LAYER_WEIGHTS)
    active = {name: weight for name, weight in weights.items() if name in layer_names and weight > 0}
    total = sum(active.values())
    if total <= 0:
        return {name: 1.0 / len(layer_names) for name in layer_names}
    return {name: weight / total for name, weight in active.items()}


def _combine_layers(layers: list[pd.DataFrame], source: str, method: str) -> pd.DataFrame:
    mapped = pd.concat(layers, ignore_index=True)
    layer_weights = _combined_layer_weights(layers)
    mapped['layer_weight'] = mapped['layer'].map(layer_weights).fillna(0.0)
    zone_layer_total = mapped.groupby(['Zone_id', 'layer'], as_index=False)['layer_share'].sum()
    zone_layer_total = zone_layer_total.loc[zone_layer_total['layer_share'] > 0].copy()
    zone_layer_total['layer_weight'] = zone_layer_total['layer'].map(layer_weights).fillna(0.0)
    zone_layer_total['normalized_layer_weight'] = zone_layer_total.groupby('Zone_id')['layer_weight'].transform(
        lambda s: s / s.sum()
    )

    mapped = mapped.merge(
        zone_layer_total[['Zone_id', 'layer', 'normalized_layer_weight']],
        on=['Zone_id', 'layer'],
        how='inner',
    )
    mapped['weighted_component'] = mapped['layer_share'] * mapped['normalized_layer_weight']

    wide = mapped.pivot_table(
        index=['Bus_id', 'Zone_id'],
        columns='layer',
        values='weighted_component',
        aggfunc='sum',
        fill_value=0.0,
    ).reset_index()
    diagnostics = mapped.groupby(['Bus_id', 'Zone_id'], as_index=False).agg(
        PointCount=('PointCount', 'sum'),
        MeanMappedDistance_km=('MeanMappedDistance_km', lambda s: float(np.average(s, weights=np.maximum(1.0, mapped.loc[s.index, 'PointCount'])))),
        MaxMappedDistance_km=('MaxMappedDistance_km', 'max'),
    )
    combined = wide.merge(diagnostics, on=['Bus_id', 'Zone_id'], how='left')
    layer_cols = [col for col in combined.columns if col not in {'Bus_id', 'Zone_id', 'PointCount', 'MeanMappedDistance_km', 'MaxMappedDistance_km'}]
    combined['Load_share'] = combined[layer_cols].sum(axis=1)
    combined = combined.loc[combined['Load_share'] > 0].copy()
    combined['Load_share'] = combined['Load_share'] / combined.groupby('Zone_id')['Load_share'].transform('sum')
    combined['Source'] = source
    combined['Method'] = method
    ordered = ['Bus_id', 'Zone_id', 'Load_share'] + sorted(layer_cols) + [
        'PointCount',
        'MeanMappedDistance_km',
        'MaxMappedDistance_km',
        'Source',
        'Method',
    ]
    return combined[ordered].sort_values(['Zone_id', 'Bus_id']).reset_index(drop=True)


def build_germany_spatial_load_shares(zip_path: Path | None = None) -> None:
    hope_buses = _prepare_hope_buses()
    egon_layers = _egon_layers(hope_buses, zip_path)
    industry_layer = _layer_from_point_weights(
        'industry',
        _load_layer('industry').assign(PointId=lambda df: df.index.astype(str)),
        hope_buses,
    )
    if not industry_layer.empty and egon_layers:
        layers = egon_layers + [industry_layer]
        source = 'egon_bus_demand_plus_industry_proxy'
        method = 'egon_bus_demand_softmapped_to_nearby_hope_buses_with_voltage_preference_within_inferred_tso_zone_plus_industry_proxy_fallback'
    elif egon_layers:
        layers = egon_layers
        source = 'egon_bus_demand'
        method = 'egon_bus_demand_softmapped_to_nearby_hope_buses_with_voltage_preference_within_inferred_tso_zone'
    else:
        layers = _legacy_public_layers(hope_buses)
        source = 'public_spatial_proxy'
        method = 'population_settlement_industry_points_mapped_to_nearest_hope_bus_within_inferred_tso_zone'

    if not layers:
        raise FileNotFoundError(
            'No usable eGon demand inputs or public spatial proxy inputs were found for Germany spatial load allocation.'
        )

    combined = _combine_layers(layers, source=source, method=method)
    REF_DIR.mkdir(parents=True, exist_ok=True)
    combined.to_csv(OUT_FILE, index=False)
    layer_text = ', '.join(sorted(col for col in combined.columns if col.startswith('egon_') or col in {'population', 'settlement', 'industry'}))
    print(f'Wrote {OUT_FILE} with {len(combined)} bus-level rows using layers: {layer_text}')


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description='Build Germany nodal load shares from eGon demand buses or public proxy layers.')
    parser.add_argument(
        '--zip-path',
        type=Path,
        default=DEFAULT_EGON_ZIP if DEFAULT_EGON_ZIP.exists() else None,
        help='Optional path to the colleague-provided eGon ZIP. Defaults to ~/Downloads/german_nodal_data.zip when present.',
    )
    return parser.parse_args()


if __name__ == '__main__':
    args = _parse_args()
    build_germany_spatial_load_shares(zip_path=args.zip_path)
