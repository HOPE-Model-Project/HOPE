# Draft: `load_timeseries_nodal` for HOPE PCM

This note defines a proposed HOPE PCM extension for direct hourly nodal load input.

Status:
- Draft updated to match the intended HOPE PCM behavior
- Nodal PCM should require this input

## Goal

Add a required nodal load input so PCM nodal runs use:

- `bus peak load`
- `hourly nodal rescaled factors`

instead of only:

- `zonal hourly load profile`
- `static bus load shares`

The intended behavior should stay consistent with the current zonal load logic:

- zonal mode: `ZonePeakLoad * zonal_profile`
- nodal mode with direct nodal input: `BusPeakLoad * nodal_profile`

## Proposed input name

Accepted names:

- CSV: `load_timeseries_nodal.csv`
- XLSX sheet: `load_timeseries_nodal`

Required in:

- `network_model = 2`
- `network_model = 3`

If supplied in zonal modes, HOPE should ignore it with an informational message.

## Proposed file format

Required time columns:

- `Time Period`
- `Hours`

Accepted legacy aliases for time columns:

- `Period` -> `Hours`
- `Hour` -> `Hours`

Optional time columns:

- `Month`
- `Day`

Required load columns:

- one column per bus
- column names must match `busdata.Bus_id` exactly

Example:

| Time Period | Hours | Month | Day | Bus 1 | Bus 2 | Bus 3 |
| :-- | :-- | :-- | :-- | :-- | :-- | :-- |
| 1 | 1 | 7 | 1 | 0.82 | 0.79 | 0.91 |
| 1 | 2 | 7 | 1 | 0.80 | 0.77 | 0.88 |

Interpretation:

- each bus column is a unitless hourly multiplier
- nodal load is built as:

`Load_nodal(n,h) = PK_bus(n) * profile_nodal(n,h)`

This mirrors the current zonal logic:

`Load_zonal(i,h) = PK_zone(i) * profile_zone(i,h)`

## Proposed bus peak load source

Use `busdata` as the primary source of peak nodal load.

Preferred columns in `busdata`:

- `Demand (MW)`
- `Load (MW)`
- `Pd`
- `PD`

Optional fallback:

- `Load_share`

If only shares are provided, convert them to bus peak MW by zone:

`PK_bus_raw(n) = Load_share(n)`

`PK_bus(n) = PK_zone(i) * PK_bus_raw(n) / sum(PK_bus_raw(k) for k in N_i)`

where bus `n` belongs to zone `i`.

If neither peak MW nor share is provided:

- split zonal peak load equally across buses in the zone

This keeps the current HOPE convention:

- bus-level loads rescale from zonal peak totals
- `sum(PK_bus(n) for n in N_i) = PK_zone(i)`

## Proposed precedence logic

For PCM nodal runs:

1. `load_timeseries_nodal` is required
2. HOPE should stop with an input error if it is missing

For PCM zonal runs:

- ignore `load_timeseries_nodal`

## Proposed alignment rules

If `load_timeseries_nodal` is provided:

- normalize its `Time Period` and `Hours` columns using the existing helper
- require row-by-row alignment with:
  - `load_timeseries_regional`
  - `wind_timeseries_regional`
  - `solar_timeseries_regional`
  - `dr_timeseries_regional`
  - `gen_availability_timeseries`

Reason:

- PCM already treats `load_timeseries_regional` as the chronology anchor
- keeping aligned time maps avoids a larger refactor

## Proposed internal formulas

### New parameters

Add:

- `PK_bus[n]`
- `P_n_t[h,n]`

with:

- `PK_bus[n]`: rescaled nodal peak load in MW
- `P_n_t[h,n]`: nodal hourly multiplier from `load_timeseries_nodal`

### Native nodal load

If nodal file exists:

`NodeNativeLoad[n,h] = PK_bus[n] * P_n_t[h,n]`

### DR and load shedding

Keep DR and zonal load shedding zonal for now, but distribute them to buses using zone-normalized bus peak-load shares:

`NodeAdjLoad[n,h] = NodeNativeLoad[n,h] + bus_zone_weight[n] * (DR_OPT[zone(n),h] - p_LS[zone(n),h])`

Then:

`NodeLoad[n,h] = NodeAdjLoad[n,h]`

This is the smallest change and keeps current zonal DR and zonal load-shedding variables intact.

### NI

Keep current zonal NI allocation for now:

`NodeNI[n,h] = bus_zone_weight[n] * NI_h[h, zone(n)]`

## Proposed constraints that need updates

### Nodal power balance

Current nodal balance uses `NodeLoad` derived from zonal profile times bus share.

Replace the current `NodeLoad` expression in nodal modes with the new `NodeNativeLoad` / `NodeAdjLoad` logic.

Affected locations in the current code:

- `src/PCM.jl`
- the `network_model == 2` branch
- the `network_model == 3` branch

### Load shedding bound

Current zonal load shedding bound:

`p_LS[i,h] <= sum(P_t[h,d] * PK[d] for d in D_i[i])`

When nodal load input exists, update to:

`p_LS[i,h] <= sum(NodeNativeLoad[n,h] for n in N_i[i])`

This keeps zonal load shedding feasible relative to the actual nodal native load of the zone.

### System load expression

Current:

`Load_system[h] = sum(sum(P_t[h,d] * PK[d] for d in D_i[i]) for i in I)`

With direct nodal load:

`Load_system[h] = sum(NodeNativeLoad[n,h] for n in N_bus)`

### State policy load

For nodal runs with bus-state accounting:

`StatePolicyLoad[w,h] = sum(NodeNativeLoad[n,h] for n in N_w[w])`

This is cleaner than reconstructing state load from zonal profiles.

## Proposed loader changes

### `src/read_input_data.jl`

In the PCM branch:

- add optional read for:
  - `load_timeseries_nodal` sheet in XLSX
  - `load_timeseries_nodal.csv` in CSV mode
- normalize time columns with:
  - `normalize_timeseries_time_columns!(...; context="load_timeseries_nodal")`
- validate time alignment against `Loaddata` with:
  - `validate_aligned_time_columns!(input_data["Loaddata"], input_data["NodalLoaddata"], "load_timeseries_nodal")`

Suggested dictionary key:

- `input_data["NodalLoaddata"]`

### `src/PCM.jl`

Add:

- `NodalLoaddata = haskey(input_data, "NodalLoaddata") ? input_data["NodalLoaddata"] : nothing`

In nodal modes:

1. build `PK_bus`
2. if `NodalLoaddata !== nothing`, reorder bus columns to bus order
3. build `NodeNativeLoad`
4. replace current `NodeLoad` expression with nodal-aware branch
5. update `LS_con`
6. update `Load_system`
7. update nodal `StatePolicyLoad`

## Proposed data validation

If `load_timeseries_nodal` is present for a nodal run:

- require `busdata`
- require every `busdata.Bus_id` to exist as a column
- reject extra unknown bus columns unless they are known time metadata columns

Recommended error messages:

- missing `busdata` for nodal load input
- missing bus columns
- duplicate bus columns
- time misalignment with the main chronology

## Proposed user-facing documentation

After implementation, update:

- `docs/src/PCM_inputs.md`

Add a new section:

- `load_timeseries_nodal (required for nodal PCM)`

State clearly:

- values are per-unit hourly multipliers
- HOPE computes hourly bus load as `PK_bus * multiplier`
- if the file is missing in nodal PCM, HOPE stops with an input error

## Recommended implementation order

1. loader support in `read_input_data.jl`
2. `PK_bus` build and nodal load expressions in `PCM.jl`
3. update `LS_con`, `Load_system`, and `StatePolicyLoad`
4. docs
5. one ISO-NE test case using public nodal load data
