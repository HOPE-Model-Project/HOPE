
```@meta
CurrentModule = HOPE
```

# Solver Settings Explanation

The **HOPE** model can use multiple solvers to solve optimization problems. The recommended default solver is **HiGHS** (`highs`), which is open-source, fast, and requires no extra installation. The solver parameters are saved in settings files named `<solver>_settings.yml` (e.g., `highs_settings.yml`, `cbc_settings.yml`, `clp_settings.yml`, `cplex_settings.yml`, `gurobi_settings.yml`, `scip_settings.yml`). In general, users do not need to modify these files. Each solver may have its own different settings parameters; if one wants to modify these parameters, it would be better to check the corresponding solver's documentation.
      


