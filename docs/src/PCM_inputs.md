# PCM Inputs Explanation

The input files for the **HOPE** model could be one big .XLSX file or multiple .csv files. If you use the XLSX file, each spreadsheet in the file needs to be prepared based on the input instructions below and the spreadsheet names should be carefully checked. If you use the csv files, each csv file will represent one spreadsheet from the XLSX file. If both XLSX file and csv files are provided, the XLSX files will be used. 
      
## network_model setting

In `HOPE_model_settings.yml`, set:
- `network_model: 0` for no network constraints (copper plate).
- `network_model: 1` for zonal transport.
- `network_model: 2` for nodal DCOPF (angle-based).
- `network_model: 3` for nodal DCOPF (PTDF-based).

When using nodal modes (`2`/`3`), provide nodal mapping via `busdata` and `branchdata` (or ensure `linedata` includes equivalent bus columns).

Related run-control settings:
- `unit_commitment: 1` makes PCM a MILP.
- `write_shadow_prices: 1` triggers MILP -> fixed-LP re-solve for dual/LMP recovery when `unit_commitment: 1`.
- `summary_table: 1` writes summary analytics to `output/Analysis/Summary_*.csv`.
- `transmission_loss: 1` enables a piecewise-linear transmission loss approximation based on absolute line flow. This is currently supported for `network_model = 1` and `2`, but not `3`.

Simple workflow for line losses:
1. Keep `transmission_loss: 0` if you want the default lossless PCM run.
2. Set `transmission_loss: 1` only when your active line table includes a `Loss (%)` column.
3. Use `network_model = 1` or `2` with transmission losses.
4. Keep `network_model = 3` with `transmission_loss: 0`; PTDF mode remains lossless in the current HOPE release.
5. In nodal angle-based PCM (`network_model = 2`), HOPE now reports a nonzero `Loss` price component when transmission losses are active.

## internal network helper utilities

These functions are implemented in `src/network_utils.jl` and used by `src/PCM.jl`:

- `first_existing_col`: finds the first available column name among aliases (for robust input parsing).
- `resolve_reference_index`: resolves reference bus/zone from either integer index or ID value.
- `compute_ptdf_from_incidence`: computes PTDF matrix from branch incidence and reactance.
- `compute_zone_ptdf_from_linedata`: convenience wrapper to build zonal PTDF from `linedata` (reserved for a future zonal-PTDF mode; not used in current PCM flow).

They are automatically called in PCM network preprocessing; users do not need to call them directly.

## zonedata

This is the input dataset for zone-relevant information (e.g., demand, mapping with state, etc.).

---
|**Column Name** | **Description**|
| :------------ | :-----------|
|Zone_id | Name of each zone (should be unique)|
|Demand (MW) | Peak demand of the zone in MW|
|State | The state that the zone is belonging to|
|Area | The area that the zone is belonging to|
---

## gendata

This is the input dataset for existing generators. 

---
|**Column Name** | **Description**|
| :------------ | :-----------|
|Pmax (MW) |Maximum generation (nameplate) capacity of the generator in MW|
|Pmin (MW) |Minimum generation (nameplate) capacity of the generator in MW|
|Zone |The zone that the generator is belonging to| 
|Type |The technology type of the generator|
|Flag_thermal | 1 if the generator belongs to thermal units, and 0 otherwise|
|Flag_VRE | 1 if the generator belongs to variable renewable energy units, and 0 otherwise|
|Flag_mustrun | 1 if the generator must run at its nameplate capacity, and 0 otherwise|
|Flag_UC | 1 if the generator is eligible for unit commitment constraints, and 0 otherwise|
|Cost (\$/MWh) |Operating cost of the generator in \$/MWh|
|Start_up_cost (\$/MW)|Start up cost for UC generator in \$/MW|
|EF |The CO2 emission factor for the generator in tons/MWh|
|CC |The capacity credit for the generator (it is the fraction of the installed/nameplate capacity of a generator that can be relied upon at a given time)|
|FOR|Forced outrage rate, unitless|
|RM_SPIN|Spinning reserve margin, unitless|
|RU|Ramp up rate, unitless|
|RD|Ramp down rate, unitless|
|Min_down_time|Minimum down time for turning off a generator, hour|
|Min_up_time|Minimum up time for turning on a generator, hour|
---

## linedata

This is the input dataset for existing transmission lines (e.g., transmission capacity limit for each inter-zonal transmission line).

---
|**Column Name** | **Description**|
| :------------ | :-----------|
|From_zone | Starting zone of the inter-zonal transmission line|
|To_zone | Ending zone of the inter-zonal transmission line|
|X or Reactance | Line reactance (recommended for nodal modes). If omitted, current code falls back to unit values (`B_l = 1` / `X = 1`) with a warning.|
|Capacity (MW) | Transmission capacity limit for the transmission line|
|Loss (%) *(optional)* | Line loss rate used only when `transmission_loss = 1`. Values can be given as percent (`2`) or fraction (`0.02`). Missing values default to `0`. Shipped example files may keep this column at `0` so the default case behavior stays lossless.|
---

## busdata (optional for zonal modes, recommended for nodal modes)

This dataset defines nodal buses and bus-to-zone mapping.

Required columns for nodal modes:
- `Bus_id`
- `Zone_id`

Optional columns:
- `Load_share` (or bus demand-like columns) to distribute zonal load/DR/load-shed to buses.

CSV name: `busdata.csv`  
XLSX sheet name: `busdata`

## branchdata (optional; used preferentially in nodal modes)

This dataset defines nodal transmission branches.

Recommended columns:
- `from_bus`/`to_bus` (or MATPOWER-style `F_BUS`/`T_BUS`)
- `Capacity (MW)` (line thermal limit)
- `X` or `Reactance` (for DC angle/PTDF physics)
- `Loss (%)` *(optional; supported when `network_model = 2` and `transmission_loss = 1`)*
- `delta_theta_max` *(optional)*: per-line max angle difference (radians). If omitted/<=0, disabled.

If `branchdata` is provided and `network_model` is nodal, HOPE uses it as network branch input.

PTDF note:
- `network_model = 3` uses a lossless PTDF-based DCOPF. Keep `transmission_loss: 0` in that mode.

CSV name: `branchdata.csv`  
XLSX sheet name: `branchdata`

## ptdf_matrix_nodal / ptdf_matrix (optional)

This optional dataset is used only when `network_model = 3` (nodal PTDF-based DCOPF).

If this file/sheet is provided, HOPE reads the PTDF matrix directly.  
If not provided, HOPE computes nodal PTDF from branch endpoints/reactance and `reference_bus`.

Required format:
- One row per line, in the **same row order as the active branch table** (`branchdata` if provided in nodal mode, otherwise `linedata`).
- One column per bus, with column names exactly matching `busdata.Bus_id` (or inferred bus labels).
- Cell value = PTDF coefficient for that line and bus (reference bus convention).

Accepted names:
- CSV: `ptdf_matrix_nodal.csv` (preferred) or `ptdf_matrix.csv`
- XLSX sheet: `ptdf_matrix_nodal` (preferred) or `ptdf_matrix`

## storagedata

This is the input dataset for existing energy storage units (e.g., battery storage and pumped storage hydropower). 

---
|**Column Name** | **Description**|
| :------------ | :-----------|
|Zone |The zone that the generator is belonging to|
|Type |The technology type of the generator|
|Capacity (MWh) |Maximun energy capacity of the storage in MWh|
|Max Power (MW) |Maximum energy rate (power capacity) of the storage in MW|
|Charging efficiency |Ratio of how much energy is transferred from the charger to the storage unit|
|Discharging efficiency |Ratio of how much energy is transferred from the storage unit to the charger|
|Cost (\$/MWh) |Operating cost of the generator in \$/MWh|
|EF |The CO2 emission factor for the generator in tons/MWh|
|CC |The capacity credit for the generator (it is the fraction of the installed/nameplate capacity of a generator that can be relied upon at a given time)|
|Charging Rate |The maximum rates of charging, unitless|
|Discharging Rate |The maximum rates of discharging, unitless|
---

## solar_timeseries_regional

This is the input dataset for the annual hourly solar PV generation profile in each zone. Each zone has 8760 data points and the values are per unit.

---
|**Column Name** | **Description**|
| :------------ | :-----------|
|Month | Months of the year, ranging from 1 to 12|
|Day | Days of the month, ranging from 1 to 31|
|Period | Hours of the day, ranging from 1 to 24|
|Zone 1 | Solar power generation data in zone 1 on a specific period, day, and month|
|Zone 2 | Solar power generation data in zone 2 on a specific period, day, and month|
|... |...|
---

## wind_timeseries_regional

This is the input dataset for the annual hourly wind generation profile in each zone. Each zone has 8760 data points and the values are per unit.

---
|**Column Name** | **Description**|
| :------------ | :-----------|
|Month | Months of the year, ranging from 1 to 12|
|Day | Days of the month, ranging from 1 to 31|
|Period | Hours of the day, ranging from 1 to 24|
|Zone 1 | Wind power generation data in zone 1 on a specific period, day, and month|
|Zone 2 | Wind power generation data in zone 2 on a specific period, day, and month|
|... |...|
---

## load_timeseries_regional

This is the input dataset for the annual hourly load profile in each zone. Each zone has 8760 data points and the values are per unit.

---
|**Column Name** | **Description**|
| :------------ | :-----------|
|Month | Months of the year, ranging from 1 to 12|
|Day | Days of the month, ranging from 1 to 31|
|Period | Hours of the day, ranging from 1 to 24|
|Zone 1 | Load data in zone 1 on a specific period, day, and month|
|Zone 2 | Load data in zone 2 on a specific period, day, and month|
|... |...|
|NI | Net load import on a specific period, day, and month|
---

## flexddata (required when `flexible_demand = 1`)

This dataset defines DR resources for PCM backlog load shifting (`dr_DF`, `dr_PB`, `b_DR` over resource set `R`).

---
|**Column Name** | **Description**|
| :------------ | :-----------|
|Zone | Zone name (must match `zonedata.Zone_id`)|
|Type | DR technology type label|
|Max Power (MW) | Maximum DR power in the zone|
|Cost (\$/MW) | DR operating cost coefficient|
|Shift_Efficiency *(optional)* | Payback efficiency factor in backlog update; default = 1.0|
|Max_Defer_Hours *(optional)* | Backlog cap multiplier in hours; default = 24.0|
---

## dr_timeseries_regional (required when `flexible_demand = 1`)

This is the annual hourly DR availability profile in each zone (per unit).

---
|**Column Name** | **Description**|
| :------------ | :-----------|
|Month | Months of the year, ranging from 1 to 12|
|Day | Days of the month, ranging from 1 to 31|
|Period | Hours of the day, ranging from 1 to 24|
|Zone 1 | DR availability in zone 1 on a specific period, day, and month|
|Zone 2 | DR availability in zone 2 on a specific period, day, and month|
|... |...|
---

## carbonpolicies

This is the input dataset for carbon policies.

---
|**Column Name** | **Description**|
| :------------ | :-----------|
|State | Name of the state|
|Time Period | Time periods for carbon allowance (can be yearly or quarterly, set by users)|
|Allowance (tons) | Carbon emission allowance for each state in tons|
---

## rpspolicies

This is the input dataset for renewable portfolio standard (RPS) policies. It defines renewable credits trading relationship between different states (i.e., the states must be neighboring states) and the renewable credit requirement for each state.
---
|**Column Name** | **Description**|
| :------------ | :-----------|
|From_state | State that trading the renewable credits from |
|To_state | State that trading the renewable credits to |
|RPS | RPS requirement (renewable generation percentage) for the state in "From_state" column, range from 0-1, unitless|
---

## single parameters

This is the input dataset for some parameters that can be directly defined based on users' need. If not changed, they remain with default values. 

Implementation note: PCM reads these fields through an internal helper (`get_singlepar`) that returns the file value when present, otherwise a built-in default. This keeps backward compatibility when older cases do not include newly added single-parameter columns.

---
|**Column Name** | **Description**|
| :------------ | :-----------|
|VOLL | Value of lost load, default = 100000 |
|planning_reserve_margin | percentage of total capacity that is used for reserve, default = 0.02|
|BigM | For penalty purpose, unitless|
|PT_RPS | Penalty of the state not satisfying RPS requirement, default = 10000000000000|
|PT_emis | Penalty of the state not satisfying CO2 emission requirement, default = 10000000000000|
|reg_up_requirement | Hourly REG-UP requirement as fraction of system load, default = 0|
|reg_dn_requirement | Hourly REG-DN requirement as fraction of system load, default = 0|
|spin_requirement | Hourly SPIN requirement as fraction of system load, default = 0.03|
|nspin_requirement | Hourly NSPIN requirement as fraction of system load, default = 0|
|delta_reg | REG reserve sustained-duration factor in energy constraints (hours), default = 1/12|
|delta_spin | SPIN reserve sustained-duration factor in energy constraints (hours), default = 1/6|
|delta_nspin | NSPIN reserve sustained-duration factor in energy constraints (hours), default = 1/2|
|theta_max | Bus angle bound in angle-based nodal DCOPF (numerical guard), default = 1000|
|delta_theta_max | Optional default line angle-difference limit (radians). If `<=0`, disabled. Can be overridden per line by `branchdata/linedata.delta_theta_max`|
|Inv_bugt_gen | Budget for newly installed generators, default = 10000000000000000|
|Inv_bugt_line | Budget for newly installed transmission lines, default = 10000000000000000|
|Inv_bugt_storage | Budget for newly installed storages, default = 10000000000000000|
---

Notes:
- `planning_reserve_margin` and `Inv_bugt_*` are currently not used by `create_PCM_model` (they are relevant to GTEP workflows).
