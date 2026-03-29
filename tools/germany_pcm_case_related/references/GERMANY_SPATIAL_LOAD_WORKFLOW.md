# Germany Spatial Load Share Workflow

This workflow upgrades the Germany nodal load allocation from a pure network heuristic to a public-data spatial method.

## Goal

Keep:
- actual 2025 hourly TSO-area load from SMARD for time variation

Replace:
- the current nodal `LoadProxy` heuristic used for static bus shares

With:
- public spatial proxies mapped onto the HOPE Germany buses
  - population grid
  - settlement centers / settlement points
  - industrial locations

## Required ingredients

### 1. HOPE-side references

These are already produced by the Germany preprocessing chain:
- `references/germany_network_buses_clean.csv`
- `references/germany_bus_zone_map.csv`
- `references/germany_zone_hourly_load_reference.csv`

### 2. Public spatial inputs

Place under `raw_sources/public_spatial_load/`:
- `population_grid_1km.csv`
- optional `settlement_centers.csv`
- optional `industrial_sites.csv`

## Build sequence

1. Build / refresh the Germany network backbone and bus-zone map.
2. Prepare public spatial input CSVs.
3. Run:

```powershell
python tools/germany_pcm_case_related/build_germany_spatial_load_shares.py
```

4. This writes:
- `references/germany_spatial_load_shares.csv`

5. Then rerun:

```powershell
python tools/germany_pcm_case_related/build_germany_pcm_case.py
```

## Mapping method

The current public fallback implementation:
1. reads population, settlement, and industry point layers,
2. maps each point to the nearest HOPE Germany bus to infer its TSO zone,
3. remaps it to the nearest HOPE bus inside that inferred TSO zone,
4. normalizes each layer into zone-level bus shares,
5. combines the layers with configurable weights.

Default layer weights:
- population: `70%`
- settlement: `15%`
- industry: `15%`

If only some layers are available, HOPE renormalizes over the available layers automatically.

## Output interpretation

`germany_spatial_load_shares.csv` is a frozen reference table with:
- `Bus_id`
- `Zone_id`
- `Load_share`
- layer contributions for population / settlement / industry
- mapping diagnostics such as mean/max mapping distance

`build_germany_pcm_case.py` prefers this file automatically.
If the file is absent, it falls back to the original network heuristic.

## Current assumptions

- Public spatial proxies are used only for the nodal split, not for hourly shape.
- Hourly shape still comes from the real 2025 SMARD TSO-area loads.
- Settlement and industry layers are optional.
- Zone consistency is preserved because final nodal shares are always normalized within the frozen TSO zone map.
