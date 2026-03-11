# `RTS24_PCM_multizone4_congested_1month_case`

Case path: `ModelCases/RTS24_PCM_multizone4_congested_1month_case`  
Data path: `ModelCases/RTS24_PCM_multizone4_congested_1month_case/Data_RTS24_PCM_full`

## Model Setup Snapshot

| Setting | Value |
| :-- | :-- |
| `model_mode` | `PCM` |
| `unit_commitment` | `1` |
| `network_model` | `3` (nodal PTDF) |
| `operation_reserve_mode` | `2` |
| `flexible_demand` | `1` |
| `clean_energy_policy` | `0` |
| `carbon_policy` | `0` |
| `representative_day!` | `0` |

## System Scale Overview

| Metric | Value |
| :-- | --: |
| Zones | 4 |
| Buses | 24 |
| Existing generators | 33 |
| Thermal generators | 9 |
| VRE generators | 15 |
| Existing storage units | 5 |
| DR resources | 4 |
| Existing transmission lines | 38 |
| Inter-zone lines | 17 |
| Unique inter-zone corridors | 5 |
| Existing generator capacity | 3,406.0 MW |
| Existing storage power/energy | 153.1 MW / 612.5 MWh |
| Sum of zonal peak demands | 2,850.0 MW |
| Hourly load profile rows | 744 |

## Existing Capacity Mix Highlights

| Type | Units | Existing Capacity (MW) |
| :-- | --: | --: |
| SolarPV | 12 | 1,362.0 |
| Hydro | 9 | 960.0 |
| NGCC | 1 | 400.0 |
| Coal | 8 | 384.0 |
| WindOn | 3 | 300.0 |

## Zone-Level Network View

![RTS24 multizone4 zone network map](assets/modelcases_rts24_multizone4_zone_map.svg)

## Nodal-Level Network View (24 Buses)

| Nodal metric | Value |
| :-- | --: |
| Buses per zone | 6 in each of Z1-Z4 |
| Intra-zone lines | 21 |
| Inter-zone tie lines | 17 |
| Intra-zone transfer capacity sum | 7,500 MW |
| Inter-zone transfer capacity sum | 2,130 MW |

![RTS24 multizone4 nodal network map](assets/modelcases_rts24_multizone4_nodal_map.svg)

Nodal note: this figure is topology-accurate to the case connectivity and line capacities; node labels are bus IDs, and line labels are linedata row IDs.
