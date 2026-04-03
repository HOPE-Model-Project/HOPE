
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
|`resource_aggregation:`| `1` | `1` aggregate resources before model build; `0` use the full input resource list.|
|`representative_day!:`| `1` | Legacy representative-day switch. `1` endogenous representative-day clustering; `0` full chronology. Prefer `endogenous_rep_day` and `external_rep_day` for new cases.|
|`endogenous_rep_day:`| `1` | `1` let HOPE cluster representative days from full chronology; `0` disable endogenous representative-day clustering.|
|`external_rep_day:`| `0` | `1` use user-provided representative periods and `rep_period_weights`; `0` disable external representative periods.|
|`time_periods:`| `1 : (3, 20, 6, 20)` | Legacy fallback for endogenous representative-day seasons. New advanced endogenous rep-day cases should define this in `HOPE_rep_day_settings.yml`.|
|`flexible_demand:`| `1` | `1` enable DR formulation; `0` disable.|
|`inv_dcs_bin:`| `0` | `GTEP`: `1` binary investment decisions; `0` relaxed investments.|
|`unit_commitment:`| `1` | `PCM`: `0` no UC; `1` integer UC; `2` convexified UC.|
|`carbon_policy:`| `1` | `0` off; `1` emissions cap; `2` cap-and-trade style.|
|`clean_energy_policy:`| `1` | `0` off; `1` enforce RPS-style constraints.|
|`planning_reserve_mode:`| `1` | `GTEP`: `0` off; `1` system-level RA; `2` zonal RA.|
|`operation_reserve_mode:`| `2` | `GTEP`: `0` off, `1` SPIN only. `PCM`: `0` off, `1` REG+SPIN, `2` REG+SPIN+NSPIN.|
|`network_model:`| `3` | `PCM`: `0` no network, `1` zonal transport, `2` nodal DCOPF angle-based, `3` nodal DCOPF PTDF-based.|
|`transmission_loss:`| `0` | `GTEP`/`PCM`: `0` lossless network; `1` piecewise-linear transmission losses using \|flow\|. In `PCM`, this is currently supported for `network_model = 1` and `2`, but not `3` (PTDF).|
|`reference_bus:`| `1` | `PCM` nodal modes: reference bus for angle and nodal price decomposition.|
|`storage_ld_duration_hours:`| `12` | `GTEP`: long-duration storage threshold (MWh/MW).|
|`write_shadow_prices:`| `0` | `1` enables MILP dual-recovery re-solve (fix discrete vars, re-solve LP). In PCM this applies when `unit_commitment=1`; in GTEP when `inv_dcs_bin=1`.|
|`summary_table:`| `0` | `PCM`: `1` generate `output/Analysis/Summary_*.csv`; `0` disable.|
|`solver:`| `gurobi` | Solver name (`cbc`, `clp`, `glpk`, `gurobi`, `cplex`, etc.).|
|`debug:` | `0` | `0` off; `1` conflict refiner; `2` penalty-based debug.|
|`save_postprocess_snapshot:`| `1` | `0` do not save; `1` save minimal machine-readable snapshot in `output/postprocess_snapshot/` for later postprocessing such as EREC; `2` save full snapshot with additional solved-run details.|
---

Notes:
- Parameters like `VOLL`, `planning_reserve_margin`, reserve requirements, `theta_max`, and other numeric constants are read from `single_parameter` input (not from `HOPE_model_settings.yml`).
- Use `endogenous_rep_day` and `external_rep_day` for new cases. `representative_day!` is still supported for backward compatibility.
- Full chronology corresponds to `endogenous_rep_day = 0` and `external_rep_day = 0`.
- Representative-day mode corresponds to `endogenous_rep_day = 1` or `external_rep_day = 1`. These two settings are mutually exclusive.
- Advanced endogenous representative-day controls are stored in `Settings/HOPE_rep_day_settings.yml`.
- Advanced resource aggregation controls are stored in `Settings/HOPE_aggregation_settings.yml` when `resource_aggregation = 1`, including grouping keys, planning-oriented clustering, selective aggregation, audit outputs, and PCM clustered thermal commitment.
- For PCM, representative-day mode is currently not the primary production workflow; nodal studies are typically run in full chronology.
- For PCM, summary tables are controlled by `summary_table=1` across network modes; nodal-specific summary tables are generated only when `network_model` is `2` or `3`.
- `save_postprocess_snapshot` is mainly useful for workflows that want to reuse a solved baseline later, such as `HOPE.calculate_erec_from_output(...)`.
- To turn on transmission losses:
  1. set `transmission_loss: 1`,
  2. add optional `Loss (%)` columns to the relevant line input tables,
  3. keep `transmission_loss: 0` in `PCM network_model = 3`, because PTDF mode is currently lossless.


