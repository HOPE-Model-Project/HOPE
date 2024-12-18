# PCM Inputs Explanation

The input files for the **HOPE** model could be one big .XLSX file or multiple .csv files. If you use the XLSX file, each spreadsheet in the file needs to be prepared based on the input instructions below and the spreadsheet names should be carefully checked. If you use the csv files, each csv file will represent one spreadsheet from the XLSX file. If both XLSX file and csv files are provided, the XLSX files will be used. 
      

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
|Cost ($/MWh) |Operating cost of the generator in $/MWh|
|Start_up_cost ($/MW)|Start up cost for UC generator in $/MW|
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
|From_zone | Ending zone of the inter-zonal transmission line|
|Capacity (MW) | Transmission capacity limit for the transmission line|
---

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
|Cost ($/MWh) |Operating cost of the generator in $/MWh|
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
|planning_reserve_margin | percentage of total capacity that is used for reserve, default = 0.02|
|Big M | For penalty purpose, unitless|
|PT_RPS | Penalty of the state not satisfying RPS requirement, default = 10000000000000|
|PT_emis | Penalty of the state not satisfying CO2 emission requirement, default = 10000000000000|
|Inv_bugt_gen | Budget for newly installed generators, default = 10000000000000000|
|Inv_bugt_line | Budget for newly installed transmission lines, default = 10000000000000000|
|Inv_bugt_storage | Budget for newly installed storages, default = 10000000000000000|
---
