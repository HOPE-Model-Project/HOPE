```@meta
CurrentModule = HOPE
```

# Installation

## 1. Install Julia

Install [Julia](http://julialang.org/) language. A short video tutorial on how to download and install Julia is provided [here](https://www.youtube.com/watch?v=t67TGcf4SmM).

## 2. Download HOPE repository

Clone or download the **HOPE** repository to your local directory - click the green "Code" button on the **HOPE** main page and choose "Download ZIP" (remember to change the folder name to **HOPE** after you decompress the zip file). You need to save the `HOPE` project in your `home` directory like: `/yourpath/home/HOPE`.
![image](https://github.com/swang22/HOPE/assets/125523842/6cd0feae-dec8-439f-a44d-98896228029e)

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

The open-source solver packages (e.g., [Cbc](https://github.com/coin-or/Cbc), [GLPK](https://github.com/firedrakeproject/glpk), [Clp](https://github.com/coin-or/Clp), etc.) will be automatically installed in step 2. While the commercial solver packages (e.g., [Gurobi](https://www.gurobi.com/) and [CPLEX](https://www.ibm.com/products/ilog-cplex-optimization-studio)) should be installed by users (if needed) by following their instructions.

```julia-repl
pkg> add https://github.com/HOPE-Model-Project/HOPE
```
