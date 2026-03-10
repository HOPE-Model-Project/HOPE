## Overview

The production cost model (PCM) simulates chronological operations given fixed infrastructure.

Model class by configuration:

- `unit_commitment = 0`: LP (no UC binaries)
- `unit_commitment = 1`: MILP (integer UC)
- `unit_commitment = 2`: LP relaxation of UC

If `unit_commitment = 1` and `write_shadow_prices = 1`, HOPE solves MILP first, then fixes discrete variables and re-solves LP to recover dual/LMP outputs.

## Active Mode Switches

- `network_model`:
  - `0`: no network constraints (copper plate)
  - `1`: zonal transport
  - `2`: nodal DCOPF angle-based
  - `3`: nodal DCOPF PTDF-based
- `operation_reserve_mode`:
  - `0`: off
  - `1`: REG + SPIN
  - `2`: REG + SPIN + NSPIN
- `clean_energy_policy` (`0`/`1`)
- `carbon_policy` (`0`/`1`/`2`)
- `flexible_demand` (`0`/`1`)

# Problem Formulation

## Objective

```math
\min \; C^{startup} + C^{op}_{gen} + C^{op}_{sto} + C^{DR} + C^{LS} + C^{RPS\_pen} + C^{CO2\_pen}
```

with startup cost active only when UC is enabled.

## Constraint Blocks

Constraint IDs in code comments use the same labels below (for example, `PCM-C1.2` in `src/PCM.jl`).

### 1. [PCM-C1] Power balance and network by `network_model`

#### [PCM-C1.0] `network_model = 0` (copper plate)

One system balance per hour:

```math
\sum_g p_{g,h} + \sum_s (dc_{s,h} - c_{s,h})
= \sum_i Load_{i,h} + \sum_i DR^{opt}_{i,h} - \sum_i p^{LS}_{i,h}
```

No transmission constraints are enforced.

#### [PCM-C1.1] `network_model = 1` (zonal transport)

Zonal balance:

```math
\sum_{g \in G_i} p_{g,h}
+ \sum_{s \in S_i}(dc_{s,h}-c_{s,h})
- \sum_{l \in LS_i} f_{l,h}
+ \sum_{l \in LR_i} f_{l,h}
+ NI_{i,h}
= Load_{i,h} + DR^{opt}_{i,h} - p^{LS}_{i,h}
```

Corridor flow bounds:

```math
-F^{eff}_l \le f_{l,h} \le F^{eff}_l
```

#### [PCM-C1.2] `network_model = 2` (nodal DCOPF, angle-based)

Nodal balance per bus `n`:

```math
\sum_{g \in G_n} p_{g,h}
+ \sum_{s \in S_n}(dc_{s,h}-c_{s,h})
- \sum_{l \in LS_n} f_{l,h}
+ \sum_{l \in LR_n} f_{l,h}
= Load_{n,h} - p^{LS}_{n,h}
```

DC line physics:

```math
f_{l,h} = B_l(\theta_{from(l),h} - \theta_{to(l),h})
```

Reference angle and optional bounds:

```math
\theta_{ref,h}=0,\quad -\theta^{max} \le \theta_{n,h} \le \theta^{max}
```

Optional per-line angle-difference limits (if enabled in data):

```math
-\Delta\theta^{max}_l \le \theta_{from(l),h} - \theta_{to(l),h} \le \Delta\theta^{max}_l
```

#### [PCM-C1.3] `network_model = 3` (nodal DCOPF, PTDF-based)

Nodal injection definition:

```math
inj_{n,h} = \sum_{g \in G_n} p_{g,h} + \sum_{s \in S_n}(dc_{s,h}-c_{s,h}) - Load_{n,h} + p^{LS}_{n,h}
```

Injection balance:

```math
\sum_n inj_{n,h}=0
```

PTDF flow mapping:

```math
f_{l,h} = \sum_n PTDF_{l,n}\,inj_{n,h}
```

and `-F^{eff}_l <= f_{l,h} <= F^{eff}_l`.

`F^{eff}_l` equals thermal limit by default and can be tightened by angle-difference limits via:

```math
F^{eff}_l = \min\left(F^{max}_l,\; |B_l|\Delta\theta^{max}_l\right)
```

### 2. [PCM-C2] Operating reserve

Reserve variables:

- Thermal generators: `r_G_REG_UP`, `r_G_REG_DN`, `r_G_SPIN`, `r_G_NSPIN`
- Storage: `r_S_REG_UP`, `r_S_REG_DN`, `r_S_SPIN`, `r_S_NSPIN`

System requirements by mode:

- Mode `1`: REG_UP, REG_DN, SPIN active; NSPIN fixed to zero
- Mode `2`: REG_UP, REG_DN, SPIN, NSPIN all active
- Mode `0`: all reserve variables fixed to zero

Thermal eligibility:

- Reserve requirements are supplied by thermal units (`G_F`) and storage.
- Non-thermal generators are forced to zero reserve provision.

Headroom/downward room and reserve capability limits are enforced with UC-aware variants for units in `G_UC`.

Ramp-response limits link reserve products to response windows:

```math
r \le RampRate \cdot P^{max} \cdot \Delta
```

for `Delta = delta_reg`, `delta_spin`, `delta_nspin`.

### 3. [PCM-C3] Generator and UC blocks

Base dispatch limits use energy plus upward reserve terms.

If UC is enabled:

- commitment state `o`
- startup/shutdown `su`, `sd`
- minimum-run variable `pmin`
- transition, min up/down, and UC-adjusted ramp constraints.

### 4. [PCM-C4] Storage blocks

- Charge and discharge are co-limited with downward/upward reserve, respectively.
- SOC dynamics:

```math
soc_{s,h} = soc_{s,h-1} + \eta^{ch}_s c_{s,h} - dc_{s,h}/\eta^{dis}_s
```

- Cyclic yearly SOC closure.
- Reserve deliverability from SOC over response windows:

```math
r_{S,s,h}\cdot \Delta \le soc_{s,h}
```

### 5. [PCM-C5] RPS and carbon policies

RPS uses `pwe[g,w,w']` (REC exports from state `w` to `w'`), with:

- state renewable generation accounting `pw`
- REC export/import feasibility
- state RPS balance with slack `pt_rps[w]`.

Carbon policy options:

- `carbon_policy = 1`: state annual emissions cap with slack
- `carbon_policy = 2`: state allowance cap and allowance-emission balance with slack.

### 6. [PCM-C6] Flexible demand

If enabled, DR variables/constraints are added to zone-level load representation and objective penalty terms.

## LMP and Congestion Outputs

When duals are available, PCM writes:

- zonal/nodal prices
- nodal price decomposition (energy, congestion, loss)
- line shadow prices and congestion rent
- optional summary analytics in `output/Analysis/Summary_*.csv` when `summary_table = 1`.
