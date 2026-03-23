# Germany Network Backbone Workflow

This note documents the intended workflow for freezing the Germany nodal transmission backbone before bus-to-zone mapping and generator assignment.

## Goal

Build a cleaned Germany network staging layer with stable buses, lines, transformers, and optional links.

The cleaned staging outputs should then feed:
- `build_germany_bus_zone_map.py`
- generator-to-bus assignment
- zonal seam aggregation
- final HOPE nodal `busdata.csv` and `linedata.csv`

## Expected raw inputs

Preferred raw source folders:
- `raw_sources/osm_europe_grid/`
- `raw_sources/pypsa_eur_reference/`

Expected raw tables if available:
- `buses.csv`
- `lines.csv`
- `transformers.csv`
- optional `links.csv`

## Expected cleaned outputs

- `references/germany_network_buses_clean.csv`
- `references/germany_network_lines_clean.csv`
- `references/germany_network_transformers_clean.csv`
- optional `references/germany_network_links_clean.csv`

## Minimum required normalized columns

### Buses
- `Bus_id`
- `SourceBusName`
- `Longitude`
- `Latitude`
- `V_nom_kV`
- `Country`
- `Carrier`
- `SourceDataset`
- `Notes`

### Lines
- `Line_id`
- `FromBus`
- `ToBus`
- `Length_km`
- `Voltage_kV`
- `Capacity_MVA`
- `R`
- `X`
- `NumParallel`
- `Carrier`
- `SourceDataset`
- `Notes`

### Transformers
- `Transformer_id`
- `Bus0`
- `Bus1`
- `S_nom_MVA`
- `X`
- `SourceDataset`
- `Notes`

## QA expectations

Before the backbone is treated as usable:
- buses have stable unique IDs
- all line endpoints resolve to known bus IDs
- voltage fields are numeric where available
- Germany subset filters are documented
- any dropped non-Germany assets or isolated islands are noted in `CASE_DATA_NOTES.md`

