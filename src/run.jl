function run_hope(case::AbstractString)
	# Normalize the case path - handle different input formats
	case_path = case
	
	# Handle HOPE prefix removal
	if startswith(case_path, "HOPE/") || startswith(case_path, "HOPE\\")
		case_path = case_path[6:end]
	end
	
	# Remove trailing slashes
	case_path = rstrip(case_path, ['/', '\\'])
	
	# Handle ModelCases prefix
	if startswith(case_path, "ModelCases/") || startswith(case_path, "ModelCases\\")
		case_path = case_path[12:end]
	end
	
	# Now try to find the directory
	path = nothing
	tried_paths = String[]
	
	# Try 1: Direct path as given (after normalization)
	test_path = case_path
	push!(tried_paths, test_path)
	if isdir(test_path)
		path = test_path
	end
	
	# Try 2: Add ModelCases/ prefix
	if path === nothing
		test_path = joinpath("ModelCases", case_path)
		push!(tried_paths, test_path)
		if isdir(test_path)
			path = test_path
		end
	end
	
	# Try 3: Use just the basename with ModelCases/ prefix
	if path === nothing
		test_path = joinpath("ModelCases", basename(case_path))
		push!(tried_paths, test_path)
		if isdir(test_path)
			path = test_path
		end
	end
	
	# If still not found, provide helpful error message
	if path === nothing
		available_cases = try
			readdir("ModelCases")
		catch
			String[]
		end
		error_msg = "Case directory does not exist: $case\n"
		error_msg *= "Tried paths:\n"
		for p in tried_paths
			error_msg *= "  - $p\n"
		end
		if !isempty(available_cases)
			error_msg *= "\nAvailable cases in ModelCases/:\n"
			for available_case in available_cases
				error_msg *= "  - $available_case\n"
			end
		end
		throw(ArgumentError(error_msg))
	end
	
	outpath = joinpath(path, "output")
	settings_file = joinpath(path, "Settings", "HOPE_model_settings.yml")
	
	if !isfile(settings_file)
		throw(ArgumentError("Settings file not found: $settings_file"))
	end
	
	try
		# Set model configuration 
		config_set = YAML.load(open(settings_file))

		# Set solver configuration
		optimizer = initiate_solver(config_set["solver"], path)

		# Read in data
		input_data = load_data(config_set, path)
		my_input = input_data
		
		# Create model
		my_model = if config_set["model_mode"] == "GTEP"
			create_GTEP_model(config_set, input_data, optimizer)
		elseif config_set["model_mode"] == "PCM"
			create_PCM_model(config_set, input_data, optimizer)
		else
			throw(ArgumentError("Invalid model mode: $(config_set["model_mode"]). Must be 'GTEP' or 'PCM'"))
		end
		
		# Solve model
		my_solved_model = solve_model(config_set, input_data, my_model)

		# Write outputs
		my_output = write_output(outpath, config_set, input_data, my_solved_model)
		
		Results = Dict(
			"solved_model" => my_solved_model,
			"output" => my_output,
			"input" => my_input
		)
		
		return Results
		
	catch e
		@error "Error running HOPE case: $case" exception=(e, catch_backtrace())
		rethrow()
	end
end

function write_hope(case::AbstractString, solved_case::Model)
	if !isdir(case)
		throw(ArgumentError("Case directory does not exist: $case"))
	end
	
	path = case
	outpath = joinpath(path, "output")
	settings_file = joinpath(case, "Settings", "HOPE_model_settings.yml")
	
	if !isfile(settings_file)
		throw(ArgumentError("Settings file not found: $settings_file"))
	end
	
	try
		# Set model configuration 
		config_set = YAML.load(open(settings_file))
		# Read in data
		input_data = load_data(config_set, path)
		write_output(outpath, config_set, input_data, solved_case)
	catch e
		@error "Error writing HOPE output for case: $case" exception=(e, catch_backtrace())
		rethrow()
	end
end