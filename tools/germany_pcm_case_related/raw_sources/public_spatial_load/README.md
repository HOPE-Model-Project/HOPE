# Public Spatial Load Inputs For Germany

Use this folder for the fallback public-data Germany nodal load allocation workflow.

The HOPE workflow keeps the real 2025 hourly TSO-area load from SMARD for time variation,
and uses public spatial proxies only for the static nodal split inside each TSO zone.

## Preferred files

### 1. Population grid

Recommended filename:
- `population_grid_1km.csv`

Minimum columns:
- `Longitude` or `lon` or `x`
- `Latitude` or `lat` or `y`
- `Population` or `population` or `weight`

Recommended source:
- Germany Census 2022 gridded data via the `z22` workflow or a direct official CSV/ZIP download converted with `convert_population_grid_to_hope.py`

### 2. Settlement points

Recommended filename:
- `settlement_centers.csv`

Minimum columns:
- `Longitude` or `lon` or `x`
- `Latitude` or `lat` or `y`
- `SettlementWeight` or `weight`

Recommended public source:
- OSM place / settlement / built-up proxies

### 3. Industrial sites

Recommended filename:
- `industrial_sites.csv`

Minimum columns:
- `Longitude` or `lon` or `x`
- `Latitude` or `lat` or `y`
- `IndustrialWeight` or `weight`

Recommended public source:
- OSM industrial locations / industrial land-use centroids / large industrial sites

## Current weighting rule

If all three layers are present, HOPE combines them as:
- population: `70%`
- settlement: `15%`
- industry: `15%`

If some layers are missing, the available layers are renormalized automatically.

## Mapping rule

`public point -> inferred TSO zone -> nearest HOPE bus inside that zone`

This produces:
- `references/germany_spatial_load_shares.csv`


## Helper files in this folder

- `export_population_grid_z22.R`: exports a Germany 1 km population grid CSV from the public `z22` package
- `OVERPASS_EXAMPLES.md`: notes for building optional settlement and industry point layers from OSM
- CSV templates for the three layer types
