# HOPE Documentation

```@meta
CurrentModule = HOPE
```

# Overview
The **Holistic Optimization Program for Electricity (HOPE)** model is a transparent and open-source tool for evaluating electric sector transition pathways and policy scenarios regarding power system planning, system operation, optimal power flow, and market designs. It is a highly configurable and modular tool coded in the [Julia](http://julialang.org/) language and optimization package [JuMP](http://jump.dev/).
The HOPE currently supports these operational modes:
1. `GTEP` mode: a generation & transmission expansion planning model
2. `PCM` mode: a production cost model
Planned future modes:
1. `OPF` mode: (under development): an optimal power flow model
2. `DART` mode: (under development): a bilevel market model for simulating day-ahead and real-time markets

Users can select the proper mode of HOPE based on their research needs. Each mode is modeled as linear or mixed-integer linear programming and can be solved with open-source (e.g., [Cbc](https://github.com/coin-or/Cbc), [GLPK](https://github.com/firedrakeproject/glpk), [Clp](https://github.com/coin-or/Clp), etc.) or commercial (e.g., [Gurobi](https://www.gurobi.com/) and [CPLEX](https://www.ibm.com/products/ilog-cplex-optimization-studio)) solver packages.

# Contributors

The HOPE model was originally developed by a team of researchers in Prof. [Benjamin F. Hobbs's group](https://hobbsgroup.johnshopkins.edu/) at [Johns Hopkins University](https://www.jhu.edu/). The main developers of the current HOPE version include Dr. [Shen Wang](https://ceepr.mit.edu/people/wang/), Dr. [Mahdi Mehrtash](https://www.mahdimehrtash.com/), and Zoe Song.

<!-- build: 2026-04-07 23:13 -->
<!-- debug-run: 2026-04-07 23:51:55 -->
