
```@meta
CurrentModule = HOPE
```

# Nomenclature

## Sets and Indices

| Notation | Description |
| :-- | :-- |
| `D` | Demand entities, index `d` |
| `G` | Generators, index `g` |
| `S` | Storage units, index `s` |
| `L` | Lines/corridors, index `l` |
| `I` | Zones, index `i` |
| `N` | Buses/nodes (PCM nodal modes), index `n` |
| `W` | States, index `w` |
| `H` | Hours, index `h` |
| `T` | Representative periods, index `t` |
| `R` | Reserve product set (PCM), e.g., `REG_UP`, `REG_DN`, `SPIN`, `NSPIN` |

## Common Subsets

| Notation | Description |
| :-- | :-- |
| `G_F` | Thermal generators eligible for operating reserves |
| `G_UC` | UC-modeled generators (PCM) |
| `G_RPS` | RPS-eligible generators |
| `G_i` | Generators in zone `i` |
| `G_n` | Generators at bus `n` |
| `S_i` | Storage in zone `i` |
| `S_n` | Storage at bus `n` |
| `S_SD`, `S_LD` | Short-/long-duration storage sets (GTEP representative-day mode) |
| `WER_w` | States that state `w` can export REC to |
| `WIR_w` | States that state `w` can import REC from |

## Key Parameters

| Notation | Description |
| :-- | :-- |
| `P^max_g`, `P^min_g` | Generator max/min power |
| `F^max_l` | Line thermal limit |
| `F^{eff}_l` | Effective line limit after optional angle-difference tightening |
| `AF_{g,h}` | Generator availability factor |
| `CC_g`, `CC_s` | Capacity credits |
| `RPS_w` | State RPS target |
| `ELMT_w` | State emissions cap (carbon policy option A) |
| `ALW_w` | State allowance cap (carbon policy option B) |
| `spin_requirement` | Fractional SPIN requirement (GTEP) |
| `reg_up_requirement`, `reg_dn_requirement`, `spin_requirement`, `nspin_requirement` | PCM reserve requirements (fraction of load) |
| `delta_reg`, `delta_spin`, `delta_nspin` | Reserve response windows |
| `theta_max` | Optional absolute bus-angle guard in angle-based DCOPF |
| `delta_theta_max_l` | Optional per-line angle-difference limit |
| `PTDF_{l,n}` | PTDF coefficient (line `l`, node `n`) |

## Key Decision Variables

| Notation | Description |
| :-- | :-- |
| `p_{g,h}` | Generator dispatch |
| `f_{l,h}` | Line flow |
| `p^{LS}` | Load shedding |
| `c_{s,h}`, `dc_{s,h}` | Storage charge/discharge |
| `soc_{s,h}` | Storage state of charge |
| `x_g`, `y_l`, `z_s` | GTEP build decisions (gen/line/storage) |
| `x_RET_g` | GTEP retirement decision for eligible existing units |
| `pwe_{g,w,w'}` | REC exported from state `w` to `w'` by unit `g` |
| `pt^{rps}_w` | RPS slack |
| `em^{emis}_w` | Carbon slack |
| `r^{SPIN}_{G,g,h}`, `r^{SPIN}_{S,s,h}` | GTEP SPIN reserves from generator/storage |
| `r^{REG_UP}_{G,g,h}`, `r^{REG_DN}_{G,g,h}`, `r^{SPIN}_{G,g,h}`, `r^{NSPIN}_{G,g,h}` | PCM generator reserve variables |
| `r^{REG_UP}_{S,s,h}`, `r^{REG_DN}_{S,s,h}`, `r^{SPIN}_{S,s,h}`, `r^{NSPIN}_{S,s,h}` | PCM storage reserve variables |
| `theta_{n,h}` | Bus angle (PCM angle-based nodal mode) |
| `inj_{n,h}` | Net bus injection (PCM PTDF mode) |
| `o_{g,h}`, `su_{g,h}`, `sd_{g,h}` | UC commitment/startup/shutdown variables |
