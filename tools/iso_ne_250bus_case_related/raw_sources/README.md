# Expected Raw Inputs For ISO-NE 250-Bus Case Build

Drop manually downloaded upstream files for the ISO-NE 250-bus build here.

This folder also holds small derived calibration specs that are meant to stay versioned with the case build workflow, for example:

- `internal_supply_adders_live_case.csv`
- `internal_supply_adders_none.csv`
- `internal_supply_adders_zonal_rebalance_v1.csv`
- `ni_interface_generation_config.json`

Recommended source set for the first HOPE PCM build:

## 1. Network backbone

- TAMU EPIGRIDS synthetic New England 250-bus case
- Save the original archive and extracted files in a subfolder that records the download date

Suggested local structure:

- `raw_sources/tamu_ne_250bus/`
  - original archive
  - extracted bus/branch/generator tables
  - any readme/license files from the source package

## 2. ISO-NE public reference data

Suggested local structure:

- `raw_sources/isone_public_2024/`
  - load-zone and capacity-zone reference material
  - nodal load weights
  - public LMP extracts used for validation
  - binding-constraint reports used for validation
  - VER/planning time-series files if used

## 3. Generator and storage fleet

Suggested local structure:

- `raw_sources/eia860_2024/`
- `raw_sources/eia923_2024/`

Keep original file names where possible so the preprocessing scripts can document provenance cleanly.

## Required metadata to record during manual download

For each raw source drop, record:

- official source name
- exact file name
- publication year / report year
- download date
- any manual filtering or renaming done before preprocessing

That metadata should then be copied into:

- `tools/iso_ne_250bus_case_related/references/SOURCE_DATA_REGISTER.csv`
- intermediate preprocessing notes if a raw file is transformed
