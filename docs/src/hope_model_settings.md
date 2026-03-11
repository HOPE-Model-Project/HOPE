
```@meta
CurrentModule = HOPE
```

# HOPE Model Settings Explanation

The `HOPE_model_settings.yml` file configures model switches and run controls.

---
|**Parameter Name** | **Example**| **Description**|
| :------------ | :-----------|:-----------|
|`DataCase:` | `Data_100RPS/`| Input data folder under the case directory.|
|`model_mode:`| `GTEP` | HOPE mode: `GTEP` or `PCM`.|
|`aggregated!:`| `1` | `1` aggregate technology resource input; `0` full technology input.|
|`representative_day!:`| `1` | `1` representative-day setup; `0` full chronology.|
|`time_periods:`| `1 : (3, 20, 6, 20)` | Seasonal windows used by representative-day/time matching workflows.|
|`flexible_demand:`| `1` | `1` enable DR formulation; `0` disable.|
|`inv_dcs_bin:`| `0` | `GTEP`: `1` binary investment decisions; `0` relaxed investments.|
|`unit_commitment:`| `1` | `PCM`: `0` no UC; `1` integer UC; `2` convexified UC.|
|`carbon_policy:`| `1` | `0` off; `1` emissions cap; `2` cap-and-trade style.|
|`clean_energy_policy:`| `1` | `0` off; `1` enforce RPS-style constraints.|
|`planning_reserve_mode:`| `1` | `GTEP`: `0` off; `1` system-level RA; `2` zonal RA.|
|`operation_reserve_mode:`| `2` | `GTEP`: `0` off, `1` SPIN only. `PCM`: `0` off, `1` REG+SPIN, `2` REG+SPIN+NSPIN.|
|`network_model:`| `3` | `PCM`: `0` no network, `1` zonal transport, `2` nodal DCOPF angle-based, `3` nodal DCOPF PTDF-based.|
|`reference_bus:`| `1` | `PCM` nodal modes: reference bus for angle and nodal price decomposition.|
|`storage_ld_duration_hours:`| `12` | `GTEP`: long-duration storage threshold (MWh/MW).|
|`write_shadow_prices:`| `0` | `1` enables MILP dual-recovery re-solve (fix discrete vars, re-solve LP). In PCM this applies when `unit_commitment=1`; in GTEP when `inv_dcs_bin=1`.|
|`summary_table:`| `0` | `PCM`: `1` generate `output/Analysis/Summary_*.csv`; `0` disable.|
|`solver:`| `gurobi` | Solver name (`cbc`, `clp`, `glpk`, `gurobi`, `cplex`, etc.).|
|`debug:` | `0` | `0` off; `1` conflict refiner; `2` penalty-based debug.|
---

Notes:
- Parameters like `VOLL`, `planning_reserve_margin`, reserve requirements, `theta_max`, and other numeric constants are read from `single_parameter` input (not from `HOPE_model_settings.yml`).
- For PCM, `representative_day!` is currently not the primary production workflow; nodal studies are typically run in full chronology.
- For PCM, summary tables are controlled by `summary_table=1` across network modes; nodal-specific summary tables are generated only when `network_model` is `2` or `3`.


