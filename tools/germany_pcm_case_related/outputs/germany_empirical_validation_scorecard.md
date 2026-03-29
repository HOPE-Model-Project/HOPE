# Germany Empirical Validation Scorecard

## Scope

This scorecard compares the current four-season Germany HOPE validation pack against external official evidence on congestion and redispatch in Germany.

Relevant model outputs:
- `germany_seasonal_week_validation_report.md`
- `germany_seasonal_week_hotspot_geo_summary.csv`
- `germany_seasonal_week_region_counts.csv`
- `germany_seasonal_week_topline_recurrence.csv`

Primary external sources:
- Bundesnetzagentur, grid reserve / congestion, 2025-04-28  
  https://www.bundesnetzagentur.de/SharedDocs/Pressemitteilungen/EN/2025/20250428_Netzreserve.html
- Bundesnetzagentur, SuedLink, 2025-05-28  
  https://www.bundesnetzagentur.de/SharedDocs/Pressemitteilungen/EN/2025/20250528_SuedLink.html
- Bundesnetzagentur, A-Nord, 2025-04-15  
  https://www.bundesnetzagentur.de/SharedDocs/Pressemitteilungen/EN/2025/20250415_ANord.html
- SMARD, congestion management in Q2 2024  
  https://www.smard.de/page/en/topic-article/5892/215186
- SMARD, congestion management in Q3 2024  
  https://www.smard.de/page/en/topic-article/5892/215936
- Netztransparenz, redispatch mechanics  
  https://www.netztransparenz.de/en/Ancillary-Services/System-operations/Redispatch
- FfE, southern wind and redispatch, 2026-03-05  
  https://www.ffe.de/en/publications/wind-energy-in-the-south-systemic-savings-through-avoided-redispatch-costs/

## What the external evidence says

The official and applied-research benchmark is consistent:

1. Germany still has a structural transfer problem from northern / northwestern renewable production toward western, southern, and southwestern demand centers.
2. Redispatch is still routinely used to reduce generation in front of congestion and increase it behind congestion.
3. North-to-south backbone projects like SuedLink and northwest-to-west projects like A-Nord exist because these transfer patterns are system-relevant.
4. Congestion should therefore show up repeatedly in:
   - northern or northwestern export-side areas,
   - west-central transfer and demand corridors,
   - southwest or southern receiving areas.

## Model evidence used here

Across the four seasonal weeks, the model hotspot counts are:

- by zone:
  - `Amprion`: 15 top-hotspot appearances
  - `TransnetBW`: 14
  - `TenneT`: 7
  - `50Hertz`: 4
- by region:
  - `west_central`: 17
  - `southwest`: 10
  - `northwest_coastal`: 7
  - `north_or_northeast`: 4
  - `central`: 2

Recurring binding lines:
- `Line 4` in `TransnetBW`: all 4 seasons
- `Line 9` in `TransnetBW`: all 4 seasons
- `Line 961` in `Amprion`: all 4 seasons
- `Line 772` in `50Hertz`: all 4 seasons
- `Line 679` in `TenneT`: 3 seasons

## Scorecard

### 1. Northern / northwestern export stress exists

Result: `PASS`

Why:
- `TenneT` northwest-coastal and `50Hertz` north/northeast hotspots appear across all seasonal windows.
- `Line 772` in `50Hertz` recurs in all 4 seasons.
- `Line 679` in `TenneT` recurs in 3 seasons.

Interpretation:
- The model does capture the export-side north/northwest part of the official German congestion story.

### 2. Southwest / southern receiving stress exists

Result: `PASS`

Why:
- `TransnetBW` southwest hotspots appear in all four seasonal runs.
- `Line 4` and `Line 9` in `TransnetBW` recur in all 4 seasons and are among the strongest recurring bottlenecks.

Interpretation:
- The model consistently produces southern/southwestern receiving-area stress, which fits the benchmark well.

### 3. West-central transfer / demand corridor stress exists

Result: `PASS`

Why:
- `Amprion` west-central hotspots are the single most common regional cluster in the seasonal pack.
- `Line 961` in `Amprion` recurs in all 4 seasons.

Interpretation:
- This is consistent with Germany needing to move power not only north-to-south but also through west-central industrial and transfer corridors.

### 4. Congestion recurrence is stable rather than accidental

Result: `PASS`

Why:
- Multiple lines recur in 3-4 seasons.
- The hotspot geography does not flip randomly between unrelated regions.

Interpretation:
- This reduces the chance that the current pattern is being driven mainly by short-horizon noise.

### 5. Known fake coastal artifact is gone

Result: `PASS`

Why:
- The earlier weak radial coastal `TenneT` bottlenecks caused by offshore generator mis-mapping no longer dominate the hotspot set.
- Northern stress remains even after the artifact was fixed, which is the desired outcome.

Interpretation:
- The model is now more credible because it still shows northern stress for the right broad reason rather than due to an obvious topology error.

### 6. Relative zone balance looks fully realistic

Result: `PARTIAL`

Why:
- The model likely leans somewhat heavy on `Amprion` and `TransnetBW` relative to the broad public narrative, while `TenneT` is clearly present but not dominant in the top-hotspot counts.
- This may still be fine, because many real German bottlenecks are internal and corridor-specific rather than simply “all in the north.”
- But without corridor-level historical redispatch data, we cannot yet say the zone mix is calibrated.

Interpretation:
- Good directional fit, but the exact regional weighting may still be imperfect.

### 7. Seasonal pattern looks fully calibrated to reality

Result: `PARTIAL`

Why:
- Autumn is the strongest congestion week in the current sample, while winter is not uniquely dominant.
- This is plausible, but we do not yet have enough observed corridor-season evidence to treat this as a calibrated empirical match.

Interpretation:
- The seasonality is believable, but not yet externally benchmarked tightly enough to call it validated.

## Bottom line

Overall result: `Strong directional empirical match`

What we can say now:
- The Germany baseline clears a meaningful empirical benchmark.
- It reproduces the main real-world congestion geography expected from official sources.
- It does so across multiple seasons.
- It no longer depends on the known fake offshore coastal bottleneck artifact.

What we still cannot say:
- that the corridor-by-corridor frequency is historically calibrated,
- that the TSO balance is quantitatively correct,
- or that the seasonal intensity ranking is fully validated.

## Best next actions

1. If we can obtain richer redispatch data from Netztransparenz or another official dataset, compare our hotspot geography against requesting-TSO or corridor-level redispatch observations.
2. If not, the highest-value model refinement is probably on the load side:
   - strengthen the industry proxy, or
   - add a carefully calibrated distributed-PV / net-load correction.
