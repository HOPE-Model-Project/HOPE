"""Simplify pjm_utility_zones.geojson by reducing vertex count for dashboard use."""
import json
from pathlib import Path

STEP = 10          # keep every Nth vertex (drops ~90% of low-detail points)
MIN_SPAN = 0.08    # drop rings smaller than ~8 km in both axes

IN  = Path("data/pjm_utility_zones.geojson")
OUT = Path("data/pjm_zones_simplified.geojson")

with open(IN) as f:
    fc = json.load(f)

def simplify_ring(ring, step):
    """Keep every Nth vertex, always keeping first and last (to close the ring)."""
    if len(ring) <= 4:
        return ring
    kept = ring[::step]
    if kept[-1] != ring[-1]:
        kept.append(ring[-1])
    return kept

new_feats = []
total_before = total_after = 0

for feat in fc["features"]:
    zone = feat["properties"].get("zone_id")
    geom = feat.get("geometry", {})
    gtype = geom.get("type")
    coords = geom.get("coordinates", [])

    if gtype == "Polygon":
        outer = [coords[0]] if coords else []
    elif gtype == "MultiPolygon":
        outer = [poly[0] for poly in coords if poly]
    else:
        continue

    kept_rings = []
    for ring in outer:
        lons_r = [c[0] for c in ring]
        lats_r = [c[1] for c in ring]
        # Skip tiny fragments
        if (max(lons_r) - min(lons_r)) < MIN_SPAN and (max(lats_r) - min(lats_r)) < MIN_SPAN:
            continue
        total_before += len(ring)
        s = simplify_ring(ring, STEP)
        total_after += len(s)
        kept_rings.append(s)

    if not kept_rings:
        continue

    if len(kept_rings) == 1:
        new_geom = {"type": "Polygon", "coordinates": [kept_rings[0]]}
    else:
        # MultiPolygon: each sub-polygon has one outer ring → [[ring1], [ring2], ...]
        new_geom = {"type": "MultiPolygon",
                    "coordinates": [[r] for r in kept_rings]}

    new_feats.append({
        "type": "Feature",
        "geometry": new_geom,
        "properties": feat["properties"],
    })

out_fc = {"type": "FeatureCollection", "features": new_feats}
with open(OUT, "w") as f:
    json.dump(out_fc, f, separators=(",", ":"))

size_kb = OUT.stat().st_size // 1024
print(f"Zones: {len(new_feats)}  Vertices: {total_before} -> {total_after}  Size: {size_kb} KB -> {OUT}")
