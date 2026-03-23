# Expected Raw Inputs For Germany PCM Case Build

Drop manually downloaded upstream files for the Germany case build here.

This folder also holds small derived calibration specs that are meant to stay versioned with the case build workflow.

A concrete first-drop checklist is in:
- `raw_sources/RAW_DROP_CHECKLIST.md`

Recommended source set for the first HOPE PCM build:

## 1. Network backbone

Suggested local structure:

- `raw_sources/osm_europe_grid/`
  - original archive or extracted tables from the OSM Europe transmission dataset
  - any readme / license files
- `raw_sources/pypsa_eur_reference/`
  - optional base-network exports or notes used for preprocessing

## 2. Germany public chronology

Suggested local structure:

- `raw_sources/smard_2025/`
  - Germany load chronology
  - generation by technology
  - interchange / market data extracts if used
- `raw_sources/opsd_time_series/`
  - OPSD packaged Germany / control-area time series files if used

## 3. Generator fleet and registry data

Suggested local structure:

- `raw_sources/powerplantmatching/`
- `raw_sources/mastr/`
- `raw_sources/kraftwerksliste/`

## 4. Reference geography for dashboard overlays

Suggested local structure:

- `raw_sources/reference_geo/`
  - Germany administrative boundary source files used to rebuild dashboard zone overlays
  - current expected file:
    - `germany_states_simplify200.geojson`

## Required metadata to record during manual download

For each raw source drop, record:
- official source name
- exact file name
- source year / release version
- download date
- any manual filtering or renaming done before preprocessing

That metadata should then be copied into:
- `references/SOURCE_DATA_REGISTER.csv`
- any intermediate preprocessing notes if a raw file is transformed
