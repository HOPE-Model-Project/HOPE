function run_hope(case::AbstractString)
	#wk_dir = @__DIR__
	#path = joinpath(wk_dir,case)
	path = case
	outpath = path*"/output/"
	#Set model configuration 
	config_set = YAML.load(open(case*"/Settings/HOPE_model_settings.yml"))

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
		println("ModeError: Please check the model mode, it should be 'GTEP' or 'PCM' !" ) 
	end
	#solve model
	my_sovled_model = solve_model(config_set, input_data, my_model)

	#write outputs
	my_output = write_output(outpath, config_set, input_data, my_sovled_model)
	return my_output
end
