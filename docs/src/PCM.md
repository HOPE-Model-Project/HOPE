## Overview

The production cost model (PCM) simulates chronological operations given fixed infrastructure.
PCM currently defaults to full-hourly resolution; representative-day reduction is planned for a future update.

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

Expanded form used in code:

```math
\begin{aligned}
\min \Gamma =\;
&\sum_{t\in T}N_t\sum_{g\in G}\sum_{h\in H_t} VCG_g\,p_{g,h}
+ \sum_{t\in T}N_t\sum_{s\in S}\sum_{h\in H_t} VCS_s\,(c_{s,h}+dc_{s,h}) \\
&+ \sum_{t\in T}N_t\sum_{i\in I}\sum_{h\in H_t} VOLL\,p^{LS}_{i,h} \\
&+ \mathbb{1}_{UC}\sum_{t\in T}N_t\sum_{g\in G^{UC}}\sum_{h\in H_t} STC_g\,P^{max}_g\,su_{g,h} \\
&+ \mathbb{1}_{FD}\sum_{t\in T}N_t\sum_{r\in R}\sum_{h\in H_t} DRC_r\,(dr^{DF}_{r,h}+dr^{PB}_{r,h}) \\
&+ \mathbb{1}_{RPS}\,PT^{rps}\sum_{w\in W} pt^{rps}_w
+ \mathbb{1}_{CO2}\,PT^{emis}\sum_{w\in W} em^{emis}_w
\end{aligned}
```

where indicators $\mathbb{1}_{UC}$, $\mathbb{1}_{FD}$, $\mathbb{1}_{RPS}$, $\mathbb{1}_{CO2}\in\{0,1\}$ are controlled by `unit_commitment`, `flexible_demand`, `clean_energy_policy`, and `carbon_policy`. In current full-hourly PCM runs, `T={1}`, `H_1=H`, and `N_1=1`.

## Constraint Blocks

Constraint IDs in code comments use the same labels below (for example, `PCM-C1.2` in `src/PCM.jl`).

### 1. [PCM-C1] Power balance and network by `network_model`

#### [PCM-C1.0] `network_model = 0` (copper plate)

One system balance per hour:

```math
\sum_g p_{g,h} + \sum_s (dc_{s,h} - c_{s,h}) + \sum_i NI_{i,h}
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
-F^{max}_l \le f_{l,h} \le F^{max}_l
```

#### [PCM-C1.2] `network_model = 2` (nodal DCOPF, angle-based)

Nodal balance per bus `n`:

```math
\sum_{g \in G_n} p_{g,h}
+ \sum_{s \in S_n}(dc_{s,h}-c_{s,h})
- \sum_{l \in LS_n} f_{l,h}
+ \sum_{l \in LR_n} f_{l,h}
+ NI_{n,h}
= Load_{n,h}
```

In current code, nodal load and interchange are allocated from zone-level terms using bus load shares.

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
inj_{n,h} = \sum_{g \in G_n} p_{g,h}
+ \sum_{s \in S_n}(dc_{s,h}-c_{s,h})
+ NI_{n,h} - Load_{n,h}
```

Injection balance:

```math
\sum_n inj_{n,h}=0
```

PTDF flow mapping:

```math
f_{l,h} = \sum_n PTDF_{l,n}\,inj_{n,h}
```

Line flow bounds in PTDF mode:

```math
-F^{eff}_l \le f_{l,h} \le F^{eff}_l
```

`F^{eff}_l` is used for PTDF mode and equals thermal limit by default; it can be tightened by angle-difference limits via:

```math
F^{eff}_l = \min\left(F^{max}_l,\; |B_l|\Delta\theta^{max}_l\right)
```

### 2. [PCM-C2] Operating reserve

Reserve variables:

- Thermal generators: $r^{REG\uparrow}_{G,g,h}$, $r^{REG\downarrow}_{G,g,h}$, $r^{SPIN}_{G,g,h}$, $r^{NSPIN}_{G,g,h}$
- Storage: $r^{REG\uparrow}_{S,s,h}$, $r^{REG\downarrow}_{S,s,h}$, $r^{SPIN}_{S,s,h}$, $r^{NSPIN}_{S,s,h}$

System requirements by mode:

- Mode `1`: $REG^\uparrow$, $REG^\downarrow$, $SPIN$ active; $NSPIN$ fixed to zero
- Mode `2`: $REG^\uparrow$, $REG^\downarrow$, $SPIN$, $NSPIN$ all active
- Mode `0`: all reserve variables fixed to zero

Thermal eligibility:

- Reserve requirements are supplied by thermal units ($G^{F}$) and storage.
- Non-thermal generators are forced to zero reserve provision.

Headroom/downward room and reserve capability limits are enforced with UC-aware variants for units in $G^{UC}$.

Ramp-response limits link reserve products to response windows:

```math
r \le RampRate \cdot P^{max} \cdot \Delta
```

with product-specific windows $\Delta \in \{\Delta^{REG}, \Delta^{SPIN}, \Delta^{NSPIN}\}$.

### 3. [PCM-C3] Generator and UC blocks

Base dispatch limits use energy plus upward reserve terms.

If UC is enabled:

- commitment state $o_{g,h}$
- startup/shutdown $su_{g,h},\;sd_{g,h}$
- minimum-run variable $pmin_{g,h}$
- transition, min up/down, and UC-adjusted ramp constraints.

### 4. [PCM-C4] Storage blocks

- Charge and discharge are co-limited with downward/upward reserve, respectively.
- SOC dynamics:

```math
soc_{s,h} = soc_{s,h-1} + \eta^{ch}_s c_{s,h} - dc_{s,h}/\eta^{dis}_s
```

- Cyclic yearly SOC closure.
- Current code enforces both:
  - `soc[s,1] = soc[s,H[end]]`
  - `soc[s,H[end]] = 0.5 * SECAP[s]`
- Reserve deliverability from SOC over response windows:

```math
r_{S,s,h}\cdot \Delta \le soc_{s,h}
```

### 5. [PCM-C5] RPS and carbon policies

RPS uses $pwe_{g,w,w^\prime}$ (REC exports from state $w$ to $w^\prime$), with:

- state renewable generation accounting $pw_{g,w}$
- REC export/import feasibility
- state RPS balance with slack $pt^{rps}_w$.

Carbon policy options:

- `carbon_policy = 1`: state annual emissions cap with slack
- `carbon_policy = 2`: state allowance cap and allowance-emission balance with slack.
- `carbon_policy = 0`: no carbon-policy constraints (no carbon slack variable/constraints are added).

Code expression for annual emissions accounting:

```math
StateCarbonEmission_w =
\sum_{t\in T}N_t\sum_{i\in I_w}\sum_{g\in G_i\cap G^F}\sum_{h\in H_t} EF_g\,p_{g,h}
```

### 6. [PCM-C6] Flexible demand

Current code uses the backlog load-shifting formulation over DR resources `r \in R`:

```math
b_{r,h} = b_{r,h-1} + dr^{DF}_{r,h} - \eta^{DR}_r\,dr^{PB}_{r,h}
```

Boundary conditions per period:

```math
b_{r,h_0(t)} = 0,\quad b_{r,h_{end}(t)} = 0
```

Bounds:

```math
dr^{DF}_{r,h} \le DR^{DF,max}_{r,h},\quad
dr^{PB}_{r,h} \le DR^{PB,max}_{r,h},\quad
b_{r,h} \le \tau^{DR}_r\cdot DR^{DF,peak}_r
```

`DR^{opt}_{i,h}` enters power balance as net load shift per zone:

```math
DR^{opt}_{i,h} = \sum_{r\in R_i}\left(dr^{PB}_{r,h} - dr^{DF}_{r,h}\right)
```

## LMP and Congestion Outputs

When duals are available, PCM writes:

- zonal/nodal prices
- nodal price decomposition (energy, congestion, loss)
- line shadow prices and congestion rent
- optional summary analytics in `output/Analysis/Summary_*.csv` when `summary_table = 1`.

For `unit_commitment = 1` MILP runs, set `write_shadow_prices = 1` to trigger fixed-LP re-solve for dual recovery.
