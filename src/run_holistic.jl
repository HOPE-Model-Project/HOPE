function fill_missing_with_group_mean(df::DataFrame, group_cols::Vector{Symbol}, cols_to_fill::Vector{Symbol})
    for col in cols_to_fill
        # Calculate group means
		#df[:,col] =  allowmissing(df[:,col])
		#df[:,col]= map(x -> x === "NaN" ? NaN : x isa Missing ? missing : parse(Float64, x), df[:,col])
		#df[:,col] = replace(df[:,col], missing=>missing)
        group_means = combine(groupby(df, group_cols), col => (x -> mean(skipmissing(x))) => Symbol(col, "_mean"))
		#print(group_means)
        # Rename the mean column to avoid conflicts during join
        rename!(group_means, Symbol(col, "_mean") => Symbol("mean_", col))
        
        # Join group means back to the original DataFrame
        df = leftjoin(df, group_means, on = group_cols, makeunique=true, matchmissing=:notequal)
        
        # Replace missing values
        df[!, col] = coalesce.(df[!, col], df[!, Symbol("mean_", col)])
        
        # Drop the mean column used for filling missing values
        select!(df, Not(Symbol("mean_", col)))
    end
    return df
end
# Function to convert specified columns to Union{Missing, Float64}
function convert_columns_to_float64!(df::DataFrame, cols::Vector{Symbol})
    for col in cols
        # Ensure the column allows missing values
        df[!, col] = allowmissing(df[!, col])

        # Convert the column values to Float64 while handling "NaN" strings and missing values
        df[!, col] = map(x -> 
            x isa Missing ? missing :
            x isa Float64 ? x :
            x isa Int ? Float64(x) :
            x === "NaN" ? NaN :
            x isa AbstractString ? parse(Float64, x) :
            throw(ArgumentError("Cannot convert value $x to Float64")), df[!, col])
    end
    return df
end

function run_hope_holistic(GTEP_case::AbstractString, PCM_case::AbstractString)
	println("Run Holistic Assessment: 'GTEP-PCM' mode!")
	println("First stage: solving 'GTEP' mode!")
	GTEP_model = HOPE.run_hope(GTEP_case)
	#PCM_model = HOPE.run_hope(PCM_case)
	GTEP_inpath = GTEP_case
	PCM_inpath = PCM_case

	GTEP_outpath = GTEP_inpath*"/output/"
	PCM_outpath = PCM_inpath*"/output/"

	GTEP_solved_model,GTEP_solved_output, GTEP_input = GTEP_model[1], GTEP_model[2], GTEP_model[3]
	#PCM_solved_model,PCM_solved_output, PCM_input = PCM_model[1], PCM_model[2], PCM_model[3]

	Capacity = GTEP_solved_output["capacity"]
	New_Build_Capacity = filter(:New_Build => isequal(1),Capacity)
	New_Build_sub = select!(New_Build_Capacity,[:Zone,:Technology, Symbol("Capacity_FIN (MW)")])
	rename!(New_Build_sub, [Symbol("Technology"),Symbol("Capacity_FIN (MW)")] .=>[:Type, Symbol("Pmax (MW)")])
	
	ES_capacity = GTEP_solved_output["es_capacity"]
	New_Build_ES_Capacity = filter(:New_Build => isequal(1),ES_capacity)
	New_Build_ES_sub = select!(New_Build_ES_Capacity,[:Zone,:Technology, Symbol("EnergyCapacity (MWh)"), Symbol("Capacity (MW)")])
	rename!(New_Build_ES_sub, [Symbol("Technology"),Symbol("EnergyCapacity (MWh)"),Symbol("Capacity (MW)")] .=>[:Type, Symbol("Capacity (MWh)"),Symbol("Max Power (MW)")])

	Line_Capacity =  GTEP_solved_output["line"]
	New_Build_Line_Capacity = filter(:New_Build => isequal(1), Line_Capacity)
	New_Build_Line_sub = select!(New_Build_Line_Capacity,[:From_zone,:To_zone,Symbol("Capacity (MW)")])

	println("Second stage: solving 'GTEP' informed 'PCM' mode!")
	##Run new PCM:
	#Set model configuration 
	config_set = YAML.load(open(PCM_case*"/Settings/HOPE_model_settings.yml"))
	PCM_input = load_data(config_set,PCM_inpath)
	#Modify PCM inputs
	PCM_Gendata = PCM_input["Gendata"]
	#PCM_agg_Gendata = aggregate_gendata_pcm(PCM_input["Gendata"],config_set)
	#update gendata
	Updated_PCM_Gendata = outerjoin(PCM_Gendata,New_Build_sub, on = [:Zone,:Type,Symbol("Pmax (MW)")])
	#Fill missing value with group mean
	if config_set["unit_commitment"] != 0
		Updated_PCM_Gendata_fillmean = fill_missing_with_group_mean(Updated_PCM_Gendata,[:Zone, :Type],[Symbol("Pmin (MW)"),Symbol("Cost (\$/MWh)"),:EF,:CC,:FOR,:RM_SPIN,:RU,:RD,:Flag_thermal,:Flag_VRE,:Flag_mustrun,:Flag_UC,:Min_down_time,:Min_up_time,Symbol("Start_up_cost (\$/MW)")])
		Updated_PCM_Gendata_fillmean = fill_missing_with_group_mean(Updated_PCM_Gendata,[:Type],[Symbol("Pmin (MW)"),Symbol("Cost (\$/MWh)"),:EF,:CC,:FOR,:RM_SPIN,:RU,:RD,:Flag_thermal,:Flag_VRE,:Flag_mustrun,:Flag_UC,:Min_down_time,:Min_up_time,Symbol("Start_up_cost (\$/MW)")])
	else
		Updated_PCM_Gendata_fillmean = fill_missing_with_group_mean(Updated_PCM_Gendata,[:Zone, :Type],[Symbol("Pmin (MW)"),Symbol("Cost (\$/MWh)"),:EF,:CC,:FOR,:RM_SPIN,:RU,:RD,:Flag_thermal,:Flag_VRE,:Flag_mustrun])
		Updated_PCM_Gendata_fillmean = fill_missing_with_group_mean(Updated_PCM_Gendata,[:Type],[Symbol("Pmin (MW)"),Symbol("Cost (\$/MWh)"),:EF,:CC,:FOR,:RM_SPIN,:RU,:RD,:Flag_thermal,:Flag_VRE,:Flag_mustrun])
	end
	#update storagedata
	PCM_Storagedata =  PCM_input["Storagedata"]
	Updated_PCM_Storagedata = outerjoin(PCM_Storagedata,New_Build_ES_sub, on = [:Zone,:Type, Symbol("Capacity (MWh)"),Symbol("Max Power (MW)")])
	#Fill missing value with mean
	convert_columns_to_float64!(Updated_PCM_Storagedata,[Symbol("Capacity (MWh)"),Symbol("Max Power (MW)"),Symbol("Charging efficiency"),Symbol("Discharging efficiency"),Symbol("Cost (\$/MWh)"),:EF,:CC,Symbol("Charging Rate"),Symbol("Discharging Rate")])
	Updated_PCM_Storagedata_fillmean = fill_missing_with_group_mean(Updated_PCM_Storagedata,[:Zone, :Type],[Symbol("Capacity (MWh)"),Symbol("Max Power (MW)"),Symbol("Charging efficiency"),Symbol("Discharging efficiency"),Symbol("Cost (\$/MWh)"),:EF,:CC,Symbol("Charging Rate"),Symbol("Discharging Rate")])
	Updated_PCM_Storagedata_fillmean = fill_missing_with_group_mean(Updated_PCM_Storagedata,[:Type],[Symbol("Capacity (MWh)"),Symbol("Max Power (MW)"),Symbol("Charging efficiency"),Symbol("Discharging efficiency"),Symbol("Cost (\$/MWh)"),:EF,:CC,Symbol("Charging Rate"),Symbol("Discharging Rate")])
	#update linedata
	PCM_Linedata =  PCM_input["Linedata"]
	Updated_PCM_Linedata = outerjoin(PCM_Linedata,New_Build_Line_sub, on = [:From_zone,:To_zone, Symbol("Capacity (MW)")])

	#Set solver configuration
	optimizer =  initiate_solver(config_set["solver"],PCM_inpath)
	#read in data
	println("Second stage: updating 'PCM' capacity!")
	input_data = load_data(config_set,PCM_inpath)
	#update input_data
	input_data["Gendata"] = Updated_PCM_Gendata_fillmean
	input_data["Storagedata"]= Updated_PCM_Storagedata_fillmean
	input_data["Linedata"] =  Updated_PCM_Linedata
	#create model
	New_PCM_model = create_PCM_model(config_set,input_data,optimizer)
	#solve model
	Sovled_new_PCM_model = solve_model(config_set, input_data, New_PCM_model)

	#write outputs
	New_PCM_output = write_output(PCM_outpath, config_set, input_data, Sovled_new_PCM_model)
	println("Holistic Two-stage 'GTEP-PCM' mode is successfully solved!")
	#return (Sovled_new_PCM_model, New_PCM_output)
end
