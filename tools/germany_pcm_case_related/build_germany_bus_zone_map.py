from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import json
import math
from typing import Iterable

import pandas as pd


TOOLS_DIR = Path(__file__).resolve().parent
RAW_DIR = TOOLS_DIR / 'raw_sources'
REF_DIR = TOOLS_DIR / 'references'

BUS_INPUT_CANDIDATES = (
    REF_DIR / 'germany_network_buses_clean.csv',
    RAW_DIR / 'germany_network_buses.csv',
    RAW_DIR / 'buses.csv',
)
BUS_ZONE_MAP_PATH = REF_DIR / 'germany_bus_zone_map.csv'
MANUAL_OVERRIDES_PATH = REF_DIR / 'germany_bus_zone_manual_overrides.csv'
ZONE_ANCHORS_PATH = REF_DIR / 'germany_zone_anchor_points.csv'
ZONE_GEOJSON_PATH = REF_DIR / 'germany_tso_zones.geojson'

TSO_ALIASES = {
    '50Hertz': ('50hertz', '50 hertz'),
    'Amprion': ('amprion',),
    'TenneT': ('tennet', 'tennet tso', 'tennet germany'),
    'TransnetBW': ('transnetbw', 'transnet bw'),
}


@dataclass(frozen=True)
class AssignmentResult:
    zone_id: str | None
    mapping_source: str
    confidence: str
    notes: str = ''


def _first_existing(paths: Iterable[Path]) -> Path | None:
    for path in paths:
        if path.exists():
            return path
    return None


def _load_bus_extract() -> pd.DataFrame:
    path = _first_existing(BUS_INPUT_CANDIDATES)
    if path is None:
        names = ', '.join(p.name for p in BUS_INPUT_CANDIDATES)
        raise FileNotFoundError(
            f'Could not find a Germany bus extract. Expected one of: {names}'
        )
    df = pd.read_csv(path)
    if df.empty:
        raise ValueError(f'Bus extract is empty: {path}')
    return df


def _normalize_bus_columns(df: pd.DataFrame) -> pd.DataFrame:
    work = df.copy()
    rename_map = {}
    if 'bus_id' in work.columns and 'Bus_id' not in work.columns:
        rename_map['bus_id'] = 'Bus_id'
    if 'x' in work.columns and 'Longitude' not in work.columns:
        rename_map['x'] = 'Longitude'
    if 'y' in work.columns and 'Latitude' not in work.columns:
        rename_map['y'] = 'Latitude'
    work = work.rename(columns=rename_map)
    required = {'Bus_id', 'Longitude', 'Latitude'}
    missing = sorted(required - set(work.columns))
    if missing:
        raise ValueError(f'Bus extract missing required columns: {missing}')
    work['Bus_id'] = work['Bus_id'].astype(str)
    work['Longitude'] = pd.to_numeric(work['Longitude'], errors='coerce')
    work['Latitude'] = pd.to_numeric(work['Latitude'], errors='coerce')
    work = work.dropna(subset=['Longitude', 'Latitude']).copy()
    return work


def _load_manual_overrides() -> dict[str, str]:
    if not MANUAL_OVERRIDES_PATH.exists():
        return {}
    df = pd.read_csv(MANUAL_OVERRIDES_PATH)
    if df.empty or not {'Bus_id', 'Zone_id'}.issubset(df.columns):
        return {}
    return {
        str(row['Bus_id']): str(row['Zone_id']).strip()
        for _, row in df.iterrows()
        if str(row['Zone_id']).strip()
    }


def _load_zone_anchors() -> pd.DataFrame:
    if not ZONE_ANCHORS_PATH.exists():
        return pd.DataFrame(columns=['Zone_id', 'Latitude', 'Longitude'])
    df = pd.read_csv(ZONE_ANCHORS_PATH)
    if df.empty:
        return df
    for col in ('Latitude', 'Longitude'):
        df[col] = pd.to_numeric(df[col], errors='coerce')
    df = df.dropna(subset=['Zone_id', 'Latitude', 'Longitude']).copy()
    df['Zone_id'] = df['Zone_id'].astype(str)
    return df


def _infer_zone_from_operator_text(text: str) -> AssignmentResult | None:
    lowered = text.lower()
    for zone_id, aliases in TSO_ALIASES.items():
        if any(alias in lowered for alias in aliases):
            return AssignmentResult(zone_id=zone_id, mapping_source='operator_text', confidence='medium')
    return None


def _haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    radius_km = 6371.0
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2.0) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2.0) ** 2
    return 2.0 * radius_km * math.atan2(math.sqrt(a), math.sqrt(max(1.0 - a, 0.0)))


def _assign_from_anchors(lat: float, lon: float, anchors: pd.DataFrame) -> AssignmentResult | None:
    if anchors.empty:
        return None
    best = None
    best_dist = float('inf')
    for _, row in anchors.iterrows():
        dist = _haversine_km(lat, lon, float(row['Latitude']), float(row['Longitude']))
        if dist < best_dist:
            best_dist = dist
            best = str(row['Zone_id'])
    if best is None:
        return None
    return AssignmentResult(zone_id=best, mapping_source='nearest_anchor', confidence='low', notes=f'distance_km={best_dist:.2f}')


def _load_geojson_features() -> list[dict]:
    if not ZONE_GEOJSON_PATH.exists():
        return []
    try:
        payload = json.loads(ZONE_GEOJSON_PATH.read_text(encoding='utf-8'))
    except (OSError, json.JSONDecodeError):
        return []
    features = payload.get('features', [])
    return features if isinstance(features, list) else []


def _point_in_ring(lon: float, lat: float, ring: list[list[float]]) -> bool:
    inside = False
    j = len(ring) - 1
    for i in range(len(ring)):
        xi, yi = ring[i][0], ring[i][1]
        xj, yj = ring[j][0], ring[j][1]
        intersects = ((yi > lat) != (yj > lat)) and (
            lon < (xj - xi) * (lat - yi) / ((yj - yi) if (yj - yi) != 0 else 1e-12) + xi
        )
        if intersects:
            inside = not inside
        j = i
    return inside


def _assign_from_geojson(lat: float, lon: float, features: list[dict]) -> AssignmentResult | None:
    for feature in features:
        props = feature.get('properties') or {}
        zone_id = str(props.get('Zone_id') or props.get('zone_id') or '').strip()
        geom = feature.get('geometry') or {}
        geom_type = geom.get('type')
        coords = geom.get('coordinates') or []
        polygon_sets = []
        if geom_type == 'Polygon':
            polygon_sets = [coords]
        elif geom_type == 'MultiPolygon':
            polygon_sets = coords
        for polygon in polygon_sets:
            if not polygon:
                continue
            outer_ring = polygon[0]
            if outer_ring and _point_in_ring(lon, lat, outer_ring):
                return AssignmentResult(zone_id=zone_id, mapping_source='zone_polygon', confidence='high')
    return None


def build_germany_bus_zone_map() -> pd.DataFrame:
    buses = _normalize_bus_columns(_load_bus_extract())
    overrides = _load_manual_overrides()
    anchors = _load_zone_anchors()
    features = _load_geojson_features()

    rows: list[dict] = []
    for _, row in buses.iterrows():
        bus_id = str(row['Bus_id'])
        lat = float(row['Latitude'])
        lon = float(row['Longitude'])
        operator_text = ' '.join(
            str(row[col])
            for col in ('operator', 'tags', 'Operator', 'Tags', 'SourceBusName', 'RawBusKey')
            if col in buses.columns and pd.notna(row[col])
        ).strip()

        assignment: AssignmentResult | None = None
        if bus_id in overrides:
            assignment = AssignmentResult(zone_id=overrides[bus_id], mapping_source='manual_override', confidence='high')
        if assignment is None and features:
            assignment = _assign_from_geojson(lat, lon, features)
        if assignment is None and operator_text:
            assignment = _infer_zone_from_operator_text(operator_text)
        if assignment is None:
            assignment = _assign_from_anchors(lat, lon, anchors)
        if assignment is None:
            assignment = AssignmentResult(zone_id=None, mapping_source='unresolved', confidence='unassigned')

        rows.append(
            {
                'Bus_id': bus_id,
                'Zone_id': assignment.zone_id or '',
                'TSO': assignment.zone_id or '',
                'State': row['state'] if 'state' in buses.columns else (row['State'] if 'State' in buses.columns else ''),
                'Latitude': lat,
                'Longitude': lon,
                'MappingSource': assignment.mapping_source,
                'Confidence': assignment.confidence,
                'Notes': assignment.notes,
            }
        )

    out = pd.DataFrame(rows)
    out.to_csv(BUS_ZONE_MAP_PATH, index=False)
    return out


if __name__ == '__main__':
    result = build_germany_bus_zone_map()
    unresolved = int((result['Zone_id'].astype(str).str.strip() == '').sum())
    print(f'Wrote {BUS_ZONE_MAP_PATH}')
    print(f'Rows: {len(result)} | Unresolved: {unresolved}')
