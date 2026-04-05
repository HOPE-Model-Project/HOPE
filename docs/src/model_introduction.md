
```@meta
CurrentModule = HOPE
```

# Model Overview
HOPE currently supports two operational model modes:

1. `GTEP`: generation and transmission expansion planning
2. `PCM`: production cost model (system operation)

Planned future modes:

1. `OPF` (under development)
2. `DART` (under development)

## Shared Modeling Features

Both `GTEP` and `PCM` support:

- RPS policy on/off via `clean_energy_policy` with renewable credit trading variable `pwe`
- Carbon policy options via `carbon_policy`:
  - `0`: off
  - `1`: state emissions cap with penalty slack
  - `2`: state allowance/cap-and-trade style with penalty slack
- Flexible demand (DR) on/off via `flexible_demand`
- Optional MILP fixed-LP dual recovery via `write_shadow_prices = 1`

## GTEP-Specific Modes

- `inv_dcs_bin`:
  - `1`: binary investment/retirement decisions (MILP)
  - `0`: relaxed investment decisions (LP relaxation)
- `planning_reserve_mode`:
  - `0`: off
  - `1`: system-level RA
  - `2`: zonal RA
- `operation_reserve_mode`:
  - `0`: off
  - `1`: SPIN reserve only
- Storage chronology:
  - Full-year mode (`endogenous_rep_day = 0` and `external_rep_day = 0`): cyclic SOC wrap across hour 8760 -> hour 1
  - Representative-day mode (`endogenous_rep_day = 1` or `external_rep_day = 1`): short-duration storage uses day anchors; long-duration storage links across representative periods

## PCM-Specific Modes

- `unit_commitment`:
  - `0`: no UC
  - `1`: integer UC (MILP)
  - `2`: convexified UC
- `network_model`:
  - `0`: no network constraints (copper plate)
  - `1`: zonal transport
  - `2`: nodal DCOPF (angle-based)
  - `3`: nodal DCOPF (PTDF-based)
- `operation_reserve_mode`:
  - `0`: off
  - `1`: REG + SPIN
  - `2`: REG + SPIN + NSPIN
- `summary_table`:
  - `1`: write summary analytics to `output/Analysis/Summary_*.csv`


