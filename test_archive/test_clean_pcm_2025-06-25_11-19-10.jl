#!/usr/bin/env julia

# Test script to run the clean master PCM model on MD_PCM_Excel_case

println("Testing the clean master PCM model...")

# Load packages
using Pkg
Pkg.activate(".")

using JuMP
using HiGHS
using DataFrames
using CSV
using XLSX
using YAML

# Include the HOPE modules
include("src/HOPE.jl")
include("src/PCM.jl")
include("src/read_input_data.jl")
include("src/solver_config.jl")
include("src/solve.jl")
include("src/write_output.jl")

println("Modules loaded successfully")

# Test case configuration
case_path = "ModelCases/MD_PCM_Excel_case"
println("Testing case: $case_path")

# Run the PCM model using HOPE infrastructure
try
    println("Starting PCM model run...")
    HOPE.run_hope(case_path)
    println("PCM model completed successfully!")
catch e
    println("Error running PCM model:")
    println(e)
    if isa(e, LoadError)
        println("Stack trace:")
        println(e.error)
    end
end
