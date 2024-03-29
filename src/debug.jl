function debug(outpath::AbstractString, config_set::Dict, model::Model)
	model_mode = config_set["model_mode"]
	

	##Debugging
	if config_set["debug"]==0
		println("Debugging method is not set, please set debug = 1 or 2 in HOPE_model_settings.yml")
	elseif config_set["debug"]==1
		println("Start to debug infeasibility for model in $model_mode mode")
		println("Debugging with 'Conflicts' method")
		optimize!(model)
		compute_conflict!(model)
		if get_attribute(model, MOI.ConflictStatus()) == MOI.CONFLICT_FOUND
			iis_model, _ = copy_conflict(model)
			open(joinpath(outpath,"debug_report.txt"), "w") do f
				println(f,iis_model)
			end
		end

	elseif config_set["debug"]==2
		println("Start to debug infeasibility for model in $model_mode mode")
		println("Debugging with 'Penalty' method")
		map = relax_with_penalty!(model)
		optimize!(model)
		open(joinpath(outpath,"debug_report.txt"), "w") do f
			for (con, penalty) in map
				violation = value(penalty)
				if violation > 0
					println(f,"Constraint `$(name(con))` is violated by $violation")
					flush(f)
				end
			end
		end
	
	elseif config_set["debug"]!=0
		println("Wrong debug method, please set debug =0, 1 or 2 in HOPE_model_settings.yml")
	end
	return model
end

function run_debug(case::AbstractString)
	path = case
	outpath = path*"/debug_report/"
	mkdir_overwrite(outpath)
	config_set = YAML.load(open(case*"/Settings/HOPE_model_settings.yml"))

	#Set solver configuration
	optimizer =  initiate_solver(config_set["solver"],path)

	#read in data
	input_data = load_data(config_set,path)

	#create model
	if config_set["model_mode"] == "GTEP"
		my_model = create_GTEP_model(config_set,input_data,optimizer)
	elseif config_set["model_mode"] == "PCM"
		my_model = create_PCM_model(config_set,input_data,optimizer)
	else
		println("ModeError: Please check the model mode, it should be 'GTEP' or 'PCM', the 'OPF' and 'DART' are currently not availiable!" ) 
	end
	#debug model
	println("Debugging...")
	my_debug_model = debug(outpath, config_set, my_model)
	#output
	#my_output = write_output(outpath, config_set, input_data,my_debug_model)
	return my_debug_model 
end
