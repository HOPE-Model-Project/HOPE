# Germany Current Baseline Validation Memo

## Purpose

This memo freezes the current Germany nodal modeling baseline after the latest load, generator-mapping, BTM-PV, and seasonal-validation updates.

The goal is to give us one stable research baseline before any new modeling branch starts.

## Current baseline

The promoted Germany nodal baseline now includes:

- spatial nodal load allocation built from eGon households and CTS demand, plus the current industry proxy
- sector-differentiated nodal hourly load construction
- calibrated base BTM-PV net-load correction
- offshore generator remapping that avoids weak radial coastal buses and prefers stronger inland injection points

The active benchmark cases are:

- `GERMANY_PCM_nodal_jan_2day_rescaled_case`
- `GERMANY_PCM_nodal_jan_week1_connected_case`
- `GERMANY_PCM_nodal_jan_week3_baseline_case`
- `GERMANY_PCM_nodal_apr_week3_baseline_case`
- `GERMANY_PCM_nodal_jul_week3_baseline_case`
- `GERMANY_PCM_nodal_oct_week3_baseline_case`

## What changed materially

The biggest changes relative to the older Germany setup are:

- nodal demand is no longer allocated mainly with coarse heuristic shares
- offshore wind is no longer trapped behind weak radial `155 kV` coastal buses
- the preferred baseline now represents net load more realistically through calibrated base BTM-PV rather than gross load alone

## Validation status

The strongest current benchmark is the four-season validation pack:

- [germany_seasonal_week_validation_report.md](e:/MIT%20Dropbox/Shen%20Wang/MIT/RA/HOPE_project/tools/germany_pcm_case_related/outputs/germany_seasonal_week_validation_report.md)
- [germany_seasonal_week_cost_summary.csv](e:/MIT%20Dropbox/Shen%20Wang/MIT/RA/HOPE_project/tools/germany_pcm_case_related/outputs/germany_seasonal_week_cost_summary.csv)
- [germany_seasonal_week_topline_recurrence.csv](e:/MIT%20Dropbox/Shen%20Wang/MIT/RA/HOPE_project/tools/germany_pcm_case_related/outputs/germany_seasonal_week_topline_recurrence.csv)

Current readout:

- all four seasonal cases solve `OPTIMAL`
- all four have zero load shedding
- hotspot geography remains directionally credible across seasons
- recurring lines remain concentrated in `TransnetBW`, `Amprion`, plus persistent northern or northwestern `TenneT` / `50Hertz` stress

The broad empirical benchmark is captured at a directional level:

- north or northwest export-side stress exists
- west-central `Amprion` corridor stress exists
- southwest `TransnetBW` receiving-area stress exists
- the old fake offshore coastal bottleneck artifact is gone

Supporting notes:

- [germany_empirical_validation_scorecard.md](e:/MIT%20Dropbox/Shen%20Wang/MIT/RA/HOPE_project/tools/germany_pcm_case_related/outputs/germany_empirical_validation_scorecard.md)
- [germany_external_empirical_validation_note.md](e:/MIT%20Dropbox/Shen%20Wang/MIT/RA/HOPE_project/tools/germany_pcm_case_related/outputs/germany_external_empirical_validation_note.md)

## BTM-PV decision

The calibrated base BTM-PV layer is now the preferred Germany baseline treatment.

Why:

- winter response is modest and conservative
- summer response is materially meaningful but smooth
- low/base/high sensitivity is monotonic rather than erratic
- congestion geography shifts in intensity more than in location

Supporting files:

- [germany_btmpv_promotion_recommendation.md](e:/MIT%20Dropbox/Shen%20Wang/MIT/RA/HOPE_project/tools/germany_pcm_case_related/outputs/germany_btmpv_promotion_recommendation.md)
- [germany_btmpv_sensitivity_comparison.csv](e:/MIT%20Dropbox/Shen%20Wang/MIT/RA/HOPE_project/tools/germany_pcm_case_related/outputs/germany_btmpv_sensitivity_comparison.csv)
- [germany_btmpv_winter_summer_validation_note.md](e:/MIT%20Dropbox/Shen%20Wang/MIT/RA/HOPE_project/tools/germany_pcm_case_related/outputs/germany_btmpv_winter_summer_validation_note.md)

Keep:

- `no-BTM` as a reference benchmark
- `low` and `high` BTM-PV as sensitivity bounds
- `base` BTM-PV as the preferred operating baseline

## Remaining caveats

This version is strong for research use, but not fully frozen as a corridor-calibrated benchmark.

Main caveats:

- industry demand is still proxy-based because direct industry load data is missing
- empirical validation is still directional rather than corridor-by-corridor
- the seasonal benchmark is four representative weeks, not a full-year run
- broader prosumer effects like EV charging and heat pumps are not yet modeled

## Recommended use

Use this baseline for:

- exploratory Germany nodal research
- internal figures and draft analysis
- sensitivity studies and further validation work

If we continue improving the model, the next highest-value steps are:

1. stronger empirical validation against redispatch or corridor evidence
2. better industry data or a more targeted industry proxy
3. only after that, new demand-side refinements beyond BTM-PV
