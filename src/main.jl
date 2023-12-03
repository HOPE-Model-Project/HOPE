#Read input data from .csv sheets
#Loading required packages
using DataFrames, CSV, XLSX, YAML, Clustering, Statistics, JuMP
using Gurobi
using Cbc


#load jl scripts

include("read_input_data.jl");		#read input data module
include("GTEP.jl");					#capacity expansion model
include("PCM.jl");					#production cost model
include("write_output.jl");			#write output module
include("solver_config.jl");		#setting solver parameters

#Set model configuration 
config_set = YAML.load(open("Settings/model_settings.yml"))

#Set solver configuration
optimizer =  initiate_solver(config_set["solver"])

#read in data
input_data = load_data(config_set,path)

#create model
if config_set["model_mode"] == "GTEP"
	my_model = create_GTEP_model(config_set,input_data,optimizer)
elseif config_set["model_mode"] == "PCM"
	my_model = create_PCM_model(config_set,input_data,optimizer)
else
	println("ModeError: Please check the model mode to be 'GTEP' or 'PCM' !" ) 
end
#solve model
my_sovled_model = solve_model(config_set, input_data, my_model)

#write outputs
my_output = write_output(outpath, config_set, input_data, my_sovled_model)

