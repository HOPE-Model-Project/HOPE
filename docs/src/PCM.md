# Introduction

## Objective Function
(1) Minimize total system cost:
```math
\begin{aligned}
        \min_{\Gamma} \quad
        &\sum_{g \in G, t \in T}VCG_{g} \times N_{t} \times \sum_{h \in H}p_{g,h} + \\
        &\sum_{s \in S, t \in T} VCS \times \sum_{h \in H} (c_{s,h} + dc_{s,h}) + \\
        &\sum_{d \in D, t \in T} VOLL_{d} \times \sum_{h \in H} p_{d,h}^{LS} + \\
        &\sum_{g \in G^{F}, t \in T} CP_{g} \times \sum_{h \in H} p_{g,h} + \\
        &\sum_{w \in W, h \in H} PT^{rps} \times pt_{w,h}^{rps} + \\
        &\sum_{t \in T} \sum_{w \in W, h \in H} PT^{emis} \times em_{w,h}^{emis}
\end{aligned}
```

```math
\Gamma = \Bigl\{ a_{g,t}, b_{g,t}, f_{l,h}, p_{g,h}, p_{d,h}^{LS}, c_{s,h}, dc_{s,h}, soc_{s,h}, pt_{h}^{rps}, em^{emis}_{h}, r_{g,h}^{G}, r_{g,h}^{S} \Bigr\}
```
## Constraints

(2) Power balance:
```math
\sum_{g \in G_{i}} P_{g,h} + \sum_{s \in S_{i}} (dc_{s,h} - c_{s,h}) - \sum_{l \in LS_{i}} f_{l,h} \\
= \sum_{d \in D_{i}} (P_{d,h} - P_{d,h}^{LS}); \forall i \in I, h \in H
```

(3) Transmission:
```math
- F_{l}^{max} \le f_{l,h} \le F_{l}^{max};  \forall l \in L, h \in H
```

(4) Operation:
```math
P_{g}^{min} \le p_{g,h} + r_{g,h}^{G} \le (1 - FOR_{g}) \times P_{g}^{max}; \forall g \in G
```

(5) Spinning reserve limit:
```math
r_{g,h}^{G} \le RM_{g}^{SPIN} \times (1 - FOR_{g}) \times P_{g}^{max}; \forall g \in G^{F}
```

(6) Ramp limits - 1:
```math
(p_{g,h} + r_{g,h}^{G}) - p_{g, h-1} \le RU_{g} \times (1 - FOR_{g}) \times P_{g}^{max}; \forall g \in G^{F}, h \in H
```

(7) Ramp limits - 2:
```math
(p_{g,h} + r_{g,h}^{G}) - p_{g, h-1} \ge -RU_{g} \times (1 - FOR_{g}) \times P_{g}^{max}; \forall g \in G^{F}, h \in H
```

(8) Load shedding limit:
```math
0 \le p_{d,h}^{LS} \le P_{d}; \forall d \in D
```

(9) Renewables generation availability:
```math
p_{g,h} \le AFRE_{g,h,i} \times P_{g}^{max}; \forall h \in H, g \in G_{PV} \cup G^{W}), i \in I
```

(10) Storage charging rate limit:
```math
\frac{c_{s,h}}{SC_{s}} \le SCAP_{s};  \forall h \in H
```

(11) Storage discharging rate limit:
```math
\frac{dc_{s,h}}{SD_{s}} \le SCAP_{s};  \forall h \in H
```

(12) Storage operation limit - 1:
```math
0 \le soc_{s,h} \le SECAP_{s};  \forall h \in H, s \in S
```

(13) Storage operation limit - 2:
```math
dc_{s,h} + r_{s,h}^{S} \le SD_{s} \times SCAP_{s};  \forall h \in H
```

(14) Storage operation limit - 3:
```math
soc_{s,h} = soc_{s,h-1} + \epsilon_{ch} \times c_{s,t,h} - \frac{dc_{s,t,h}}{\epsilon_{dis}};  \forall h \in H
```

(15) RPS policy - State renewable credits export limitation:
```math
pw_{g,w} \ge \sum_{w' \in WER_{w}} pwi_{g,w,w'};  \forall g \in (\bigcup_{i \in I_{w'}} G_{i}) \cap (G^{RPS}), w \in W
```

(16) RPS policy - State renewable credits import limitation:
```math
pw_{g,w'} \ge pwi_{g,w,w'};  \forall g \in (\bigcup_{i \in I_{w'}} G_{i}) \cap (G^{RPS}), w \in W, w' \in WIR_{w}
```

(17) RPS policy - Renewable credits trading meets state RPS requirements:
```math
\begin{aligned}
\sum_{g \in (\bigcup_{i \in I_{w'}} G_{i}) \cap (G^{RPS}), w' \in WIR_{w}} pwi_{g,w,w'}
- \sum_{g \in (\bigcup_{i \in I_{w'}} G_{i}) \cap (G^{RPS}), w' \in WER_{w}} pwi_{g,w',w} + \sum_{w \in W, h \in H} pt_{w,h}^{rps} \\
\ge \sum_{i \in I_{w},h \in H} \sum_{d \in D_{i}} p_{d,h} \times RPS_{w};\\
w \in W
\end{aligned}
```

(18) Cap & Trade - State carbon allowance cap:
```math
\sum_{g \in (\bigcup_{i \in I_{w}} G_{i}) \cap G^{F}} a+{g,t} - \sum_{t \in T} N_{t} em_{w,h}^{emis} \le ALW_{t,w};  w \in W
```

(19) Cap & Trade - Balance between allowances and emissions:
```math
\sum_{h \in H} EF_{g} \times p_{g,h} = a_{g,t} + b_{g,t-1} = b_{g,t};  g \in (\bigcup_{i \in I_{w}} G_{i}) \cap G_{F}, w \in W, t \in T
```

(20) Cap & Trade - No cross-year banking:
```math
b_{g,1} = b_{g,end} = 0; g \in G_{F}
```

(21) Nonnegative variable:
```math
a_{g,t}, b_{g,t}, p_{g,h}, p_{d,h}^{LS}, c_{s,h}, soc_{s,h}, pt^{rps}, pw_{g,w}, pwi_{g,w,w'}, em^{emis} \\
\ge 0
```
