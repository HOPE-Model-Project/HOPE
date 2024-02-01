```@meta
CurrentModule = HOPE
```

# Installation

## 1. Install Julia
Install [Julia](http://julialang.org/) language.

## 2. Download HOPE repository
Clone OR download the **HOPE** repository to your local directory - click the green "Code" button on the **HOPE** main page and choose "Download ZIP" (remember to change the folder name to **HOPE** after you decompress zip file). You need to save the `HOPE` project in your `home` directory like: `/yourpath/home/HOPE`. 
![image](https://github.com/swang22/HOPE/assets/125523842/6cd0feae-dec8-439f-a44d-98896228029e)

**After released**
```julia-repl
pkg> add https://github.com/swang22/HOPE.jl
```

## 3. Solver Packages
The open-source packages (i.e., [Cbc](https://github.com/coin-or/Cbc), [GLPK](https://github.com/firedrakeproject/glpk), [Clp](https://github.com/coin-or/Clp), etc.) will be automatically installed in the step 2. While the commercial (e.g., [Groubi](https://www.gurobi.com/) and [CPLEX](https://www.ibm.com/products/ilog-cplex-optimization-studio)) solver packages (if needed) should be installed by users follow their instructions. 

```julia-repl
pkg> add https://github.com/swang22/HOPE.jl
```

