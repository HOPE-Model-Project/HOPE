# `ISONE_PCM_250bus_case`

Case path: `ModelCases/ISONE_PCM_250bus_case`  
Data path: `ModelCases/ISONE_PCM_250bus_case/Data_ISONE_PCM_250bus`

## Dashboard

Interactive dashboard for this case: [HOPE Dashboard](http://127.0.0.1:8050/)

Dashboard note: start it from the repo root with `python tools/hope_dashboard/app.py`, then select `ISONE_PCM_250bus_case` from the case dropdown. The dashboard is pinned to the finalized reference output through `ModelCases/ISONE_PCM_250bus_case/dashboard_output.txt`, which currently points to `output_nocarbon_check`.

## Current Build Summary

This case is a public-data hybrid ISO-NE-like nodal PCM case built on a synthetic 250-bus New England backbone.

- Network source:
  - TAMU EPIGRIDS `Summer90Tight` New England 250-bus MATPOWER case
- Load source:
  - public July 2024 ISO-NE nodal load weights
  - public EIA balancing-authority hourly demand for the ISO-NE load zones
- VRE source:
  - public July 2024 ISO-NE hourly wind and solar production chronology from EIA balancing-authority data
  - shaped at plant level using EIA-860 wind and solar attributes
- Fleet source:
  - EIA-860 operable generators for CT / ME / MA / NH / RI / VT
- Storage source:
  - EIA-860 operable storage plus pumped-storage generators converted to explicit storage

## Model Setup Snapshot

| Setting | Value |
| :-- | :-- |
| `model_mode` | `PCM` |
| `network_model` | `2` (nodal angle-based DC) |
| `unit_commitment` | `0` |
| `transmission_loss` | `0` |
| `carbon_policy` | `0` |
| `clean_energy_policy` | `1` |

Settings file: `ModelCases/ISONE_PCM_250bus_case/Settings/HOPE_model_settings.yml`

## Current Solved Status

| Metric | Value |
| :-- | --: |
| Buses | 250 |
| HOPE zones | 4 |
| Hours | 744 |
| Solve status | `OPTIMAL` |
| Load shedding | `0.0 MWh` over July 2024 |
| Objective | about `2.83345e8` |
| Average NI | about `1585.53 MW` |

Current reference output: `ModelCases/ISONE_PCM_250bus_case/output_nocarbon_check`

## Geography and Mapping Notes

- `Bus_id` is the operating geography for nodal PCM.
- `State` is retained at the bus level for future nodal policy accounting.
- `Zone_id` is currently used mainly as a higher-level grouping layer.
- The dashboard map is not official ISO-NE GIS data.
- The current coordinates are built from:
  - electrical partitioning
  - public city / load-center anchors
  - public load-zone corridor pulls
  - optional OSM transmission substations and high-voltage corridor samples
  - public plant-coordinate blending

## Validation Snapshot

- High-spread July hours are concentrated around:
  - `188`, `189`, `212`, `237`, `236`
- Repeatedly binding constraints are concentrated in:
  - internal `ROP` corridors
  - selected `SENE` corridors
  - a clearer coastal / southern `NNE` pocket
  - a more visible `NNE` to `ROP` interface path
- Persistent basis separation is strongest on:
  - `136` vs `104`
  - `136` vs `164`
  - `136` vs `28`
  - `136` vs `77`
- The case is now suitable for:
  - dashboard-based congestion exploration
  - bus-to-bus basis analysis
  - nodal dispatch and congestion-driver study

## Storage Assumptions

- Battery storage uses public EIA-860 power and energy values where available.
- Pumped hydro is modeled as explicit long-duration storage:
  - `Northfield Mountain`: `7.5` hours
  - `Bear Swamp`: `3028 MWh`
  - `Rocky River (CT)`: `8-hour` fallback

## Policy Note

- The finalized demo settings keep the first-pass state RPS inputs but disable the
  carbon cap (`carbon_policy: 0`).
- This is intentional: the current state carbon-cap inputs were binding enough to
  force excess NI and load shedding in the July 2024 test case, so the no-carbon
  settings are the cleaner default example.

## Current Limitations

- The 250-bus transmission network is still synthetic.
- Generator-to-bus placement is public-data-informed, but not a market replication model.
- Northern corridor realism can still be improved further, especially for Maine-facing stress.

## Reference Files

- Preprocessing notes: `tools/iso_ne_250bus_case_related/references/CASE_DATA_NOTES.md`
- OSM transmission proposal: `tools/iso_ne_250bus_case_related/references/OSM_TRANSMISSION_PROPOSAL.md`
- OSM extraction outputs:
  - `tools/iso_ne_250bus_case_related/references/osm_substations.csv`
  - `tools/iso_ne_250bus_case_related/references/osm_corridor_points.csv`
  - `tools/iso_ne_250bus_case_related/references/osm_interface_portal_summary.csv`
- Source register: `tools/iso_ne_250bus_case_related/references/SOURCE_DATA_REGISTER.csv`
- Validation summary: `tools/iso_ne_250bus_case_related/references/VALIDATION_SUMMARY.md`
