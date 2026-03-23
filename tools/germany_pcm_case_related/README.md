# Germany PCM HOPE Case Workspace

This folder is the preprocessing workspace for a Germany PCM case in HOPE.

Current recommendation:
- canonical master case: Germany nodal PCM case
- derivative comparison case: Germany 4-zone zonal PCM case
- research zones: German TSO regions
  - `50Hertz`
  - `Amprion`
  - `TenneT`
  - `TransnetBW`

That means the intended geography is:

`Generator -> Bus -> Zone (TSO area) -> Germany`

The guiding design rule is:
- build one canonical nodal dataset first
- derive the zonal case mechanically from the nodal case
- do not calibrate zonal and nodal cases independently

This keeps zonal and nodal assumptions consistent for comparison of:
- dispatch
- congestion
- curtailment
- interchange
- nodal price dispersion versus zonal price spreads

## Current HOPE PCM target files

### Nodal master case

Target folder:
- `ModelCases/GERMANY_PCM_nodal_case/`

Expected direct inputs:
- `zonedata.csv`
- `busdata.csv`
- `linedata.csv`
- `gendata.csv`
- `load_timeseries.csv`
- `load_timeseries_nodal.csv`
- `gen_availability_timeseries.csv`
- `ni_timeseries.csv`
- optional `ni_timeseries_nodal.csv`
- `HOPE_model_settings.yml`

### Zonal derivative case

Target folder:
- `ModelCases/GERMANY_PCM_zonal4_case/`

Expected direct inputs:
- `zonedata.csv`
- `busdata.csv`
- `linedata.csv`
- `gendata.csv`
- `load_timeseries.csv`
- `gen_availability_timeseries.csv`
- `ni_timeseries.csv`
- `HOPE_model_settings.yml`

## Recommended build sequence

### Step 1. Nodal network backbone

Primary sources:
- OSM Europe transmission dataset from Xiong et al. 2025
- PyPSA-Eur base-network workflow

Goal:
- create a HOPE-friendly Germany nodal backbone with stable bus IDs, line connectivity, coordinates, and zone tags

### Step 2. Zone mapping

Build and freeze a bus-to-zone table for the four TSO regions.

This is the main consistency layer for both nodal and zonal cases.

### Step 3. Generator fleet

Primary source:
- `powerplantmatching`

Validation sources:
- BNetzA Marktstammdatenregister
- BNetzA Kraftwerksliste
- SMARD power plant map

Goal:
- assign each generator to one nodal bus once, then aggregate from that same mapping for the zonal case

### Step 4. Load and VRE chronology

Primary chronology sources:
- SMARD
- ENTSO-E / OPSD where helpful

Goal:
- build nodal hourly load and renewable availability so they aggregate exactly to the zonal series

### Step 5. Zonal derivative case

Goal:
- aggregate buses, generators, load, and seams from the nodal master case
- derive zonal interface capacities from nodal cutsets instead of manual ATC guesses

## Workspace layout

- `raw_sources/`: manually downloaded upstream files and versioned small calibration specs
- `references/`: mapping tables, source registers, case notes, and validation summaries
- `outputs/`: editable templates and intermediate exports
- `build_germany_pcm_case.py`: nodal master-case build entry point
- `build_germany_zonal_case.py`: zonal derivative-case build entry point
- `SOURCE_MANIFEST.md`: source strategy and intended use
- `build_germany_network_backbone.py`: normalize raw Germany network inputs into cleaned buses / lines / transformers staging tables
- `build_germany_bus_zone_map.py`: freeze the Germany bus-to-zone mapping reference from a bus extract and optional polygon / override inputs
- `build_germany_tso_geojson.py`: rebuild the dashboard-ready Germany TSO overlay from reference geography and the frozen bus-zone map

## Dashboard zone geometry

The Germany dashboard overlay now uses a file-backed GeoJSON instead of bubble polygons.

Primary files:
- `tools/hope_dashboard/data/germany_tso_zones.geojson`
- `tools/germany_pcm_case_related/build_germany_tso_geojson.py`
- `tools/germany_pcm_case_related/raw_sources/reference_geo/germany_states_simplify200.geojson`

Interpretation:
- outer geometry comes from Germany state boundaries
- clearly covered states are assigned directly to one TSO region
- mixed states are split with the frozen Germany bus-zone layout as the internal seam guide

This is a research-grade reconstructed control-area overlay for dashboard use.
It is more realistic than bubbles, but it is not an official TSO shapefile.

## Current source stack

Transmission network and workflow:
- `https://www.nature.com/articles/s41597-025-04550-7`
- `https://bxio.ng/assets/osm`
- `https://pypsa-eur.readthedocs.io/en/latest/introduction.html`

Generator fleet:
- `https://github.com/PyPSA/powerplantmatching`
- `https://www.bundesnetzagentur.de/DE/Fachthemen/ElektrizitaetundGas/Monitoringberichte/Marktstammdatenregister/artikel.html`
- `https://www.bundesnetzagentur.de/DE/Fachthemen/ElektrizitaetundGas/Versorgungssicherheit/Erzeugungskapazitaeten/Kraftwerksliste/start.html?gtp=861646_list%253D2&r=1`
- `https://www.smard.de/en/power-plant-map-updated-217834`

Chronology:
- `https://www.smard.de/en/downloadcenter/download-market-data`
- `https://data.open-power-system-data.org/time_series/2018-03-13/`

Zone geometry / dashboard overlay:
- `https://github.com/SBejga/germany-administrative-geojson`
- `https://raw.githubusercontent.com/SBejga/germany-administrative-geojson/master/geojson/germany_states_simplify200.geojson`

Weather / future refinement:
- `https://opendata.dwd.de/climate_environment/CDC/grids_germany/hourly/hostrada/DESCRIPTION_gridsgermany_hourly_hostrada_en.pdf`


