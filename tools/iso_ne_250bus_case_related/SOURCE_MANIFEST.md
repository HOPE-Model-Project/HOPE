# ISO-NE 250-Bus Case Source Manifest

This file records the intended public data sources for the ISO-NE-like 250-bus HOPE PCM case.

## Backbone network

### Preferred
- TAMU EPIGRIDS New England synthetic cases
- URL: https://electricgrids.engr.tamu.edu/electric-grid-test-cases/EPIGRIDS-NewEngland/
- Intended use:
  - bus list
  - branch list
  - synthetic topology
  - any available geographic coordinates

### Secondary reference only
- Zenodo record 4538590
- URL: https://zenodo.org/records/4538590
- Intended use:
  - optional reference / cross-check
  - not the primary topology backbone unless TAMU proves insufficient

## ISO-NE market / load / policy context

### Pricing nodes
- ISO-NE pricing node tables
- URL: https://www.iso-ne.com/markets-operations/settlements/pricing-node-tables
- Intended use:
  - public nodal naming reference
  - location naming sanity checks

### Nodal load weights
- ISO-NE nodal load weights
- URL: https://www.iso-ne.com/isoexpress/web/reports/load-and-demand/-/tree/nodal-load-weights
- Intended use:
  - distribute zonal load to buses or validate bus allocation weights

### Nodal LMP
- ISO-NE LMP by node reports
- URL: https://www.iso-ne.com/isoexpress/web/reports/pricing/-/tree/lmp-by-node
- Intended use:
  - validate congestion timing and spread patterns

### Binding constraints
- ISO-NE day-ahead constraints
- URL: https://www.iso-ne.com/isoexpress/web/reports/grid/-/tree/constraint-da
- Intended use:
  - validate recurring constraint names and congestion periods

### Variable energy resources
- ISO-NE VER planning data
- URL: https://www.iso-ne.com/system-planning/planning-models-and-data/variable-energy-resource-data/
- Intended use:
  - wind / solar profile references

## Generator fleet

### EIA-860
- URL: https://www.eia.gov/electricity/data/eia860/
- Intended use:
  - existing generator inventory
  - nameplate capacity
  - technology / fuel labels
  - planned / retired status if needed

### EIA-923
- URL: https://www.eia.gov/electricity/data/eia923/
- Intended use:
  - generation
  - fuel use
  - fuel costs
  - emissions proxy inputs

## Explicitly not assumed available

These are not assumed open enough for direct use as the case backbone:

- ISO-NE transmission planning models
  - URL: https://www.iso-ne.com/system-planning/planning-models-and-data/transmission-planning-models
- FERC Form 715 transmission planning data
  - URL: https://www.ferc.gov/industries-data/electric/electric-industry-forms/form-no-715-annual-transmission-planning-and-evaluation-repor-data

Reason:
- real transmission topology/model data is CEII-restricted or otherwise not practically open for a reproducible public case.
