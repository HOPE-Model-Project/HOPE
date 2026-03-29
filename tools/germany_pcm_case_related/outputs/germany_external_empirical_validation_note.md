# Germany External Empirical Validation Note

## Purpose

This note strengthens the Germany nodal-case validation benchmark beyond the earlier purely structural check. It compares the current four-season HOPE validation pack against recent official German congestion and redispatch evidence.

Relevant model outputs:
- `germany_seasonal_week_validation_report.md`
- `germany_seasonal_week_cost_summary.csv`
- `germany_seasonal_week_hotspot_geo_summary.csv`
- `germany_seasonal_week_topline_recurrence.csv`

## External benchmark we are using

### 1. Germany still has a structural north/northwest to south/southwest congestion problem

Recent official sources continue to describe congestion as a consequence of renewable generation being concentrated in the north and northwest while major demand centers and receiving areas remain farther south and southwest.

- Bundesnetzagentur, 2025-04-28: grid reserve is still needed to prevent transmission overloading caused by congestion; redispatch works by lowering generation in front of congestion and raising it behind congestion.
  - Source: https://www.bundesnetzagentur.de/SharedDocs/Pressemitteilungen/EN/2025/20250428_Netzreserve.html
- Bundesnetzagentur, 2025-05-28: SuedLink is described as a north-to-south backbone connecting Schleswig-Holstein to Baden-Wuerttemberg and Bavaria.
  - Source: https://www.bundesnetzagentur.de/SharedDocs/Pressemitteilungen/EN/2025/20250528_SuedLink.html
- Bundesnetzagentur, 2025-04-15: A-Nord is explicitly intended to move wind power from the northwest and North Sea toward the Rhine/Ruhr demand centers in the west.
  - Source: https://www.bundesnetzagentur.de/SharedDocs/Pressemitteilungen/EN/2025/20250415_ANord.html
- SMARD, article on Q2 2024 congestion management: strong wind feed-in in the north combined with large consumption centers in the south can drive north-to-south flows beyond line capacity.
  - Source: https://www.smard.de/page/en/topic-article/5892/215186

### 2. Redispatch remains a live operational tool, so congestion should show up as recurring spatial stress rather than one-off noise

- SMARD congestion-management dashboard and historical development pages show redispatch, grid reserve, and countertrading remain significant and are tracked over time.
  - Sources:
    - https://www.smard.de/page/en/topic-article/212250/214060/congestion-management
    - https://www.smard.de/page/en/topic-article/212250/217910/the-development-of-congestion-management
- Netztransparenz confirms redispatch is used by German TSOs to balance flows by decreasing injection on one side of congestion and increasing it on the other.
  - Source: https://www.netztransparenz.de/en/Ancillary-Services/System-operations/Redispatch

### 3. Southern or southwestern supply additions should help, not hurt

- FfE, 2026-03-05: more wind in southern Germany can reduce redispatch costs, which is consistent with congestion being driven by north-heavy renewable geography relative to southern demand.
  - Source: https://www.ffe.de/en/publications/wind-energy-in-the-south-systemic-savings-through-avoided-redispatch-costs/

## What we expect a credible HOPE Germany case to show

For the current model stage, we do not require exact historical line-by-line replication. We do require directional consistency with the external benchmark:

1. recurring northern or northwestern export-side stress, especially in `TenneT` and sometimes `50Hertz`
2. recurring southwest or southern receiving-area stress, especially in `TransnetBW`
3. meaningful west-central `Amprion` congestion, since west/central Germany is part of the transfer path and demand geography
4. redispatch-like spatial logic rather than domination by obviously artificial weak radial buses
5. recurrence across multiple seasons, not just one stressed week

## How the current seasonal HOPE runs compare

The four validation weeks are:
- winter: `jan_week3`
- spring: `apr_week3`
- summer: `jul_week3`
- autumn: `oct_week3`

All four solved with zero load shedding.

### Geography match

From `germany_seasonal_week_region_counts.csv` and `germany_seasonal_week_hotspot_geo_summary.csv`:

- winter:
  - `Amprion` west-central hotspots dominate
  - `TenneT` northwest coastal hotspots appear
  - `TransnetBW` southwest hotspots appear
  - `50Hertz` north/northeast hotspot appears
- spring:
  - `TransnetBW` southwest hotspots are strongest
  - `Amprion` west-central hotspots remain present
  - `TenneT` northwest coastal hotspots remain present
- summer:
  - `Amprion` west-central hotspots remain strong
  - `TransnetBW` southwest hotspots remain strong
  - northern/northwestern stress still appears, though weaker
- autumn:
  - `Amprion` west-central hotspots remain
  - `TenneT` northwest coastal hotspots remain
  - `TransnetBW` southwest hotspots remain

This is a good directional fit to the official benchmark.

### Recurring line pattern

From `germany_seasonal_week_topline_recurrence.csv`:

- `Line 4` in `TransnetBW` appears in all 4 seasons with 432 total binding hours
- `Line 9` in `TransnetBW` appears in all 4 seasons with 401 total binding hours
- `Line 961` in `Amprion` appears in all 4 seasons with 127 total binding hours
- `Line 772` in `50Hertz` appears in all 4 seasons with 114 total binding hours
- `Line 679` in `TenneT` appears in 3 seasons

That recurrence is important because it suggests stable corridor stress rather than random numerical artifacts.

### What improved compared with the older baseline

The earlier offshore-wind mapping artifact created fake dominant coastal radial bottlenecks in `TenneT`. After moving offshore generation away from weak radial `155 kV` buses and onto stronger upstream buses, those fake bottlenecks disappeared while north/northwest stress still remained in the hotspot set. This makes the current validation signal more credible.

## Current verdict

The Germany nodal baseline is now empirically plausible at a directional level.

That means:
- the model reproduces the broad German congestion geography we expect from official sources,
- it does so across multiple seasons,
- and it no longer depends on the known fake coastal radial artifact.

## What this still does not prove

The model is not yet validated against:

- historical line-by-line redispatch actions
- exact congestion volumes by corridor
- measured locational prices
- a fully realistic industry-demand geography
- distributed-PV / prosumer net-load effects

So the current claim should remain:

`The model is directionally and empirically credible, but not yet fully calibrated to observed German congestion data at corridor or nodal resolution.`

## Best next empirical upgrade

The next strongest validation step would be to compare our seasonal hotspot geography against a more explicit real-world congestion dataset, for example:

1. redispatch measures by federal state, TSO, or corridor from Netztransparenz / SMARD / BNetzA data products
2. any published map of frequently constrained transmission corridors
3. seasonal redispatch and renewable-curtailment patterns by region

If those data are obtainable, we can move from a qualitative directional benchmark to a semi-quantitative validation scorecard.
