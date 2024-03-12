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
4. `DART` mode: (under development): a bilevel market model for simulating day-ahead and real-time markets

Users can select the proper mode of HOPE based on their research needs. Each mode is modeled as linear/mixed linear programming and can be solved with open-source (i.e., [Cbc](https://github.com/coin-or/Cbc), [GLPK](https://github.com/firedrakeproject/glpk), [Clp](https://github.com/coin-or/Clp), etc.) or commercial (e.g., [Gurobi](https://www.gurobi.com/) and [CPLEX](https://www.ibm.com/products/ilog-cplex-optimization-studio)) solver packages.

The HOPE model was originally developed by a team of researchers in Prof. [Benjamin F. Hobbs's group](https://hobbsgroup.johnshopkins.edu/) at [Johns Hopkins University](https://www.jhu.edu/). The main contributors include Dr. [Shen Wang](https://ceepr.mit.edu/people/wang/), Dr. [Mahdi Mehrtash](https://www.mahdimehrtash.com/) and [Zoe Song](https://).

# Preparation Phase
## 1. Install Julia
Install [Julia](http://julialang.org/) language. A short video tutorial on how to download and install Julia is provided [here](https://www.youtube.com/watch?v=t67TGcf4SmM).

## 2. Download HOPE repository
Clone OR download the **HOPE** repository to your local directory - click the green "Code" button on the **HOPE** main page and choose "Download ZIP". 
![image](https://github.com/swang22/HOPE/assets/125523842/6cd0feae-dec8-439f-a44d-98896228029e)
Then save the `HOPE-master` project in your working folder/home directory (e.g., the path to the `HOPE` project could be: `/yourpath/home/HOPE`). 
>[!NOTE]
>Remember to change the folder name `HOPE-master` to `HOPE` after you decompress the zip file.

In your `HOPE` project, the files should be something like below:
![image](https://github.com/swang22/HOPE/assets/125523842/6bd739bd-b5a7-4fdb-95a5-d8115de23c38)
 

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

**(3)** Make sure you are in the right working directory. Then, type `]` into the Julia package mode, and type `activate HOPE` (if you are in your `home` directory) or `activate yourpath/home/HOPE` (if you are not in your `home` directory), you will see prompt `(@v1.8) pkg>` changing to `(HOPE) pkg>`, which means the HOPE project is activated successfully. 

   ![image](https://github.com/swang22/HOPE/assets/125523842/2a0c259d-060e-4799-a044-8dedb8e5cc4d)
   
**(4)** Type `instantiate` in the (HOPE) pkg prompt (make sure you are in your `home` directory, not the `home/HOPE` directory!).

**(5)** Type `st` to check that the dependencies (packages that HOPE needs) have been installed. Type `up` to update the version of dependencies (packages). (This step may take some time when you install HOPE for the first time. After the HOPE is successfully installed, you can skip this step)

![image](https://github.com/swang22/HOPE/assets/125523842/1eddf81c-97e4-4334-85ee-44958fcf8c2f)

**(6)** If there is no error in the above processes, the **HOPE** model has been successfully installed! Then, press `Backspace` button to return to the Juila prompt. To run an example case (e.g., default Maryland 2035 case in `PCM` mode), type `using HOPE`, and type `HOPE.run_hope("HOPE/ModelCases/MD_Excel_case/")`, you will see the **HOPE** is running:
![image](https://github.com/swang22/HOPE/assets/125523842/33fa4fbc-6109-45ce-ac41-f41a29885525)
The results will be saved in `yourpath/home/HOPE/ModelCases/MD_Excel_case/output`. An example of a successful run in Julia prompt can be seen below.
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
![ccf1c53042925fcfb13ee232c13210e](https://github.com/swang22/HOPE/assets/144710777/6efb4646-8c81-4f4b-bcfc-6daabbdeb615)

**(6)** If there is no error in the above processes, the **HOPE** model has been successfully installed. Then, click `Backspace` to return to the Juila prompt. To run an example case (e.g., default Maryland 2035 case in `PCM` mode), type `using HOPE`, and type `HOPE.run_hope("HOPE/ModelCases/MD_Excel_case/")`, you will see the **HOPE** is running:

![image](https://github.com/swang22/HOPE/assets/125523842/c36c6384-7e04-450d-921a-784c3b13f8bd)

The results will be saved in `yourpath/home/HOPE/ModelCases/MD_Excel_case/output`. 

![image](https://github.com/swang22/HOPE/assets/125523842/7a760912-b8f2-4d5c-aea0-b85b6eb00bf4)

**(7)** For your future new runs, you can skip steps 4 and 5, and just follow steps 1,2,3,6.  

  
#### Mac users

# Run your case
Follow these steps:
![image](https://github.com/swang22/HOPE/assets/125523842/bc0ef4d9-b9b1-468a-a9a0-a0b2aa3d4340)


# Solvers
## Free Solvers
**Cbc**

## Commercial Solvers
If you want to use commercial solvers, e.g., **Gurobi** and **CPLEX**
1. You need to get the licenses from these solvers. [Gurobi](https://www.gurobi.com/solutions/licensing/?campaignid=2027425882&adgroupid=138872525680&creative=596136109143&keyword=gurobi%20license&matchtype=e&_bn=g&gad_source=1&gclid=CjwKCAiAlcyuBhBnEiwAOGZ2S58i-V4O5NOhUBGcfMmqsbiM1jWYudIrbNsfUYIozsGvJDUu_lE05hoCJMAQAvD_BwE) or [CPLEX](https://www.ibm.com/products/ilog-cplex-optimization-studio/cplex-optimizer)
2. In the `(HOPE) pkg>` project package mode (type `]` in the Julia package mode), install the Gurobi or CPLEX dependencies `(HOPE) pkg> add Gurobi` or `(HOPE) pkg> add CPLEX`
3. Uncomment the `using Gurobi` or `using CPLEX` in the file `HOPE/src/HOPE.jl`
4. Set the solver you want to use in the file `ModelCases/<the case folder you want to run>/Settings/HOPE_model_settings.yml`
>[!NOTE]
>You may need to re-activate HOPE if you have made modifications as above.

# Documentation

Check online [Documentation](https://swang22.github.io/HOPE/dev/) for HOPE.


# Program Sponsors
<img src="https://github.com/swang22/HOPE/assets/125523842/6abb8305-ca8f-4506-8e59-5f82e2893118" width="200" height="70" />
<br clear="both"/>
<img src="https://github.com/swang22/HOPE/assets/125523842/a0c7ee3e-1ac5-4a59-9698-d654b542d64e" width="300" height="150" />




