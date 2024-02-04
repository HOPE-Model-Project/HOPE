## Overview


# Problem Formulation
## Objective function

(1) Minimize total system cost:
```math
\begin{aligned}
        \text{min} \quad
        &\sum_{g \in G^{+}} \tilde{I}_{g} \times x_{g} + \sum_{g \in G, t \in T}VCG_{g} \times N_{t} \times \sum_{h \in H_{t}}p_{g,t,h} + \\
        &\sum_{l \in L^{+}} \tilde{I}_{l} \times y_{l} + \\
        &\sum_{s \in S^{+}} \tilde{I}_{s} \times z_{s} + \sum_{s \in S, t \in T} VCS \times N_{t} \times \sum_{h \in H_{t}} (c_{s,t,h} + dc_{s,t,h}) + \\
        &\sum_{d \in D, t \in T} VOLL_{d} \times N_{t} \times \sum_{h \in H_{t}} p_{d,t,h}^{LS} + \\
        & PT^{rps} \times \sum_{w \in W} pt_{w}^{rps} + \\
        & PT^{emis} \times \sum_{w \in W} em_{w}^{emis}  
\end{aligned}
```

```math
\Gamma = \Bigl\{ x_{g}, y_{l}, z_{s}, f_{l,h}, p_{g,t,h}, p_{d,t.h}^{LS}, c_{s,t,h}, dc_{s,t,h}, soc_{s,t,h}, pt^{rps}, pw_{g,w}, pwi_{g,w,w'}, em^{emis}_{w}, a_{g,t}, b_{g,t} \Bigr\}
```
## Constraints

(2) Generator investment budget:
```math
\sum_{g \in G_{+}} \tilde{I}_{g} \times x_{g} \le IBG
```

(3) Transmission line investment budget:
```math
\sum_{l \in L_{+}} \tilde{I}_{l} \times y_{l} \le IBL
```

(4) Storage investment budget:
```math
\sum_{s \in S_{+}} \tilde{I}_{s} \times z_{s} \le IBS
```

(5) Power balance:
```math
\sum_{g \in G_{i}} P_{g,t,h} + \sum_{s \in S_{i}} (dc_{s,t,h} - c_{s,t,h}) - \sum_{l \in LS_{i}} f_{l.t.h} \\
+ \sum_{l \in LR_{i}} f_{l.t.h} = \sum_{d \in D_{i}} (P_{d,t,h} - P_{d,t,h}^{LS}) ; \forall i \in I, h \in H_{t}, t \in T
```

(6) Transmission power flow limit for existing transmission lines:
```math
- F_{l}^{max} \le f_{g,l,t,h} \le F_{l}^{max};  \forall g \in G, l \in L^{E}, h \in H_{t}, t \in T
```

(7) Transmission power flow limit for new installed transmission lines:
```math
- y_{l} \times F_{l}^{max} \le f_{g,l,t,h} \le y_{l} \times F_{l}^{max};  \forall g \in G, l \in L^{+}, h \in H_{t}, t \in T
```

(8) Maximum capacity limits for existing power generation:
```math
0 \le p_{g,t,h} \le P_{g}^{max};  \forall g \in G_{E}, h \in H_{t}, t \in T
```

(9) Maximum capacity limits for installed power generation:
```math
0 \le p_{g,t,h} \le P_{g}^{max} \times x_{g};  \forall g \in G_{+}, h \in H_{t}, t \in T
```

(10) Load shedding limit:
```math
0 \le p_{g,t,h}^{LS} \le P_{g,t,h};  \forall d \in D_{i}, i \in I, h \in H_{t}, t \in T
```

(11) Renewables generation availability for the existing plants:
```math
p_{g,h} \le AFRE_{g,t,h,i} \times P_{g}^{max}; \forall g \in G_{E} \cap G_{i} \cap (G^{PV} \cup G^{W}), i \in I, h \in H_{t}, t \in T
```

(12) Renewables generation availability for new installed plants:
```math
p_{g,h} \le AFRE_{g,t,h,i} \times P_{g}^{max} \times x_{g}; \forall g \in G_{+} \cap G_{i} \cap (G^{PV} \cup G^{W}), i \in I, h \in H_{t}, t \in T
```

(13) Storage charging rate limit for existing units:
```math
\frac{c_{s,t,h}}{SC_{s}} \le SCAP_{s};  \forall h \in H_{t}, t \in T, s \in S_{E}
```

(14) Storage discharging rate limit for existing units:
```math
\frac{dc_{s,t,h}}{SD_{s}} \le SCAP_{s};  \forall h \in H_{t}, t \in T, s \in S_{E}
```

(15) Storage charging rate limit for new installed units:
```math
\frac{c_{s,t,h}}{SC_{s}} \le z_{s} \times SCAP_{s};  \forall h \in H_{t}, t \in T, s \in S_{+}
```

(16) Storage discharging rate limit for new installed units:
```math
\frac{dc_{s,t,h}}{SD_{s}} \le z_{s} \times SCAP_{s};  \forall h \in H_{t}, t \in T, s \in S_{+}
```

(17) Sate of charge limit for existing units:
```math
0 \le soc_{s,t,h} \le SECAP_{s}; \forall h \in H_{t}, t \in T, s \in S_{E}
```

(18) Sate of charge limit for new installed units:
```math
0 \le soc_{s,t,h} \le z_{s} \times SECAP_{s}; \forall h \in H_{t}, t \in T, s \in S_{+}
```

(19) Storage operation constraints:
```math
soc_{s,t,h} = soc_{s,t,h-1} + \epsilon_{ch} \times c_{s,t,h} - \frac{dc_{s,t,h}}{\epsilon_{dis}};  \forall h \in H_{t}, t \in T, s \in S
```

(20) Daily 50% of storage level balancing for existing units:
```math
soc_{s,1} = soc_{s,end} = 0.5 \times SCAP_{s}; s \in S_{E}
```

(21) Daily 50% of storage level balancing for new installed units:
```math
soc_{s,t,1} = soc_{s,t,end} = 0.5 \times z_{s} SCAP_{s}; s \in S_{+}
```

(22) Resource adequacy:
```math
\sum_{g \in G_{E}} (CC_{g} \times P_{g}^{max}) + \sum_{g \in G_{+}} (CC_{g} \times P_{g}^{max} \times x_{g}) \\
+ \sum_{s \in S^{E}}(CC_{s} \times SCAP_{s}) + \sum_{s \in S^{E}}(CC_{s} \times SCAP_{s} \times z_{s}) \ge (1 + RM) \times PK
```

(23) RPS policy - State total renewable energy generation:
```math
pw_{g,w} = \sum_{t \in T} N_{t} \times \sum_{h \in H_{t}} p+{g,t,h};  \forall g \in (\bigcup_{i \in I_{w}} G_{i}) \cap (G^{RPS}), w \in W
```

(24) RPS policy - State renewable credits export limitation:
```math
pw_{g,w} \ge \sum_{w' \in WER_{w}} pwi_{g,w,w'};  \forall g \in (\bigcup_{i \in I_{w}} G_{i}) \cap (G^{RPS}), w \in W
```

(25) RPS policy - State renewable credits import limitation:
```math
pw_{g,w'} \ge pwi_{g,w,w'};  \forall g \in (\bigcup_{i \in I_{w}} G_{i}) \cap (G^{RPS}), w \in W, w' \in WIR_{w}
```

(26) RPS policy - Renewable credits trading meets state RPS requirements:
```math
\begin{aligned}
\sum_{g \in (\bigcup_{i \in I_{w'}} G_{i}) \cap (G^{RPS}), w' \in WIR_{w}} pwi_{g,w,w'}
- \sum_{g \in (\bigcup_{i \in I_{w}} G_{i}) \cap (G^{RPS}), w' \in WER_{w}} pwi_{g,w',w} + pt_{w}^{rps} \\
\ge \sum_{t \in T} N_{t} \times \sum_{i \in I_{w},h \in H_{t}} \sum_{d \in D_{i}} p_{d,t,h} \times RPS_{w};\\
w \in W
\end{aligned}
```

(27) Cap & Trade - State carbon allowance cap:
```math
\sum_{g \in (\bigcup_{i \in I_{w}} G_{i}) \cap G^{F}} a+{g,t} - em_{w}^{emis} \le ALW_{t,w};  w \in W, t \in T
```

(28) Cap & Trade - Balance between allowances and emissions:
```math
N_{t} \sum_{h \in H_{t}} EF_{g} \times p_{g,t,h} = a_{g,t} + b_{g,t-1} = b_{g,t};  g \in (\bigcup_{i \in I_{w}} G_{i}) \cap G_{F}, w \in W, t \in T
```

(29) Cap & Trade - No cross-year banking:
```math
b_{g,1} = b_{g,end} = 0; g \in G_{F}
```

(30) Binary variables:
```math
x_{g} = \{0,1 \};  \forall g \in G_{+}
y_{l} = \{0,1 \};  \forall l \in L_{+}
z_{s} = \{0,1 \};  \forall s \in S_{+}
```

(31) Nonnegative variable:
```math
a_{g,t}, b_{g,t}, p_{g,t,h}, p_{d,t,h}^{LS}, c_{s,t,h}, soc_{s,t,h}, pt^{rps}, pw_{g,w}, pwi_{g,w,w'}, em^{emis} \\
\ge 0
```


