# Dashboard Geometry Data

This folder holds small file-backed geometry layers used by the dashboard map overlay.

Current files:
- `isone_load_zones.geojson`
- `germany_tso_zones.geojson`

Notes:
- `germany_tso_zones.geojson` is a generated research overlay for dashboard use.
- The raw Germany state boundary source used to rebuild it is stored in:
  - `tools/germany_pcm_case_related/raw_sources/reference_geo/germany_states_simplify200.geojson`
- Rebuild command:

```powershell
python tools/germany_pcm_case_related/build_germany_tso_geojson.py
```
