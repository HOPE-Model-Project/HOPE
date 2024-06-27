
```@meta
CurrentModule = HOPE
```

# Nomenclature

## Sets and Indices
---
|**Notation** | **Description**|
| :------------ | :-----------|
|$D$ |Set of demand, index $d$|
|$G$ |Set of all types of generating units, index $g$|
|$H$ |Set of hours, index $h$|
|$K$ |Set of technology types, index $k$|
|$T$ |Set of time periods (e.g., representative days of seasons), index $t$|
|$S$ |Set of storage units, index $s$|
|$I,J$ |Set of zones, index $i,j$|
|$L$ |Set of transmission corridors, index $l$|
|$W$ |Set of states, index $w/w’$|
---
## Subsets
---
|**Notation** | **Description**|
| :------------ | :-----------|
|$D_{i}$ | Set of demand connected to zone $i$, a subset of $D$|
|$G^{PV}$, $G^{W}$, $G^{F}$ | Set of solar, wind, and dispatchable generators, respectively, subsets of $G$|
|$G^{RPS}$ | Set of generators could provide RPS credits, subsets of $G$| 
|$G^{L}_{l}$ | Set of generators linked to line $i$, subset of $G$|  
|$G_{i}$ | Set of generating units connected to zone $i$, subset of $G$|  
|$G^{E}/G^{+}$ | Set of existing/candidate generation units, index $g$, subset of $G$|
|$H_{t}$ | Set of hours in time period (day) $t$, index $h$, subset of $H$|
|$S^{E}/S^{+}$ | Set of existing/candidate storage units, subset of $S$|
|$S_{i}$ | Set of storage units connected to zone $i$, subset of $S$|
|$L^{E}/L^{+}$ | Set of existing/candidate transmission corridors|
|$LS_{l}/LR_{l}$ | Set of sending/receiving corridors for zone $i$, subset of $L$|
|$WIR_{w}$ | Set of states that state w can import renewable credits from (includes $w$ itself), subset of $W$|
|$WER_{w}$ | Set of states that state w can export renewable credits to (excludes $w$ itself), subset of $W$|
---
## Parameters
---
|**Notation** | **Description**|
| :------------ | :-----------|
|$ALW_{t,w}$ | Total carbon allowance in time period $t$ in state $w$, ton|
|$AFRE_{g,h,i}$ | Availability factor of renewable energy source $g$ in hour $h$ in zone $i$, $g \in G^{PV} \bigcup G^{W}$|
|$CC_{g/s}$ | Capacity credit of resource $g/s$, unitless|
|$CP_{g}$ | Carbon price of generation $g \in\ G^{F}$, M$/t|
|$DR_{i,t,h}^{ref} | Reference demand of demand response aggregator in time-period $t in hour $h, MW|
|$DR_{i}^{MAX} | Maximum capacity limit for demand consumption of DR aggregator in zone $i, MW|
|$DRC| Cost of demand response, unitless|
|$EF_{g}$ | Carbon emission factor of generator $g$, t/MWh|
|$ELMT_{w}$ | Carbon emission limits at state $w, t$|
|$F^{max}_{l}$ | Maximum capacity of transmission corridor/line $l$, MW|
|$\tilde{I}_{g}$ | Investment cost of candidate generator $g$, M$|
|$\tilde{I}_{l}$ | Investment cost of  transmission line $l$, M$|
|$\tilde{I}_{s}$ | Investment cost of  storage unit $s$, M$|
|$IBG$ | Total investment budget for generators|
|$IBL$ | Total investment budget for transmission lines|
|$IBS$ | Total investment budget for storages|
|$N_{t}$ | Number of time periods (days) represented by time period (day) $t$ per year, $/sum_{t /in T} N_{t} |H_{t}| = 8760$|
|$NI_{i.h}$ | Net interchange in zone $i$ in hour $$h, MWh|
|$P_{d,h}$ | Active power demand, MW|
|$PK$ | Peak power demand, MW|
|$PT^{rps}$ | RPS volitation penalty, $/MWh|
|$PT^{emis}$ | Carbon emission volitation penalty, $/t|
|$P_{g}^{min}/P_{g}^{max}$ | Minimum/Maximum power generation of unit $g$, MW|
|$RPS_{w}$ | Renewable portfolio standard in state $w$, %, unitless|
|$RM$ | Planning reserve margin, unitless|
|$SCAP_{s}$ | Maximum capacity of storage unit $s$, MW|
|$SECAP_{s}$ | Maximum energy capacity of storage unit $s$, MWh|
|$SC_{s}/SD_{s}$ |  The maximum rates of charging/discharging, unitless|
|$VCG_{g}$ | Variable cost of generation unit $g$, $/ MWh|
|$VCS_{g}$ | Variable (degradation) cost of storage unit $s$, $/ MWh|
|$VOLL_{d}$ | Value of loss of load $d$, $/MWh|
|$\epsilon_{ch}$ | Charging efficiency of storage unit $s$, unitless|
|$\epsilon_{dis}$ | Discharging efficiency of storage unit $s$, unitless|
---
## Variables
---
|**Notation** | **Description**|
| :------------ | :-----------|
|$a_{g,t}$ | Bidding carbon allowance of unit $g$ in time period $t$, ton|
|$b_{g,t}$ | Banking of allowance of g in time period $t$, ton|
|$dr_{i,t,h}^{UP/DN} | Upwards/downwards demand change relative to reference demand during $h in time period $t in zone $i, MW|
|$dr_{i,t,h}^{DR} | Demand from DR aggregator during $h in time period $t in zone $i, MW|
|$p_{g,t,h}$ | Active power generation of unit $g$ in time period $t$ hour $h$, MW|
|$pw_{g,w}$ | Total renewable generation of unit $g$ in state $w$, MWh|
|$p^{LS}_{d,t,h}$ | Load shedding of demand $d$ in time period $t$ in hour $h$, MW|
|$pt^{rps}_{w}$ | Amount of active power violated RPS policy in state $w$, MW|
|$pwi_{g,w,w'}$ | State $w$ imported renewable credits of from state $w'$ annually, MWh|
|$f_{l,t,h}$ | Active power of generator $g$ through transmission corridor/line $l$ in time period $t$ and hour $h$, MW|
|$em^{emis}_{w}$ | Carbon emission violated emission limit in state $w$, ton|
|$x_{g}$ | Decision variable for candidate generator $g$, binary|
|$y_{l}$ | Decision variable for candidate line $l$, binary|
|$z_{s}$ | Decision variable for candidate storage $s$, binary|
|$soc_{s,t,h}$ | State of charge level of storage $s$ in time period $t$ in hour $h$, MWh|
|$c_{s,t,h}$ | Charging power of storage $s$ from grid in time period $t$ in hour $h$, MW|
|$dc_{s,t,h}$ | Discharging power of storage $s$ from grid in time period $t$ in hour $h$, MW|
---

