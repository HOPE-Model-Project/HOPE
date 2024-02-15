function solve_model(config_set::Dict, input_data::Dict, model::Model)
    model_mode = config_set["model_mode"]
	## Start solve timer
	solver_start_time = time()
	solver_time = time()
	optimize!(model)
	## Record solver time
	solver_time = time() - solver_start_time

	##read input for print	
	W=unique(input_data["Zonedata"][:,"State"])							#Set of states, index w/w’
	RPSdata = input_data["RPSdata"]
	RPS=Dict(zip(RPSdata[:,:From_state],RPSdata[:,:RPS]))
	if model_mode == "GTEP"
		Estoragedata_candidate = input_data["Estoragedata_candidate"]
		Linedata_candidate = input_data["Linedata_candidate"]
		Gendata_candidate = input_data["Gendata_candidate"]
		#Printing results for debugging purpose-------------------------
		print("\n\n","Model mode: GTEP","\n\n");
		print("\n\n","Objective_value= ",objective_value(model),"\n\n");
		print("Investment_cost= ",value.(model[:INVCost]),"\n\n");
		print("Operation_cost= ",value.(model[:OPCost]),"\n\n");
		print("Load_shedding= ",value.(model[:LoadShedding]),"\n\n");
		print("RPS_requirement ",RPS,"\n\n");
		print("RPSPenalty= ",value.(model[:RPSPenalty]),"\n\n");
		print("CarbonCapPenalty= ",value.(model[:CarbonCapPenalty]),"\n\n");
		print("CarbonCapEmissions= ",[(w,value.(model[:CarbonEmission][w])) for w in W],"\n\n");
		
		print("Selected_lines= ",value.(model[:y]),"\n\n");
		Linedata_candidate[:,"Capacity (MW)"] .= [v for (i,v) in enumerate(Linedata_candidate[:,"Capacity (MW)"] .*value.(model[:y]))]
		print("Selected_lines_table",Linedata_candidate[[i for (i, v) in enumerate(value.(model[:y])) if v > 0],:],"\n\n");
		print("Selected_units= ",value.(model[:x]),"\n\n");
		Gendata_candidate[:,"Pmax (MW)"] .= [v for (i,v) in enumerate(Gendata_candidate[:,"Pmax (MW)"] .*value.(model[:x]))]
		print("Selected_units_table",Gendata_candidate[[i for (i, v) in enumerate(value.(model[:x])) if v > 0],:],"\n\n");
		print("Selected_storage= ",value.(model[:z]),"\n\n");
		Estoragedata_candidate[:,"Capacity (MWh)"] .= [v for (i,v) in enumerate(Estoragedata_candidate[:,"Capacity (MWh)"] .*value.(model[:z]))]
		Estoragedata_candidate[:,"Max Power (MW)"] .= [v for (i,v) in enumerate(Estoragedata_candidate[:,"Max Power (MW)"] .*value.(model[:z]))]
		print("Selected_storage_table",Estoragedata_candidate[[i for (i, v) in enumerate(value.(model[:z])) if v > 0],:],"\n\n")
		#-----------------------------------------------------------
		print("Solving time: ", solver_time)
	elseif model_mode == "PCM"
		#Printing results for debugging purpose-------------------------
		print("\n\n","Model mode: PCM","\n\n");
		print("\n\n","Objective_value= ",objective_value(model),"\n\n");
		#print("Investment_cost= ",value.(INVCost),"\n\n");
		print("Operation_cost= ",value.(model[:OPCost]),"\n\n");
		print("Load_shedding= ",value.(model[:LoadShedding]),"\n\n");
		print("RPS_requirement ",RPS,"\n\n");
		print("RPSPenalty= ",value.(model[:RPSPenalty]),"\n\n");
		print("CarbonCapPenalty= ",value.(model[:CarbonCapPenalty]),"\n\n");
		print("CarbonCapEmissions= ",[(w,value.(model[:CarbonEmission][w])) for w in W],"\n\n");
		print("Solving time: ", solver_time)
	end
	return  model
end



