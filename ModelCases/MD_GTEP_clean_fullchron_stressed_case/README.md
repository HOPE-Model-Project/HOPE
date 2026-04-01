`MD_GTEP_clean_fullchron_stressed_case` is a temporary stressed full-chronology derivative of `MD_GTEP_clean_case`.

Key changes from the source case:
- full chronology enabled with `representative_day!: 0`, `endogenous_rep_day: 0`, and `external_rep_day: 0`
- `planning_reserve_mode: 0`
- `save_postprocess_snapshot: 1`
- `solver: gurobi`
- `flexible_demand`, `carbon_policy`, and `clean_energy_policy` turned off
- `VOLL` reduced to `15000`
- generator, line, and storage investment budgets set to `0`
- `NI` set to `0` in `load_timeseries_regional.csv`
- thermal `FOR` added to `gendata.csv` and `gendata_candidate.csv`
- `gen_availability_timeseries.csv` rebuilt so wind and solar units use the case's own regional wind/solar profiles instead of all-ones AF

Validated workflow:
- `HOPE.run_hope(...)` writes `output/postprocess_snapshot/`
- `HOPE.calculate_erec_from_output(...)` runs successfully from the saved output

Latest checked outcome:
- baseline EUE is nonzero
- storage EREC output is written in `output/output_erec_from_snapshot/`
