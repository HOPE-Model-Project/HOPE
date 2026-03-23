# Germany Bus-Zone Mapping Workflow

This note documents the intended workflow for freezing `germany_bus_zone_map.csv`.

## Goal

Assign every nodal bus in the Germany nodal backbone to exactly one research zone:
- `50Hertz`
- `Amprion`
- `TenneT`
- `TransnetBW`

## Inputs

Expected upstream bus extract:
- `raw_sources/germany_network_buses.csv`

Preferred columns if available:
- `Bus_id`
- `bus_id`
- `x`
- `y`
- `Longitude`
- `Latitude`
- `operator`
- `tags`
- `country`

Optional supporting references:
- `references/germany_tso_zones.geojson`
- `references/germany_bus_zone_manual_overrides.csv`
- `references/germany_zone_anchor_points.csv`

## Assignment priority

The intended assignment order is:
1. manual override by `Bus_id`
2. polygon containment if `germany_tso_zones.geojson` exists
3. direct operator-tag match if the bus metadata names a TSO
4. nearest-zone-anchor fallback if anchor points are provided
5. unresolved status for manual QA

## Output

The frozen reference file is:
- `references/germany_bus_zone_map.csv`

Expected columns:
- `Bus_id`
- `Zone_id`
- `TSO`
- `State`
- `Latitude`
- `Longitude`
- `MappingSource`
- `Confidence`
- `Notes`

## QA expectations

Before the file is treated as final:
- every Germany bus should have a non-empty `Zone_id`
- every assigned zone should be one of the four TSO regions
- visual review should be done on a Germany map
- large border substations and seam buses should be manually checked
