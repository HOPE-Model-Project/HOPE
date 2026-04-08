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

try
    using Gurobi
catch
    # Keep HOPE loadable in environments without Gurobi.
end
#using CPLEX
using Cbc
using HiGHS
#using SCIP
using Clp
using GLPK

#include HOPE module scripts
include("constants.jl");            #shared constants and configuration
include("utils.jl");                #utility functions
include("rep_day.jl");              #representative-day utilities
include("aggregation.jl");          #resource aggregation settings/utilities
include("network_utils.jl");        #network/DCOPF helper utilities
include("read_input_data.jl");		#read input data module
include("GTEP.jl");					#capacity expansion model
include("PCM.jl");					#production cost model
include("write_output.jl");			#write output module
include("solver_config.jl");		#setting solver parameters
include("solve.jl");                #solve model function
include("run.jl");                  #run module
include("erec.jl");                 #EREC postprocessing module
include("debug.jl");                #debug function
include("run_holistic.jl");         #Holistic assessment: GTEP-PCM two stage

#export HOPE functions
export aggregate_gendata_gtep
export aggregate_gendata_pcm
export create_GTEP_model
export create_PCM_model
export calculate_erec
export calculate_erec_from_output
export default_aggregation_settings
export default_erec_settings
export default_rep_day_settings
export initiate_solver
export build_endogenous_rep_periods
export load_data
export load_aggregation_settings
export load_erec_settings
export load_rep_day_settings
export load_postprocess_snapshot
export resolve_rep_day_time_periods
export run_hope
export run_hope_holistic
export run_hope_holistic_fresh
export solve_model
export write_output

export marginal_load_price_from_dual

end
