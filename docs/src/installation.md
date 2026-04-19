```@meta
CurrentModule = HOPE
```

# Installation

## 1. Install Julia

Install [Julia](http://julialang.org/) language. Julia 1.9 or later is required for the current HOPE package setup. A short video tutorial on how to download and install Julia is provided [here](https://www.youtube.com/watch?v=t67TGcf4SmM).

## 2. Download HOPE repository

Clone or download the **HOPE** repository to your local directory - click the green "Code" button on the **HOPE** main page and choose "Download ZIP" (remember to change the folder name to **HOPE** after you decompress the zip file). You need to save the `HOPE` project in your `home` directory like: `/yourpath/home/HOPE`.
![image](https://github.com/HOPE-Model-Project/HOPE/assets/125523842/6cd0feae-dec8-439f-a44d-98896228029e)

## 3. Get model cases

Model cases are maintained in a separate repository: [HOPEModelCases](https://github.com/HOPE-Model-Project/HOPEModelCases). Clone it into the `ModelCases/` folder inside your HOPE directory:

```bash
git clone https://github.com/HOPE-Model-Project/HOPEModelCases /yourpath/home/HOPE/ModelCases
```

This is the **recommended setup** — HOPE will find the cases automatically with no extra configuration.

**Alternative:** If you prefer to store model cases in a different location, clone `HOPEModelCases` anywhere and set the `HOPE_MODELCASES_PATH` environment variable to that path before running HOPE:

- **Linux / macOS:** `export HOPE_MODELCASES_PATH=/path/to/HOPEModelCases`
- **Windows (PowerShell):** `$env:HOPE_MODELCASES_PATH = "C:\path\to\HOPEModelCases"`

## 4. Solver Packages

After cloning the repo, activate the HOPE project and install the default dependencies:

```julia
import Pkg
Pkg.activate(".")
Pkg.instantiate()
```

This installs HOPE together with the bundled open-source solvers, including
[HiGHS](https://github.com/jump-dev/HiGHS.jl), [Cbc](https://github.com/coin-or/Cbc),
[GLPK](https://github.com/firedrakeproject/glpk), and
[Clp](https://github.com/coin-or/Clp).

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

```julia-repl
pkg> add https://github.com/HOPE-Model-Project/HOPE
```
