# Germany Week1 Industry Proxy Update

## What changed

This update improved the Germany load model in two ways:

1. the fallback industry spatial share is now more transmission-aware and more concentrated on buses that already have stronger industrial signal
2. the synthetic industry hourly profile now includes:
   - flatter weekday industrial demand
   - lower Saturday and Sunday activity
   - national-holiday treatment
   - mild August and year-end shutdown effects

The active load files were refreshed for:
- `GERMANY_PCM_nodal_case`
- `GERMANY_PCM_nodal_jan_2day_rescaled_case`
- `GERMANY_PCM_nodal_jan_week1_connected_case`

The validation solve here is the refreshed week1 case.

## Week1 comparison

Baseline week1 metrics before this update:
- total cost: `38,347,584.77`
- binding hours: `1,223`
- absolute congestion rent: `10,162,729.99`
- mean load-weighted LMP: `9.0721`

Updated week1 metrics after this update:
- total cost: `38,276,581.05`
- binding hours: `1,361`
- absolute congestion rent: `9,350,581.23`
- mean load-weighted LMP: `9.0273`
- load shedding: `0`

Change relative to the previous week1 baseline:
- total cost: `-71,003.71` (`-0.19%`)
- binding hours: `+138` (`+11.3%`)
- absolute congestion rent: `-812,148.76` (`-8.0%`)
- mean load-weighted LMP: `-0.0448` (`-0.49%`)

## Hotspot read

Top binding lines after the update:
- `Line 961` in `Amprion`
- `Line 4` in `TransnetBW`
- `Line 773` in `Amprion`
- `Line 676` in `Amprion`
- `Line 444` in `TenneT`

Interpretation:
- the broad geography remains familiar and credible
- `Amprion` west-central stress remains important
- `TransnetBW` southwest stress remains important
- `TenneT` remains present in the top hotspot set
- the update did not reintroduce the old fake coastal radial artifact

## Takeaway

This looks like a useful modeling improvement.

Why:
- the change is physically motivated,
- it reduces congestion rent without simply collapsing congestion,
- and it preserves the broad empirical Germany congestion pattern that we have been using as the realism benchmark.

## Recommendation

Promote this industry-proxy update into the working Germany baseline and use the four-season validation pack as the next check after the next load-model change.
