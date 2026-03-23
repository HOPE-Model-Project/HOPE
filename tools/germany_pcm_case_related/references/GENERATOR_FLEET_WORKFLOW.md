# Germany Generator Fleet Workflow

This note documents the intended workflow for freezing the Germany generation fleet and generator-to-bus assignment used by both:
- `GERMANY_PCM_nodal_case`
- `GERMANY_PCM_zonal4_case`

## Goal

Build one canonical Germany generator fleet table, then assign each generator to exactly one nodal bus so the zonal case can be derived by aggregation rather than separate calibration.

## Preferred raw inputs

### First-pass fleet backbone
- `raw_sources/powerplantmatching/`

### Optional validation layers
- `raw_sources/mastr/`
- `raw_sources/kraftwerksliste/`
- `raw_sources/smard_2025/` for major plant geography checks if needed

### Required upstream reference tables
- `references/germany_network_buses_clean.csv`
- `references/germany_bus_zone_map.csv`

## Expected cleaned outputs

- `references/germany_generator_fleet_clean.csv`
- `references/germany_generator_bus_map.csv`

## Minimum normalized generator fields

- `GenId`
- `PlantName`
- `FuelType`
- `Technology`
- `Status`
- `Capacity_MW`
- `Latitude`
- `Longitude`
- `Bus_id`
- `Zone_id`
- `AssignmentMethod`
- `AssignmentDistance_km`
- `SourceDataset`
- `SourceRecordId`
- `ValidationFlag`
- `Notes`

## First-pass assignment logic

The intended assignment order is:
1. read a Germany generator extract from `powerplantmatching`
2. filter to active or plausibly in-service Germany plants for the study basis
3. normalize technology and capacity fields into HOPE-friendly staging columns
4. assign each generator to the nearest cleaned Germany bus using coordinates
5. inherit `Zone_id` from the assigned bus
6. write the frozen cleaned fleet and bus-assignment map for QA

## QA expectations

Before the file is treated as usable:
- every retained generator should have a non-empty `GenId`
- every generator with coordinates should have an assigned `Bus_id`
- assignment distances should be reviewed for outliers
- the largest thermal plants should be manually checked against MaStR or Kraftwerksliste
- the zonal capacity totals implied by `Zone_id` should be reviewed before nodal-to-zonal aggregation
