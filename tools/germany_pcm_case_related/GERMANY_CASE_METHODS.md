# Methods for Constructing the Germany Nodal and Zonal HOPE PCM Cases

## 1. Study Design

We construct a Germany power market clearing (PCM) dataset for HOPE using a two-stage workflow. First, we build a canonical nodal transmission case for Germany. Second, we derive a four-zone transport case mechanically from the nodal master case rather than calibrating zonal and nodal cases independently. The four zones correspond to the German transmission system operators (TSOs): `50Hertz`, `Amprion`, `TenneT`, and `TransnetBW`.

The design principle is that all major assumptions should be introduced once at the nodal level and then inherited by the zonal derivative. This keeps the zonal and nodal cases comparable in terms of generator fleet, load chronology, renewable availability, and network geography.

The implemented preprocessing entry points are:

- nodal master-case builder: [build_germany_pcm_case.py](e:/MIT%20Dropbox/Shen%20Wang/MIT/RA/HOPE_project/tools/germany_pcm_case_related/build_germany_pcm_case.py)
- zonal derivative-case builder: [build_germany_zonal_case.py](e:/MIT%20Dropbox/Shen%20Wang/MIT/RA/HOPE_project/tools/germany_pcm_case_related/build_germany_zonal_case.py)

## 2. Source Data

### 2.1 Transmission network

The network backbone is assembled from the local Germany extracts of the OSM Europe transmission dataset and PyPSA-Eur style network tables. The preprocessing script searches for buses, lines, transformers, and links under the Germany network raw-source staging folders and writes cleaned staging tables to the `references/` directory.

Implemented source normalization:

- buses: [build_germany_network_backbone.py](e:/MIT%20Dropbox/Shen%20Wang/MIT/RA/HOPE_project/tools/germany_pcm_case_related/build_germany_network_backbone.py)
- source manifest: [SOURCE_MANIFEST.md](e:/MIT%20Dropbox/Shen%20Wang/MIT/RA/HOPE_project/tools/germany_pcm_case_related/SOURCE_MANIFEST.md)

### 2.2 Generator fleet

The generator fleet is built from a local Germany extract of `powerplantmatching`. Plant status, capacity, fuel type, technology, and coordinates are normalized into a clean fleet table. If Germany registry validation files are present locally, the fleet is flagged as validation-enabled, but the current core fleet is still built from the normalized `powerplantmatching` extract.

Implemented source normalization:

- fleet builder: [build_germany_generator_fleet.py](e:/MIT%20Dropbox/Shen%20Wang/MIT/RA/HOPE_project/tools/germany_pcm_case_related/build_germany_generator_fleet.py)

### 2.3 Load and renewable chronology

Hourly chronology is built from public German market data staged under the local SMARD and OPSD folders. The chronology builder searches for:

- national hourly load
- national technology-specific generation
- TSO-area hourly load

The cleaned outputs are:

- national chronology: `references/germany_hourly_chronology_clean.csv`
- TSO-area load reference: `references/germany_zone_hourly_load_reference.csv`

Implemented chronology builder:

- [build_germany_chronology.py](e:/MIT%20Dropbox/Shen%20Wang/MIT/RA/HOPE_project/tools/germany_pcm_case_related/build_germany_chronology.py)

### 2.4 Spatial nodal demand data

The nodal load allocation uses locally staged eGon/eTraGo bus-level demand data when available. In the current implementation, the direct sectoral inputs are:

- `egon_etrago_electricity_households.csv`
- `egon_etrago_electricity_cts.csv`

The direct industry eGon table is still missing. Industry demand is therefore represented by a fallback spatial proxy layer assembled from public industrial-location data. The load-share builder also supports a legacy fallback using public population, settlement, and industry proxies if the eGon bus-demand files are unavailable.

Implemented spatial-load builder:

- [build_germany_spatial_load_shares.py](e:/MIT%20Dropbox/Shen%20Wang/MIT/RA/HOPE_project/tools/germany_pcm_case_related/build_germany_spatial_load_shares.py)

## 3. Nodal Network Construction

### 3.1 Bus normalization

Raw bus records are filtered to Germany (`Country == DE`) and standardized to a uniform HOPE bus table containing:

- stable HOPE bus ID
- raw source bus key
- source bus name
- longitude and latitude
- nominal voltage
- carrier

The cleaned bus file is written to:

- `references/germany_network_buses_clean.csv`

### 3.2 Line, transformer, and link normalization

Raw lines and transformers are filtered so both endpoints lie on the retained Germany buses. Source-specific column names are harmonized into HOPE staging fields. Electrical parameters are carried through where available:

- line length
- nominal voltage
- thermal capacity
- resistance
- reactance
- number of parallel circuits

Transformers are written separately and later merged with lines when the HOPE nodal network is assembled.

### 3.3 Connected-component filtering

The nodal PCM case keeps only the largest connected component of the combined bus-line-transformer graph. This avoids isolated remnants and ensures a single consistent transmission backbone in the master case.

This step is implemented in:

- [_largest_connected_bus_set](e:/MIT%20Dropbox/Shen%20Wang/MIT/RA/HOPE_project/tools/germany_pcm_case_related/build_germany_pcm_case.py)

## 4. Zone Assignment

Each retained transmission bus is assigned to one of the four TSO zones using a frozen bus-to-zone mapping table. The assignment procedure is hierarchical:

1. manual override if present
2. point-in-polygon assignment using the local Germany TSO GeoJSON
3. operator-text inference from bus metadata
4. nearest-zone-anchor fallback

The resulting zone mapping is written to:

- `references/germany_bus_zone_map.csv`

Implemented mapper:

- [build_germany_bus_zone_map.py](e:/MIT%20Dropbox/Shen%20Wang/MIT/RA/HOPE_project/tools/germany_pcm_case_related/build_germany_bus_zone_map.py)

This bus-to-zone layer is the main geography bridge for both the nodal and zonal cases.

## 5. Generator and Storage Mapping

### 5.1 Fleet normalization

All non-retired Germany generator records with positive capacity are retained. Capacity is drawn from the first available net-capacity style field in the staged `powerplantmatching` file.

### 5.2 Bus assignment

Generators are mapped to transmission buses using great-circle distance to the cleaned bus set. The default rule is nearest-bus assignment.

More explicitly, the assignment is performed on the cleaned Germany transmission backbone after bus-zone mapping. For each generator with valid coordinates, the algorithm computes the haversine distance to the eligible HOPE buses and assigns the nearest bus.

The frozen assignment output stores:

- assigned bus ID
- assigned TSO zone
- assignment method
- assignment distance in kilometers
- a confidence label

Assignments with very long distance are explicitly flagged in the notes field, so the bus map preserves traceability for lower-confidence placements.

### 5.3 Offshore correction

Large offshore wind units can be misassigned to weak or radial coastal buses if simple nearest-bus logic is used. To avoid this artifact, offshore generators are remapped when their nearest candidate is a low-voltage or radial bus. In those cases, the algorithm prefers stronger inland injection buses, defined operationally as buses with:

- nominal voltage at least `220 kV`
- graph degree at least `2`

If no such strong bus exists, a weaker fallback set of buses with at least `155 kV` and degree at least `2` is used.

This correction removed earlier artificial coastal bottlenecks that were caused by gigawatt-scale offshore generation sitting behind weak radial buses.

In implementation terms, the offshore rule is triggered only for generators identified as offshore wind from their fuel and technology labels. For those units, the algorithm first performs the ordinary nearest-bus assignment, checks whether that bus is weak, and if so recomputes the nearest assignment over the restricted strong-bus subset. Offshore units therefore remain distance-mapped, but only after weak radial injection buses have been excluded from the candidate set.

### 5.4 Generator and storage typing

Fuel and technology labels are mapped into HOPE technology classes, including:

- `NuC`
- `Coal`
- `NGCC`
- `NGCT`
- `Oil`
- `Hydro`
- `WindOn`
- `WindOff`
- `SolarPV`
- `Bio`
- `MSW`
- `Landfill_NG`
- `Other`

Storage technologies are separated into:

- `PHS`
- `BES`

The clean generator reference and frozen bus map are written to:

- `references/germany_generator_fleet_clean.csv`
- `references/germany_generator_bus_map.csv`

## 6. Chronology Construction

### 6.1 National chronology

The chronology builder normalizes hourly German load and generation time series to a single study year, currently 2025. Timestamps are filtered to:

- start: `2025-01-01 00:00`
- end: `2026-01-01 00:00`

The national chronology contains:

- `Load_MW`
- `WindOnshore_MW`
- `WindOffshore_MW`
- `SolarPV_MW`
- `Hydro_MW`
- `Biomass_MW`
- `OtherRenewables_MW`
- `NetImports_MW`

### 6.2 TSO-area load chronology

The zonal helper chronology contains hourly TSO-area load for:

- `50Hertz`
- `Amprion`
- `TenneT`
- `TransnetBW`

When a combined zonal file is not available, the builder falls back to separate SMARD control-area files and merges them onto the national hourly index.

## 7. Nodal Load Construction

### 7.0 Schematic overview

The nodal load workflow can be summarized as:

```text
TSO-area hourly gross load L(z,h)
            |
            v
  sectoral hourly activity weights
  {w_hh(z,h), w_cts(z,h), w_ind(z,h)}
            |
            v
  bus-level sectoral spatial shares
  {s_hh(b,h|z), s_cts(b,h|z), s_ind(b,h|z)}
            |
            v
  hourly gross nodal load
  Load_gross(b,h) = L(z,h) * s(b,h|z)
            |
            v
  calibrated BTM-PV offset on non-industry load
  BTM_PV(b,h)
            |
            v
  final hourly nodal net load
  Load_net(b,h) = max(Load_gross(b,h) - BTM_PV(b,h), 0)
```

### 7.1 Static spatial shares

Static bus-level demand shares are built by mapping direct eGon demand buses onto the HOPE transmission buses. The mapping is zone-constrained and distance-weighted. For eGon buses, demand is softly distributed to up to `k = 4` nearby HOPE buses inside the inferred TSO zone, with weights based on:

- inverse distance
- voltage compatibility

The current static share stack is:

- direct demand component from eGon households and CTS
- industry fallback component from public industrial-location proxies

The layer combination weights are:

- direct eGon demand: `0.85`
- industry fallback proxy: `0.15`

Within each direct-demand layer, shares are first normalized by zone and scenario, then averaged across available scenarios. The final frozen bus-level static shares are written to:

- `references/germany_spatial_load_shares.csv`

### 7.1.1 Soft mapping from eGon buses to HOPE buses

The eGon demand buses are not assumed to coincide exactly with the HOPE transmission buses. Each eGon bus is therefore mapped softly onto a small candidate set of nearby HOPE buses within the inferred TSO zone.

For each eGon bus, the algorithm:

1. infers a coarse TSO zone from the nearest HOPE bus
2. restricts the candidate set to HOPE buses in that same TSO zone
3. keeps the nearest `k = 4` HOPE candidate buses
4. assigns candidate weights using:
   - inverse distance, with a minimum distance floor of `2 km`
   - a voltage-match score that penalizes large voltage mismatch
5. normalizes those weights to sum to `1`
6. allocates the eGon demand fractionally across the candidate HOPE buses

Thus, the static nodal share is not based on an all-or-nothing nearest-bus rule. It is a local soft allocation that preserves zone consistency while reducing sensitivity to any single bus placement.

### 7.2 Sectoral hourly nodal load

Hourly nodal load is then constructed using a sectoral allocation model. For each zone, the method combines:

- households
- CTS
- industry

Households and CTS use direct hourly profiles derived from the eGon `p_set` arrays mapped onto HOPE buses. Industry uses direct eGon industry if available; otherwise a synthetic hourly activity profile is used together with the static industry proxy.

For each zone, the algorithm:

1. computes sector-specific hourly activity signals
2. estimates zone-level sector weights, with a ridge-regularized fit anchored to prior weights
3. reuses the full-year structural sector mix for short-horizon derivative cases
4. distributes each hour's zonal load across buses using a convex combination of sector-specific nodal shares

More explicitly, for each zone `z` and hour `h`, the algorithm first computes the zonal gross load level `L(z,h)` from the TSO-area chronology. It then constructs three sector-specific hourly weight series:

- `w_hh(z,h)` for households
- `w_cts(z,h)` for CTS
- `w_ind(z,h)` for industry

with:

`w_hh(z,h) + w_cts(z,h) + w_ind(z,h) = 1`

For the same zone and hour, each bus `b` in zone `z` also has sector-specific nodal shares:

- `s_hh(b,h|z)` from mapped eGon household demand
- `s_cts(b,h|z)` from mapped eGon CTS demand
- `s_ind(b,h|z)` from direct industry demand if available, otherwise the refined industry proxy

The pre-BTM hourly bus share is then:

`s(b,h|z) = w_hh(z,h) * s_hh(b,h|z) + w_cts(z,h) * s_cts(b,h|z) + w_ind(z,h) * s_ind(b,h|z)`

and the corresponding hourly bus-level gross load is:

`Load_gross(b,h) = L(z,h) * s(b,h|z)`

This means the model does not simply apply one common hourly profile to all buses inside a TSO zone. Instead, the hourly bus profile depends on each bus's sector composition and mapped sectoral activity.

### 7.2.1 When buses within the same TSO do and do not share the same hourly shape

The hourly nodal load profile is generally not identical across buses in the same region.

It differs within a zone because:

- households, CTS, and industry have different hourly activity patterns
- buses have different sectoral mixes
- the industry fallback is refined by voltage, local bus peak, and industrial proxy strength
- BTM-PV is applied to the non-industry component and therefore offsets some buses more than others

Two buses in the same TSO will have very similar hourly load shapes only if they have very similar:

- household shares
- CTS shares
- industry shares
- exposure to the BTM-PV offset

The within-zone profiles can collapse toward a more common zonal shape in edge cases, for example:

- when direct sectoral signal is weak or missing for a sector
- when a short-horizon case inherits the full-year structural sector weights
- when the fallback static shares dominate the sector mix

But even in those cases, the current implementation is still more differentiated than a pure zone-flat nodal allocation.

Industry fallback is refined further using:

- static industry signal relative to the fallback load share
- local bus voltage
- local bus peak demand

### 7.3 BTM-PV net-load correction

The promoted Germany baseline includes a calibrated behind-the-meter photovoltaic (BTM-PV) correction. The purpose is to convert zonal gross demand into a closer approximation of transmission-visible net demand.

The annual calibration target is:

- `12.28 TWh` of German PV self-consumption

The correction is applied only to the non-industry portion of load and is distributed with weights:

- households: `0.75`
- CTS: `0.25`

The BTM-PV signal is tilted across zones using a mild zone-specific solar-penetration signal inferred from zonal solar capacity relative to zonal peak demand. Hourly BTM-PV offsets are capped so that no more than `45%` of the non-industry load component is removed in a given hour. For short-horizon derivative cases, the zonal BTM-PV multipliers are inherited from the full-year structural case rather than re-fit locally.

Operationally, the BTM-PV offset is distributed to buses using the non-industry part of their hourly load mix, with weights:

- `0.75` on the household component
- `0.25` on the CTS component

The resulting bus-level net load is:

`Load_net(b,h) = max(Load_gross(b,h) - BTM_PV(b,h), 0)`

so buses with stronger residential and CTS concentration receive larger midday BTM-PV offsets than industry-dominated buses in the same zone.

Diagnostics are written to:

- `load_sector_weight_diagnostics.csv`
- `load_btmpv_diagnostics.csv`

### 7.4 HOPE load-file representation

In the HOPE nodal case, bus demand is represented by two files:

1. `busdata.csv`, which stores each bus peak demand in MW
2. `load_timeseries_nodal.csv`, which stores hourly dimensionless multipliers

Actual hourly nodal demand is therefore:

`Load(b,h) = DemandPeak(b) x Multiplier(b,h)`

An analogous representation is used for zonal load:

- `zonedata.csv` stores zonal peak demand
- `load_timeseries_regional.csv` stores zonal hourly multipliers

## 8. Nodal Generator, Storage, and Network Inputs

### 8.1 Generator table

The nodal generator table is built by grouping the mapped generator fleet by:

- zone
- bus
- HOPE technology type

Installed capacity is summed within each group. Technical parameters such as cost, emissions factor, forced outage rate, ramp limits, reserve capability, and unit-commitment settings are assigned from a fixed technology parameter dictionary in the nodal-case builder.

### 8.2 Storage table

Storage assets are built from the mapped storage subset of the fleet and grouped by:

- zone
- bus
- storage technology type

Power capacity is summed, and energy capacity is computed as power multiplied by a technology-specific default duration when an explicit duration is not available.

### 8.3 Line table

The final HOPE nodal line table merges lines and transformers into a common transmission-edge table. Each element is assigned:

- from-bus
- to-bus
- from-zone
- to-zone
- reactance-like coefficient used by HOPE DCOPF
- thermal capacity
- loss fraction

For transformers lacking raw reactance, a conservative default per-unit transformer reactance is used and converted onto the HOPE scaling convention.

The final HOPE line table is therefore not a direct copy of the raw OSM/PyPSA-Europe branch tables. It is a normalized edge list in which:

- raw lines and transformers are represented in one common transmission table
- raw bus identifiers are translated into the frozen HOPE bus numbering
- TSO-zone IDs are attached through the frozen bus-to-zone map
- branch capacities are converted into the HOPE MW-style transmission-capacity field
- branch reactance is transformed into the scaling used by the HOPE DC power-flow formulation

For raw lines with available electrical reactance, the HOPE branch coefficient is computed from the raw reactance and voltage level. For transformers lacking explicit raw reactance, the model uses a conservative default transformer reactance and converts it to the HOPE scaling on the transformer's own MVA base. This preserves a numerically stable first-pass transmission representation while retaining the original network topology.

## 9. Renewable Availability Representation

The current renewable representation is chronology-consistent but simplified spatially. Wind and solar availability are derived from the national chronology and normalized by the national annual maximum. The resulting hourly profiles are then copied across all German zones. Thus, the present implementation preserves the national renewable time pattern but does not yet introduce spatially differentiated weather-driven renewable profiles by zone or bus.

This simplification should be kept in mind when interpreting renewable curtailment and congestion.

## 10. Zonal Case Derivation

The four-zone zonal case is derived mechanically from the current nodal master case.

### 10.1 Zonal demand

The zonal load chronology is copied directly from the nodal master regional load file. This means the zonal case inherits the promoted `base` BTM-PV treatment and any future zonal load changes introduced at the nodal master level.

### 10.2 Zonal fleet

The zonal generator fleet is obtained by aggregating nodal generators by:

- zone
- technology type

Zonal storage is aggregated similarly by zone and storage technology. Capacity-weighted averages are used for technical parameters where needed.

In practical terms, the zonal fleet is not rebuilt from raw source data. It is aggregated directly from the current nodal fleet so that any change in nodal mapping, technology typing, or capacity immediately propagates to the zonal case as well.

### 10.3 Zonal transmission seams

The zonal transmission network is built from the set of nodal lines whose endpoints lie in different TSO zones. For each ordered zone pair, all cross-zone lines are grouped into one interface. The interface capacity is the sum of the underlying nodal seam capacities. A representative bus pair is retained only for bookkeeping and traceability.

The zonal case therefore represents a transport-style reduction of the nodal seam set rather than a manually chosen net-transfer-capacity approximation.

More explicitly, the seam aggregation proceeds as follows:

1. identify every nodal branch for which `From_zone != To_zone`
2. reorder the two endpoint zones so each seam belongs to one unique unordered zone pair
3. group all seam branches by that zone pair
4. define zonal interface capacity as the sum of all underlying nodal seam capacities
5. define zonal interface loss as the mean of the underlying seam-loss values
6. retain the largest underlying seam branch as the representative interface record for bookkeeping

The resulting zonal interface therefore behaves like a cutset-style reduction of the nodal seam set. It is not an independently chosen ATC-style transfer parameter.

### 10.4 Consistency principle

The zonal derivative is not calibrated independently. It is intended as a consistency benchmark against the nodal case, so differences between zonal and nodal outputs can be interpreted as modeling-resolution effects rather than differences in core input assumptions.

## 11. Validation Workflow

The Germany baseline has been validated in several steps:

1. removal of artificial coastal congestion caused by offshore generator mis-mapping
2. week-scale congestion audits
3. four-season directional validation using winter, spring, summer, and autumn weeks
4. sensitivity testing of the calibrated BTM-PV layer

The current baseline is therefore best described as a research-ready directional benchmark rather than a corridor-by-corridor historical replica.

Key validation notes are stored in:

- [germany_current_baseline_validation_memo.md](e:/MIT%20Dropbox/Shen%20Wang/MIT/RA/HOPE_project/tools/germany_pcm_case_related/outputs/germany_current_baseline_validation_memo.md)
- [germany_seasonal_week_validation_report.md](e:/MIT%20Dropbox/Shen%20Wang/MIT/RA/HOPE_project/tools/germany_pcm_case_related/outputs/germany_seasonal_week_validation_report.md)
- [germany_btmpv_promotion_recommendation.md](e:/MIT%20Dropbox/Shen%20Wang/MIT/RA/HOPE_project/tools/germany_pcm_case_related/outputs/germany_btmpv_promotion_recommendation.md)

## 12. Current Limitations

The present workflow still has several important limitations.

1. Industry demand is still proxy-based because the direct eGon industry demand table is missing.
2. Renewable availability is not yet weather-resolved spatially by zone or bus.
3. Validation is strong at the directional level but not yet calibrated against corridor-level historical redispatch data.
4. Broader prosumer effects such as electric vehicles and heat pumps are not yet included.

## 13. Reproducibility

The main preprocessing sequence is:

1. [build_germany_network_backbone.py](e:/MIT%20Dropbox/Shen%20Wang/MIT/RA/HOPE_project/tools/germany_pcm_case_related/build_germany_network_backbone.py)
2. [build_germany_bus_zone_map.py](e:/MIT%20Dropbox/Shen%20Wang/MIT/RA/HOPE_project/tools/germany_pcm_case_related/build_germany_bus_zone_map.py)
3. [build_germany_generator_fleet.py](e:/MIT%20Dropbox/Shen%20Wang/MIT/RA/HOPE_project/tools/germany_pcm_case_related/build_germany_generator_fleet.py)
4. [build_germany_chronology.py](e:/MIT%20Dropbox/Shen%20Wang/MIT/RA/HOPE_project/tools/germany_pcm_case_related/build_germany_chronology.py)
5. [build_germany_spatial_load_shares.py](e:/MIT%20Dropbox/Shen%20Wang/MIT/RA/HOPE_project/tools/germany_pcm_case_related/build_germany_spatial_load_shares.py)
6. [build_germany_pcm_case.py](e:/MIT%20Dropbox/Shen%20Wang/MIT/RA/HOPE_project/tools/germany_pcm_case_related/build_germany_pcm_case.py)
7. [build_germany_zonal_case.py](e:/MIT%20Dropbox/Shen%20Wang/MIT/RA/HOPE_project/tools/germany_pcm_case_related/build_germany_zonal_case.py)

The active outputs are then stored in:

- nodal master case: `ModelCases/GERMANY_PCM_nodal_case`
- zonal derivative case: `ModelCases/GERMANY_PCM_zonal4_case`
