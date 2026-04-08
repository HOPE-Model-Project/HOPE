# GTEP Inputs Explanation

The input files for the **HOPE** model could be one big .XLSX file or multiple .csv files. If you use the XLSX file, each spreadsheet in the file needs to be prepared based on the input instructions below and the spreadsheet names should be carefully checked. If you use the csv files, each csv file will represent one spreadsheet from the XLSX file. If both XLSX file and csv files are provided, the XLSX files will be used.

## zonedata

This is the input dataset for zone-relevant information (e.g., demand, mapping with state, etc.).

---
|**Column Name** | **Description**|
| :------------ | :-----------|
|Zone_id | Name of each zone (should be unique)|
|Demand (MW) | Peak demand of the zone in MW|
|State | The state that the zone is belonging to|
|Zonal PRM *(optional)* | Zonal planning reserve margin. If omitted, system `planning_reserve_margin` is used for all zones.|
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
|Flag_RET | 1 if the generator is eligible for retirement, and 0 otherwise|
|Flag_thermal | 1 if the generator belongs to thermal units, and 0 otherwise|
|Flag_VRE | 1 if the generator belongs to variable renewable energy units, and 0 otherwise|
|Flag_mustrun | 1 if the generator must run at its nameplate capacity, and 0 otherwise|
|Cost (\$/MWh) |Operating cost of the generator in \$/MWh|
|EF |The CO2 emission factor for the generator in tons/MWh|
|CC |The capacity credit for the generator |
|AF *(optional)* |Fallback availability factor for non-VRE generators. If omitted, default = 1. This value is used to construct hourly availability \(AF_{g,h}\) for non-VRE units.|
---

## gendata_candidate

This is the input dataset for candidate generators (a set of all generators that can be selected for installation).

---
|**Column Name** | **Description**|
| :------------ | :-----------|
|Pmax (MW) |Maximum generation (nameplate) capacity of the generator in MW|
|Pmin (MW) |Minimum generation (nameplate) capacity of the generator in MW|
|Zone |The zone that the generator is belonging to|
|Type |The technology type of the generator|
|Cost (\$/MW/yr) |Annualized investment cost for the generator in \$/MW/yr|
|Cost (\$/MWh) |Operating cost of the generator in \$/MWh|
|Flag_thermal | 1 if the generator belongs to thermal units, and 0 otherwise|
|Flag_VRE | 1 if the generator belongs to variable renewable energy units, and 0 otherwise|
|Flag_mustrun | 1 if the generator must run at its nameplate capacity, and 0 otherwise|
|EF |The CO2 emission factor for the generator in tons/MWh|
|CC |The capacity credit for the generator|
|AF *(optional)* |Fallback availability factor for non-VRE generators. If omitted, default = 1. This value is used to construct hourly availability \(AF_{g,h}\) for non-VRE units.|
---

## linedata

This is the input dataset for existing transmission lines (e.g., transmission capacity limit for each inter-zonal transmission line).

---
|**Column Name** | **Description**|
| :------------ | :-----------|
|From_zone | Starting zone of the inter-zonal transmission line|
|To_zone | Ending zone of the inter-zonal transmission line|
|Capacity (MW) | Transmission capacity limit for the transmission line|
|Loss (%) *(optional)* | Line loss rate used only when `transmission_loss = 1`. Values can be given as percent (`2`) or fraction (`0.02`). Missing values default to `0`.|
---

## linedata_candidate

This is the input dataset for candidate transmission lines (a set of all inter-zonal lines that can be selected for installation).

---
|**Column Name** | **Description**|
| :------------ | :-----------|
|From_zone | Starting zone of the inter-zonal transmission line|
|To_zone | Ending zone of the inter-zonal transmission line|
|Capacity (MW) | Transmission capacity limit for the transmission line|
|Cost (M\$) |Investment cost for the generator in million dollars (M\$)|
|X |Reactance of the line in P.U. (optional)|
|Loss (%) *(optional)* | Candidate line loss rate used only when `transmission_loss = 1`. Values can be given as percent (`2`) or fraction (`0.02`). Missing values default to `0`.|
---

## transmission loss workflow

To run GTEP with line losses:
1. set `transmission_loss: 1` in `HOPE_model_settings.yml`,
2. provide `Loss (%)` in `linedata` and/or `linedata_candidate`,
3. use `0` in those columns if you want to keep the example dataset structure visible while preserving the default lossless behavior.

## storagedata

This is the input dataset for existing energy storage units (e.g., battery storage and pumped storage hydropower).

---
|**Column Name** | **Description**|
| :------------ | :-----------|
|Zone |The zone that the storage is belonging to|
|Type |The technology type of the storage|
|Capacity (MWh) |Maximun energy capacity of the storage in MWh|
|Max Power (MW) |Maximum energy rate (power capacity) of the storage in MW|
|Charging efficiency |Ratio of how much energy is transferred from the charger to the storage unit|
|Discharging efficiency |Ratio of how much energy is transferred from the storage unit to the charger|
|Cost (\$/MWh) |Operating cost of the storage in \$/MWh|
|EF |The CO2 emission factor for the storage in tons/MWh|
|CC |The capacity credit for the storage|
|Charging Rate |The maximum rates of charging, unitless|
|Discharging Rate |The maximum rates of discharging, unitless|
---

## storagedata_candidate

This is the input dataset for candidate energy storage units (a set of all storage units that can be selected for installation).

---
|**Column Name** | **Description**|
| :------------ | :-----------|
|Zone |The zone that the storage is belonging to|
|Type |The technology type of the storage|
|Capacity (MWh) |Maximun energy capacity of the storage in MWh|
|Max Power (MW) |Maximum energy rate (power capacity) of the storage in MW|
|Charging efficiency |Ratio of how much energy is transferred from the charger to the storage unit|
|Discharging efficiency |Ratio of how much energy is transferred from the storage unit to the charger|
|Cost (\$/MW/yr) |Annualized investment cost for the storage in \$/MW/yr|
|Cost (\$/MWh) |Operating cost of the storage in \$/MWh|
|EF |The CO2 emission factor for the storage in tons/MWh|
|CC |The capacity credit for the storage|
|Charging Rate |The maximum rates of charging, unitless|
|Discharging Rate |The maximum rates of discharging, unitless|
---

## gen_availability_timeseries

This is the input dataset for the annual hourly generator-level availability profile \(AF_{g,h}\). It contains 8760 rows in `gen_availability_timeseries.csv`.

---
|**Column Name** | **Description**|
| :------------ | :-----------|
|Month | Months of the year, ranging from 1 to 12|
|Day | Days of the month, ranging from 1 to 31|
|Period | Hours of the day, ranging from 1 to 24|
|G1 | Hourly availability factor of generator index 1 (optional if fallback is acceptable)|
|G2 | Hourly availability factor of generator index 2 (optional if fallback is acceptable)|
|... | Optional columns through `G(N)`, where `N = (# existing generators + # candidate generators)` and ordering is `[gendata; gendata_candidate]`|
---

Notes:
- Only `Month`, `Day`, and `Period` are strictly required.
- Missing generator columns will fallback to the generator static `AF` in `gendata/gendata_candidate` (default `1` if missing there).
- Recommended: provide hourly profiles for all VRE/RPS-relevant generators to avoid unintended static fallback.

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

## flexddata

This is the input dataset for demand response (DR) resources used in the backlog DR formulation.

---
|**Column Name** | **Description**|
| :------------ | :-----------|
|Zone | Zone name|
|Type | DR technology type (e.g., `Loadshifting`)|
|Max Power (MW) | Maximum DR power for the zone|
|Cost (\$/MW) | DR operating cost coefficient|
|CC | Capacity credit of DR resource (default = 1 if omitted)|
|Shift_Efficiency | Demand shifting efficiency, \(\eta_{DR}\) (default = `1.0`)|
|Max_Defer_Hours | Maximum defer window, \(\tau_{DR}\), in hours (default = `24.0`)|
---

## dr_timeseries_regional

This is the input dataset for the annual hourly DR availability profile in each zone. Each zone has 8760 data points and the values are per unit.

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

---
|**Column Name** | **Description**|
| :------------ | :-----------|
|VOLL | Value of lost load, default = 100000 |
|planning_reserve_margin | System planning reserve margin (PRM), default = 0.02|
|Big M | For penalty purpose, unitless|
|PT_RPS | Penalty of the state not satisfying RPS requirement, default = 10000000000000|
|PT_emis | Penalty of the state not satisfying CO2 emission requirement, default = 10000000000000|
|spin_requirement | Hourly SPIN requirement as fraction of system load (used when `operation_reserve_mode = 1`), default = 0.03|
|delta_spin | SPIN reserve sustained-duration factor in storage/headroom constraints (hours), default = 1/6|
|Inv_bugt_gen | Budget for newly installed generators, default = 10000000000000000|
|Inv_bugt_line | Budget for newly installed transmission lines, default = 10000000000000000|
|Inv_bugt_storage | Budget for newly installed storages, default = 10000000000000000|
---
