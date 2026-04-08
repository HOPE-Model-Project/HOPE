"""
    solve_model(config_set::Dict, input_data::Dict, model::Model)

Solve the HOPE optimization model and print results.

# Arguments
- `config_set::Dict`: Configuration settings from YAML file
- `input_data::Dict`: Input data loaded from files
- `model::Model`: JuMP model to solve

# Returns
- `Model`: The solved optimization model

# Throws
- Optimization errors if model fails to solve
"""
function has_feasible_primal_solution(model::Model)
	pr_status = primal_status(model)
	return result_count(model) > 0 && pr_status in (MOI.FEASIBLE_POINT, MOI.NEARLY_FEASIBLE_POINT)
end

function require_feasible_primal_solution(model::Model; context::AbstractString="Model solve")
	term_status = termination_status(model)
	pr_status = primal_status(model)
	n_results = result_count(model)
	if !has_feasible_primal_solution(model)
		throw(ArgumentError("$(context) did not find a feasible primal solution. termination_status=$(term_status), primal_status=$(pr_status), result_count=$(n_results)"))
	end
	return nothing
end

function solve_model(config_set::Dict, input_data::Dict, model::Model)
    model_mode = config_set["model_mode"]
	## Start solve timer
	solver_start_time = time()
	optimize!(model)
	term_status = termination_status(model)
	pr_status = primal_status(model)
	has_primal_solution = has_feasible_primal_solution(model)

	# Optional second pass for MILP: fix discrete vars and re-solve LP for dual prices.
	# Applies to:
	# - PCM with integer UC (unit_commitment=1)
	# - GTEP with binary investment decisions (inv_dcs_bin=1)
	write_shadow_prices_raw = get(config_set, "write_shadow_prices", 0)
	write_shadow_prices = write_shadow_prices_raw isa Integer ? Int(write_shadow_prices_raw) : parse(Int, string(write_shadow_prices_raw))
	solver_name = lowercase(string(get(config_set, "solver", "")))
	need_lp_reresolve = false
	if write_shadow_prices == 1
		if model_mode == "PCM"
			unit_commitment_raw = get(config_set, "unit_commitment", 0)
			unit_commitment_mode = unit_commitment_raw isa Integer ? Int(unit_commitment_raw) : parse(Int, string(unit_commitment_raw))
			need_lp_reresolve = unit_commitment_mode == 1
		elseif model_mode == "GTEP"
			inv_dcs_bin_raw = get(config_set, "inv_dcs_bin", 0)
			inv_dcs_bin_mode = inv_dcs_bin_raw isa Integer ? Int(inv_dcs_bin_raw) : parse(Int, string(inv_dcs_bin_raw))
			need_lp_reresolve = inv_dcs_bin_mode == 1
		end
	end
	if need_lp_reresolve
		if solver_name == "cbc"
			println("write_shadow_prices=1 requested, but CBC does not provide dual prices for this workflow. Skipping LP re-solve.")
		else
			if has_primal_solution
				println("write_shadow_prices=1: fixing discrete variables and re-solving LP for dual prices...")
				local undo_relax = nothing
				try
					undo_relax = fix_discrete_variables(model)
					optimize!(model)
					term_status = termination_status(model)
					pr_status = primal_status(model)
					has_primal_solution = pr_status in (MOI.FEASIBLE_POINT, MOI.NEARLY_FEASIBLE_POINT)
					if has_duals(model)
						println("LP re-solve complete. Dual prices are available for output.")
					else
						println("LP re-solve complete, but dual prices are still unavailable from solver/model state.")
					end
				catch e
					println("Warning: LP re-solve for shadow prices failed. Keeping MILP solution. Error: $(e)")
					if undo_relax !== nothing
						try
							undo_relax()
						catch
						end
					end
				end
			else
				println("Skipping LP re-solve for shadow prices because no feasible MILP point is available (primal_status=$(pr_status)).")
			end
		end
	end

	## Record solver time (includes optional second pass)
	solver_time = time() - solver_start_time

	##read input for print
	W=unique(input_data["Zonedata"][:,"State"])							#Set of states, index w/w’
	H=[h for h=1:size(input_data["Loaddata"],1)]
	PT_rps = 10^9
	RPSdata = input_data["RPSdata"]
	RPS=Dict(zip(RPSdata[:,:From_state],RPSdata[:,:RPS]))
	if model_mode == "GTEP"
		Estoragedata_candidate = input_data["Estoragedata_candidate"]
		Linedata_candidate = input_data["Linedata_candidate"]
		Gendata_candidate = input_data["Gendata_candidate"]
		#Printing results for debugging purpose-------------------------
		print("\n\n","Model mode: GTEP","\n\n");
		print("Termination_status= ",term_status,"\n\n");
		print("Primal_status= ",pr_status,"\n\n");
		if !has_primal_solution
			print("No primal solution available. Skipping objective and variable value prints.\n\n")
			print("Solving time: ", solver_time)
			return model
		end
		print("\n\n","Objective_value= ",objective_value(model),"\n\n");
		print("Investment_cost= ",value.(model[:INVCost]),"\n\n");
		print("Operation_cost= ",value.(model[:OPCost]),"\n\n");
		print("Load_shedding= ",value.(model[:LoadShedding]),"\n\n");
		print("RPS_requirement ",RPS,"\n\n");
		print("RPSPenalty= ",value.(model[:RPSPenalty]),"\n\n");
		print("RPS:state:Pen",[(w,sum(PT_rps*value.(model[:pt_rps][w]))) for w in W ],"\n\n");
		print("CarbonCapPenalty= ",value.(model[:CarbonCapPenalty]),"\n\n");
		print("CarbonCapEmissions= ",[(w,value.(model[:CarbonEmission][w])) for w in W],"\n\n");

		y_val = [Float64(value(model[:y][l])) for l in axes(model[:y], 1)]
		x_val = [Float64(value(model[:x][g])) for g in axes(model[:x], 1)]
		z_val = [Float64(value(model[:z][s])) for s in axes(model[:z], 1)]
		print("Selected_lines= ",y_val,"\n\n");
		Linedata_candidate[!, "Capacity (MW)"] = Float64.(Linedata_candidate[:, "Capacity (MW)"]) .* y_val
		print("Selected_lines_table",Linedata_candidate[[i for (i, v) in enumerate(y_val) if v > 0],:],"\n\n");
		print("Selected_units= ",x_val,"\n\n");
		Gendata_candidate[!, "Pmax (MW)"] = Float64.(Gendata_candidate[:, "Pmax (MW)"]) .* x_val
		print("Selected_units_table",Gendata_candidate[[i for (i, v) in enumerate(x_val) if v > 0],:],"\n\n");
		print("Selected_storage= ",z_val,"\n\n");
		Estoragedata_candidate[!, "Capacity (MWh)"] = Float64.(Estoragedata_candidate[:, "Capacity (MWh)"]) .* z_val
		Estoragedata_candidate[!, "Max Power (MW)"] = Float64.(Estoragedata_candidate[:, "Max Power (MW)"]) .* z_val
		print("Selected_storage_table",Estoragedata_candidate[[i for (i, v) in enumerate(z_val) if v > 0],:],"\n\n")
		#-----------------------------------------------------------
		print("Solving time: ", solver_time)
	elseif model_mode == "PCM"
		#Printing results for debugging purpose-------------------------
		print("\n\n","Model mode: PCM","\n\n");
		print("Termination_status= ",term_status,"\n\n");
		print("Primal_status= ",pr_status,"\n\n");
		if !has_primal_solution
			print("No primal solution available. Skipping objective and variable value prints.\n\n")
			print("Solving time: ", solver_time)
			return model
		end
		print("\n\n","Objective_value= ",objective_value(model),"\n\n");
		#print("Investment_cost= ",value.(INVCost),"\n\n");
		if config_set["unit_commitment"]!=0
			print("Startup_cost= ",value.(model[:STCost]),"\n\n");
		end
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
