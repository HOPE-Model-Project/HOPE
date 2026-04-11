# HOPE - Holistic Optimization Program for Electricity

[![Docs](https://img.shields.io/badge/docs-dev-blue.svg)](https://hope-model-project.github.io/HOPE/dev/)
[![Build Status](https://github.com/HOPE-Model-Project/HOPE/actions/workflows/Test.yml/badge.svg?branch=main)](https://github.com/HOPE-Model-Project/HOPE/actions/workflows/Test.yml?query=branch%3Amain)

![image](https://github.com/swang22/HOPE/assets/125523842/ec1e57fe-c65e-4e41-a128-43d2bbc3963c)

## How to cite HOPE?

You can cite the paper:

```
Wang, S., Song, Z., Mehrtash, M., & Hobbs, B. F. (2025). HOPE: Holistic Optimization Program for Electricity. SoftwareX, 29, 101982. https://doi.org/10.1016/j.softx.2024.101982
```

# Overview

The **Holistic Optimization Program for Electricity (HOPE)** model is a transparent and open-source tool for evaluating electric sector transition pathways and policy scenarios regarding power system planning, system operation, optimal power flow, and market designs. It is a highly configurable and modulized tool coded in the  [Julia](http://julialang.org/) language and optimization package [JuMP](http://jump.dev/). The HOPE consists of multiple modes for modeling optimization problems of modern power systems and electricity markets, including:

1. `GTEP` mode: a generation & transmission expansion planning model
2. `PCM` mode: a production cost model
3. `DART` mode: (under development): a SCUC/SCED market model for simulating day-ahead and real-time markets
4. `OPF` mode: (under development): an optimal power flow model
5. `HOPE-AI` mode: (under development): an AI agent helps connect all HOPE modules and enables complex modeling workflows. The current HOPE-AI framework is powered by [PowerAgent](https://github.com/Power-Agent), while more specialized agents are under development.

Users can select the proper mode of HOPE based on their research needs. Each mode is modeled as linear/mixed linear programming and can be solved with open-source (i.e., [Cbc](https://github.com/coin-or/Cbc), [GLPK](https://github.com/firedrakeproject/glpk), [Clp](https://github.com/coin-or/Clp), etc.) or commercial (e.g., [Gurobi](https://www.gurobi.com/) and [CPLEX](https://www.ibm.com/products/ilog-cplex-optimization-studio)) solver packages.

The HOPE model was originally developed by a team of researchers in Prof. [Benjamin F. Hobbs's group](https://hobbsgroup.johnshopkins.edu/) at [Johns Hopkins University](https://www.jhu.edu/). The main contributors for Verson 1 include Dr. [Shen Wang](https://ceepr.mit.edu/people/wang/), Dr. [Mahdi Mehrtash](https://www.mahdimehrtash.com/), [Zoe Song](https://pwrlab.org/team.html), and [Ziting Huang](https://hobbsgroup.johnshopkins.edu/members.html).

Current HOPE model is also maintaining by researchers at MIT, including Shen Wang, Dr. [Juan Senga](https://ceepr.mit.edu/people/senga/) and Prof. [Christopher Knittel](https://mitsloan.mit.edu/faculty/directory/christopher-knittel)

The HOPE-AI module is developed in collaboration with [Qian Zhang](https://seas.harvard.edu/person/qian-zhang) at Harvard University.

> **Looking for the legacy Maryland-focused version?** The pre-v2 codebase is archived at [HOPE-MD](https://github.com/HOPE-Model-Project/HOPE-MD).

# Preparation Phase

## 1. Install Julia

Install [Julia](http://julialang.org/) language. A short video tutorial on how to download and install Julia is provided [here](https://www.youtube.com/watch?v=t67TGcf4SmM).

## 2. Download HOPE repository

Clone OR download the **HOPE** repository to your local directory - click the green "Code" button on the **HOPE** main page and choose **"Clone"** (recommended) or **"Download ZIP"**.
![image](https://github.com/swang22/HOPE/assets/125523842/6cd0feae-dec8-439f-a44d-98896228029e)
Then save the `HOPE` project in your working folder/home directory (e.g., the path to the `HOPE` project could be: `/yourpath/home/HOPE`).
>[!NOTE]
>If you downloaded the ZIP, rename the extracted folder to `HOPE` (the zip extracts to a folder named after the branch, e.g., `HOPE-main`).

In your `HOPE` project, the files should be something like below:
![image](https://github.com/swang22/HOPE/assets/125523842/6bd739bd-b5a7-4fdb-95a5-d8115de23c38)

## 3. Get model cases

Model cases are maintained in a separate repository: [HOPEModelCases](https://github.com/HOPE-Model-Project/HOPEModelCases). Clone it into the `ModelCases/` folder inside your HOPE directory:

```bash
git clone https://github.com/HOPE-Model-Project/HOPEModelCases HOPE/ModelCases
```

This is the **recommended setup** — HOPE will find the cases automatically with no extra configuration. To update your model cases later, run `git pull` inside `HOPE/ModelCases/`.

>[!NOTE]
>If you prefer to store model cases elsewhere, clone `HOPEModelCases` to any path and set the `HOPE_MODELCASES_PATH` environment variable to that path before running HOPE. See the [HOPEModelCases README](https://github.com/HOPE-Model-Project/HOPEModelCases) for details.

# Run a Case in HOPE

## Using VScode to Run a Case (Recommend)

Install Visual Studio Code: Download [VScode](https://code.visualstudio.com/) and [install](https://code.visualstudio.com/docs/setup/setup-overview) it. A short video tutorial on how to install VScode and add Julia to it can be found [here](https://www.youtube.com/watch?v=oi5dZxPGNlk).

**(1)** Open the VScode, click the 'File' tab, select 'Open Folder...', and navigate to your home working directory:`/yourpath/home`

>[!NOTE]
>The `home` directory could be any folder where you save your HOPE project. The `home` directory in the example below is named `Maryland-Electric-Sector-Transition`.

![image](https://github.com/swang22/HOPE/assets/125523842/c8acf95d-909d-44e2-8ded-61635367dc53)

**(2)** In the VScode TERMINAL, type `Julia` and press the "Enter" button. Julia will be opened as below:

   ![image](https://github.com/swang22/HOPE/assets/125523842/5fc3a8c9-23f8-44a3-92ab-135c4dbdc118)

In Julia, you can use `pwd()` to check if your current working directory is your `home` directory, if it is not, you can use `cd("/yourpath/home")` to change your working directory, as the picture is shown below.

![image](https://github.com/swang22/HOPE/assets/125523842/a35268e3-b6ca-4d43-ad62-e5d0a67b0e8b)

**(3)** Make sure you are in the right working directory. Then, type `]` into the Julia package mode, and type `activate HOPE` (if you are in your `home` directory) or `activate yourpath/home/HOPE` (if you are not in your `home` directory), you will see prompt `(HOPE) pkg>`, which means the HOPE project is activated successfully.

   ![image](https://github.com/swang22/HOPE/assets/125523842/2a0c259d-060e-4799-a044-8dedb8e5cc4d)

**(4)** Type `instantiate` in the (HOPE) pkg prompt (make sure you are in your `home` directory, not the `home/HOPE` directory!).

**(5)** Type `st` to check that the dependencies (packages that HOPE needs) have been installed. Type `up` to update the version of dependencies (packages). (This step may take some time when you install HOPE for the first time. After the HOPE is successfully installed, you can skip this step)

![image](https://github.com/swang22/HOPE/assets/125523842/1eddf81c-97e4-4334-85ee-44958fcf8c2f)

**(6)** If there is no error in the above processes, the **HOPE** model has been successfully installed! Then, press `Backspace` button to return to the Juila prompt. To run an example case (e.g., default Maryland 2035 100% clean case in `GTEP` mode), type `using HOPE`, and type `HOPE.run_hope("HOPE/ModelCases/MD_GTEP_clean_case/")`, you will see the **HOPE** is running:
![image](https://github.com/swang22/HOPE/assets/125523842/519de1bf-03d0-4bad-8e69-a8a4fe2ad682)
The results will be saved in `yourpath/home/HOPE/ModelCases/MD_GTEP_clean_case/output`. An example of a successful run in Julia prompt can be seen below.
![image](https://github.com/swang22/HOPE/assets/125523842/99790827-4337-4991-a320-85ae2bd10be2)

**(7)**  For your future new runs, you can skip steps 4 and 5, and just follow steps 1,2,3,6.

## Using System Terminal to Run a Case

You can use a system terminal () either with a "Windows system" or a "Mac system" to run a test case. See details below.

### Windows users

**(1)** Open **Command Prompt** from Windows **Start** and navigate to your home path:`/yourpath/home`.

**(2)** Type `julia`. Julia will be opened as below:

![image](https://github.com/swang22/HOPE/assets/125523842/6c61bed1-bf8e-4186-bea2-22413fd1328e)

**(3)** Type `]` into the Julia package mode, and type `activate HOPE` (if you are in your `home` directory), you will see prompt `(HOPE) pkg>`, which means the HOPE project is activated successfully.

**(4)** Type `instantiate` in the (HOPE) pkg prompt. ( After the HOPE is successfully installed, you can skip this step)

**(5)** Type `st` to check that the dependencies (packages that HOPE needs) have been installed. Type `up` to update the version of dependencies (packages). (This step may take some time when you install HOPE for the first time. After the HOPE is successfully installed, you can skip this step)
![ccf1c53042925fcfb13ee232c13210e](https://github.com/swang22/HOPE/assets/144710777/6efb4646-8c81-4f4b-bcfc-6daabbdeb615)

**(6)** If there is no error in the above processes, the **HOPE** model has been successfully installed. Then, click `Backspace` to return to the Juila prompt. To run an example case (e.g., default Maryland 2035 100% clean case in `GTEP` mode), type `using HOPE`, and type `HOPE.run_hope("HOPE/ModelCases/MD_GTEP_clean_case/")`, you will see the **HOPE** is running:

![image](https://github.com/swang22/HOPE/assets/125523842/519de1bf-03d0-4bad-8e69-a8a4fe2ad682)

The results will be saved in `yourpath/home/HOPE/ModelCases/MD_GTEP_clean_case/output`.

![image](https://github.com/swang22/HOPE/assets/125523842/99790827-4337-4991-a320-85ae2bd10be2)

**(7)** For your future new runs, you can skip steps 4 and 5, and just follow steps 1,2,3,6.

#### Mac users

# Run your case

Follow these steps:
![image](https://github.com/swang22/HOPE/assets/125523842/bc0ef4d9-b9b1-468a-a9a0-a0b2aa3d4340)

# Solvers

## Free Solvers

HOPE bundles the following open-source solvers and no extra installation is needed:
**HiGHS** (default), **GLPK**, **Clp**, **Cbc**.

Set `solver: highs` (or any of the above) in
`ModelCases/<case>/Settings/HOPE_model_settings.yml`.

## Commercial Solvers

**Gurobi**, **SCIP**, and **CPLEX** are supported but are *not* installed by default.
Because they require a separate license, they are optional dependencies that you add to
your own Julia environment — HOPE does not pull them in automatically.

### Steps to enable a commercial solver

**Step 1 — Obtain a license.**

- [Gurobi Academic or Commercial License](https://www.gurobi.com/solutions/licensing/)
- [SCIP (free for academic use)](https://scipopt.org/)
- [CPLEX Academic or Commercial License](https://www.ibm.com/products/ilog-cplex-optimization-studio)

**Step 2 — Install the Julia package** in the HOPE project environment.

```julia
# start Julia in the HOPE repo root, then:
import Pkg
Pkg.activate(".")          # activate the HOPE environment
Pkg.add("Gurobi")          # or "SCIP" / "CPLEX"
```

> [!NOTE]
> `Gurobi.jl` requires the Gurobi solver itself to be installed on your machine
> and a valid `GRB_LICENSE_FILE` environment variable. See the
> [Gurobi.jl README](https://github.com/jump-dev/Gurobi.jl) for details.

**Step 3 — Set the solver** in the case settings file.

```yaml
# ModelCases/<case>/Settings/HOPE_model_settings.yml
solver: gurobi    # or: scip / cplex
```

HOPE will load the commercial solver package automatically the first time it is
requested. If the package is not installed, a clear error message is shown.

# Documentation

Check online [Documentation](https://hope-model-project.github.io/HOPE/dev/) for HOPE.

# Research & Publication

[Energy Resilience and Efficiency in Maryland](https://mde.maryland.gov/programs/air/ClimateChange/MCCC/Doclib_ERE/EREWG%20Study%20Report%20--%20Energy%20Resilience%20and%20Efficiency%20in%20Maryland.pdf)

## Acknowledgement

This project is funded by [Maryland Energy Administration](https://energy.maryland.gov/Pages/default.aspx)

# Program Sponsors

<img src="https://github.com/swang22/HOPE/assets/125523842/6abb8305-ca8f-4506-8e59-5f82e2893118" width="200" height="70" />
<br clear="both"/>
<img src="https://github.com/swang22/HOPE/assets/125523842/a0c7ee3e-1ac5-4a59-9698-d654b542d64e" width="320" height="160" />
<br clear="both"/>
<img src="https://ceepr.mit.edu/wp-content/uploads/2024/01/CEEPR_Logo_05_revised.png" width="280" alt="MIT CEEPR logo" />
<br clear="both"/>
<img src="docs/src/assets/poweragent-logo.png" width="280" alt="PowerAgent logo" />
