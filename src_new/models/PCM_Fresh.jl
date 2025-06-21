"""
PCM.jl - Production Cost Model for HOPE

Transparent and modular implementation of the Production Cost Model
with clear separation of sets, parameters, variables, constraints, and objective

Model formulation reference: https://hope-model-project.github.io/HOPE/dev/PCM/
"""

module PCM

using JuMP
using DataFrames

export PCMModel, build_pcm_model!, solve_pcm_model!

"""
    PCMModel

Transparent structure containing all PCM model components
"""
mutable struct PCMModel
    # Model object
    model::Model
    
    # Data and configuration
    input_data::Dict
    config::Dict
    time_manager::Any  # TimeManager object
    
    # Model components (transparent structure)
    sets::Dict{String, Any}
    parameters::Dict{String, Any}
    variables::Dict{String, Any}
    constraints::Dict{String, Any}
    objective::Dict{String, Any}
    
    # Solution and results
    results::Dict{String, Any}
    
    function PCMModel()
        new(
            Model(),
            Dict(),
            Dict(),
            nothing,
            Dict(),
            Dict(),
            Dict(),
            Dict(),
            Dict(),
            Dict()
        )
    end
end

"""
    build_pcm_model!(pcm_model::PCMModel, input_data::Dict, config::Dict, time_manager, optimizer)

Build the complete PCM model with transparent structure
"""
function build_pcm_model!(pcm_model::PCMModel, input_data::Dict, config::Dict, time_manager, optimizer)
    println("🏗️  Building Complete PCM Model...")
    println("=" ^ 50)
    
    # Store input data and configuration
    pcm_model.input_data = input_data
    pcm_model.config = config
    pcm_model.time_manager = time_manager
    
    # Set optimizer
    set_optimizer(pcm_model.model, optimizer)
    
    # Build model components in order
    create_pcm_sets!(pcm_model)
    create_pcm_parameters!(pcm_model)
    create_pcm_variables!(pcm_model)
    create_pcm_constraints!(pcm_model)
    create_pcm_objective!(pcm_model)
    
    println("=" ^ 50)
    println("✅ PCM Model Build Complete!")
    println("   Model ready for optimization")
    
    return pcm_model
end

"""
    solve_pcm_model!(pcm_model::PCMModel)

Solve the PCM model and extract results
"""
function solve_pcm_model!(pcm_model::PCMModel)
    println("🔧 Solving PCM Model...")
    
    # Solve the model
    optimize!(pcm_model.model)
    
    # Check solution status
    status = termination_status(pcm_model.model)
    println("   Solver status: $status")
    
    if status == MOI.OPTIMAL
        println("   ✅ Optimal solution found!")
        
        # Extract results
        pcm_model.results["status"] = "optimal"
        pcm_model.results["objective_value"] = objective_value(pcm_model.model)
        pcm_model.results["solve_time"] = solve_time(pcm_model.model)
        
        # Extract variable values
        pcm_model.results["generation"] = value.(pcm_model.variables["p"])
        pcm_model.results["transmission"] = value.(pcm_model.variables["f"])
        pcm_model.results["load_shedding"] = value.(pcm_model.variables["p_LS"])
        
        if !isempty(pcm_model.sets["S_exist"])
            pcm_model.results["storage_soc"] = value.(pcm_model.variables["soc"])
            pcm_model.results["storage_charge"] = value.(pcm_model.variables["c"])
            pcm_model.results["storage_discharge"] = value.(pcm_model.variables["dc"])
        end
        
        println("   💰 Total cost: \$$(round(pcm_model.results["objective_value"], digits=2))")
        println("   ⏱️  Solve time: $(round(pcm_model.results["solve_time"], digits=2)) seconds")
        
    else
        println("   ❌ Solution not optimal: $status")
        pcm_model.results["status"] = string(status)
    end
    
    return pcm_model.results
end

"""
    create_pcm_sets!(pcm_model::PCMModel)

Define all sets for the PCM model with transparent documentation
"""
function create_pcm_sets!(pcm_model::PCMModel)
    println("📋 Creating PCM Sets...")
    
    input_data = pcm_model.input_data
    config = pcm_model.config
    
    # Extract basic dimensions
    Zonedata = input_data["Zonedata"]
    Gendata = input_data["Gendata"]
    Linedata = input_data["Linedata"]
    Storagedata = input_data["Storagedata"]
    
    Num_zone = size(Zonedata, 1)
    Num_gen = size(Gendata, 1)
    Num_line = size(Linedata, 1)
    Num_storage = size(Storagedata, 1)
    
    # Create zone mapping dictionaries
    Idx_zone_dict = Dict(zip(1:Num_zone, Zonedata[:, "Zone_id"]))
    Zone_idx_dict = Dict(zip(Zonedata[:, "Zone_id"], 1:Num_zone))
    Ordered_zone_nm = [Idx_zone_dict[i] for i in 1:Num_zone]
    
    sets = pcm_model.sets
    
    # Primary sets
    sets["I"] = collect(1:Num_zone)                    # Zones
    sets["G"] = collect(1:Num_gen)                     # Generators
    sets["L"] = collect(1:Num_line)                    # Lines
    sets["S"] = collect(1:Num_storage)                 # Storage
    sets["H"] = collect(1:8760)                        # Hours
    sets["W"] = unique(Zonedata[:, "State"])           # States
    
    # Generator subsets
    sets["G_exist"] = collect(1:Num_gen)
    sets["G_thermal"] = findall(x -> x == 1, Gendata[:, "Flag_thermal"])
    sets["G_mustrun"] = findall(x -> x == 1, Gendata[:, "Flag_mustrun"])
    sets["G_wind"] = findall(x -> x in ["WindOn", "WindOff"], Gendata[:, "Type"])
    sets["G_solar"] = findall(x -> x == "SolarPV", Gendata[:, "Type"])
    sets["G_renewable"] = findall(x -> x in ["Hydro", "MSW", "Bio", "Landfill_NG", "WindOn", "WindOff", "SolarPV"], Gendata[:, "Type"])
    
    # Geographic subsets
    sets["G_i"] = [findall(Gendata[:, "Zone"] .== Idx_zone_dict[i]) for i in sets["I"]]
    sets["S_i"] = [findall(Storagedata[:, "Zone"] .== Idx_zone_dict[i]) for i in sets["I"]]
    sets["LS_i"] = [findall(Linedata[:, "From_zone"] .== Idx_zone_dict[i]) for i in sets["I"]]
    sets["LR_i"] = [findall(Linedata[:, "To_zone"] .== Idx_zone_dict[i]) for i in sets["I"]]
    sets["I_w"] = Dict(w => findall(Zonedata[:, "State"] .== w) for w in sets["W"])
    
    # Mappings
    sets["mappings"] = Dict(
        "idx_zone" => Idx_zone_dict,
        "zone_idx" => Zone_idx_dict,
        "ordered_zones" => Ordered_zone_nm
    )
    
    println("   ✅ PCM Sets created successfully")
end

"""
    create_pcm_parameters!(pcm_model::PCMModel)

Define all parameters for the PCM model
"""
function create_pcm_parameters!(pcm_model::PCMModel)
    println("📊 Creating PCM Parameters...")
    
    input_data = pcm_model.input_data
    sets = pcm_model.sets
    parameters = pcm_model.parameters
    
    # Extract data
    Zonedata = input_data["Zonedata"]
    Gendata = input_data["Gendata"]
    Linedata = input_data["Linedata"]
    Storagedata = input_data["Storagedata"]
    Loaddata = input_data["Loaddata"]
    Winddata = input_data["Winddata"]
    Solardata = input_data["Solardata"]
    NIdata = input_data["NIdata"]
    Singlepar = input_data["Singlepar"]
    
    # Generator parameters
    parameters["P_max"] = Gendata[:, "Pmax (MW)"]
    parameters["P_min"] = Gendata[:, "Pmin (MW)"]
    parameters["VCG"] = Gendata[:, "Cost (\$/MWh)"]
    parameters["EF"] = Gendata[:, "EF"]
    parameters["FOR"] = Dict(zip(sets["G"], Gendata[:, "FOR"]))
    
    # Storage parameters
    if !isempty(sets["S"])
        parameters["SCAP"] = Storagedata[:, "Max Power (MW)"]
        parameters["SECAP"] = Storagedata[:, "Capacity (MWh)"]
        parameters["VCS"] = Storagedata[:, "Cost (\$/MWh)"]
        parameters["e_ch"] = Storagedata[:, "Charging efficiency"]
        parameters["e_dis"] = Storagedata[:, "Discharging efficiency"]
    end
    
    # Transmission parameters
    parameters["F_max"] = Linedata[:, "Capacity (MW)"]
    
    # Load parameters
    parameters["PK"] = Zonedata[:, "Demand (MW)"]
    ordered_zones = sets["mappings"]["ordered_zones"]
    parameters["P_load"] = Dict()
    for (i, zone) in enumerate(ordered_zones)
        if zone in names(Loaddata)
            parameters["P_load"][i] = Loaddata[:, zone]
        else
            parameters["P_load"][i] = ones(8760)
        end
    end
    
    # System parameters
    parameters["VOLL"] = Singlepar[1, "VOLL"]
    parameters["PT_rps"] = Singlepar[1, "PT_RPS"]
    parameters["PT_emis"] = Singlepar[1, "PT_emis"]
    
    println("   ✅ PCM Parameters created successfully")
end

"""
    create_pcm_variables!(pcm_model::PCMModel)

Define all variables for the PCM model
"""
function create_pcm_variables!(pcm_model::PCMModel)
    println("🔧 Creating PCM Variables...")
    
    model = pcm_model.model
    sets = pcm_model.sets
    variables = pcm_model.variables
    
    # Generation variables
    variables["p"] = @variable(model, p[sets["G"], sets["H"]] >= 0, base_name = "power_generation")
    
    # Storage variables (if any storage exists)
    if !isempty(sets["S"])
        variables["soc"] = @variable(model, soc[sets["S"], sets["H"]] >= 0, base_name = "state_of_charge")
        variables["c"] = @variable(model, c[sets["S"], sets["H"]] >= 0, base_name = "charging_power")
        variables["dc"] = @variable(model, dc[sets["S"], sets["H"]] >= 0, base_name = "discharging_power")
    end
    
    # Transmission variables
    variables["f"] = @variable(model, f[sets["L"], sets["H"]], base_name = "transmission_flow")
    
    # Load shedding variables
    variables["p_LS"] = @variable(model, p_LS[sets["I"], sets["H"]] >= 0, base_name = "load_shedding")
    
    # Policy variables
    variables["pt_rps"] = @variable(model, pt_rps[sets["W"], sets["H"]] >= 0, base_name = "rps_violation")
    variables["em_emis"] = @variable(model, em_emis[sets["W"]] >= 0, base_name = "emission_violation")
    
    println("   ✅ PCM Variables created successfully")
end

"""
    create_pcm_constraints!(pcm_model::PCMModel)

Define all constraints for the PCM model
"""
function create_pcm_constraints!(pcm_model::PCMModel)
    println("⚖️  Creating PCM Constraints...")
    
    model = pcm_model.model
    sets = pcm_model.sets
    parameters = pcm_model.parameters
    variables = pcm_model.variables
    constraints = pcm_model.constraints
    
    # Get variables
    p = variables["p"]
    f = variables["f"]
    p_LS = variables["p_LS"]
    
    # Power balance constraints
    constraints["power_balance"] = @constraint(model, [i in sets["I"], h in sets["H"]],
        # Generation in zone i
        sum(p[g, h] for g in sets["G_i"][i]; init=0) +
        # Storage contribution (if any)
        (haskey(variables, "dc") ? sum(variables["dc"][s, h] - variables["c"][s, h] for s in sets["S_i"][i]; init=0) : 0) +
        # Transmission inflow minus outflow
        sum(f[l, h] for l in sets["LR_i"][i]; init=0) -
        sum(f[l, h] for l in sets["LS_i"][i]; init=0)
        ==
        # Load demand minus load shedding
        parameters["P_load"][i][h] * parameters["PK"][i] - p_LS[i, h],
        base_name = "power_balance"
    )
    
    # Generator capacity constraints
    constraints["gen_capacity"] = @constraint(model, [g in sets["G"], h in sets["H"]],
        parameters["P_min"][g] <= p[g, h] <= (1 - parameters["FOR"][g]) * parameters["P_max"][g],
        base_name = "generator_capacity"
    )
    
    # Must-run generators
    if !isempty(sets["G_mustrun"])
        constraints["must_run"] = @constraint(model, [g in sets["G_mustrun"], h in sets["H"]],
            p[g, h] == (1 - parameters["FOR"][g]) * parameters["P_max"][g],
            base_name = "must_run_generators"
        )
    end
    
    # Transmission capacity constraints
    constraints["transmission_capacity"] = @constraint(model, [l in sets["L"], h in sets["H"]],
        -parameters["F_max"][l] <= f[l, h] <= parameters["F_max"][l],
        base_name = "transmission_capacity"
    )
    
    # Load shedding constraints
    constraints["load_shedding_limit"] = @constraint(model, [i in sets["I"], h in sets["H"]],
        0 <= p_LS[i, h] <= parameters["P_load"][i][h] * parameters["PK"][i],
        base_name = "load_shedding_limit"
    )
    
    # Storage constraints (if storage exists)
    if haskey(variables, "soc")
        add_storage_constraints!(pcm_model)
    end
    
    println("   ✅ PCM Constraints created successfully")
end

"""
    add_storage_constraints!(pcm_model::PCMModel)

Add storage-specific constraints
"""
function add_storage_constraints!(pcm_model::PCMModel)
    model = pcm_model.model
    sets = pcm_model.sets
    parameters = pcm_model.parameters
    variables = pcm_model.variables
    constraints = pcm_model.constraints
    
    soc = variables["soc"]
    c = variables["c"]
    dc = variables["dc"]
    
    # Storage power capacity
    constraints["storage_power"] = @constraint(model, [s in sets["S"], h in sets["H"]],
        c[s, h] + dc[s, h] <= parameters["SCAP"][s],
        base_name = "storage_power_capacity"
    )
    
    # Storage energy capacity
    constraints["storage_energy"] = @constraint(model, [s in sets["S"], h in sets["H"]],
        0 <= soc[s, h] <= parameters["SECAP"][s],
        base_name = "storage_energy_capacity"
    )
    
    # Storage operation (SOC evolution)
    constraints["storage_operation"] = @constraint(model, [s in sets["S"], h in sets["H"][2:end]],
        soc[s, h] == soc[s, h-1] + 
        parameters["e_ch"][s] * c[s, h] - dc[s, h] / parameters["e_dis"][s],
        base_name = "storage_operation"
    )
    
    # End-of-year balance
    constraints["storage_balance"] = @constraint(model, [s in sets["S"]],
        soc[s, 1] == soc[s, 8760],
        base_name = "storage_balance"
    )
end

"""
    create_pcm_objective!(pcm_model::PCMModel)

Define the objective function for the PCM model
"""
function create_pcm_objective!(pcm_model::PCMModel)
    println("🎯 Creating PCM Objective Function...")
    
    model = pcm_model.model
    sets = pcm_model.sets
    parameters = pcm_model.parameters
    variables = pcm_model.variables
    objective = pcm_model.objective
    
    p = variables["p"]
    p_LS = variables["p_LS"]
    pt_rps = variables["pt_rps"]
    em_emis = variables["em_emis"]
    
    # Generation cost
    objective["generation_cost"] = @expression(model,
        sum(parameters["VCG"][g] * sum(p[g, h] for h in sets["H"]) for g in sets["G"])
    )
    
    # Storage cost (if storage exists)
    if haskey(variables, "c")
        c = variables["c"]
        dc = variables["dc"]
        objective["storage_cost"] = @expression(model,
            sum(parameters["VCS"][s] * sum(c[s, h] + dc[s, h] for h in sets["H"]) for s in sets["S"])
        )
    else
        objective["storage_cost"] = @expression(model, 0)
    end
    
    # Load shedding penalty
    objective["load_shedding_penalty"] = @expression(model,
        parameters["VOLL"] * sum(p_LS[i, h] for i in sets["I"] for h in sets["H"])
    )
    
    # Policy penalties
    objective["rps_penalty"] = @expression(model,
        parameters["PT_rps"] * sum(pt_rps[w, h] for w in sets["W"] for h in sets["H"])
    )
    
    objective["emission_penalty"] = @expression(model,
        parameters["PT_emis"] * sum(em_emis[w] for w in sets["W"])
    )
    
    # Total objective
    objective["total_cost"] = @expression(model,
        objective["generation_cost"] +
        objective["storage_cost"] +
        objective["load_shedding_penalty"] +
        objective["rps_penalty"] +
        objective["emission_penalty"]
    )
    
    @objective(model, Min, objective["total_cost"])
    
    println("   ✅ PCM Objective created successfully")
end

end # module PCM
