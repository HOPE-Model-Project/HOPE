
```@meta
CurrentModule = HOPE
```

# HOPE Model Settings Explanation

The `Hope_model_settings.yml` file configures system-level settings for running a HOPE case, including scenario settings (folder names), model mode settings, technology aggregation or not, using representative day or 8760 hourly time steps, integer or continuous for decision investment decisions, periods for setting representative days, planning reserve margin, value of loss of load, solver, debug flag, etc.   

There are two columns: 1) the first column contains the names of setting parameters; 2) the second column contains the setting values. The explanation for setting parameters is also provided in the `Hope_model_settings.yml` file.   
      
---
|**Parameter Name** | **Parameter Value (examples)**| **Description**|
| :------------ | :-----------|:-----------|
|`DataCase:` | `Data_100RPS/`| #String, the folder name of data, default Data/ GTEP example: `Data_100RPS/`; PCM example: `Data_PCM2035/`|
|`model_mode:`| `GTEP` | #String, HOPE model mode: `GTEP` or `PCM` or ...|
|`aggregated!:`| `1` | #Binary, `1` aggregate technology resource; `0` Does Not|
|`representative_day!:`| `1` |  #Binary, `1` use representative days (need to set time_periods); `0` Does Not|
|`inv_dcs_bin:`| `0` | #Binary, `1` use integer variable for investment decisions; `0` Does Not|
|`time_periods:`| `1 : (3, 20, 6, 20)` <br> `2 : (6, 21, 9, 21)` <br> `3 : (9, 22, 12, 20)` <br> `4 : (12, 21, 3, 19)` | # `1: spring, March 20th to June 20th`;  <br> #  `2: summer, June 21st to September 21st`;  <br> #  `3: fall, September 22nd to December 20th`;  <br> # `4: winter, December 21st to March 19th`. |
|`planning_reserve_margin:`| `0.02` |#Float, planning_reserve_margin|
|`value_of_loss_of_load:`| `100000` | #Float, value of loss of load d, $/MWh|
|`solver:`| `cbc` | #String, solver: `cbc`, `glpk`, `cplex`, `gurobi`, etc.|
|`debug:` | `0` | #Binary, flag for turning on the Method of Debug, `0` = not active; `1` = active conflict method (works for `gurobi` and `cplex`); `2` = active penalty method|
---


