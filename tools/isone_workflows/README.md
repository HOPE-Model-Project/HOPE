# ISO-NE Workflows

This folder contains runnable workflow scripts for the finalized ISO-NE 250-bus case.

- `run_isone_pcm_scenario.jl`: solve the ISO-NE case with selected settings/output path
- `prepare_isone_flexible_ni.py`: generate flexible nodal NI target/cap files
- `apply_isone_internal_supply_adders.py`: apply retained internal-supply calibration adders
- `recalibrate_isone_gas_fleet.py`: apply the optional gas-fleet recalibration spec
- `scorecard_isone_july_2024.py`: build the July 2024 ISO-NE scorecard
- `score_isone_osm_seams.py`: build the OSM seam/corridor scorecard

Shared builders, references, and raw-source inputs remain under `tools/iso_ne_250bus_case_related/`.
