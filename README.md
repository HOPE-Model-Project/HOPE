# HOPE 

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://SW.github.io/HOPE.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://SW.github.io/HOPE.jl/dev/)
[![Build Status](https://github.com/SW/HOPE.jl/actions/workflows/CI.yml/badge.svg?branch=master)](https://github.com/SW/HOPE.jl/actions/workflows/CI.yml?query=branch%3Amaster)

## Overview
The Holistic Optimization Program for Electricity (HOPE) model is a transparent tool for evaluating electric sector transition paths regarding power system planning, system operation, optimal power follow, and market designs. It is highly configurable and modulized programming coded in the  [Julia](http://julialang.org/) language and optimization package [JuMP](http://jump.dev/). The HOPE consists of multiple modes for modeling modern power systems and electricity market, including:
1. GTEP mode: a generation & transmission expansion planning model
2. PCM mode: a production cost model
3. OPF mode (under development): an optimal power flow model
4. DART mode (under development): a bilevel market model for simulating day-head and real-time market
Users can select the proper mode of HOPE based on their research needs. 

The HOPE model was originally developed by a team of researchers in the [Hobbs group](https://hobbsgroup.johnshopkins.edu/) at [Johns Hopkins University](https://www.jhu.edu/) The main contributors include [Shen Wang](https://ceepr.mit.edu/people/wang/) and [Mahdi Mehrtash](https://github.com/MahdiMehrtash).

## Installation
