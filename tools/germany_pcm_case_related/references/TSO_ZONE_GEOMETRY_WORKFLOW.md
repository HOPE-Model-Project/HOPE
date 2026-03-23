# Germany TSO Zone Geometry Workflow

This note documents how the Germany dashboard zone overlay is built.

## Goal

Create a dashboard-friendly polygon layer for the four Germany research zones:
- `50Hertz`
- `Amprion`
- `TenneT`
- `TransnetBW`

The overlay should:
- look geographically realistic
- remain consistent with the frozen Germany PCM bus-zone assignment
- be reproducible from tracked source files

## Inputs

Reference geography:
- `tools/germany_pcm_case_related/raw_sources/reference_geo/germany_states_simplify200.geojson`

Case geography:
- `ModelCases/GERMANY_PCM_nodal_jan_2day_rescaled_case/Data_GERMANY_PCM_nodal/busdata.csv`

Builder:
- `tools/germany_pcm_case_related/build_germany_tso_geojson.py`

Output:
- `tools/hope_dashboard/data/germany_tso_zones.geojson`

## Build logic

1. Start from the Germany state boundary GeoJSON.
2. Assign clearly covered states directly to a single TSO region.
3. For mixed states, split the state internally using the frozen bus-zone geography as the seam guide.
4. Drop very small polygon fragments so the dashboard remains readable.
5. Write a single file-backed GeoJSON for the dashboard.

## Interpretation

This is a reconstructed research layer.

It is:
- more realistic than bubble polygons
- based on real outer geography
- aligned with the Germany HOPE case assumptions

It is not:
- an official public TSO shapefile
- a legal or operational control-area definition

## Rebuild command

From repo root:

```powershell
python tools/germany_pcm_case_related/build_germany_tso_geojson.py
```
