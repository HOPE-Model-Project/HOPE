# eGon / eTraGo Spatial Demand Inputs

Use this folder for the Germany nodal load-allocation upgrade.

The HOPE workflow keeps the real 2025 hourly TSO-area load from SMARD for time variation,
and uses eGon/eTraGo-style spatial demand shares only for the static nodal split inside each TSO zone.

## Preferred raw extracts

1. `egon_etrago_bus.csv`
   - expected source table: `grid.egon_etrago_bus`
   - minimum columns:
     - `bus_id`
     - `x` or `lon` or `longitude`
     - `y` or `lat` or `latitude`

2. At least one of:
   - `egon_etrago_electricity_households.csv`
   - `egon_etrago_electricity_cts.csv`
   - `egon_etrago_electricity_industry.csv`

Current local drop:
- `egon_etrago_bus.csv`
- `egon_etrago_electricity_cts.csv`
- `egon_etrago_electricity_households.csv`

Working assumption for the colleague ZIP rename:
- `edut_00_027.csv` -> `egon_etrago_electricity_cts.csv`
- `edut_00_029.csv` -> `egon_etrago_electricity_households.csv`

## Accepted sector-table columns

Each sector table must contain:
- `bus_id`
- and either:
  - `annual_mwh` / `demand_mwh` style annual-energy column, or
  - `p_set` as an hourly array-like column

Optional:
- `scn_name`

## Current HOPE mapping method

`eGon bus -> inferred TSO zone -> nearest HOPE bus inside that zone`

This produces the frozen reference table:
- `references/germany_spatial_load_shares.csv`

Then `build_germany_pcm_case.py` uses that file to allocate zonal SMARD hourly load to HOPE buses.
