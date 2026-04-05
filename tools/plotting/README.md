# Plotting Utilities

These scripts are lightweight plotting helpers for HOPE case outputs.

They are intentionally kept under `tools/plotting/` instead of `src/` so the
main HOPE package stays focused on model setup, solve, and reporting.

Typical usage:

```bash
julia --project=. tools/plotting/plot_output_capacity.jl ModelCases/MD_GTEP_clean_case
julia --project=. tools/plotting/plot_output_generation.jl ModelCases/MD_GTEP_clean_case
julia --project=. tools/plotting/plot_output_GTEP_operation.jl ModelCases/MD_GTEP_clean_case
julia --project=. tools/plotting/plot_output_operation.jl ModelCases/MD_PCM_Excel_case
```

Each script writes an HTML plot into the case `plots/` folder.
