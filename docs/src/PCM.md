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

When `transmission_loss = 1`, HOPE adds endpoint-allocated line losses to the zonal balance:

```math
\mathrm{ZoneLineLoss}_{i,h} = \frac{1}{2}\sum_{l \in LS_i \cup LR_i} loss_{l,h},
\qquad
loss_{l,h} = \rho_l |f_{l,h}|
```

Positive flow follows the input row from `From_zone`/`from_bus` to
`To_zone`/`to_bus`. Corridor flow bounds are:

```math
-F^{reverse}_l \le f_{l,h} \le F^{forward}_l
```

#### [PCM-C1.2] `network_model = 2` (nodal DCOPF, angle-based)

Nodal balance per bus `n`:

```math
\sum_{g \in G_n} p_{g,h}
+ \sum_{s \in S_n}(dc_{s,h}-c_{s,h})
- \sum_{l \in LS_n} f_{l,h}
+ \sum_{l \in LR_n} f_{l,h}
+ NI^{actual}_{n,h}
= Load_{n,h}
```

When `transmission_loss = 1`, HOPE adds endpoint-allocated line losses to each nodal balance:

```math
\mathrm{NodeLineLoss}_{n,h} = \frac{1}{2}\sum_{l \in LS_n \cup LR_n} loss_{l,h},
\qquad
loss_{l,h} = \rho_l |f_{l,h}|
```

Nodal load comes from `load_timeseries_nodal`. Nodal interchange uses direct bus-level input from `ni_timeseries_nodal` when provided; otherwise HOPE falls back to allocating system NI from zone-level terms using bus load shares. In the ISO-NE 250-bus example, that nodal NI file is built from official interface chronology, scaled to the synthetic case NI magnitude, and blended with a small load-share balancing tail so the nodal case remains solvable without smearing NI uniformly across the system.

When both `ni_timeseries_nodal_target` and `ni_timeseries_nodal_cap` are provided, HOPE instead treats nodal NI as a decision variable bounded between the target and cap profiles. Deviation from the target profile is penalized in the objective:

```math
NI^{actual}_{n,h} - NI^{target}_{n,h}
= dev^{+}_{n,h} - dev^{-}_{n,h}
```

```math
\mathrm{NIDeviationPenalty}
= PT^{NI}_{dev}\sum_{t\in T}N_t\sum_{h\in H_t}\sum_{n\in N}
\left(dev^{+}_{n,h}+dev^{-}_{n,h}\right)
```

DC line physics:

```math
f_{l,h} = B_l(\theta_{from(l),h} - \theta_{to(l),h})
```

All transport, angle-based, and PTDF network formulations apply directional
line limits:

```math
-F^{reverse}_l \le f_{l,h} \le F^{forward}_l
```

Positive flow follows the input row from `From_zone`/`from_bus` to
`To_zone`/`to_bus`. For symmetric branches, the two ratings are equal.

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
+ NI^{actual}_{n,h} - Load_{n,h}
```

Injection balance:

```math
\sum_n inj_{n,h}=0
```

PTDF flow mapping:

```math
f_{l,h} = \sum_n PTDF_{l,n}\,inj_{n,h}
```

PTDF mode in the current HOPE release is lossless. Keep `transmission_loss = 0` when `network_model = 3`.

Line flow bounds in PTDF mode:

```math
-F^{reverse,eff}_l \le f_{l,h} \le F^{forward,eff}_l
```

Each effective directional rating equals its corresponding thermal limit by
default and can be tightened independently by an angle-difference limit:

```math
F^{d,eff}_l =
\min\left(F^{d}_l,\; |B_l|\Delta\theta^{max}_l\right),
\qquad d\in\{forward,reverse\}
```

### 2. [PCM-C2] Operating reserve

Reserve feasibility is enforced in three layers:

1. **System requirement constraints** — total reserve from all eligible resources must meet the hourly system requirement for each product.
2. **Resource capability/eligibility constraints** — each generator or storage unit is bounded by its rated reserve headroom and ramp response window. Only thermal generators ($G^F$) and storage are eligible; non-thermal generators are forced to zero.
3. **Physical headroom, ramp-response, and storage energy deliverability constraints** — generators must have sufficient dispatch margin; storage must have sufficient stored energy (upward) or charging headroom (downward) to deliver the committed reserve over the response window.

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

Note: the same response window $\Delta^{REG}$ applies to both $REG^\uparrow$ and $REG^\downarrow$:

```math
\Delta^{REG\uparrow} = \Delta^{REG\downarrow} = \Delta^{REG}
```

### 3. [PCM-C3] Generator and UC blocks

Base dispatch limits use energy plus upward reserve terms.

If UC is enabled:

- commitment state $o_{g,h}$ (integer units online, or continuous relaxation)
- startup/shutdown counts $su_{g,h},\;sd_{g,h}$
- minimum-run variable $pmin_{g,h}$, defined by equality:

```math
pmin_{g,h} = (1 - FOR_g)\,P^{min\text{-}unit}_g\,o_{g,h}
```

This equality (rather than inequality) ensures that committed units always face a binding minimum online output, so downstream headroom and ramp constraints are physically meaningful.

- state transition, minimum up/down time, and UC-adjusted ramp constraints.

### 4. [PCM-C4] Storage blocks

- Discharge is co-limited with upward reserve; charge is co-limited with downward reserve:

```math
dc_{s,h} + ReserveUp_{S,s,h} \le SD_s\,SCAP_s
```
```math
c_{s,h} + ReserveDn_{S,s,h} \le SC_s\,SCAP_s
```

- SOC dynamics:

```math
soc_{s,h} = soc_{s,h-1} + \eta^{ch}_s c_{s,h} - dc_{s,h}/\eta^{dis}_s
```

- Cyclic yearly SOC closure.
- Current code enforces both:
  - `soc[s,1] = soc[s,H[end]]`
  - `soc[s,H[end]] = 0.5 * SECAP[s]`

- **Reserve energy deliverability** over response windows:
  - *Upward* reserve (discharge) requires sufficient stored energy:

  ```math
  r^{REG\uparrow}_{S,s,h}\cdot\Delta^{REG} \le soc_{s,h}
  ```
  ```math
  r^{SPIN}_{S,s,h}\cdot\Delta^{SPIN} \le soc_{s,h}
  ```
  ```math
  r^{NSPIN}_{S,s,h}\cdot\Delta^{NSPIN} \le soc_{s,h}
  ```

  - *Downward* regulation reserve (charge) requires sufficient charging headroom:

  ```math
  r^{REG\downarrow}_{S,s,h}\cdot\Delta^{REG} \le SECAP_s - soc_{s,h}
  ```

  A fully charged battery ($soc = SECAP$) has zero charging headroom and therefore cannot provide downward regulation even though it has maximum stored energy.

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

### 5b. [PCM-C1/C3] Load shedding

Load shedding is modeled at the **zone** level using variable $p^{LS}_{i,h}$, bounded by the native zonal demand:

```math
0 \le p^{LS}_{i,h} \le Load^{native}_{i,h}
```

In nodal network modes (`network_model = 2` or `3`), zonal shedding is allocated to individual buses through the bus load-share weight (`bus_zone_weight`), so `NodeLoad[n,h]` is reduced proportionally across all buses in the zone. A future nodal-level shedding formulation with explicit $p^{LS}_{n,h}$ per bus is not yet implemented.

### 5c. [PCM-C1.NI] Net interchange

Net interchange $NI_{i,h}$ (zonal) or $NodeNI_{n,h}$ (nodal) represents exogenous scheduled imports/exports. It is **optional**: if no NI data is provided, it defaults to zero and has no effect on the solution. Three representations are supported:

- **Copper-plate / zonal** (`network_model = 0` or `1`): zonal $NI_{i,h}$ allocated from system-level NI by zone peak-load share.
- **Fixed nodal NI** (nodal modes with `ni_timeseries_nodal`): direct bus-level values, treated as parameters.
- **Flexible nodal NI** (nodal modes with both `ni_timeseries_nodal_target` and `ni_timeseries_nodal_cap`): nodal NI becomes a decision variable bounded between the target and cap profiles; deviations from target are penalized in the objective.

### 6. [PCM-C6] Flexible demand

The DR operating cost is charged on **both** defer and payback actions:

```math
C^{DR} = \sum_{t\in T}N_t\sum_{r\in R}\sum_{h\in H_t} DRC_r\,(dr^{DF}_{r,h}+dr^{PB}_{r,h})
```

This reflects that both shifting load out ($dr^{DF}$) and recovering it ($dr^{PB}$) incur dispatch cost for the DR resource.

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

### Price Sign Convention

HOPE exports PCM prices as the **marginal objective change from a +1 MW increase in load**. That is the economic quantity users typically mean by LMP.

Important implementation note:

- The raw sign of `dual(constraint)` is **not** stable across algebraically equivalent equality constraints.
- In particular, multiplying an equality row by `-1` can flip the raw dual sign without changing the economics.

So HOPE now applies a formulation-specific sign rule when writing prices:

- `network_model = 0`, `1`, or `2`:
  - power balance is written in `supply == load` form
  - exported price = `dual(balance_constraint)`
- `network_model = 3`:
  - the reported nodal price comes from the PTDF injection-definition row `inj == supply - load`
  - exported price = `-dual(PTDFInjDef_con)`

This rule is now regression-tested against two independent checks:

- `shadow_price`
- a direct `+1 MW` load perturbation test

The regression is implemented in `test/test-lmp-sign-regression.jl` and currently covers:

- the ISO-NE 250-bus nodal angle case
- the RTS24 nodal PTDF case

So the sign convention is now tied to the **formulation family**, not to a specific case's historical behavior.
