# Power Balance

The power balance constraint of the model ensures that electricity demand is met at every time step in each zone. As shown in the constraint, electricity demand, $D_{t,z}$, at each time step and for each zone must be strictly equal to the sum of generation, $\Theta_{y,z,t}$, from thermal technologies ($\mathcal{H}$), curtailable variable renewable energy resources ($\mathcal{VRE}$), must-run resources ($\mathcal{MR}$), and hydro resources ($\mathcal{W}$). At the same time, energy storage devices ($\mathcal{O}$) can discharge energy, $\Theta_{y,z,t}$ to help satisfy demand, while when these devices are charging, $\Pi_{y,z,t}$, they increase demand. For the case of flexible demand resources ($\mathcal{DF}$), delaying demand, $\Pi_{y,z,t}$, decreases demand while satisfying delayed demand, $\Theta_{y,z,t}$, increases demand. Price-responsive demand curtailment, $\Lambda_{s,z,t}$, also reduces demand. Finally, power flows, $\Phi_{l,t}$, on each line $l$ into or out of a zone (defined by the network map $\varphi^{map}_{l,z}$), are considered in the demand balance equation for each zone. By definition, power flows leaving their reference zone are positive, thus the minus sign in the below constraint. At the same time losses due to power flows increase demand, and one-half of losses across a line linking two zones are attributed to each connected zone. The losses function $\beta_{l,t}(\cdot)$ will depend on the configuration used to model losses (see [Transmission](https://genxproject.github.io/GenX/docs/build/transmission.html)).

## Problem Formulation
(1) Objective function
```math
\begin{aligned}
&\min\sum_{g \in G^{+}} \tilde{I}_{g} x_{g} + \sum_{g \in G, t \in T} VCG_{g} N_{t} \sum_{h \in H_{t}} (c_{s,t,h} + dc_{s,t,h}) \\
&+ \sum_{l \in L_{+}} \tilde{I}_{l} Y_{l} + \sum_{d \in D, t \in T} VOLL_{d} N_{t} \sum_{h \in H_{t}} p_{d,t,h}^{LS} + PT^{rps} \sum_{w \in W} pt_{w}^{rps} + PT^{emis} \sum_{w \in W} em_{w}^{emis}  (1)
\end{aligned}
```

## Constraints
(2)
```math
 = 
```
(3) Generator investment budget:
```math
\sum_{g \in G_{+}} \tilde{I}_{g} x_{g} \le IBG
```

(4) Transmission line investment budget:
```math
\sum_{l \in L_{+}} \tilde{I}_{l} y_{l} \le IBL
```

(5) Storage investment budget:
```math
\sum_{s \in S_{+}} \tilde{I}_{s} z_{s} \le IBS
```

(6) Power balance:
```math
\sum_{g \in G_{i}} P_{g,t,h} + \sum_{s \in S_{i}} (dc_{s,t,h} - c_{s,t,h}) - \sum_{l \in LS_{i}} f_{l.t.h} \\
+ \sum_{l \in LR_{i}} f_{l.t.h} = \sum_{d \in D_{i}} (P_{d,t,h} - P_{d,t,h}^{LS}) ; \forall i \in I, h \in H_{t}, t \in T
```

(7) Transmission power flow limit for existing transmission lines:
```math
- F_{l}^{max} \le f_{g,l,t,h} \le F_{l}^{max};  \forall g \in G, l \in L^{E}, h \in H_{t}, t \in T
```

(8) Transmission power flow limit for new installed transmission lines:
```math
- y_{l} F_{l}^{max} \le f_{g,l,t,h} \le y_{l} F_{l}^{max};  \forall g \in G, l \in L^{+}, h \in H_{t}, t \in T
```

(9) Maximum capacity limits for existing power generation:
```math
0 \le p_{g,t,h} \le P_{g}^{max};  \forall g \in G_{E}, h \in H_{t}, t \in T
```

(10) Maximum capacity limits for installed power generation:
```math
0 \le p_{g,t,h} \le P_{g}^{max} x_{g};  \forall g \in G_{+}, h \in H_{t}, t \in T
```

(11) Load shedding limit:
```math
0 \le p_{g,t,h}^{LS} \le P_{g,t,h};  \forall d \in D_{i}, i \in I, h \in H_{t}, t \in T
```

(12) Renewables generation availability for the existing plants:
```math
p_{g,h} \le AFRE_{g,t,h,i} P_{g}^{max}; \forall g \in G_{E} \cap G_{i} \cap (G^{PV} \cup G^{W}), i \in I, h \in H_{t}, t \in T
```

(13) Renewables generation availability for new installed plants:
```math
p_{g,h} \le AFRE_{g,t,h,i} P_{g}^{max} x_{g}; \forall g \in G_{+} \cap G_{i} \cap (G^{PV} \cup G^{W}), i \in I, h \in H_{t}, t \in T
```

(14) Storage charging rate limit for existing units:
```math
\frac{c_{s,t,h}}{SC_{s}} \le SCAP_{s};  \forall h \in H_{t}, t \in T, s \in S_{E}
```

(15) Storage discharging rate limit for existing units:
```math
\frac{dc_{s,t,h}}{SD_{s}} \le SCAP_{s};  \forall h \in H_{t}, t \in T, s \in S_{E}
```

(16) Storage charging rate limit for new installed units:
```math
\frac{c_{s,t,h}}{SC_{s}} \le z_{s} SCAP_{s};  \forall h \in H_{t}, t \in T, s \in S_{+}
```

(17) Storage discharging rate limit for new installed units:
```math
\frac{dc_{s,t,h}}{SD_{s}} \le z_{s} SCAP_{s};  \forall h \in H_{t}, t \in T, s \in S_{+}
```

(18) Sate of charge limit for existing units:
```math
0 \le soc_{s,t,h} \le SECAP_{s}; \forall h \in H_{t}, t \in T, s \in S_{E}
```

(19) Sate of charge limit for new installed units:
```math
0 \le soc_{s,t,h} \le z_{s} SECAP_{s}; \forall h \in H_{t}, t \in T, s \in S_{+}
```

(20) Storage operation constraints:
```math
soc_{s,t,h} = soc_{s,t,h-1} + \epsilon_{ch} c_{s,t,h} - \frac{dc_{s,t,h}}{\epsilon_{dis}};  \forall h \in H_{t}, t \in T, s \in S
```

(21) Daily 50% of storage level balancing for existing units:
```math
soc_{s,1} = soc_{s,end} = 0.5 x SCAP_{s}; s \in S_{E}
```

(22) Daily 50% of storage level balancing for new installed units:
```math
soc_{s,t,1} = soc_{s,t,end} = 0.5 x z_{s} SCAP_{s}; s \in S_{+}
```

(23) Resource adequacy:
```math
\sum_{g \in G_{E}} (CC_{g} P_{g}^{max}) + \sum_{g \in G_{+}} (CC_{g} P_{g}^{max} x_{g}) \\
+ \sum_{s \in S^{E}}(CC_{s} SCAP_{s}) + \sum_{s \in S^{E}}(CC_{s} SCAP_{s} z_{s}) \ge (1 + RM) PK
```

(24) RPS policy - State total renewable energy generation:
```math
pw_{g,w} = \sum_{t \in T} N_{t} \sum_{h \in H_{t}} p+{g,t,h};  \forall g \in (\bigcup_{i \in I_{w}} G_{i}) \cap (G^{RPS}), w \in W
```

(25) RPS policy - State renewable credits export limitation:
```math
pw_{g,w} \ge \sum_{w' \in WER_{w}} pwi_{g,w,w'};  \forall g \in (\bigcup_{i \in I_{w}} G_{i}) \cap (G^{RPS}), w \in W
```

(26) RPS policy - State renewable credits import limitation:
```math
pw_{g,w'} \ge pwi_{g,w,w'};  \forall g \in (\bigcup_{i \in I_{w}} G_{i}) \cap (G^{RPS}), w \in W, w' \in WIR_{w}
```

(27) RPS policy - Renewable credits trading meets state RPS requirements:
```math
\begin{aligned}
\sum_{g \in (\bigcup_{i \in I_{w'}} G_{i}) \cap (G^{RPS}), w' \in WIR_{w}} pwi_{g,w,w'}
- \sum_{g \in (\bigcup_{i \in I_{w}} G_{i}) \cap (G^{RPS}), w' \in WER_{w}} pwi_{g,w',w} + pt_{w}^{rps} \\
\ge \sum_{t \in T} N_{t} \sum_{i \in I_{w},h \in H_{t}} \sum_{d \in D_{i}} p_{d,t,h} * RPS_{w};\\
w \in W
\end{aligned}
```

(28) Cap & Trade - State carbon allowance cap:
```math
\sum_{g \in (\bigcup_{i \in I_{w}} G_{i}) \cap G^{F}} a+{g,t} - em_{w}^{emis} \le ALW_{t,w};  w \in W, t \in T
```

(29) Cap & Trade - Balance between allowances and emissions:
```math
N_{t} \sum_{h \in H_{t}} EF_{g} p_{g,t,h} = a_{g,t} + b_{g,t-1} = b_{g,t};  g \in (\bigcup_{i \in I_{w}} G_{i}) \cap G_{F}, w \in W, t \in T
```

(30) Cap & Trade - No cross-year banking:
```math
b_{g,1} = b_{g,end} = 0; g \in G_{F}
```

(31) Binary variables:
```math
x_{g} = \{0,1 \};  \forall g \in G_{+}
y_{l} = \{0,1 \};  \forall l \in L_{+}
z_{s} = \{0,1 \};  \forall s \in S_{+}
```

(32) Nonnegative variable:
```math
a_{g,t}, b_{g,t}, p_{g,t,h}, p_{d,t,h}^{LS}, c_{s,t,h}, soc_{s,t,h}, pt^{rps}, pw_{g,w}, pwi_{g,w,w'}, em^{emis} \\
\ge 0
```


