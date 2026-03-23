# Germany PCM Case Source Manifest

This file records the intended public data sources for the Germany HOPE PCM case build.

## Backbone network

### Preferred
- OSM Europe transmission dataset described in Xiong et al. 2025
- URL: https://www.nature.com/articles/s41597-025-04550-7
- Intended use:
  - Germany buses
  - Germany transmission lines and links
  - transformers
  - line geography
  - topology backbone for the nodal master case

### Interactive QA / inspection
- OSM Europe grid map
- URL: https://bxio.ng/assets/osm
- Intended use:
  - visual inspection of German substations and line coverage
  - manual QA for zone seams and major corridors

### Workflow / preprocessing reference
- PyPSA-Eur documentation
- URL: https://pypsa-eur.readthedocs.io/en/latest/introduction.html
- Intended use:
  - reference workflow for retrieving and building the Europe base network
  - guidance on clustering and electricity-only preprocessing

## Generator fleet

### Preferred first-pass fleet
- powerplantmatching
- URL: https://github.com/PyPSA/powerplantmatching
- Intended use:
  - cleaned Germany plant inventory
  - standardized fuel / technology labels
  - coordinates and capacity for initial HOPE fleet mapping

### Germany registry validation
- Marktstammdatenregister export entry point
- URL: https://www.bundesnetzagentur.de/DE/Fachthemen/ElektrizitaetundGas/Monitoringberichte/Marktstammdatenregister/artikel.html
- Intended use:
  - Germany-specific validation of plant status, capacity, and technology

### Thermal fleet validation
- BNetzA Kraftwerksliste
- URL: https://www.bundesnetzagentur.de/DE/Fachthemen/ElektrizitaetundGas/Versorgungssicherheit/Erzeugungskapazitaeten/Kraftwerksliste/start.html?gtp=861646_list%253D2&r=1
- Intended use:
  - validation of large thermal units
  - status checks for the study month

### Plant geography validation
- SMARD power plant map
- URL: https://www.smard.de/en/power-plant-map-updated-217834
- Intended use:
  - location sanity checks
  - operator / technology cross-checks for major units

## Load and generation chronology

### Preferred official chronology
- SMARD download center
- URL: https://www.smard.de/en/downloadcenter/download-market-data
- Intended use:
  - Germany load chronology
  - generation by technology
  - price and interchange reference data where useful

### Convenience package
- Open Power System Data time series package
- URL: https://data.open-power-system-data.org/time_series/2018-03-13/
- Intended use:
  - packaged Germany and control-area time series
  - quick access to DE-LU and TSO-area chronologies where available

## Weather / renewable refinement

### Future refinement source
- DWD gridded hourly data reference
- URL: https://opendata.dwd.de/climate_environment/CDC/grids_germany/hourly/hostrada/DESCRIPTION_gridsgermany_hourly_hostrada_en.pdf
- Intended use:
- later weather-based renewable availability modeling
- not required for the first chronology-consistent build

## Dashboard zone geometry

### Germany administrative boundary base
- Germany administrative GeoJSON
- URL: https://github.com/SBejga/germany-administrative-geojson
- Raw file used:
  - https://raw.githubusercontent.com/SBejga/germany-administrative-geojson/master/geojson/germany_states_simplify200.geojson
- Intended use:
  - state-boundary base geometry for the Germany dashboard overlay
  - coastline and outer-border fidelity for the reconstructed TSO map

### Germany TSO overlay build output
- Local generated file
- Path: `tools/hope_dashboard/data/germany_tso_zones.geojson`
- Intended use:
  - dashboard polygon overlay for `50Hertz`, `Amprion`, `TenneT`, and `TransnetBW`
  - file-backed replacement for the old bubble fallback

### Germany TSO overlay builder
- Local build script
- Path: `tools/germany_pcm_case_related/build_germany_tso_geojson.py`
- Intended use:
  - regenerate the dashboard zone GeoJSON from the state boundary base and frozen bus-zone geography
  - keep the dashboard overlay reproducible instead of hand-editing polygons

## Frozen preprocessing sequence

The intended Germany case build order is:
1. freeze the Germany network backbone from the OSM Europe dataset and any PyPSA-Eur helper metadata
2. freeze the Germany bus-to-zone map for the four research zones
3. freeze the canonical Germany generator fleet from powerplantmatching and validate major assets against MaStR and Kraftwerksliste
4. freeze chronology inputs from SMARD on the same study basis
5. derive the zonal case strictly by aggregating the nodal master case

## Explicit design choice

The Germany zonal case should be derived from the Germany nodal master case.

That means:
- zonal load comes from aggregating nodal load
- zonal generation comes from aggregating nodal generators
- zonal interfaces come from nodal cross-zone cutsets
- zonal chronology should not be calibrated independently from the nodal case
