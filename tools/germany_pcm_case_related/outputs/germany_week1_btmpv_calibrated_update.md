# Germany Week1 Calibrated BTM-PV Update

## What changed

This update adds a calibrated behind-the-meter PV net-load correction to the Germany sectoral load builder.

Calibration logic:
- national annual target anchored to `12.28 TWh` of German PV self-consumption
- zonal split tilted by the model's solar-to-load signal, but kept conservative
- hourly offsets capped by the non-industry portion of load so BTM-PV cannot create unrealistic negative demand
- short-horizon cases reuse the full-year calibrated zonal multipliers rather than recalibrating on a short window

Relevant implementation:
- `tools/germany_pcm_case_related/build_germany_sectoral_nodal_load.py`
- `Data_GERMANY_PCM_nodal/load_btmpv_diagnostics.csv`

## Full-year calibration result

The main Germany case calibrated exactly to the annual target:
- realized BTM-PV offset: `12.28 TWh`

Realized full-year zonal gross-load offsets:
- `TransnetBW`: `3.18%`
- `50Hertz`: `3.36%`
- `TenneT`: `2.65%`
- `Amprion`: `2.01%`

## Week1 comparison

Pre-BTM week1 baseline:
- total cost: `38,276,581.05`
- binding hours: `1,361`
- absolute congestion rent: `9,350,581.23`
- mean load-weighted LMP: `9.0273`

Calibrated BTM-PV week1 result:
- total cost: `37,931,803.59`
- binding hours: `1,343`
- absolute congestion rent: `8,888,529.94`
- mean load-weighted LMP: `8.9182`
- load shedding: `0`

Change relative to the pre-BTM week1 baseline:
- total cost: `-344,777.46` (`-0.90%`)
- binding hours: `-18` (`-1.32%`)
- absolute congestion rent: `-462,051.29` (`-4.94%`)
- mean load-weighted LMP: `-0.1090` (`-1.21%`)

## January realized BTM-PV intensity

Realized week1 load offsets by zone:
- `TransnetBW`: `0.57%`
- `50Hertz`: `0.54%`
- `TenneT`: `0.44%`
- `Amprion`: `0.33%`

Realized 2-day load offsets by zone:
- `TransnetBW`: `0.75%`
- `50Hertz`: `0.70%`
- `TenneT`: `0.58%`
- `Amprion`: `0.44%`

This is much more conservative than the earlier rough BTM-PV prototype.

## Takeaway

This looks like a plausible next realism upgrade.

Why:
- the calibration is externally anchored,
- the January effect is modest rather than disruptive,
- congestion is reduced slightly rather than collapsing,
- and the system still solves cleanly with zero load shedding.

## Recommendation

This correction is strong enough for the next validation step:
1. rerun the four seasonal benchmark pack with calibrated BTM-PV enabled
2. compare the new seasonal hotspot geography against the current no-BTM benchmark
3. only then decide whether to promote BTM-PV into the default Germany baseline
