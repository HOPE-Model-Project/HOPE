module HOPE
##using package##

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

##using solver#

#using Gurobi
#using CPLEX
using Cbc
#using HiGHS
#using SCIP
using Clp
using GLPK

#include HOPE module scripts
include("constants.jl");            #shared constants and configuration
include("utils.jl");                #utility functions
include("read_input_data.jl");		#read input data module
include("GTEP.jl");					#capacity expansion model
include("PCM.jl");					#production cost model
include("write_output.jl");			#write output module
include("solver_config.jl");		#setting solver parameters
include("solve.jl");                #solve model function
include("run.jl");                  #run module
include("debug.jl");                #debug function
include("run_holistic.jl");         #Holistic assessment: GTEP-PCM two stage

#export HOPE functions
export aggregate_gendata_gtep
export aggregate_gendata_pcm
export configure_settings
export create_GTEP_model
export create_PCM_model
export initiate_solver
export debug
export get_representative_ts
export get_TPmatched_ts
export load_data
export run_debug
export run_hope
export run_hope_holistic
export solve_model
export write_output

# Export constants for plotting and utilities
export COLOR_MAP, TECH_ACRONYM_MAP, ORDERED_TECH_POWER, ORDERED_TECH_CAPACITY, ORDERED_ES_TECH
export VALID_MODEL_MODES, HOURS_PER_YEAR, REQUIRED_FILES
export get_project_root, get_case_paths, get_paths
export validate_case_directory, validate_model_mode, safe_file_read, safe_remove_directory
export ensure_output_directory, apply_technology_mapping, aggregate_capacity_data

end
