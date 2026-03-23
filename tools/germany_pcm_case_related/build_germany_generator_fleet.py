from __future__ import annotations

from pathlib import Path
import math

import numpy as np
import pandas as pd


TOOLS_DIR = Path(__file__).resolve().parent
RAW_DIR = TOOLS_DIR / 'raw_sources'
REF_DIR = TOOLS_DIR / 'references'

POWERPLANTMATCHING_DIR = RAW_DIR / 'powerplantmatching'
MASTR_DIR = RAW_DIR / 'mastr'
KRAFTWERKSLISTE_DIR = RAW_DIR / 'kraftwerksliste'

PPM_CANDIDATES = (
    POWERPLANTMATCHING_DIR / 'germany_powerplantmatching.csv',
    POWERPLANTMATCHING_DIR / 'powerplants.csv',
    POWERPLANTMATCHING_DIR / 'powerplantmatching_germany.csv',
)

BUSES_CLEAN_PATH = REF_DIR / 'germany_network_buses_clean.csv'
BUS_ZONE_MAP_PATH = REF_DIR / 'germany_bus_zone_map.csv'
FLEET_OUT = REF_DIR / 'germany_generator_fleet_clean.csv'
GENERATOR_BUS_MAP_OUT = REF_DIR / 'germany_generator_bus_map.csv'


def _first_existing(paths: tuple[Path, ...]) -> Path | None:
    for path in paths:
        if path.exists():
            return path
    return None


def _has_non_readme_files(folder: Path) -> bool:
    if not folder.exists():
        return False
    for path in folder.iterdir():
        if path.is_file() and path.name.lower() != 'readme.md':
            return True
    return False


def _read_powerplantmatching() -> pd.DataFrame:
    path = _first_existing(PPM_CANDIDATES)
    if path is None:
        names = ', '.join(p.name for p in PPM_CANDIDATES)
        raise FileNotFoundError(
            f'Could not find a Germany powerplantmatching extract. Expected one of: {names}'
        )
    df = pd.read_csv(path)
    if df.empty:
        raise ValueError(f'Generator fleet input is empty: {path}')
    df.attrs['source_path'] = str(path)
    return df


def _read_required_csv(path: Path, label: str) -> pd.DataFrame:
    if not path.exists():
        raise FileNotFoundError(f'Missing required {label}: {path}')
    df = pd.read_csv(path)
    if df.empty:
        raise ValueError(f'{label} is empty: {path}')
    return df


def _pick_first_existing(row: pd.Series, columns: tuple[str, ...]) -> object:
    for col in columns:
        if col in row.index and pd.notna(row[col]) and str(row[col]).strip() != '':
            return row[col]
    return ''


def _normalize_country(value: object) -> str:
    text = str(value).strip()
    lowered = text.lower()
    if lowered in {'de', 'deu', 'germany', 'deutschland'}:
        return 'DE'
    return text


def _is_germany_record(row: pd.Series) -> bool:
    candidates = (
        _pick_first_existing(row, ('country', 'Country', 'country_code', 'Country_Code')),
        _pick_first_existing(row, ('country_long', 'Country_Long', 'CountryName', 'country_name')),
    )
    normalized = {_normalize_country(value) for value in candidates if str(value).strip()}
    return 'DE' in normalized or 'Germany' in normalized


def _normalize_status(value: object) -> str:
    text = str(value).strip()
    lowered = text.lower()
    if not text:
        return 'unknown'
    if any(token in lowered for token in ('operating', 'running', 'in service', 'active', 'existing')):
        return 'operating'
    if any(token in lowered for token in ('retired', 'decommissioned', 'shutdown', 'closed')):
        return 'retired'
    if any(token in lowered for token in ('planned', 'construction', 'proposal', 'permitted')):
        return 'planned'
    return text


def _select_capacity_mw(row: pd.Series) -> float:
    for col in (
        'capacity_net_bnetza',
        'capacity_net_mw',
        'capacity',
        'capacity_net',
        'capacity_gross_uba',
        'Capacity',
        'Capacity_MW',
    ):
        if col in row.index:
            value = pd.to_numeric(pd.Series([row[col]]), errors='coerce').iloc[0]
            if pd.notna(value):
                return float(value)
    return float('nan')


def _normalize_fleet(df: pd.DataFrame) -> pd.DataFrame:
    rows: list[dict] = []
    source_dataset = Path(df.attrs.get('source_path', '')).name
    for i, row in df.iterrows():
        if not _is_germany_record(row):
            continue

        plant_name = str(_pick_first_existing(row, ('name', 'Name', 'plant_name', 'PlantName'))).strip()
        source_record_id = str(_pick_first_existing(row, ('id', 'projectID', 'project_id', 'EIC', 'eic_code'))).strip()
        gen_id = source_record_id or f'GEN_{i + 1}'
        fuel_type = str(_pick_first_existing(row, ('fueltype', 'Fueltype', 'FuelType', 'fuel'))).strip()
        technology = str(_pick_first_existing(row, ('technology', 'Technology', 'set', 'Set'))).strip()
        status = _normalize_status(_pick_first_existing(row, ('status', 'Status', 'project_status', 'ProjectStatus')))
        capacity_mw = _select_capacity_mw(row)
        latitude = pd.to_numeric(pd.Series([_pick_first_existing(row, ('lat', 'latitude', 'Latitude'))]), errors='coerce').iloc[0]
        longitude = pd.to_numeric(pd.Series([_pick_first_existing(row, ('lon', 'longitude', 'Longitude'))]), errors='coerce').iloc[0]

        if status == 'retired':
            continue
        if pd.isna(capacity_mw) or capacity_mw <= 0:
            continue

        rows.append(
            {
                'GenId': str(gen_id),
                'PlantName': plant_name or str(gen_id),
                'FuelType': fuel_type,
                'Technology': technology,
                'Status': status,
                'Capacity_MW': float(capacity_mw),
                'Latitude': latitude,
                'Longitude': longitude,
                'SourceDataset': source_dataset,
                'SourceRecordId': source_record_id,
                'ValidationFlag': '',
                'Notes': '',
            }
        )

    out = pd.DataFrame(rows)
    if out.empty:
        raise ValueError('No Germany generator records remained after normalization.')

    out = out.sort_values(['FuelType', 'PlantName', 'GenId']).drop_duplicates(subset=['GenId']).reset_index(drop=True)
    return out


def _haversine_km_array(lat_deg: np.ndarray, lon_deg: np.ndarray, bus_lats_deg: np.ndarray, bus_lons_deg: np.ndarray) -> np.ndarray:
    radius_km = 6371.0
    lat_rad = np.radians(lat_deg)[:, None]
    lon_rad = np.radians(lon_deg)[:, None]
    bus_lat_rad = np.radians(bus_lats_deg)[None, :]
    bus_lon_rad = np.radians(bus_lons_deg)[None, :]
    dlat = bus_lat_rad - lat_rad
    dlon = bus_lon_rad - lon_rad
    a = np.sin(dlat / 2.0) ** 2 + np.cos(lat_rad) * np.cos(bus_lat_rad) * np.sin(dlon / 2.0) ** 2
    return 2.0 * radius_km * np.arctan2(np.sqrt(a), np.sqrt(np.maximum(1.0 - a, 0.0)))


def _assign_generators_to_buses(fleet: pd.DataFrame, buses: pd.DataFrame, bus_zone_map: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    bus_zone_lookup = bus_zone_map.set_index('Bus_id')['Zone_id'].astype(str).to_dict()

    clean_buses = buses.copy()
    clean_buses['Latitude'] = pd.to_numeric(clean_buses['Latitude'], errors='coerce')
    clean_buses['Longitude'] = pd.to_numeric(clean_buses['Longitude'], errors='coerce')
    clean_buses = clean_buses.dropna(subset=['Latitude', 'Longitude']).reset_index(drop=True)
    if clean_buses.empty:
        raise ValueError('No bus coordinates available for generator assignment.')

    bus_ids = clean_buses['Bus_id'].astype(str).to_numpy()
    bus_lats = clean_buses['Latitude'].astype(float).to_numpy()
    bus_lons = clean_buses['Longitude'].astype(float).to_numpy()

    out = fleet.copy().reset_index(drop=True)
    out['Latitude'] = pd.to_numeric(out['Latitude'], errors='coerce')
    out['Longitude'] = pd.to_numeric(out['Longitude'], errors='coerce')
    out['Bus_id'] = ''
    out['Zone_id'] = ''
    out['AssignmentMethod'] = 'unassigned'
    out['AssignmentDistance_km'] = np.nan
    out['Notes'] = out['Notes'].astype(str)

    valid_mask = out['Latitude'].notna() & out['Longitude'].notna()
    valid_idx = out.index[valid_mask].to_numpy()

    chunk_size = 2000
    for start in range(0, len(valid_idx), chunk_size):
        idx = valid_idx[start:start + chunk_size]
        lat_chunk = out.loc[idx, 'Latitude'].to_numpy(dtype=float)
        lon_chunk = out.loc[idx, 'Longitude'].to_numpy(dtype=float)
        distances = _haversine_km_array(lat_chunk, lon_chunk, bus_lats, bus_lons)
        nearest = distances.argmin(axis=1)
        nearest_dist = distances[np.arange(len(idx)), nearest]
        out.loc[idx, 'Bus_id'] = bus_ids[nearest]
        out.loc[idx, 'AssignmentDistance_km'] = nearest_dist
        out.loc[idx, 'AssignmentMethod'] = 'nearest_bus'

    out.loc[valid_mask, 'Zone_id'] = out.loc[valid_mask, 'Bus_id'].map(bus_zone_lookup).fillna('')
    long_mask = out['AssignmentDistance_km'].notna() & (out['AssignmentDistance_km'] > 100.0)
    out.loc[long_mask, 'Notes'] = out.loc[long_mask, 'Notes'].map(lambda value: (value + '; long_bus_assignment_distance').strip('; '))
    missing_coord_mask = ~valid_mask
    out.loc[missing_coord_mask, 'Notes'] = out.loc[missing_coord_mask, 'Notes'].map(lambda value: (value + '; missing_generator_coordinates').strip('; '))

    generator_bus_map = out[['GenId', 'PlantName', 'Bus_id', 'Zone_id', 'AssignmentMethod', 'AssignmentDistance_km', 'SourceDataset', 'Notes']].copy()
    generator_bus_map = generator_bus_map.rename(columns={'AssignmentDistance_km': 'Distance_km'})
    generator_bus_map['Confidence'] = 'medium'
    generator_bus_map.loc[generator_bus_map['Bus_id'].astype(str).str.strip() == '', 'Confidence'] = 'unassigned'
    generator_bus_map.loc[generator_bus_map['Distance_km'].fillna(0) > 50.0, 'Confidence'] = 'low'

    fleet_out = out[['GenId', 'PlantName', 'FuelType', 'Technology', 'Status', 'Capacity_MW', 'Latitude', 'Longitude', 'Bus_id', 'Zone_id', 'AssignmentMethod', 'AssignmentDistance_km', 'SourceDataset', 'SourceRecordId', 'ValidationFlag', 'Notes']].copy()
    return fleet_out, generator_bus_map


def _append_validation_note(fleet: pd.DataFrame) -> pd.DataFrame:
    flags = []
    if _has_non_readme_files(MASTR_DIR):
        flags.append('mastr_available')
    if _has_non_readme_files(KRAFTWERKSLISTE_DIR):
        flags.append('kraftwerksliste_available')
    if not flags:
        return fleet
    out = fleet.copy()
    marker = '|'.join(flags)
    out['ValidationFlag'] = out['ValidationFlag'].astype(str).map(lambda value: marker if not value else f'{value}|{marker}')
    return out


def build_germany_generator_fleet() -> tuple[pd.DataFrame, pd.DataFrame]:
    raw = _read_powerplantmatching()
    buses = _read_required_csv(BUSES_CLEAN_PATH, 'clean Germany bus staging table')
    bus_zone_map = _read_required_csv(BUS_ZONE_MAP_PATH, 'Germany bus-zone map')

    fleet = _normalize_fleet(raw)
    fleet, generator_bus_map = _assign_generators_to_buses(fleet, buses, bus_zone_map)
    fleet = _append_validation_note(fleet)

    fleet.to_csv(FLEET_OUT, index=False)
    generator_bus_map.to_csv(GENERATOR_BUS_MAP_OUT, index=False)
    return fleet, generator_bus_map


if __name__ == '__main__':
    fleet, generator_bus_map = build_germany_generator_fleet()
    unresolved = int((generator_bus_map['Bus_id'].astype(str).str.strip() == '').sum())
    print(f'Wrote {FLEET_OUT}')
    print(f'Wrote {GENERATOR_BUS_MAP_OUT}')
    print(f'Fleet rows: {len(fleet)} | Unassigned generators: {unresolved}')
