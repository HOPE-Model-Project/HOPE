```@meta
CurrentModule = HOPE.DART
```

# DART

DART is HOPE's lightweight day-ahead and real-time operations module. It is an
in-memory API: callers construct typed Julia inputs and receive typed Julia
results. It does not introduce another case-file schema.

The V1 model contains:

- hourly individual-generator day-ahead SCUC;
- rolling real-time SCED, normally at five-minute resolution;
- lossless nodal PTDF transmission constraints;
- regulation, spinning, and quick-start non-spinning reserves;
- generator N-1 corrective redispatch;
- chronological storage; and
- day-ahead/real-time energy, reserve, and uplift settlements.

The implementation is contained in `src/DART.jl`. The main entry points are
`solve_dart_scuc`, `solve_dart_sced`, `run_dart_rolling`, and
`calculate_dart_settlements`.

## Formulation mapping

| Formulation group | Implementation |
|:--|:--|
| SCUC-OBJ, UC-1--UC-4 | Commitment, startup/shutdown, minimum up/down time, and commitment costs |
| GEN-1--GEN-7, RAMP-1--RAMP-2 | Generator bounds, transition limits, hourly ramps, and reserve headroom |
| REN-1--REN-2 | Time-varying availability; zero-cost curtailment is eliminated algebraically |
| RES-1--RES-5 | Product capability, response time, requirements, and quick-start eligibility |
| STO-1--STO-6 | Charge, discharge, SOC chronology, and reserve-energy deliverability |
| NET-1--NET-4 | Nodal injection, balance, PTDF flow, and line limits |
| SEC-1--SEC-5 | One corrective scenario per eligible generator |
| RT-1--RT-3 | Fixed DA commitment and energy-only real-time ramping |
| COUP-1 | Binding RT dispatch and SOC are carried into the next solve |

V1 deliberately uses system-wide reserve requirements, nodal load shedding,
generator contingencies, and the lossless PTDF network option. Line outages,
zonal transport, demand response, and policy constraints remain outside this
small operational core.

## Minimal example

The ModelCases repository contains `DART_two_bus_example.jl`, a programmatic
example with no generated or committed data files.
