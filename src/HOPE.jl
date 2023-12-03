module HOPE
#using package
using JuMP 
using DataFrames 
using CSV
using XLSX
using LinearAlgebra
using YAML
using Dates
using Clustering
using Distances
using Combinatorics
using Statistics

#using solver
#using Gurobi
#using CPLEX
using Cbc
using HiGHS
#using Clp

#include HOPE module scripts
include("read_input_data.jl");		#read input data module
include("GTEP.jl");					#capacity expansion model
include("PCM.jl");					#production cost model
include("write_output.jl");			#write output module
include("solver_config.jl");		#setting solver parameters
include("run.jl")                   #run modual

#export HOPE functions
export aggregate_gendata_gtep
export aggregate_gendata_pcm
export configure_settings
export create_GTEP_model
export create_PCM_model
export load_data
export get_representative_ts
export get_TPmatched_ts
export solve_model
export write_outputs
export run_hope

end
