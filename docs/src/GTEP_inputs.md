
```@meta
CurrentModule = HOPE
```

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
|Area | The area that the zone is belonging to|
|Flag_MD | 1 if the zone belongs to a desired state (e.g., Maryland), and 0 otherwise|
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
|Cost ($/MWh) |Operating cost of the generator in $/MWh|
|EF |The CO2 emission factor for the generator in tons/MWh|
|CC |The capacity credit for the generator (it is the fraction of the installed/nameplate capacity of a generator that can be relied upon at a given time)|
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
|Cost (M$) |Investment cost for the generator in million dollars (M$)|
|Cost ($/MWh) |Operating cost of the generator in $/MWh|
|EF |The CO2 emission factor for the generator in tons/MWh|
|CC |The capacity credit for the generator (it is the fraction of the installed/nameplate capacity of a generator that can be relied upon at a given time)|
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

## linedata_candidate

This is the input dataset for candidate transmission lines (a set of all inter-zonal lines that can be selected for installation).

---
|**Column Name** | **Description**|
| :------------ | :-----------|
|From_zone | Starting zone of the inter-zonal transmission line|
|From_zone | Ending zone of the inter-zonal transmission line|
|Capacity (MW) | Transmission capacity limit for the transmission line|
|Cost (M$) |Investment cost for the generator in million dollars (M$)|
|X |Reactance of the line in P.U. (optional)|
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

## storagedata_candidate

This is the input dataset for candidate energy storage units (a set of all storage units that can be selected for installation). 

---
|**Column Name** | **Description**|
| :------------ | :-----------|
|Zone |The zone that the storage is belonging to|
|Type |The technology type of the generator|
|Capacity (MWh) |Maximun energy capacity of the storage in MWh|
|Max Power (MW) |Maximum energy rate (power capacity) of the storage in MW|
|Charging efficiency |Ratio of how much energy is transferred from the charger to the storage unit|
|Discharging efficiency |Ratio of how much energy is transferred from the storage unit to the charger|
|Cost (M$) |Investment cost for the new storage in million dollars (M$)|
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
|From_state | The state that |
|To_state | The state that |
|RPS | State RPS requirement for state in column "From_state"|
---





