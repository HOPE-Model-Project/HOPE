from __future__ import annotations

import csv
import json
import math
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
TOOLS_DIR = ROOT / "tools" / "iso_ne_250bus_case_related"
RAW_DIR = TOOLS_DIR / "raw_sources"
REF_DIR = TOOLS_DIR / "references"
RAW_JSON_PATH = RAW_DIR / "osm_power_new_england.json"
SUBSTATIONS_CSV = REF_DIR / "osm_substations.csv"
CORRIDOR_POINTS_CSV = REF_DIR / "osm_corridor_points.csv"
INTERFACE_CANDIDATES_CSV = REF_DIR / "osm_interface_portal_candidates.csv"
INTERFACE_SUMMARY_CSV = REF_DIR / "osm_interface_portal_summary.csv"
MANIFEST_JSON = REF_DIR / "osm_power_manifest.json"

OVERPASS_URL = "https://overpass-api.de/api/interpreter"
NEW_ENGLAND_BBOX = (40.85, -74.95, 47.65, -66.55)
TRANSMISSION_VOLTAGES = ["110000", "115000", "120000", "138000", "161000", "230000", "345000", "450000", "500000", "765000"]
INTERFACE_WINDOWS: dict[str, dict[str, Any]] = {
    "SALBRYNB": {"lat_min": 44.55, "lat_max": 47.65, "lon_min": -68.55, "lon_max": -66.55},
    "HQHIGATE": {"lat_min": 44.55, "lat_max": 45.30, "lon_min": -73.45, "lon_max": -72.35},
    "ROSETON": {"lat_min": 41.70, "lat_max": 42.95, "lon_min": -73.95, "lon_max": -72.55},
    "SHOREHAM": {"lat_min": 41.00, "lat_max": 41.55, "lon_min": -73.25, "lon_max": -72.35},
    "NORTHPORT": {"lat_min": 40.95, "lat_max": 41.45, "lon_min": -73.75, "lon_max": -72.90},
    "HQ_P1_P2": {"lat_min": 42.20, "lat_max": 43.25, "lon_min": -72.05, "lon_max": -70.85},
}


def build_query() -> str:
    bbox = ",".join(str(x) for x in NEW_ENGLAND_BBOX)
    voltage_regex = "(^|;)(" + "|".join(TRANSMISSION_VOLTAGES) + ")(;|$)"
    return f"""
[out:json][timeout:300];
(
  nwr["power"="substation"]["substation"~"transmission|generation|transition"]({bbox});
  way["power"="line"]["voltage"~"{voltage_regex}"]({bbox});
  way["power"="cable"]["voltage"~"{voltage_regex}"]({bbox});
);
out center geom tags;
""".strip()


def fetch_overpass(query: str) -> dict[str, Any]:
    data = urllib.parse.urlencode({"data": query}).encode("utf-8")
    req = urllib.request.Request(
        OVERPASS_URL,
        data=data,
        headers={"User-Agent": "HOPE-ISO-NE-OSM-Prior/1.0"},
    )
    with urllib.request.urlopen(req, timeout=300) as resp:
        return json.loads(resp.read().decode("utf-8"))


def _parse_max_voltage_kv(value: str | None) -> float | None:
    if not value:
        return None
    volts: list[float] = []
    for part in str(value).replace(",", ";").split(";"):
        token = part.strip()
        if not token:
            continue
        try:
            volts.append(float(token) / 1000.0)
        except ValueError:
            continue
    return max(volts) if volts else None


def _parse_circuits(value: str | None) -> int:
    if not value:
        return 1
    token = str(value).split(";")[0].strip()
    try:
        return max(1, int(float(token)))
    except ValueError:
        return 1


def _weight_from_voltage(voltage_kv: float | None, circuits: int, *, substation: bool) -> float:
    base = 1.0 if voltage_kv is None else max(1.0, voltage_kv / 115.0)
    circuit_factor = max(1.0, math.sqrt(float(circuits)))
    if substation:
        return round(base * circuit_factor, 6)
    return round(base * circuit_factor * 0.65, 6)


def _element_lat_lon(element: dict[str, Any]) -> tuple[float | None, float | None]:
    if "lat" in element and "lon" in element:
        return float(element["lat"]), float(element["lon"])
    center = element.get("center")
    if isinstance(center, dict) and "lat" in center and "lon" in center:
        return float(center["lat"]), float(center["lon"])
    geometry = element.get("geometry")
    if isinstance(geometry, list) and geometry:
        lats = [float(pt["lat"]) for pt in geometry if "lat" in pt]
        lons = [float(pt["lon"]) for pt in geometry if "lon" in pt]
        if lats and lons:
            return sum(lats) / len(lats), sum(lons) / len(lons)
    return None, None


def _sample_geometry(points: list[dict[str, Any]]) -> list[tuple[int, float, float]]:
    if not points:
        return []
    if len(points) <= 6:
        idxs = range(len(points))
    else:
        step = max(1, len(points) // 5)
        idxs = sorted({0, len(points) - 1, *range(0, len(points), step)})
    sampled: list[tuple[int, float, float]] = []
    for idx in idxs:
        pt = points[idx]
        sampled.append((idx, float(pt["lat"]), float(pt["lon"])))
    return sampled


def build_outputs(payload: dict[str, Any]) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[dict[str, Any]]]:
    substations: list[dict[str, Any]] = []
    corridor_points: list[dict[str, Any]] = []
    interface_candidates: list[dict[str, Any]] = []

    for element in payload.get("elements", []):
        tags = element.get("tags", {})
        power = str(tags.get("power", "")).strip()
        voltage_kv = _parse_max_voltage_kv(tags.get("voltage"))
        circuits = _parse_circuits(tags.get("circuits"))

        if power == "substation":
            lat, lon = _element_lat_lon(element)
            if lat is None or lon is None:
                continue
            row = {
                "OSMType": element.get("type"),
                "OSMId": element.get("id"),
                "Name": str(tags.get("name", "")),
                "SubstationType": str(tags.get("substation", "")),
                "VoltageTag": str(tags.get("voltage", "")),
                "VoltageKV": voltage_kv,
                "Circuits": circuits,
                "Operator": str(tags.get("operator", "")),
                "Ref": str(tags.get("ref", "")),
                "Latitude": round(lat, 6),
                "Longitude": round(lon, 6),
                "AnchorWeight": _weight_from_voltage(voltage_kv, circuits, substation=True),
            }
            substations.append(row)
            for interface, window in INTERFACE_WINDOWS.items():
                if (
                    window["lat_min"] <= lat <= window["lat_max"]
                    and window["lon_min"] <= lon <= window["lon_max"]
                ):
                    interface_candidates.append(
                        {
                            "Interface": interface,
                            **row,
                        }
                    )
        elif power in {"line", "cable"}:
            geometry = element.get("geometry") or []
            if not geometry:
                continue
            for point_index, lat, lon in _sample_geometry(geometry):
                corridor_points.append(
                    {
                        "OSMType": element.get("type"),
                        "OSMId": element.get("id"),
                        "PowerType": power,
                        "Name": str(tags.get("name", "")),
                        "VoltageTag": str(tags.get("voltage", "")),
                        "VoltageKV": voltage_kv,
                        "Circuits": circuits,
                        "Operator": str(tags.get("operator", "")),
                        "PointIndex": point_index,
                        "Latitude": round(lat, 6),
                        "Longitude": round(lon, 6),
                        "AnchorWeight": _weight_from_voltage(voltage_kv, circuits, substation=False),
                    }
                )

    interface_candidates.sort(
        key=lambda row: (
            row["Interface"],
            -(row["VoltageKV"] or 0.0),
            -float(row["AnchorWeight"]),
            row["Name"],
        )
    )
    return substations, corridor_points, interface_candidates


def build_interface_summary(interface_candidates: list[dict[str, Any]]) -> list[dict[str, Any]]:
    summary: list[dict[str, Any]] = []
    grouped: dict[str, list[dict[str, Any]]] = {}
    for row in interface_candidates:
        grouped.setdefault(str(row["Interface"]), []).append(row)

    for interface, rows in sorted(grouped.items()):
        weights = [max(0.25, float(row["AnchorWeight"])) for row in rows]
        latitudes = [float(row["Latitude"]) for row in rows]
        longitudes = [float(row["Longitude"]) for row in rows]
        centroid_lat = sum(w * lat for w, lat in zip(weights, latitudes)) / sum(weights)
        centroid_lon = sum(w * lon for w, lon in zip(weights, longitudes)) / sum(weights)
        summary.append(
            {
                "Interface": interface,
                "CandidateCount": len(rows),
                "CentroidLatitude": round(centroid_lat, 6),
                "CentroidLongitude": round(centroid_lon, 6),
                "LatMin": round(min(latitudes) - 0.20, 6),
                "LatMax": round(max(latitudes) + 0.20, 6),
                "LonMin": round(min(longitudes) - 0.20, 6),
                "LonMax": round(max(longitudes) + 0.20, 6),
            }
        )
    return summary


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not rows:
        path.write_text("", encoding="utf-8")
        return
    fieldnames = list(rows[0].keys())
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    REF_DIR.mkdir(parents=True, exist_ok=True)

    query = build_query()
    payload = fetch_overpass(query)
    RAW_JSON_PATH.write_text(json.dumps(payload), encoding="utf-8")

    substations, corridor_points, interface_candidates = build_outputs(payload)
    interface_summary = build_interface_summary(interface_candidates)
    write_csv(SUBSTATIONS_CSV, substations)
    write_csv(CORRIDOR_POINTS_CSV, corridor_points)
    write_csv(INTERFACE_CANDIDATES_CSV, interface_candidates)
    write_csv(INTERFACE_SUMMARY_CSV, interface_summary)

    manifest = {
        "source": "OpenStreetMap via Overpass API",
        "url": OVERPASS_URL,
        "bbox": NEW_ENGLAND_BBOX,
        "substations": len(substations),
        "corridor_points": len(corridor_points),
        "interface_candidates": len(interface_candidates),
        "files": {
            "raw_json": str(RAW_JSON_PATH),
            "substations_csv": str(SUBSTATIONS_CSV),
            "corridor_points_csv": str(CORRIDOR_POINTS_CSV),
            "interface_candidates_csv": str(INTERFACE_CANDIDATES_CSV),
            "interface_summary_csv": str(INTERFACE_SUMMARY_CSV),
        },
    }
    MANIFEST_JSON.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
