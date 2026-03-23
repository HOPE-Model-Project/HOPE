# Germany PCM Case Blueprint

This document defines a concrete blueprint for building a Germany PCM case in HOPE with a nodal master case and a zonal derivative case that share the same underlying assumptions.

## 1. Objective

Build two Germany PCM cases that are directly comparable:

- `GERMANY_PCM_nodal_case`: geographically grounded nodal transmission model
- `GERMANY_PCM_zonal4_case`: 4-zone aggregation of the same nodal master case

The key design principle is:

- build one canonical nodal dataset first
- derive the zonal case mechanically from the nodal case
- avoid separate zonal calibration whenever possible

This keeps zonal and nodal assumptions aligned for clean comparison of:

- dispatch
- congestion
- curtailment
- net interchange
- zonal price spreads versus nodal price dispersion

## 2. Recommended Study Scope

### Initial version

- Geography: Germany only, with explicit cross-border interchange placeholders or interfaces
- Zonal aggregation: 4 German TSO regions
  - `50Hertz`
  - `Amprion`
  - `TenneT`
  - `TransnetBW`
- Time scope: one pilot month first
  - recommended pilot months: `2025-01` and `2025-07`
- Network model targets:
  - nodal case: `network_model = 3` in HOPE when ready for PTDF runs
  - zonal case: `network_model = 1`

### Why this scope

- Germany has strong public chronology and plant data
- 4-zone TSO regions provide a meaningful research aggregation
- month-scale pilots are much easier to debug before full-year runs

## 3. Canonical Modeling Principle

The nodal case is the source of truth.

Everything else is derived from it:

- zonal load = sum of nodal load by TSO zone
- zonal generation fleet = aggregation of nodal generators by TSO zone
- zonal transmission interfaces = aggregation of nodal cutsets between zones
- zonal renewable availability = aggregation of nodal renewable availability
- zonal NI / imports = aggregation of nodal border interface treatment

This means we should not build a zonal Germany case independently from national statistics. Instead we should aggregate the nodal master case.

## 4. Target HOPE Outputs

We should aim to generate the same basic case inputs used by HOPE PCM cases already in the repo.

### Nodal master case

Target folder:

- `ModelCases/GERMANY_PCM_nodal_case/`

Target data files:

- `busdata.csv`
- `linedata.csv`
- `gendata.csv`
- `zonedata.csv`
- `load_timeseries.csv`
- `load_timeseries_nodal.csv`
- `gen_availability_timeseries.csv`
- `ni_timeseries.csv`
- optional: `ni_timeseries_nodal.csv`
- reference tables under a `references/` or tool output folder

### Zonal derivative case

Target folder:

- `ModelCases/GERMANY_PCM_zonal4_case/`

Target data files:

- `busdata.csv`
- `linedata.csv`
- `gendata.csv`
- `zonedata.csv`
- `load_timeseries.csv`
- `gen_availability_timeseries.csv`
- `ni_timeseries.csv`

For the zonal case, buses can remain as representative buses if HOPE expects bus-level structure, but all economics and constraints should reduce to zone-level transport behavior.

## 5. Recommended Data Stack

## 5.1 Transmission network backbone

Primary source:

- Europe-wide OSM transmission dataset described in Xiong et al. 2025
- Nature Scientific Data paper
- interactive inspection map
- PyPSA-Eur base-network workflow

Recommended use:

- extract Germany buses, AC lines, transformers, and any relevant DC links
- use this as the initial nodal topology backbone

Why:

- much stronger than hand-built German transmission geometry
- already structured around buses and lines
- fits PyPSA-Eur workflows and validation ecosystem

## 5.2 Generator fleet

Primary source:

- `powerplantmatching`

Validation / correction sources:

- BNetzA Marktstammdatenregister complete public export
- BNetzA Kraftwerksliste
- SMARD power plant map for large-unit location and metadata checks

Recommended use:

- use `powerplantmatching` as the first-pass cleaned fleet
- use BNetzA sources to validate capacities, status, and major thermal units
- preserve source provenance per unit or plant cluster

## 5.3 Load and generation chronology

Primary source:

- SMARD official time series downloads

Supporting source:

- OPSD time series package for Germany and German control-area convenience tables

Recommended use:

- system load, national generation by technology, and if available TSO-area series from SMARD / OPSD
- use a single historical period consistently across load, generation, fuel assumptions, and cross-border interchange

## 5.4 Renewable availability

Initial practical approach:

- use actual hourly wind and solar generation by Germany or TSO area
- distribute to nodal renewable buses by installed-capacity shares within each zone / technology bucket

Later refinement:

- replace with weather-derived nodal capacity factors from PyPSA-Eur or DWD-backed workflows

Reason:

- first-pass actual generation chronology keeps zonal and nodal assumptions tightly consistent
- weather-derived nodal profiles can be a second-phase realism upgrade

## 5.5 Zonal boundaries

Target research zones:

- `50Hertz`
- `Amprion`
- `TenneT`
- `TransnetBW`

Important note:

- these are research aggregation zones, not the actual DE-LU market design
- we will need a frozen bus-to-zone mapping reference file

## 6. Required Build Artifacts

The following reference files should be created under something like:

- `tools/germany_case_related/references/`

### 6.1 Core mapping files

- `germany_bus_zone_map.csv`
  - `Bus_id`
  - `Zone_id`
  - `TSO`
  - `State`
  - `Latitude`
  - `Longitude`
  - `MappingSource`
  - `Confidence`

- `germany_generator_bus_map.csv`
  - `GenId`
  - `PlantName`
  - `Bus_id`
  - `Zone_id`
  - `AssignmentMethod`
  - `Distance_km`
  - `SourceDataset`

- `germany_border_interface_map.csv`
  - interface definitions for external interchange treatment

### 6.2 Validation tables

- `germany_capacity_by_zone_source_compare.csv`
- `germany_load_by_zone_source_compare.csv`
- `germany_interzonal_cutset_summary.csv`
- `germany_fleet_source_manifest.csv`

## 7. Concrete Build Workflow

## Step 1. Freeze case specification

Create a case specification YAML or JSON with:

- study year
- study month(s)
- chosen zones
- nodal bus target count
- included voltage levels
- treatment of cross-border links
- treatment of offshore wind and HVDC links

Suggested file:

- `tools/germany_case_related/germany_case_config.yml`

Recommended initial settings:

- year: `2025`
- pilot month: `2025-07`
- zones: 4 TSO areas
- nodal bus target: `200 +/- 50`
- AC voltage levels: `220 kV` and `380 kV`
- include major DC links only if clearly represented in source network

## Step 2. Build Germany nodal topology

Input sources:

- OSM Europe transmission dataset / PyPSA-Eur base network

Process:

- subset to Germany and near-border assets relevant to German interchange
- keep buses, lines, transformers, and major links
- simplify to HOPE-friendly nodal resolution
- preserve geographic coordinates
- assign provisional thermal limits and reactance values from source data where available

Deliverables:

- `buses_raw.csv`
- `lines_raw.csv`
- `transformers_raw.csv`
- `germany_network_cleaned.csv` or equivalent intermediate tables

Open design choice:

- whether to start from a PyPSA-Eur clustered Germany network directly, or from the higher-resolution OSM data and do our own clustering

Recommendation:

- start from PyPSA-Eur-compatible network outputs if available
- only fall back to custom clustering if needed for HOPE compatibility

## Step 3. Define Germany zones and bus-to-zone map

Inputs:

- TSO control-area references
- bus coordinates
- operator metadata if present in the network data

Process:

- assign every nodal bus to one TSO zone
- validate that contiguous regional structure looks sensible
- freeze the mapping in `germany_bus_zone_map.csv`

This file is critical because both nodal and zonal cases depend on it.

## Step 4. Build generator fleet

Inputs:

- `powerplantmatching`
- BNetzA MaStR export
- BNetzA Kraftwerksliste
- SMARD power plant map metadata where useful

Process:

- filter to Germany and chosen study date
- remove retired / inactive plants for the study month
- map technologies into HOPE categories
- assign each plant to the nearest or electrically appropriate nodal bus
- preserve fuel, type, pmax, pmin, heat-rate proxy or marginal-cost proxy, emissions factor, outage assumptions

Recommended HOPE fields to produce in `gendata.csv`:

- `PlantCode`
- `PlantName`
- `SourceTechnology`
- `State`
- `Zone`
- `Bus_id`
- `Latitude`
- `Longitude`
- `Pmax (MW)`
- `Pmin (MW)`
- `Type`
- `Flag_thermal`
- `Flag_RET`
- `Flag_VRE`
- `Cost ($/MWh)`
- `EF`
- `CC`
- `AF`
- `FOR`
- reserve and ramp fields consistent with other HOPE PCM cases

## Step 5. Build nodal and zonal load consistently

Inputs:

- Germany national load chronology from SMARD
- control-area load chronology where available from SMARD / OPSD / ENTSO-E
- static regional allocation basis for bus shares

Process:

- create zone-level hourly load first for the 4 TSO zones
- define static or weakly dynamic nodal load shares within each zone
- create `load_timeseries_nodal.csv` such that hourly sum by zone exactly matches zonal load
- aggregate that same nodal load back into `load_timeseries.csv`

Key rule:

- zonal load must be the exact aggregation of nodal load, not an independently calibrated series

## Step 6. Build renewable and generator availability

Initial version:

- use actual hourly zonal wind / solar generation chronologies
- allocate to nodal renewable generators using installed-capacity shares by zone and technology
- derive plant-level availability series that aggregate back to official zonal totals

Outputs:

- `gen_availability_timeseries.csv`

Later version:

- replace with nodal weather-based capacity factors from PyPSA-Eur / atlite / DWD-backed weather workflow

## Step 7. Build interchange treatment

Need to decide whether Germany is modeled as:

- isolated with exogenous NI, or
- Germany plus simplified border nodes, or
- Germany with explicit foreign neighboring zones as external slack / trade interfaces

Recommended first version:

- Germany internal network with exogenous net imports represented through `ni_timeseries.csv`
- if HOPE nodal NI support is needed, derive `ni_timeseries_nodal.csv` from border buses and interface weights

Potential external interfaces:

- Denmark
- Netherlands
- Belgium
- France
- Switzerland
- Austria
- Czechia
- Poland
- Luxembourg

## Step 8. Derive zonal network from nodal network

This is the most important consistency step.

Process:

- aggregate all buses to the 4 TSO zones
- sum generation and load by zone
- identify all nodal branches crossing zone boundaries
- compute seam statistics:
  - count of lines
  - sum of thermal capacities
  - PTDF-informed effective transfer capability if available
- create zonal `linedata.csv` using these seam-derived capacities

Rule:

- zonal interfaces must be derived from the nodal cutsets, not guessed manually

## Step 9. Calibrate economics and validate

Validate against public data for the same pilot month:

- total Germany load
- total net imports
- generation by major fuel / technology
- zonal shares of load and capacity
- plausible congestion locations
- plausible spreads across TSO regions in stressed periods

Suggested outputs:

- monthly scorecard tables similar in spirit to the ISO-NE scorecard workflow

## 8. Proposed Repo Structure

Suggested new tool area:

- `tools/germany_case_related/`

Recommended files:

- `build_germany_pcm_case.py`
- `build_germany_zonal_case.py`
- `germany_case_config.yml`
- `references/`
- `raw_sources/README.md`
- `SOURCE_MANIFEST.md`
- `validate_germany_case.py`
- `scorecard_germany_pcm.py`

Suggested model cases:

- `ModelCases/GERMANY_PCM_nodal_case/`
- `ModelCases/GERMANY_PCM_zonal4_case/`

## 9. Initial Simplifying Assumptions

For a first robust prototype, I recommend:

- focus on Germany internal system only
- use 4 TSO zones
- use one pilot month
- use actual historical load and VRE chronology
- use exogenous NI rather than explicit neighboring countries in version 1
- use a moderate nodal network size around `200` buses
- use line capacities from source network where available; otherwise conservative engineering proxies
- keep storage and hydro simple if source complexity becomes a blocker

## 10. Main Risks and Mitigations

### Risk 1. Bus-to-zone mapping uncertainty

Mitigation:

- freeze and review `germany_bus_zone_map.csv`
- visualize every bus and boundary before finalizing

### Risk 2. Generator assignment noise

Mitigation:

- use nearest-bus assignment with voltage / region sanity checks
- manually review the largest plants

### Risk 3. Zonal transfer capacities are not comparable to nodal congestion

Mitigation:

- derive zonal seam capacities from nodal cutsets
- do not hand-tune ATCs until after first validation

### Risk 4. Too much realism too early

Mitigation:

- use actual zonal chronology first
- defer weather-driven nodal VRE and detailed UC realism to later versions

## 11. Recommended Implementation Order

### Phase A. Blueprint freeze

- finalize study month
- finalize zoning choice
- finalize network source choice

### Phase B. Nodal master case

- topology
- bus geography
- zone map
- generator fleet
- load chronology
- VRE chronology
- NI chronology

### Phase C. Zonal derivative case

- zonal aggregation of buses, generators, load, and interfaces
- transport network inputs

### Phase D. Validation

- compare nodal and zonal totals
- compare against historical public benchmarks
- run HOPE PCM pilot simulations

## 12. Recommended First Deliverable

The first concrete milestone should be:

- a Germany `July 2025` nodal prototype with about `200` buses
- a mechanically aggregated 4-zone TSO derivative case
- a validation notebook or scorecard confirming:
  - nodal and zonal totals match by construction
  - aggregated nodal load equals zonal load
  - aggregated nodal VRE equals zonal VRE
  - zonal seam capacities are derived from nodal network structure

## 13. Source List

Transmission network and workflow:

- Xiong et al. 2025, Scientific Data: `https://www.nature.com/articles/s41597-025-04550-7`
- interactive OSM Europe map: `https://bxio.ng/assets/osm`
- PyPSA-Eur docs: `https://pypsa-eur.readthedocs.io/en/latest/introduction.html`

Generator fleet:

- powerplantmatching: `https://github.com/PyPSA/powerplantmatching`
- BNetzA MaStR article / export entry point: `https://www.bundesnetzagentur.de/DE/Fachthemen/ElektrizitaetundGas/Monitoringberichte/Marktstammdatenregister/artikel.html`
- BNetzA Kraftwerksliste: `https://www.bundesnetzagentur.de/DE/Fachthemen/ElektrizitaetundGas/Versorgungssicherheit/Erzeugungskapazitaeten/Kraftwerksliste/start.html?gtp=861646_list%253D2&r=1`
- SMARD power plant map note: `https://www.smard.de/en/power-plant-map-updated-217834`

Chronology:

- SMARD download center: `https://www.smard.de/en/downloadcenter/download-market-data`
- OPSD time series package: `https://data.open-power-system-data.org/time_series/2018-03-13/`

Weather / future refinement:

- DWD open gridded hourly data reference: `https://opendata.dwd.de/climate_environment/CDC/grids_germany/hourly/hostrada/DESCRIPTION_gridsgermany_hourly_hostrada_en.pdf`

## 14. Practical Next Actions

1. freeze the study month and whether version 1 uses `2025-01` or `2025-07`
2. decide whether to start from PyPSA-Eur clustered Germany network or the raw OSM Europe grid dataset
3. create `tools/germany_case_related/germany_case_config.yml`
4. create the empty mapping-table templates listed above
5. build the bus-to-zone map first, because everything else depends on it
6. then build the nodal topology and fleet around that map
