# Germany Case Handoff

## Purpose

This note is the practical handoff guide for the current Germany HOPE PCM example cases.

Use this file if you want to understand:

- which Germany cases are the recommended examples
- what assumptions they use
- what has already been validated
- what the main caveats are
- where to start if you want to rerun or compare cases

For the full technical construction details, see:

- [GERMANY_CASE_METHODS.md](e:/MIT%20Dropbox/Shen%20Wang/MIT/RA/HOPE_project/tools/germany_pcm_case_related/GERMANY_CASE_METHODS.md)

## Recommended example cases

These are the cases I recommend sharing as the Germany benchmark set.

### 1. Zonal reference

- [GERMANY_PCM_zonal4_case](e:/MIT%20Dropbox/Shen%20Wang/MIT/RA/HOPE_project/ModelCases/GERMANY_PCM_zonal4_case)

What it is:

- 4-zone Germany PCM case
- zones are the German TSOs:
  - `50Hertz`
  - `Amprion`
  - `TenneT`
  - `TransnetBW`

Why keep it:

- this is the clean zonal comparison case
- it is mechanically derived from the nodal master assumptions
- it is the best reference for zonal vs nodal comparison

### 2. Fast nodal debug case

- [GERMANY_PCM_nodal_jan_2day_rescaled_case](e:/MIT%20Dropbox/Shen%20Wang/MIT/RA/HOPE_project/ModelCases/GERMANY_PCM_nodal_jan_2day_rescaled_case)

What it is:

- 2-day nodal Germany case
- same nodal modeling logic as the larger seasonal cases

Why keep it:

- fastest nodal smoke-test case
- useful for debugging, quick reruns, and dashboard checks

### 3. Winter nodal benchmark

- [GERMANY_PCM_nodal_jan_week3_baseline_case](e:/MIT%20Dropbox/Shen%20Wang/MIT/RA/HOPE_project/ModelCases/GERMANY_PCM_nodal_jan_week3_baseline_case)

What it is:

- 7-day winter nodal benchmark case

Why keep it:

- representative winter validation case
- useful for higher-load and winter-stress behavior

### 4. Autumn nodal benchmark

- [GERMANY_PCM_nodal_oct_week3_baseline_case](e:/MIT%20Dropbox/Shen%20Wang/MIT/RA/HOPE_project/ModelCases/GERMANY_PCM_nodal_oct_week3_baseline_case)

What it is:

- 7-day autumn nodal benchmark case

Why keep it:

- strongest congestion case in the seasonal validation pack
- good benchmark for transmission-stress analysis

### Optional 5. Summer nodal benchmark

- [GERMANY_PCM_nodal_jul_week3_baseline_case](e:/MIT%20Dropbox/Shen%20Wang/MIT/RA/HOPE_project/ModelCases/GERMANY_PCM_nodal_jul_week3_baseline_case)

Why keep it:

- best case for seeing the effect of calibrated BTM-PV
- useful if summer net-load and curtailment behavior matter for the study

If a smaller benchmark pack is preferred, this is the first case I would omit after the core four.

## Cases not recommended as shared examples

These are still useful locally, but I would not prioritize them as colleague-facing examples.

- [GERMANY_PCM_nodal_case](e:/MIT%20Dropbox/Shen%20Wang/MIT/RA/HOPE_project/ModelCases/GERMANY_PCM_nodal_case)
  Keep as the master build source, but it is not the cleanest example case.
- [GERMANY_PCM_nodal_jan_week1_connected_case](e:/MIT%20Dropbox/Shen%20Wang/MIT/RA/HOPE_project/ModelCases/GERMANY_PCM_nodal_jan_week1_connected_case)
  Useful for calibration history, but largely superseded by the week3 baseline cases.
- [GERMANY_PCM_nodal_apr_week3_baseline_case](e:/MIT%20Dropbox/Shen%20Wang/MIT/RA/HOPE_project/ModelCases/GERMANY_PCM_nodal_apr_week3_baseline_case)
  Spring is informative but less essential than winter, autumn, and optionally summer.

## Current baseline assumptions

The current preferred Germany nodal baseline includes:

- transmission-network backbone built from cleaned Germany network staging tables
- frozen bus-to-zone mapping for the four TSO regions
- generator fleet mapped to buses from the cleaned `powerplantmatching`-based fleet
- offshore generator remapping that avoids weak radial coastal buses
- nodal load allocation based on:
  - eGon households
  - eGon CTS
  - fallback industry proxy
- sector-differentiated hourly nodal load construction
- calibrated `base` BTM-PV net-load correction

Important modeling choice:

- the zonal case is derived mechanically from the nodal master assumptions
- zonal and nodal cases are not calibrated independently

## What is the same and what is different between zonal and nodal

This is the key interpretation for zonal-versus-nodal comparison.

### Held constant as much as possible

The comparison is designed to keep these aligned:

- study horizon and chronology
- zonal load totals
- zonal renewable profile shapes
- technology-cost assumptions
- technology-operating assumptions
- total capacity by zone and technology
- storage capacity by zone and storage type
- policy settings

### Changed between the two cases

The main differences are:

- nodal case represents within-zone network detail; zonal case does not
- nodal case can have internal congestion inside a TSO; zonal case cannot
- nodal case places load and generators at bus level; zonal case aggregates them to zone level
- nodal and zonal cases do not have the same number of generator rows

Important clarification:

- the nodal case keeps generators at `zone + bus + technology` resolution
- the zonal case aggregates the same fleet to `zone + technology`

So the row count differs, but the intended underlying fleet is the same in an aggregated sense. The fairness criterion is consistency of the fleet and assumptions, not equality of generator count.

## Generator cost assumptions

Generator costs are currently assigned by modeled technology type, not by individual plant.

That means generators of the same HOPE technology class share the same default:

- variable cost
- emissions factor
- capacity credit
- outage assumptions
- ramp assumptions
- reserve assumptions
- startup and minimum up/down assumptions

So yes, costs differ across technologies, but not yet across individual plants within the same modeled type.

Examples of distinct HOPE generator types with different assumed costs include:

- `SolarPV`
- `WindOn`
- `WindOff`
- `Hydro`
- `NuC`
- `Coal`
- `NGCC`
- `NGCT`
- `Bio`
- `Oil`

## What has been validated already

The current Germany baseline has passed these checks:

### 1. Offshore artifact removal

- earlier artificial coastal `TenneT` bottlenecks caused by bad offshore mapping were removed
- the model still shows northern stress after the fix, which is the desired outcome

### 2. Seasonal congestion validation

The current seasonal validation pack is:

- [germany_seasonal_week_validation_report.md](e:/MIT%20Dropbox/Shen%20Wang/MIT/RA/HOPE_project/tools/germany_pcm_case_related/outputs/germany_seasonal_week_validation_report.md)

Main result:

- all four seasonal weeks solve `OPTIMAL`
- all four have zero load shedding
- congestion geography is directionally credible

The repeated structural pattern is:

- northern or northwestern export-side stress
- west-central `Amprion` corridor stress
- southwest `TransnetBW` receiving-area stress

### 3. BTM-PV sensitivity

The calibrated BTM-PV layer was tested with low/base/high sensitivity.

Main result:

- winter response is modest
- summer response is meaningful but smooth
- congestion geography changes in intensity more than in location

Recommendation:

- use `base` BTM-PV as the preferred operating baseline
- keep `no-BTM` only as a reference benchmark

Supporting note:

- [germany_btmpv_promotion_recommendation.md](e:/MIT%20Dropbox/Shen%20Wang/MIT/RA/HOPE_project/tools/germany_pcm_case_related/outputs/germany_btmpv_promotion_recommendation.md)

## Main caveats

The current Germany cases are strong research examples, but they are not a fully finalized historical benchmark.

Main caveats:

- industry demand is still proxy-based because the direct eGon industry table is missing
- empirical validation is directional rather than corridor-by-corridor
- renewable availability is still spatially simplified
- broader prosumer effects such as EV charging and heat pumps are not included

## How to explain the nodal load model quickly

If you need a short explanation for a colleague:

1. start from TSO-area hourly load
2. allocate that zonal load to buses using static spatial shares informed by eGon households and CTS plus an industry proxy
3. reshape hourly bus load using sector-specific hourly activity, so buses in the same TSO do not all have identical hourly profiles
4. subtract calibrated BTM-PV from the non-industry part of load to get a more realistic net-load approximation

## What to run first

Recommended sequence for a new user:

1. open the zonal case and the 2-day nodal case
2. compare [GERMANY_PCM_zonal4_case](e:/MIT%20Dropbox/Shen%20Wang/MIT/RA/HOPE_project/ModelCases/GERMANY_PCM_zonal4_case) against [GERMANY_PCM_nodal_jan_2day_rescaled_case](e:/MIT%20Dropbox/Shen%20Wang/MIT/RA/HOPE_project/ModelCases/GERMANY_PCM_nodal_jan_2day_rescaled_case)
3. move to [GERMANY_PCM_nodal_jan_week3_baseline_case](e:/MIT%20Dropbox/Shen%20Wang/MIT/RA/HOPE_project/ModelCases/GERMANY_PCM_nodal_jan_week3_baseline_case) and [GERMANY_PCM_nodal_oct_week3_baseline_case](e:/MIT%20Dropbox/Shen%20Wang/MIT/RA/HOPE_project/ModelCases/GERMANY_PCM_nodal_oct_week3_baseline_case) for seasonal nodal benchmarks
4. add [GERMANY_PCM_nodal_jul_week3_baseline_case](e:/MIT%20Dropbox/Shen%20Wang/MIT/RA/HOPE_project/ModelCases/GERMANY_PCM_nodal_jul_week3_baseline_case) if summer net-load behavior is important

## Best companion files to share

If these cases are passed to a colleague, the most helpful companion docs are:

- [GERMANY_CASE_METHODS.md](e:/MIT%20Dropbox/Shen%20Wang/MIT/RA/HOPE_project/tools/germany_pcm_case_related/GERMANY_CASE_METHODS.md)
- [germany_current_baseline_validation_memo.md](e:/MIT%20Dropbox/Shen%20Wang/MIT/RA/HOPE_project/tools/germany_pcm_case_related/outputs/germany_current_baseline_validation_memo.md)
- [germany_seasonal_week_validation_report.md](e:/MIT%20Dropbox/Shen%20Wang/MIT/RA/HOPE_project/tools/germany_pcm_case_related/outputs/germany_seasonal_week_validation_report.md)

## Bottom line

If someone asks, “Which Germany examples should I use?”, the short answer is:

- `GERMANY_PCM_zonal4_case`
- `GERMANY_PCM_nodal_jan_2day_rescaled_case`
- `GERMANY_PCM_nodal_jan_week3_baseline_case`
- `GERMANY_PCM_nodal_oct_week3_baseline_case`

and optionally:

- `GERMANY_PCM_nodal_jul_week3_baseline_case`

That set is the best balance of:

- compactness
- reproducibility
- seasonal coverage
- nodal vs zonal comparability
- current baseline realism
