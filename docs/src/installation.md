```@meta
CurrentModule = HOPE
```

# Installation

## 1. Install Julia

Install [Julia](http://julialang.org/) language. Julia 1.9 or later is required for the current HOPE package setup. A short video tutorial on how to download and install Julia is provided [here](https://www.youtube.com/watch?v=t67TGcf4SmM).

## 2. Install HOPE

After registration in General, install the latest release by package name:

```julia
import Pkg
Pkg.add("HOPE")
```

Until the initial registration is accepted, or to install the development branch
directly, use the repository URL:

```julia
import Pkg
Pkg.add(url = "https://github.com/HOPE-Model-Project/HOPE.jl")
```

Both commands install and precompile the Julia package. They do not download
model cases, start dashboards or MCP services, install Python, or require a
commercial solver license.

## 3. Get model cases

Model cases are maintained in the separate [HOPEModelCases](https://github.com/HOPE-Model-Project/HOPEModelCases) repository. Clone them to a user-selected location:

```bash
git clone https://github.com/HOPE-Model-Project/HOPEModelCases /path/to/HOPEModelCases
```

Model-case downloads are explicit and separate from package installation. Set `HOPE_MODELCASES_PATH` to that location before running a file-based case:

- **Linux / macOS:** `export HOPE_MODELCASES_PATH=/path/to/HOPEModelCases`
- **Windows (PowerShell):** `$env:HOPE_MODELCASES_PATH = "C:\path\to\HOPEModelCases"`

## 4. Solvers and source development

A normal package installation includes the open-source solvers
[HiGHS](https://github.com/jump-dev/HiGHS.jl), [Cbc](https://github.com/coin-or/Cbc),
[GLPK](https://github.com/jump-dev/GLPK.jl), and
[Clp](https://github.com/jump-dev/Clp.jl). No commercial license is required.

For development from a source checkout, activate and instantiate the repository:

```julia
import Pkg
Pkg.activate(".")
Pkg.instantiate()
```

Commercial solver packages such as [Gurobi](https://www.gurobi.com/),
[SCIP](https://scipopt.org/), and
[CPLEX](https://www.ibm.com/products/ilog-cplex-optimization-studio) are **not**
installed by `Pkg.instantiate()` by default. If needed, add them manually while the HOPE
project is active:

```julia
import Pkg
Pkg.activate(".")
Pkg.add("Gurobi")   # or "SCIP" / "CPLEX"
```

When you do this from an active HOPE environment, the commercial solver package is added
to the **HOPE project environment**, not just Julia's global default environment.

## 5. Minimal self-contained example

This one-bus DART SCUC example uses only package dependencies and creates no files:

```julia
using HOPE

data = DARTSystemData(
    generators = [
        DARTGenerator(
            name = "unit",
            bus = "bus",
            pmax_mw = 100.0,
            variable_cost_per_mwh = 25.0,
            commitment_required = false,
        ),
    ],
    network = DARTNetwork(bus_names = ["bus"]),
)
forecast = DARTForecast(
    interval_hours = 1.0,
    load_mw = reshape([40.0], 1, 1),
    availability = ones(1, 1),
)
result = solve_dart_scuc(data, forecast, default_dart_state(data))

result.generation_mw
```

The expected dispatch is 40 MW. Larger GTEP, PCM, holistic, and EREC examples
are maintained separately in
[HOPEModelCases](https://github.com/HOPE-Model-Project/HOPEModelCases).
