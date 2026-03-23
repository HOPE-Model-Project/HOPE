from __future__ import annotations

from pathlib import Path
import json

import matplotlib
matplotlib.use("Agg")
from matplotlib import pyplot as plt
from matplotlib.path import Path as MplPath
import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[2]
STATE_GEOJSON = ROOT / "tools" / "germany_pcm_case_related" / "raw_sources" / "reference_geo" / "germany_states_simplify200.geojson"
CASE_BUSDATA = ROOT / "ModelCases" / "GERMANY_PCM_nodal_jan_2day_rescaled_case" / "Data_GERMANY_PCM_nodal" / "busdata.csv"
OUTPUT_GEOJSON = ROOT / "tools" / "hope_dashboard" / "data" / "germany_tso_zones.geojson"

WHOLE_STATE_ASSIGNMENTS = {
    "Schleswig-Holstein": "TenneT",
    "Hamburg": "50Hertz",
    "Bremen": "TenneT",
    "Nordrhein-Westfalen": "Amprion",
    "Rheinland-Pfalz": "Amprion",
    "Baden-W?rttemberg": "TransnetBW",
    "Bayern": "TenneT",
    "Saarland": "Amprion",
    "Berlin": "50Hertz",
    "Brandenburg": "50Hertz",
    "Mecklenburg-Vorpommern": "50Hertz",
    "Sachsen": "50Hertz",
    "Sachsen-Anhalt": "50Hertz",
    "Th?ringen": "50Hertz",
}

SPLIT_STATE_ZONES = {
    "Niedersachsen": ("Amprion", "TenneT"),
    "Hessen": ("Amprion", "TenneT"),
}

ZONE_SOURCE_NAME = {
    "50Hertz": "Germany TSO area (state-boundary reconstruction)",
    "Amprion": "Germany TSO area (state-boundary reconstruction)",
    "TenneT": "Germany TSO area (state-boundary reconstruction)",
    "TransnetBW": "Germany TSO area (state-boundary reconstruction)",
}


def polygon_area(coords: list[list[float]]) -> float:
    if len(coords) < 3:
        return 0.0
    arr = np.asarray(coords, dtype=float)
    x = arr[:, 0]
    y = arr[:, 1]
    return 0.5 * abs(float(np.dot(x, np.roll(y, -1)) - np.dot(y, np.roll(x, -1))))


def close_ring(coords: list[list[float]]) -> list[list[float]]:
    if not coords:
        return coords
    if coords[0] != coords[-1]:
        coords = coords + [coords[0]]
    return coords


def simplify_zone_polygons(polygons: list[list[list[list[float]]]]) -> list[list[list[list[float]]]]:
    if not polygons:
        return []
    areas = [polygon_area(polygon[0]) for polygon in polygons if polygon and polygon[0]]
    if not areas:
        return []
    largest_area = max(areas)
    keep_floor = max(0.03, largest_area * 0.012)
    kept = []
    for polygon in polygons:
        if not polygon or not polygon[0]:
            continue
        if polygon_area(polygon[0]) < keep_floor:
            continue
        kept.append(polygon)
    return kept


def feature_polygons(feature: dict) -> list[list[list[list[float]]]]:
    geometry = feature.get("geometry") or {}
    geo_type = geometry.get("type")
    coords = geometry.get("coordinates") or []
    if geo_type == "Polygon":
        return [coords]
    if geo_type == "MultiPolygon":
        return coords
    return []


def geometry_bbox(multipolygon: list[list[list[list[float]]]]) -> tuple[float, float, float, float]:
    lon_vals = []
    lat_vals = []
    for polygon in multipolygon:
        for ring in polygon:
            arr = np.asarray(ring, dtype=float)
            lon_vals.extend(arr[:, 0].tolist())
            lat_vals.extend(arr[:, 1].tolist())
    return min(lon_vals), min(lat_vals), max(lon_vals), max(lat_vals)


def points_in_multipolygon(points: np.ndarray, multipolygon: list[list[list[list[float]]]]) -> np.ndarray:
    mask = np.zeros(len(points), dtype=bool)
    for polygon in multipolygon:
        outer = np.asarray(polygon[0], dtype=float)
        inside = MplPath(outer).contains_points(points)
        for hole in polygon[1:]:
            inside &= ~MplPath(np.asarray(hole, dtype=float)).contains_points(points)
        mask |= inside
    return mask


def extract_contour_polygons(contour_set, area_floor: float) -> list[np.ndarray]:
    polygons: list[np.ndarray] = []
    for segment_group in getattr(contour_set, "allsegs", []):
        for segment in segment_group:
            arr = np.asarray(segment, dtype=float)
            if len(arr) < 4:
                continue
            if not np.allclose(arr[0], arr[-1]):
                arr = np.vstack([arr, arr[0]])
            if polygon_area(arr.tolist()) < area_floor:
                continue
            polygons.append(arr)
    return polygons


def split_state_geometry(
    state_geometry: list[list[list[list[float]]]],
    state_buses: pd.DataFrame,
    allowed_zones: tuple[str, ...],
) -> dict[str, list[list[list[list[float]]]]]:
    lon_min, lat_min, lon_max, lat_max = geometry_bbox(state_geometry)
    lon_span = max(lon_max - lon_min, 0.5)
    lat_span = max(lat_max - lat_min, 0.5)
    lon_scale = max(float(np.cos(np.deg2rad((lat_min + lat_max) / 2.0))), 0.45)

    lat_steps = 220
    lon_steps = int(np.clip(round(lat_steps * (lon_span * lon_scale) / lat_span), 160, 280))
    lon_values = np.linspace(lon_min, lon_max, lon_steps)
    lat_values = np.linspace(lat_min, lat_max, lat_steps)
    grid_lon, grid_lat = np.meshgrid(lon_values, lat_values)
    grid_points = np.column_stack([grid_lon.ravel(), grid_lat.ravel()])
    inside_mask = points_in_multipolygon(grid_points, state_geometry).reshape(grid_lon.shape)

    zone_bus_points: dict[str, np.ndarray] = {}
    for zone in allowed_zones:
        zone_points = state_buses.loc[state_buses["LoadZone"] == zone, ["Longitude", "Latitude"]].to_numpy(dtype=float)
        if len(zone_points) == 0:
            continue
        zone_bus_points[zone] = zone_points
    if len(zone_bus_points) < 2:
        return {}

    zone_distance_stack = []
    active_zones = []
    for zone, zone_points in zone_bus_points.items():
        diff_lon = (grid_lon[..., None] - zone_points[:, 0]) * lon_scale
        diff_lat = grid_lat[..., None] - zone_points[:, 1]
        zone_distance_stack.append(np.sqrt(diff_lon**2 + diff_lat**2).min(axis=2))
        active_zones.append(zone)
    distance_stack = np.stack(zone_distance_stack, axis=2)
    winner = np.argmin(distance_stack, axis=2)

    area_floor = lon_span * lat_span * 0.003
    fig, ax = plt.subplots(figsize=(4, 4))
    try:
        result: dict[str, list[list[list[list[float]]]]] = {zone: [] for zone in active_zones}
        for zone_index, zone in enumerate(active_zones):
            zone_mask = inside_mask & (winner == zone_index)
            if zone_mask.sum() < 20:
                continue
            contour = ax.contour(lon_values, lat_values, zone_mask.astype(float), levels=[0.5])
            candidate_polygons = extract_contour_polygons(contour, area_floor=area_floor)
            if not candidate_polygons:
                continue
            polygon_areas = [polygon_area(polygon.tolist()) for polygon in candidate_polygons]
            largest_area = max(polygon_areas)
            keep_floor = max(area_floor, largest_area * 0.08)
            kept_polygons: list[list[list[list[float]]]] = []
            for polygon, this_area in sorted(zip(candidate_polygons, polygon_areas), key=lambda item: item[1], reverse=True):
                if this_area < keep_floor:
                    continue
                kept_polygons.append([close_ring(polygon.tolist())])
            result[zone] = kept_polygons
        return result
    finally:
        plt.close(fig)


def main() -> None:
    states = json.loads(STATE_GEOJSON.read_text(encoding="utf-8"))
    bus = pd.read_csv(CASE_BUSDATA)
    bus = bus.dropna(subset=["Longitude", "Latitude", "LoadZone"]).copy()
    bus["Longitude"] = pd.to_numeric(bus["Longitude"], errors="coerce")
    bus["Latitude"] = pd.to_numeric(bus["Latitude"], errors="coerce")
    bus = bus.dropna(subset=["Longitude", "Latitude"])

    zone_geometries: dict[str, list[list[list[list[float]]]]] = {zone: [] for zone in ["50Hertz", "Amprion", "TenneT", "TransnetBW"]}

    for feature in states["features"]:
        state_name = feature["properties"].get("GEN")
        state_geometry = feature_polygons(feature)
        if not state_geometry:
            continue
        lon_min, lat_min, lon_max, lat_max = geometry_bbox(state_geometry)
        state_points = bus[(bus["Longitude"] >= lon_min) & (bus["Longitude"] <= lon_max) & (bus["Latitude"] >= lat_min) & (bus["Latitude"] <= lat_max)].copy()
        if not state_points.empty:
            inside = points_in_multipolygon(state_points[["Longitude", "Latitude"]].to_numpy(dtype=float), state_geometry)
            state_points = state_points.loc[inside].copy()

        if state_name in WHOLE_STATE_ASSIGNMENTS:
            zone_geometries[WHOLE_STATE_ASSIGNMENTS[state_name]].extend(state_geometry)
            continue

        if state_name in SPLIT_STATE_ZONES and not state_points.empty:
            split_result = split_state_geometry(state_geometry, state_points, SPLIT_STATE_ZONES[state_name])
            if split_result:
                for zone, polygons in split_result.items():
                    zone_geometries[zone].extend(polygons)
                continue

        if not state_points.empty:
            dominant_zone = state_points["LoadZone"].mode().iat[0]
            zone_geometries[str(dominant_zone)].extend(state_geometry)

    features = []
    for zone, polygons in zone_geometries.items():
        polygons = simplify_zone_polygons(polygons)
        if not polygons:
            continue
        features.append(
            {
                "type": "Feature",
                "properties": {
                    "load_zone": zone,
                    "source_name": ZONE_SOURCE_NAME[zone],
                },
                "geometry": {
                    "type": "MultiPolygon",
                    "coordinates": polygons,
                },
            }
        )

    output = {
        "type": "FeatureCollection",
        "name": "germany_tso_zones",
        "features": features,
    }
    OUTPUT_GEOJSON.write_text(json.dumps(output, ensure_ascii=False), encoding="utf-8")
    print(f"wrote {OUTPUT_GEOJSON}")


if __name__ == "__main__":
    main()
