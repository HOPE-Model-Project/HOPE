# `USA_64zone_GTEP_case`

Case path: `ModelCases/USA_64zone_GTEP_case`  
Data path: `ModelCases/USA_64zone_GTEP_case/Data_USA64_GTEP`

## Model Setup Snapshot

| Setting | Value |
| :-- | :-- |
| `model_mode` | `GTEP` |
| `solver` | `gurobi` |
| `aggregated!` | `0` |
| `endogenous_rep_day` | `0` |
| `external_rep_day` | `1` |
| `planning_reserve_mode` | `0` |
| `operation_reserve_mode` | `0` |
| `transmission_expansion` | `1` |
| `carbon_policy` | `0` |
| `clean_energy_policy` | `0` |

## System Scale Overview

| Metric | Value |
| :-- | --: |
| Zones | 64 |
| Transmission regions | 11 |
| Existing generators | 667 |
| Candidate generators | 830 |
| Existing transmission lines | 122 |
| Candidate transmission lines | 140 |
| Existing generator capacity | 1,178,149.1 MW |
| Candidate generator capacity | 35,866,189.1 MW |
| Existing line capacity sum | 209,348.0 MW |
| Sum of zonal peak demands | 777,401.0 MW |
| Modeled time-series rows | 480 |
| Solved total system cost | \$61,958,382,751.4 |

## HOPE Results Summary

Note: this page reports HOPE run outputs only. Cross-model comparisons are omitted because input assumptions are not aligned.

### Transmission Buildout Summary

| Metric | Value |
| :-- | --: |
| HOPE built corridors (MW > 0) | 81 |
| HOPE total buildout | 521,234.2 MW |
| Existing transmission capacity sum | 209,348.0 MW |

| Corridor | HOPE build (MW) |
| :-- | --: |
| `z7-z35` | 63673.0 |
| `z8-z35` | 59726.1 |
| `z8-z48` | 54833.2 |
| `z7-z33` | 48258.4 |
| `z18-z46` | 37987.8 |
| `z18-z43` | 29572.1 |
| `z33-z39` | 20798.9 |
| `z47-z63` | 18646.2 |
| `z4-z43` | 16972.0 |
| `z9-z35` | 14350.8 |

### Generation Build Summary by Technology

| Technology | HOPE final (MW) | HOPE new build (MW) |
| :-- | --: | --: |
| `WindOn` | 443258.9 | 292119.1 |
| `SolarPV` | 187472.6 | 76590.7 |
| `NGCC` | 317250.9 | 0.0 |
| `WindOff` | 29.3 | 0.0 |
| `Hydro` | 76024.2 | 0.0 |
| `Coal` | 197052.7 | 0.0 |
| `NGCT` | 152777.6 | 0.0 |
| `Thermal` | 73900.1 | 0.0 |
| `NuC` | 99092.6 | 0.0 |

## Network Map: Existing Corridors

![USA64 existing transmission network map](assets/modelcases_usa64_base_network_map.svg)

## Network Map: Optimized Buildouts

![USA64 optimized transmission buildout map](assets/modelcases_usa64_buildout_map.svg)

Map notes: boundaries follow EPA IPM v6 regions; corridor widths scale with MW.
The buildout map overlays HOPE-optimized expansion capacities from `output/line.csv`.
