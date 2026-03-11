```@meta
CurrentModule = HOPE
```

# Nomenclature

## Sets and Indices

| Notation | Description |
| :-- | :-- |
| $D$ | Set of demand nodes, index $d$ |
| $G$ | Set of all types of generating units, index $g$ |
| $H$ | Set of hour/representative hour, index $h$ |
| $K$ | Set of operation reserve types (mode-dependent): PCM uses $\{REG^\uparrow, REG^\downarrow, SPIN, NSPIN\}$; current GTEP uses $\{SPIN\}$ |
| $T$ | Set of time periods (e.g., representative days of seasons), index $t$ |
| $R$ | Set of DR resources (backlog load-shifting formulation), index $r$ |
| $S$ | Set of storage units, index $s$ |
| $I,\,J$ | Set of zones, index $i,\,j$ |
| $L$ | Set of transmission corridors, index $l$ |
| $W$ | Set of states, index $w/w^\prime$ |

## Subsets

| Notation | Description |
| :-- | :-- |
| $D_i$ | Set of demand nodes located in zone $i$, subset of $D$ |
| $G^{PV},\,G^{W},\,G^{F}$ | Sets of solar, wind, and dispatchable generators, respectively, subsets of $G$ |
| $G_l^{L}$ | Set of generators linked to line $l$, subset of $G$ |
| $G_i$ | Set of generating units connected to zone $i$, subset of $G$ |
| $G^{E}/G^{+}$ | Set of existing/candidate generation units, index $g$, subset of $G$ |
| $G^{RET}$ | Set of existing generators eligible for retirement, index $g$, subset of $G^{E}$ |
| $G^{RPS}$ | Set of generators eligible for RPS, index $g$, subset of $G$ |
| $G^{MR}$ | Set of must-run generators, index $g$, subset of $G$ |
| $H_t$ | Set of hours in time period (day) $t$, index $h$, subset of $H$ |
| $R_i$ | Set of DR resources connected to zone $i$ (backlog form), subset of $R$ |
| $S^{E}/S^{+}$ | Set of existing/candidate storage units, subset of $S$ |
| $S^{SD}/S^{LD}$ | Set of short-duration/long-duration storage units, subset of $S$ |
| $S_i$ | Set of storage units connected to zone $i$, subset of $S$ |
| $L^{E}/L^{+}$ | Set of existing/candidate transmission corridors |
| $LS_i/LR_i$ | Set of sending/receiving corridors for zone $i$, subset of $L$ |
| $I_w$ | Set of zones in state $w$, subset of $I$ |
| $WIR_w$ | Set of states that state $w$ can import renewable credits from (excluding itself), subset of $W$ |
| $WER_w$ | Set of states that state $w$ can export renewable credits to (excluding itself), subset of $W$ |

## Parameters

| Notation | Unit | Description |
| :-- | :-- | :-- |
| $AF_{g,h}$ | unitless | Availability factor of generator $g$ in hour $h$, $g\in G$ |
| $ALW_w$ | ton | Total carbon allowance in one year in state $w$ |
| $CC_{g/s}$ | unitless | Capacity credit of resource $g/s$ |
| $DRC_r$ | USD/MW | DR operating cost coefficient for DR resource $r$ |
| $DR_t[h,i(r)]$ | unitless | Zonal DR availability profile used by DR resource $r$ in hour $h$ |
| $DR_r^{max}$ | MW | Maximum DR power of resource $r$ |
| $DR_{r,h}^{DF/PB,max}$ | MW | Deferrable/payback DR upper bounds of resource $r$ in hour $h$ |
| $ELMT_w$ | ton | Carbon emission limits at state $w$ |
| $F_l^{max}$ | MW | Maximum capacity of transmission corridor/line $l$ |
| $\tilde{I}_g$ | MUSD | Investment cost of candidate generator $g$ |
| $\tilde{I}_l$ | MUSD | Investment cost of transmission line $l$ |
| $\tilde{I}_s$ | MUSD | Investment cost of storage unit $s$ |
| $IBG$ | MUSD | Total investment budget for generators |
| $IBL$ | MUSD | Total investment budget for transmission lines |
| $IBS$ | MUSD | Total investment budget for storage |
| $N_t$ | day | Number of time period (day) $t$ per year; with full 8760-hour run, $N_t=1$ |
| $NI_{i,h}$ | MW | Net interchange in zone $i$ in hour $h$ (default 0) |
| $P_{d,h}$ | MW | Active power demand at node $d$ |
| $PK$ | MW | Peak power demand |
| $PK_i^{zone}$ | MW | Peak power demand of zone $i$ |
| $PT^{rps}$ | USD/MWh | RPS violation penalty |
| $PT^{emis}$ | USD/t | Carbon emission violation penalty |
| $P_g^{min}/P_g^{max}$ | MW | Minimum/maximum power generation of unit $g$ |
| $R_h^{req,k}$ | MW | Operation reserve $k$ requirement in hour $h$ |
| $RPS_w$ | unitless | Renewable portfolio standard in state $w$ |
| $RM$ | unitless | Planning reserve margin |
| $SCAP_s$ | MW | Maximum charging/discharging power capacity of storage unit $s$ |
| $SECAP_s$ | MWh | Maximum energy capacity of storage unit $s$ |
| $SC_s/SD_s$ | unitless | Maximum rates of charging/discharging (default 1) |
| $VCG_g$ | USD/MWh | Variable cost of generation unit $g$ |
| $VCS_s$ | USD/MWh | Variable (degradation) cost of storage unit $s$ |
| $VOLL$ | USD/MWh | Value of loss of load |
| $\Delta^k$ | h | Response window of reserve $k$ (e.g., $\Delta^{REG}=5/60,\Delta^{SPIN}=10/60,\Delta^{NSPIN}=30/60$) |
| $\eta_s^{ch}$ | unitless | Charging efficiency of storage unit $s$ |
| $\eta_s^{dis}$ | unitless | Discharging efficiency of storage unit $s$ |
| $\eta_r^{DR}$ | unitless | DR shifting efficiency of resource $r$ (backlog formulation) |
| $\tau_r^{DR}$ | h | DR defer-window parameter of resource $r$ (backlog formulation) |
| $\alpha$ | unitless | Storage anchor, default 0.5 |

## Variables

| Notation | Unit | Description |
| :-- | :-- | :-- |
| $a_g$ | ton | Bidding carbon allowance of unit $g$ (active when `carbon_policy = 2`) |
| $b_{r,h}$ | MWh | DR backlog state in backlog load-shifting formulation |
| $c_{s,h}$ | MW | Charging power of storage $s$ from grid in hour $h$ |
| $dc_{s,h}$ | MW | Discharging power of storage $s$ into grid in hour $h$ |
| $dr_{r,h}^{DF/PB}$ | MW | Deferred/payback DR variables of resource $r$ |
| $em_w^{emis}$ | ton | Carbon-emission slack in state $w$ (active when carbon policy is on) |
| $p_{g,h}$ | MW | Active power generation of unit $g$ in hour $h$ |
| $pw_{g,w}$ | MWh | Total renewable generation of unit $g$ in state $w$ |
| $p_{i,h}^{LS}$ | MW | Load shedding in zone $i$ in hour $h$ |
| $pt_w^{rps}$ | MWh | Amount of energy violated RPS policy in state $w$ |
| $pwe_{g,w,w^\prime}$ | MWh | Renewable credits generated by unit $g$ in state $w$ and exported to state $w^\prime$ annually |
| $r_{g,h}^{k}$ | MW | Operation reserve $k$ of generator $g$ in hour $h$ |
| $r_{s,h}^{k}$ | MW | Operation reserve $k$ provided by storage $s$ in hour $h$ |
| $f_{l,h}$ | MW | Active power through transmission corridor/line $l$ in hour $h$ |
| $soc_{s,h}$ | MWh | State of charge level of storage $s$ in hour $h$ |
| $x_g$ | binary | Decision variable for candidate generator $g$ |
| $x_g^{RET}$ | binary | Decision variable for retirement of existing generator $g$ |
| $y_l$ | binary | Decision variable for candidate line $l$ |
| $z_s$ | binary | Decision variable for candidate storage $s$ |

## Auxiliary Expressions

| Notation | Unit | Description |
| :-- | :-- | :-- |
| $Load_{i,h}$ | MW | Zonal demand in zone $i$ and hour $h$ |
| $DR_{i,h}^{opt}$ | MW | Net DR term in power balance (positive = payback, negative = defer) |
