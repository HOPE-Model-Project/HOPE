# HOPE - Holistic Optimization Program for Electricity 

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://SW.github.io/HOPE.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://SW.github.io/HOPE.jl/dev/)
[![Build Status](https://github.com/SW/HOPE.jl/actions/workflows/CI.yml/badge.svg?branch=master)](https://github.com/SW/HOPE.jl/actions/workflows/CI.yml?query=branch%3Amaster)

![image](https://github.com/swang22/HOPE/assets/125523842/ec1e57fe-c65e-4e41-a128-43d2bbc3963c)

## Overview
The Holistic Optimization Program for Electricity (HOPE) model is a transparent tool for evaluating electric sector transition paths regarding power system planning, system operation, optimal power flow, and market designs. It is a highly configurable and modulized tool coded in the  [Julia](http://julialang.org/) language and optimization package [JuMP](http://jump.dev/). The HOPE consists of multiple modes for modeling optimization problems of modern power systems and electricity markets, including:
1. `GTEP` mode: a generation & transmission expansion planning model
2. `PCM` mode: a production cost model
3. `OPF` mode: (under development): an optimal power flow model
4. `DART` mode: (under development): a bilevel market model for simulating day-head and real-time market

Users can select the proper mode of HOPE based on their research needs. 

The HOPE model was originally developed by a team of researchers in Prof. [Benjamin F. Hobbs group](https://hobbsgroup.johnshopkins.edu/) at [Johns Hopkins University](https://www.jhu.edu/) The main contributors include Dr. [Shen Wang](https://ceepr.mit.edu/people/wang/) and Dr. [Mahdi Mehrtash](https://www.mahdimehrtash.com/).

## Installation
### Install Julia and clone the HOPE repository
1. Install [Julia](http://julialang.org/) language.
2. Clone or download the **HOPE** repository to your local directory. For example, save the **HOPE** project in your `home` directory:`/yourpath/home/HOPE`.
### Using Visual Studio Code to Run a Case
Download [VScode](https://code.visualstudio.com/) and [install](https://code.visualstudio.com/docs/setup/setup-overview) it. 
1. Open the VScode, click the 'File' tab, select 'Open Folder...', and navigate to your home path:`/yourpath/home`.
2. In the TERMINAL, type `Julia`. Julia will be opened as below:
   ![image](https://github.com/swang22/HOPE/assets/125523842/5fc3a8c9-23f8-44a3-92ab-135c4dbdc118)
3. Type `]` into the Julia package mode, and type `activate HOPE` (if you are in your `home` directory) or `activate yourpath/home/HOPE` (if you are not in your `home` directory), you will see prompt `(@v1.8)` changing to `(HOPE)`, which means the HOPE project is activated successfully. 
   ![image](https://github.com/swang22/HOPE/assets/125523842/2a0c259d-060e-4799-a044-8dedb8e5cc4d)
4. Type `instantiate` in the (HOPE) pkg prompt.
5. Type `st` to check that the dependencies (packages that HOPE needs) have been installed.  Type `up` to update the version of dependencies (packages). 
![image](https://github.com/swang22/HOPE/assets/125523842/1eddf81c-97e4-4334-85ee-44958fcf8c2f)
6. If there is no error in the above processes, the **HOPE** model has been successfully installed. Then, click on `Backspace` to back to the Juila prompt.
   To run an example case (e.g., default Maryland 2035 case in `PCM` mode), type `using HOPE`, and type `HOPE.run_hope("HOPE/ModelCases/MD_Excel_case/")`, you will see the **HOPE** is running:
![image](https://github.com/swang22/HOPE/assets/125523842/33fa4fbc-6109-45ce-ac41-f41a29885525)
The results will be saved in `yourpath/home/HOPE/ModelCases/MD_Excel_case/output`. 
![image](https://github.com/swang22/HOPE/assets/125523842/7a760912-b8f2-4d5c-aea0-b85b6eb00bf4)

### Using Command Prompt to Run a Case

## Solvers
## Program Sponsors
<img src="https://github.com/swang22/HOPE/assets/125523842/6abb8305-ca8f-4506-8e59-5f82e2893118" width="200" height="65" />
<img src="https://github.com/swang22/HOPE/assets/125523842/a63ec280-f6b0-4451-b80a-bd9f13b54519" width="200" height="50" />



