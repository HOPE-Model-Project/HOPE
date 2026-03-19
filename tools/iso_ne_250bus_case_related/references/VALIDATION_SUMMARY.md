# ISO-NE 250-Bus Validation Summary

This note summarizes the current solved behavior of the public-data hybrid
ISO-NE 250-bus nodal PCM case.

## Solve status

- Solver:
  - `Gurobi`
- Status:
  - `OPTIMAL`
- Load shedding:
  - `0.0`
- Objective:
  - about `2.13694e8`

## Current interpretation

The case is now strong enough for:

- nodal congestion analysis
- dashboard exploration
- relative comparison of spread hours, repeated constraints, and bus-to-bus basis

It is still not intended as an exact market replication model.

## Highest spread hours

The latest solve shows the largest nodal LMP spreads around:

- `Hour 188`
- `Hour 189`
- `Hour 212`
- `Hour 237`
- `Hour 236`

These are useful first checkpoints in the dashboard for reviewing whether the
geographic congestion pattern looks plausible.

## Repeatedly binding lines

The most persistent constraints in the latest solve are concentrated in:

- internal `ROP` corridors
- selected internal `SENE` corridors
- a clearer coastal / southern `NNE` pocket
- one visible `NNE` to `ROP` interface path

Representative repeatedly binding lines include:

- `Line 159`: bus `104` to `136` in `ROP`
- `Line 161`: bus `105` to `136` in `ROP`
- `Line 194`: bus `128` to `130` in `NNE`
- `Line 334`: bus `236` to `153` in `NNE`
- `Line 172`: bus `114` to `136` in `ROP`
- `Line 196`: bus `131` to `152` across `NNE` to `ROP`
- `Line 165`: bus `107` to `119` in `ROP`
- `Line 77`: bus `28` to `203` in `SENE`
- `Line 126`: bus `77` to `217` in `SENE`

## Persistent basis pairs

The strongest persistent basis separation in the latest solve is concentrated on:

- `Bus 136` versus `Bus 104`
- `Bus 136` versus `Bus 164`
- `Bus 136` versus `Bus 28`
- `Bus 136` versus `Bus 77`
- `Bus 136` versus `Bus 89`
- `Bus 136` versus `Bus 88`
- `Bus 104` versus `Bus 102`

This points to a recurring CT-to-eastern-MA separation pattern rather than a
uniform region-wide spread pattern.

## Geographic hotspot check

The current congestion hotspots are at least directionally plausible:

- strongest congestion exposure sits in `ROP` buses mapped into Connecticut
- the second cluster is in `SENE`, consistent with eastern Massachusetts /
  Boston-facing stress
- a smaller `NNE` cluster appears around buses `128`, `135`, `137`, `151`,
  `153`, and `236`
- Maine remains present but more muted than the prior pass, while coastal NH
  and the `NNE`-to-`ROP` interface now carry more of the northern story

Remaining limitation:

- Maine congestion is present but weaker than the CT / eastern MA pattern, so
  the northern corridor geometry can still be improved further

## Policy readiness decision

State policy constraints are now active in a conservative first-pass form:

- `carbon_policy = 1`
- `clean_energy_policy = 1`

The current policy files validate the bus-state accounting path without turning
the case into a hard policy stress test.

## Recommended dashboard checks

1. Open `ISONE_PCM_250bus_case` and jump to the top spread hours.
2. Check whether the most stressed lines align with plausible CT / eastern MA /
   Maine / NH pockets.
3. Compare basis across:
   - `136` vs `104`
   - `136` vs `164`
   - `136` vs `28`
   - `136` vs `77`
4. Check whether the `NNE` hotspot around buses `153`, `135`, `151`, and `137`
   looks directionally plausible on the map.
5. Check whether the updated coastal NH pattern around buses `128`, `130`, and
   `135` looks more plausible than the prior pass.
