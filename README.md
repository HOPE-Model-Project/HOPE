# HOPE - Holistic Optimization Program for Electricity 

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://swang22.github.io/HOPE.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://swang22.github.io/HOPE/dev/)
[![Build Status](https://github.com/swang22/HOPE/actions/workflows/CI.yml/badge.svg?branch=master)](https://github.com/swang22/HOPE/actions/workflows/CI.yml?query=branch%3Amaster)

![image](https://github.com/swang22/HOPE/assets/125523842/ec1e57fe-c65e-4e41-a128-43d2bbc3963c)
## Acknowledgement
This project is funded by [Maryland Energy Administration](https://energy.maryland.gov/Pages/default.aspx)
<img src="https://github.com/swang22/HOPE/assets/125523842/6abb8305-ca8f-4506-8e59-5f82e2893118" width="200" height="70" />

# Overview
The **Holistic Optimization Program for Electricity (HOPE)** model is a transparent and open-source tool for evaluating electric sector transition pathways and policy scenarios regarding power system planning, system operation, optimal power flow, and market designs. It is a highly configurable and modulized tool coded in the  [Julia](http://julialang.org/) language and optimization package [JuMP](http://jump.dev/). The HOPE consists of multiple modes for modeling optimization problems of modern power systems and electricity markets, including:
1. `GTEP` mode: a generation & transmission expansion planning model
2. `PCM` mode: a production cost model
3. `OPF` mode: (under development): an optimal power flow model
4. `DART` mode: (under development): a bilevel market model for simulating day-head and real-time markets

Users can select the proper mode of HOPE based on their research needs. Each mode is modeled as linear/mixed linear programming and can be solved with open-source (i.e., [Cbc](https://github.com/coin-or/Cbc), [GLPK](https://github.com/firedrakeproject/glpk), [Clp](https://github.com/coin-or/Clp), etc.) or commercial (e.g., [Groubi](https://www.gurobi.com/) and [CPLEX](https://www.ibm.com/products/ilog-cplex-optimization-studio)) solver packages.

The HOPE model was originally developed by a team of researchers in Prof. [Benjamin F. Hobbs's group](https://hobbsgroup.johnshopkins.edu/) at [Johns Hopkins University](https://www.jhu.edu/). The main contributors include Dr. [Shen Wang](https://ceepr.mit.edu/people/wang/), Dr. [Mahdi Mehrtash](https://www.mahdimehrtash.com/) and [Zoe Song](https://).

# Preparation Phase
## 1. Install Julia
Install [Julia](http://julialang.org/) language.

## 2. Download HOPE repository
Clone OR download the **HOPE** repository to your local directory - click the green "Code" button on the **HOPE** main page and choose "Download ZIP" (remember to change the folder name to **HOPE** after you decompress zip file). You need to save the `HOPE` project in your `home` directory like: `/yourpath/home/HOPE`. 
![image](https://github.com/swang22/HOPE/assets/125523842/6cd0feae-dec8-439f-a44d-98896228029e)

 

# Run a Case in HOPE
## Using VScode to Run a Case (Recommend)
Install Visual Studio Code: Download [VScode](https://code.visualstudio.com/) and [install](https://code.visualstudio.com/docs/setup/setup-overview) it.

**(1)** Open the VScode, click the 'File' tab, select 'Open Folder...', and navigate to your home working directory:`/yourpath/home` (The `home` directory could be any folder where you save your HOPE repo. The `home` directory in the examples below is named `Maryland-Electric-Sector-Transition`).  

**(2)** In the VScode TERMINAL, type `Julia` and press the "Enter" button. Julia will be opened as below:

   ![image](https://github.com/swang22/HOPE/assets/125523842/5fc3a8c9-23f8-44a3-92ab-135c4dbdc118)
   
**(3)** Type `]` into the Julia package mode, and type `activate HOPE` (if you are in your `home` directory) or `activate yourpath/home/HOPE` (if you are not in your `home` directory), you will see prompt `(@v1.8) pkg>` changing to `(HOPE) pkg>`, which means the HOPE project is activated successfully. 

   ![image](https://github.com/swang22/HOPE/assets/125523842/2a0c259d-060e-4799-a044-8dedb8e5cc4d)
   
**(4)** Type `instantiate` in the (HOPE) pkg prompt (make sure you are in your `home` directory, not the `home/HOPE` directory!).

**(5)** Type `st` to check that the dependencies (packages that HOPE needs) have been installed. Type `up` to update the version of dependencies (packages). (This step may take some time when you install HOPE for the first time. After the HOPE is successfully installed, you can skip this step)

![image](https://github.com/swang22/HOPE/assets/125523842/1eddf81c-97e4-4334-85ee-44958fcf8c2f)

**(6)** If there is no error in the above processes, the **HOPE** model has been successfully installed! Then, press `Backspace` button to return to the Juila prompt. To run an example case (e.g., default Maryland 2035 case in `PCM` mode), type `using HOPE`, and type `HOPE.run_hope("HOPE/ModelCases/MD_Excel_case/")`, you will see the **HOPE** is running:
![image](https://github.com/swang22/HOPE/assets/125523842/33fa4fbc-6109-45ce-ac41-f41a29885525)
The results will be saved in `yourpath/home/HOPE/ModelCases/MD_Excel_case/output`. 
![image](https://github.com/swang22/HOPE/assets/125523842/af68d3a7-4fe7-4d9c-97f5-6d8898e2c522)

**(7)**  For your future new runs, you can skip steps 4 and 5, and just follow steps 1,2,3,6.   

## Using System Terminal to Run a Case
You can use a system terminal () either with a "Windows system" or a "Mac system" to run a test case. See details below.
### Windows users
**(1)** Open **Command Prompt** from Windows **Start** and navigate to your home path:`/yourpath/home`.

**(2)** Type `julia`. Julia will be opened as below:

![image](https://github.com/swang22/HOPE/assets/125523842/6c61bed1-bf8e-4186-bea2-22413fd1328e)

**(3)** Type `]` into the Julia package mode, and type `activate HOPE` (if you are in your `home` directory), you will see prompt `(@v1.8) pkg>` changing to `(HOPE) pkg>`, which means the HOPE project is activated successfully. 

**(4)** Type `instantiate` in the (HOPE) pkg prompt. ( After the HOPE is successfully installed, you can skip this step)

**(5)** Type `st` to check that the dependencies (packages that HOPE needs) have been installed. Type `up` to update the version of dependencies (packages). (This step may take some time when you install HOPE for the first time. After the HOPE is successfully installed, you can skip this step)

![image](https://github.com/swan,g22/HOPE/assets/125523842/66ce1ea1-1b06-43d0-9f2b-542c473797aa)

**(6)** If there is no error in the above processes, the **HOPE** model has been successfully installed. Then, click `Backspace` to return to the Juila prompt. To run an example case (e.g., default Maryland 2035 case in `PCM` mode), type `using HOPE`, and type `HOPE.run_hope("HOPE/ModelCases/MD_Excel_case/")`, you will see the **HOPE** is running:

![image](https://github.com/swang22/HOPE/assets/125523842/c36c6384-7e04-450d-921a-784c3b13f8bd)

The results will be saved in `yourpath/home/HOPE/ModelCases/MD_Excel_case/output`. 

![image](https://github.com/swang22/HOPE/assets/125523842/7a760912-b8f2-4d5c-aea0-b85b6eb00bf4)

**(7)** For your future new runs, you can skip steps 4 and 5, and just follow steps 1,2,3,6.  

  
#### Mac users

# Solvers
## Free Solvers
**Cbc**

## Commercial Solvers
**Gorubi**

# Documentation

[Documentation](https://swang22.github.io/HOPE/dev/) for HOPE.


# Program Sponsors
<img src="https://github.com/swang22/HOPE/assets/125523842/6abb8305-ca8f-4506-8e59-5f82e2893118" width="200" height="70" />
<img src="https://github.com/swang22/HOPE/assets/125523842/a0c7ee3e-1ac5-4a59-9698-d654b542d64e" width="300" height="150" />




