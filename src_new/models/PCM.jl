"""
# PCM.jl - Production Cost Model using Modular ConstraintPool Architecture
# 
# NEW APPROACH: 
# - PCM.jl orchestrates model building and calls ConstraintPool functions
# - All constraints come from ConstraintPool (NOT hard-coded!)
# - Reusable constraint functions can be shared with GTEP and other models
# 
# Model formulation reference: https://hope-model-project.github.io/HOPE/dev/PCM/
"""

module PCM

using JuMP
using DataFrames
using ..ConstraintPool

"""
    PCMModel

Lightweight structure that orchestrates PCM model building using ConstraintPool
"""
mutable struct PCMModel
    # Core JuMP model
    model::Model
    
    # Input data and configuration
    input_data::Dict
    config::Dict
    time_manager::Any  # TimeManager object
    
    # Model components (generated through ConstraintPool)
    sets::Dict{String, Any}
    parameters::Dict{String, Any}
    variables::Dict{String, Any}
    objective::Dict{String, Any}  # Add missing objective field
    
    # Results storage
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
            Dict(),  # Initialize objective
            Dict()
        )
    end
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
    RPSdata = input_data["RPSdata"]
    CBPdata = input_data["CBPdata"]
    
    Num_zone = size(Zonedata, 1)
    Num_gen = size(Gendata, 1)
    Num_line = size(Linedata, 1)
    Num_storage = size(Storagedata, 1)
    
    # Create zone mapping dictionaries
    Idx_zone_dict = Dict(zip(1:Num_zone, Zonedata[:, "Zone_id"]))
    Zone_idx_dict = Dict(zip(Zonedata[:, "Zone_id"], 1:Num_zone))
    Ordered_zone_nm = [Idx_zone_dict[i] for i in 1:Num_zone]
    
    sets = pcm_model.sets
    
    # ============================================================================
    # PRIMARY SETS
    # ============================================================================
    sets["I"] = collect(1:Num_zone)                    # Set of zones/buses, index i
    sets["J"] = sets["I"]                              # Set of zones/buses, index j
    sets["G"] = collect(1:Num_gen)                     # Set of generators, index g
    sets["L"] = collect(1:Num_line)                    # Set of transmission lines, index l
    sets["S"] = collect(1:Num_storage)                 # Set of storage units, index s
    # Set time horizon based on configuration or default to full year
    time_horizon = get(config, "hours", 8760)
    sets["H"] = collect(1:time_horizon)                 # Set of hours, index h
    sets["T"] = collect(1:4)                           # Set of time periods, index t
    sets["D"] = sets["I"]                              # Set of demand nodes (same as zones), index d
    sets["W"] = unique(Zonedata[:, "State"])           # Set of states, index w
    sets["K"] = unique(Gendata[:, "Type"])             # Set of technology types, index k
    
    # ============================================================================
    # GENERATOR SUBSETS
    # ============================================================================
    sets["G_exist"] = collect(1:Num_gen)                                # Existing generators
    sets["G_thermal"] = findall(x -> x == 1, Gendata[:, "Flag_thermal"]) # Thermal generators
    sets["G_mustrun"] = findall(x -> x == 1, Gendata[:, "Flag_mustrun"]) # Must-run generators
    sets["G_wind"] = findall(x -> x in ["WindOn", "WindOff"], Gendata[:, "Type"]) # Wind generators
    sets["G_solar"] = findall(x -> x == "SolarPV", Gendata[:, "Type"])   # Solar generators
    sets["G_renewable"] = findall(x -> x in ["Hydro", "MSW", "Bio", "Landfill_NG", "WindOn", "WindOff", "SolarPV"], Gendata[:, "Type"]) # RPS-eligible generators
    
    # Unit commitment subset (if enabled)
    if get(config, "unit_commitment", 0) != 0
        sets["G_UC"] = findall(x -> x == 1, Gendata[:, "Flag_UC"])      # Unit commitment generators
    end
    
    # ============================================================================
    # STORAGE SUBSETS
    # ============================================================================
    sets["S_exist"] = collect(1:Num_storage)                            # Existing storage units
    
    # ============================================================================
    # TRANSMISSION SUBSETS
    # ============================================================================
    sets["L_exist"] = collect(1:Num_line)                               # Existing transmission lines
    
    # ============================================================================
    # GEOGRAPHIC SUBSETS
    # ============================================================================
    # Generators by zone
    sets["G_i"] = [findall(Gendata[:, "Zone"] .== Idx_zone_dict[i]) for i in sets["I"]]
    
    # Storage by zone
    sets["S_i"] = [findall(Storagedata[:, "Zone"] .== Idx_zone_dict[i]) for i in sets["I"]]
    
    # Transmission lines by zone (sending)
    sets["LS_i"] = [findall(Linedata[:, "From_zone"] .== Idx_zone_dict[i]) for i in sets["I"]]
    
    # Transmission lines by zone (receiving)
    sets["LR_i"] = [findall(Linedata[:, "To_zone"] .== Idx_zone_dict[i]) for i in sets["I"]]
    
    # Zones by state
    sets["I_w"] = Dict(w => findall(Zonedata[:, "State"] .== w) for w in sets["W"])
    
    # RPS Trading sets (for renewable credits trading between states)
    sets["WER_w"] = Dict(zip(unique(RPSdata[:, "From_state"]), 
                             [RPSdata[findall(RPSdata[:, "From_state"] .== i), "To_state"] for i in unique(RPSdata[:, "From_state"])]))
    [sets["WER_w"][w] = [] for w in unique(RPSdata[:, "From_state"]) if [w] == sets["WER_w"][w]]
    
    sets["WIR_w"] = Dict(zip(unique(RPSdata[:, "From_state"]), 
                             [unique(push!(RPSdata[findall(RPSdata[:, "From_state"] .== i), "To_state"], i)) for i in unique(RPSdata[:, "From_state"])]))
    
    # ============================================================================
    # TIME SUBSETS
    # ============================================================================
    sets["HD"] = collect(1:24)                                          # Hours in a day
    
    # Time periods (if using representative periods)
    if get(config, "representative_day!", 0) == 1
        # This will be handled by the time manager
        # For now, use simple time periods
        sets["H_t"] = Dict(t => collect(((t-1)*2160+1):(t*2160)) for t in sets["T"])
    else
        # Full year operation
        sets["H_t"] = Dict(1 => sets["H"])
        sets["T"] = [1]
    end
    
    # ============================================================================
    # MAPPING DICTIONARIES
    # ============================================================================
    sets["mappings"] = Dict(
        "idx_zone" => Idx_zone_dict,
        "zone_idx" => Zone_idx_dict,
        "ordered_zones" => Ordered_zone_nm
    )
    
    println("   ✅ PCM Sets created successfully")
    println("      Zones: $(length(sets["I"])), Generators: $(length(sets["G"]))")
    println("      Lines: $(length(sets["L"])), Storage: $(length(sets["S"]))")
    println("      Hours: $(length(sets["H"])), Time periods: $(length(sets["T"]))")
end

"""
    create_pcm_parameters!(pcm_model::PCMModel)

Define all parameters for the PCM model with transparent documentation
"""
function create_pcm_parameters!(pcm_model::PCMModel)
    println("📊 Creating PCM Parameters...")
    
    input_data = pcm_model.input_data
    config = pcm_model.config
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
    CBPdata = input_data["CBPdata"]
    RPSdata = input_data["RPSdata"]
    Singlepar = input_data["Singlepar"]
    
    # ============================================================================
    # GENERATOR PARAMETERS
    # ============================================================================
    parameters["P_max"] = Gendata[:, "Pmax (MW)"]                       # Maximum capacity [MW]
    parameters["P_min"] = Gendata[:, "Pmin (MW)"]                       # Minimum capacity [MW]
    parameters["VCG"] = Gendata[:, "Cost (\$/MWh)"]                     # Variable cost [$/MWh]
    parameters["EF"] = Gendata[:, "EF"]                                 # Emission factor [t/MWh]
    parameters["FOR"] = Dict(zip(sets["G"], Gendata[:, "FOR"]))         # Forced outage rate
    parameters["CC"] = Gendata[:, "CC"]                                 # Capacity credit
    parameters["G_zone"] = Gendata[:, "Zone"]                           # Generator zone mapping
    
    # Ramping parameters
    parameters["RU"] = Dict(zip(sets["G"], Gendata[:, "RU"]))           # Ramp up rate
    parameters["RD"] = Dict(zip(sets["G"], Gendata[:, "RD"]))           # Ramp down rate
    parameters["RM_SPIN"] = Dict(zip(sets["G"], Gendata[:, "RM_SPIN"])) # Spinning reserve capability
    
    # Unit commitment parameters (if enabled)
    if get(config, "unit_commitment", 0) != 0
        parameters["Min_up_time"] = Gendata[:, "Min_up_time"]            # Minimum up time
        parameters["Min_down_time"] = Gendata[:, "Min_down_time"]        # Minimum down time
        parameters["Start_up_cost"] = Gendata[:, "Start_up_cost (\$/MW)"] # Start-up cost [$/MW]
    end
    
    # ============================================================================
    # STORAGE PARAMETERS
    # ============================================================================
    parameters["SCAP"] = Storagedata[:, "Max Power (MW)"]               # Storage power capacity [MW]
    parameters["SECAP"] = Storagedata[:, "Capacity (MWh)"]              # Storage energy capacity [MWh]
    parameters["VCS"] = Storagedata[:, "Cost (\$/MWh)"]                 # Storage variable cost [$/MWh]
    parameters["SC"] = Storagedata[:, "Charging Rate"]                  # Charging rate
    parameters["SD"] = Storagedata[:, "Discharging Rate"]               # Discharging rate
    parameters["e_ch"] = Storagedata[:, "Charging efficiency"]          # Charging efficiency
    parameters["e_dis"] = Storagedata[:, "Discharging efficiency"]      # Discharging efficiency
    parameters["CC_s"] = Storagedata[:, "CC"]                           # Storage capacity credit
    
    # ============================================================================
    # TRANSMISSION PARAMETERS
    # ============================================================================
    parameters["F_max"] = Linedata[:, "Capacity (MW)"]                  # Line capacity [MW]
    
    # ============================================================================
    # DEMAND PARAMETERS
    # ============================================================================
    parameters["PK"] = Zonedata[:, "Demand (MW)"]                       # Peak demand [MW]
      # Load time series (normalized to peak)
    ordered_zones = sets["mappings"]["ordered_zones"]
    parameters["P_load"] = Dict()
    for (i, zone) in enumerate(ordered_zones)
        if zone in names(Loaddata)
            # Take only the first part of the time series to match our reduced hours
            full_load = Loaddata[:, zone]
            parameters["P_load"][i] = full_load[1:length(sets["H"])]
        else
            @warn "Zone $zone not found in load data"
            parameters["P_load"][i] = ones(length(sets["H"]))  # Default to flat profile
        end
    end
    
    # Net imports - Fixed to match old PCM structure
    parameters["NI"] = Dict()
    for h in sets["H"], i in sets["I"]
        weight = parameters["PK"][i] / sum(parameters["PK"])
        parameters["NI"][(h, i)] = NIdata[h] * weight
    end
    
    # ============================================================================
    # RENEWABLE AVAILABILITY FACTORS - FIXED to match old PCM structure
    # ============================================================================
    parameters["AFRE"] = Dict()
    
    # Wind availability factors: AFRE[g][(h, i)] = availability
    for g in sets["G_wind"]
        parameters["AFRE"][g] = Dict()
        zone_id = Gendata[g, "Zone"]
        zone_idx = findfirst(x -> x == zone_id, ordered_zones)
        if zone_idx !== nothing && zone_id in names(Winddata)
            full_wind = Winddata[:, zone_id]
            for h in sets["H"], i in sets["I"]
                if i == zone_idx
                    parameters["AFRE"][g][(h, i)] = full_wind[h]
                else
                    parameters["AFRE"][g][(h, i)] = 0.0  # Not available at other zones
                end
            end
        else
            @warn "Wind data not found for generator $g in zone $zone_id"
            for h in sets["H"], i in sets["I"]
                parameters["AFRE"][g][(h, i)] = 0.0
            end
        end
    end
    
    # Solar availability factors: AFRE[g][(h, i)] = availability
    for g in sets["G_solar"]
        parameters["AFRE"][g] = Dict()
        zone_id = Gendata[g, "Zone"]
        zone_idx = findfirst(x -> x == zone_id, ordered_zones)
        if zone_idx !== nothing && zone_id in names(Solardata)
            full_solar = Solardata[:, zone_id]
            for h in sets["H"], i in sets["I"]
                if i == zone_idx
                    parameters["AFRE"][g][(h, i)] = full_solar[h]
                else
                    parameters["AFRE"][g][(h, i)] = 0.0  # Not available at other zones
                end
            end
        else
            @warn "Solar data not found for generator $g in zone $zone_id"
            for h in sets["H"], i in sets["I"]
                parameters["AFRE"][g][(h, i)] = 0.0
            end
        end
    end
    
    # ============================================================================
    # POLICY PARAMETERS
    # ============================================================================
    # RPS requirements
    parameters["RPS"] = Dict(zip(RPSdata[:, "From_state"], RPSdata[:, "RPS"]))
    
    # Carbon emission limits
    CBP_state_data = combine(groupby(CBPdata, :State), Symbol("Allowance (tons)") => sum)
    parameters["ELMT"] = Dict(zip(CBP_state_data[:, "State"], CBP_state_data[:, "Allowance (tons)_sum"]))
    
    # ============================================================================
    # SYSTEM PARAMETERS
    # ============================================================================
    parameters["VOLL"] = Singlepar[1, "VOLL"]                          # Value of lost load [$/MWh]
    parameters["PT_rps"] = Singlepar[1, "PT_RPS"]                      # RPS violation penalty [$/MWh]
    parameters["PT_emis"] = Singlepar[1, "PT_emis"]                    # Emission violation penalty [$/t]
    parameters["BigM"] = Singlepar[1, "BigM"]                          # Big M parameter
    
    println("   ✅ PCM Parameters created successfully")
    println("      Generator params: P_max, P_min, VCG, EF, etc.")
    println("      Storage params: SCAP, SECAP, efficiencies, etc.")
    println("      System params: VOLL, penalties, emission limits")
end

"""
    create_pcm_variables!(pcm_model::PCMModel)

Define all variables for the PCM model with transparent documentation
"""
function create_pcm_variables!(pcm_model::PCMModel)
    println("🔧 Creating PCM Variables...")
    
    model = pcm_model.model
    sets = pcm_model.sets
    config = pcm_model.config
    
    variables = pcm_model.variables
    
    # ============================================================================
    # GENERATION VARIABLES
    # ============================================================================
    variables["p"] = @variable(model, p[sets["G"], sets["H"]] >= 0, 
                              base_name = "power_generation")           # Power generation [MW]
    
    variables["r_G"] = @variable(model, r_G[sets["G"], sets["H"]] >= 0, 
                                base_name = "spinning_reserve_gen")     # Spinning reserve from generators [MW]
    
    # ============================================================================
    # STORAGE VARIABLES
    # ============================================================================
    variables["soc"] = @variable(model, soc[sets["S"], sets["H"]] >= 0, 
                                base_name = "state_of_charge")          # State of charge [MWh]
    
    variables["c"] = @variable(model, c[sets["S"], sets["H"]] >= 0, 
                              base_name = "charging_power")             # Charging power [MW]
    
    variables["dc"] = @variable(model, dc[sets["S"], sets["H"]] >= 0, 
                               base_name = "discharging_power")         # Discharging power [MW]
    
    variables["r_S"] = @variable(model, r_S[sets["S"], sets["H"]] >= 0, 
                                base_name = "spinning_reserve_storage")  # Spinning reserve from storage [MW]
    
    # ============================================================================
    # TRANSMISSION VARIABLES
    # ============================================================================
    variables["f"] = @variable(model, f[sets["L"], sets["H"]], 
                              base_name = "transmission_flow")          # Transmission flow [MW]
    
    # ============================================================================
    # DEMAND VARIABLES
    # ============================================================================
    variables["p_LS"] = @variable(model, p_LS[sets["I"], sets["H"]] >= 0, 
                                 base_name = "load_shedding")           # Load shedding [MW]
    
    # ============================================================================
    # NET IMPORTS VARIABLES (matching old PCM)
    # ============================================================================
    variables["ni"] = @variable(model, ni[sets["H"], sets["I"]], 
                               base_name = "net_imports")               # Net imports [MW]
    
    # ============================================================================
    # POLICY VARIABLES
    # ============================================================================
    variables["pw"] = @variable(model, pw[sets["G_renewable"], sets["W"]] >= 0, 
                               base_name = "renewable_generation_state") # Annual renewable generation by state [MWh]
    
    variables["pwi"] = @variable(model, pwi[sets["G_renewable"], sets["W"], sets["W"]] >= 0, 
                                base_name = "renewable_credits_trade")   # Renewable credits trading [MWh]
    
    variables["pt_rps"] = @variable(model, pt_rps[sets["W"], sets["H"]] >= 0, 
                                   base_name = "rps_violation")          # RPS violation [MW]
    
    variables["em_emis"] = @variable(model, em_emis[sets["W"]] >= 0, 
                                    base_name = "emission_violation")    # Emission limit violation [ton]
    
    # ============================================================================
    # UNIT COMMITMENT VARIABLES (if enabled)
    # ============================================================================
    if get(config, "unit_commitment", 0) != 0
        if config["unit_commitment"] == 1  # Binary UC
            variables["o"] = @variable(model, o[sets["G_UC"], sets["H"]], Bin, 
                                      base_name = "unit_online")         # Unit online status (binary)
            variables["su"] = @variable(model, su[sets["G_UC"], sets["H"]], Bin, 
                                       base_name = "unit_startup")       # Unit startup (binary)
            variables["sd"] = @variable(model, sd[sets["G_UC"], sets["H"]], Bin, 
                                       base_name = "unit_shutdown")      # Unit shutdown (binary)
        elseif config["unit_commitment"] == 2  # Relaxed UC
            variables["o"] = @variable(model, 0 <= o[sets["G_UC"], sets["H"]] <= 1, 
                                      base_name = "unit_online")         # Unit online status (continuous)
            variables["su"] = @variable(model, 0 <= su[sets["G_UC"], sets["H"]] <= 1, 
                                       base_name = "unit_startup")       # Unit startup (continuous)
            variables["sd"] = @variable(model, 0 <= sd[sets["G_UC"], sets["H"]] <= 1, 
                                       base_name = "unit_shutdown")      # Unit shutdown (continuous)
        end
          variables["pmin"] = @variable(model, pmin[sets["G_UC"], sets["H"]] >= 0, 
                                     base_name = "minimum_generation")   # Minimum generation [MW]
    end
    
    # ============================================================================
    # DEMAND RESPONSE VARIABLES (if enabled)
    # ============================================================================
    if get(config, "flexible_demand", 0) == 1
        variables["dr"] = @variable(model, dr[sets["D"], sets["H"]] >= 0, 
                                   base_name = "demand_response")        # Demand response [MW]
        variables["dr_UP"] = @variable(model, dr_UP[sets["D"], sets["H"]] >= 0, 
                                      base_name = "demand_response_up")  # Demand response up [MW]
        variables["dr_DN"] = @variable(model, dr_DN[sets["D"], sets["H"]] >= 0, 
                                      base_name = "demand_response_down") # Demand response down [MW]
    end
    
    println("   ✅ PCM Variables created successfully")
    # Simple variable count 
    println("      Total variable groups: $(length(pcm_model.variables))")
end

"""
    create_pcm_constraints!(pcm_model::PCMModel)

Apply PCM constraints using direct, transparent constraint functions that match the original PCM order
"""
function create_pcm_constraints!(pcm_model::PCMModel)
    # ============================================================================
    # APPLY CONSTRAINTS - Direct, transparent constraint functions in PCM order
    # ============================================================================
    
    println("🔗 Applying PCM Constraints with direct, transparent constraint functions...")
    
    # Constraint data for direct function calls
    sets = pcm_model.sets
    parameters = pcm_model.parameters
    variables = pcm_model.variables
    config = pcm_model.config
    model = pcm_model.model
    
    # (1) Power balance constraints - Main constraint from original PCM
    println("   📊 (1) Power balance constraints...")
    ConstraintPool.add_power_balance_con!(model, sets, parameters, variables)
    
    # (2) Generator capacity constraints - Non-UC generators only
    println("   ⚡ (2) Generator capacity constraints...")
    ConstraintPool.add_generator_capacity_con!(model, sets, parameters, variables, config)
    
    # (3) Renewable availability constraints
    println("   🌞 (3) Renewable availability constraints...")
    ConstraintPool.add_renewable_availability_con!(model, sets, parameters, variables)
    
    # (4) Transmission capacity constraints
    println("   🔌 (4) Transmission capacity constraints...")
    ConstraintPool.add_transmission_capacity_con!(model, sets, parameters, variables)
    
    # Storage constraints (only if storage exists)
    if !isempty(sets["S_exist"])
        # (5) Storage SOC evolution constraints
        println("   🔋 (5) Storage SOC evolution constraints...")
        ConstraintPool.add_storage_soc_evolution_con!(model, sets, parameters, variables)
        
        # (6) Storage cyclic constraints
        println("   🔄 (6) Storage cyclic constraints...")
        ConstraintPool.add_storage_cyclic_con!(model, sets, parameters, variables)
        
        # (7) Storage capacity constraints
        println("   📦 (7) Storage capacity constraints...")
        ConstraintPool.add_storage_capacity_con!(model, sets, parameters, variables)
    end
    
    # (8) Load shedding limit constraints
    println("   💡 (8) Load shedding limit constraints...")
    ConstraintPool.add_load_shedding_limit_con!(model, sets, parameters, variables)
    
    # (9) Net imports constraints
    println("   🌐 (9) Net imports constraints...")
    ConstraintPool.add_net_imports_con!(model, sets, parameters, variables)
    
    # (10) Spinning reserve constraints
    println("   🔄 (10) Spinning reserve constraints...")
    ConstraintPool.add_spinning_reserve_con!(model, sets, parameters, variables)
    
    # (11) Ramping up constraints
    println("   ⬆️  (11) Ramping up constraints...")
    ConstraintPool.add_ramping_up_con!(model, sets, parameters, variables)
    
    # (12) Ramping down constraints
    println("   ⬇️  (12) Ramping down constraints...")
    ConstraintPool.add_ramping_down_con!(model, sets, parameters, variables)
    
    # (13) Must-run constraints
    println("   🔒 (13) Must-run constraints...")
    ConstraintPool.add_must_run_con!(model, sets, parameters, variables)
    
    # Policy constraints
    println("   📋 (14) RPS annual constraints...")
    ConstraintPool.add_rps_annual_con!(model, sets, parameters, variables)
    
    println("   🏛️  (15) RPS state requirement constraints...")
    ConstraintPool.add_rps_state_requirement_con!(model, sets, parameters, variables)
    
    println("   🌍 (16) Emissions limit constraints...")
    ConstraintPool.add_emissions_limit_con!(model, sets, parameters, variables)
    
    # Unit commitment constraints (only if UC > 0)
    uc_setting = get(config, "unit_commitment", 0)
    if uc_setting > 0 && haskey(sets, "G_UC") && !isempty(sets["G_UC"])
        println("   🏭 Unit commitment constraints (UC=$uc_setting)...")
        
        # (UC-1) UC capacity constraints
        println("     ⚡ UC capacity constraints...")
        ConstraintPool.add_uc_capacity_con!(model, sets, parameters, variables)
        
        # (UC-2) UC state transition constraints
        println("     🔄 UC state transition constraints...")
        ConstraintPool.add_uc_transition_con!(model, sets, parameters, variables)
        
        # (UC-3) Minimum up time constraints
        println("     ⬆️  UC minimum up time constraints...")
        ConstraintPool.add_uc_min_up_time_con!(model, sets, parameters, variables)
        
        # (UC-4) Minimum down time constraints  
        println("     ⬇️  UC minimum down time constraints...")
        ConstraintPool.add_uc_min_down_time_con!(model, sets, parameters, variables)
    end
    
    println("   ✅ All PCM constraints applied through direct, transparent functions!")
    println("   🔍 Constraint structure is now transparent and matches original PCM order!")
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
    config = pcm_model.config
    
    objective = pcm_model.objective
    
    # Get variables
    p = variables["p"]
    c = variables["c"]
    dc = variables["dc"]
    p_LS = variables["p_LS"]
    pt_rps = variables["pt_rps"]
    em_emis = variables["em_emis"]
    
    # ============================================================================
    # OPERATING COST COMPONENTS
    # ============================================================================
    
    # (1) Generator operating cost
    objective["generation_cost"] = @expression(model,
        sum(parameters["VCG"][g] * sum(p[g, h] for h in sets["H"]) for g in sets["G"])
    )
    
    # (2) Storage operating cost
    if !isempty(sets["S_exist"])
        objective["storage_cost"] = @expression(model,
            sum(parameters["VCS"][s] * sum(c[s, h] + dc[s, h] for h in sets["H"]) for s in sets["S_exist"])
        )
    else
        objective["storage_cost"] = @expression(model, 0)
    end
    
    # (3) Load shedding penalty
    objective["load_shedding_penalty"] = @expression(model,
        parameters["VOLL"] * sum(p_LS[i, h] for i in sets["I"] for h in sets["H"])
    )
    
    # (4) RPS violation penalty
    objective["rps_penalty"] = @expression(model,
        parameters["PT_rps"] * sum(pt_rps[w, h] for w in sets["W"] for h in sets["H"])
    )
    
    # (5) Carbon emission violation penalty
    objective["emission_penalty"] = @expression(model,
        parameters["PT_emis"] * sum(em_emis[w] for w in sets["W"])
    )
    
    # ============================================================================
    # UNIT COMMITMENT COSTS (if enabled)
    # ============================================================================
    if get(config, "unit_commitment", 0) != 0 && haskey(variables, "su")
        su = variables["su"]
        objective["startup_cost"] = @expression(model,
            sum(parameters["Start_up_cost"][g] * sum(su[g, h] * parameters["P_max"][g] for h in sets["H"]) 
                for g in sets["G_UC"])
        )
    else
        objective["startup_cost"] = @expression(model, 0)
    end
    
    # ============================================================================
    # TOTAL OBJECTIVE
    # ============================================================================
    objective["total_cost"] = @expression(model,
        objective["generation_cost"] +
        objective["storage_cost"] +
        objective["load_shedding_penalty"] +
        objective["rps_penalty"] +
        objective["emission_penalty"] +
        objective["startup_cost"]
    )
    
    # Set the objective
    @objective(model, Min, objective["total_cost"])
    
    println("   ✅ PCM Objective created successfully")
    println("      Components: Generation, Storage, Load Shedding, RPS, Emissions, Start-up")
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

# Export main functions
export PCMModel, build_pcm_model!, solve_pcm_model!
export create_pcm_sets!, create_pcm_parameters!, create_pcm_variables!
export create_pcm_constraints!, create_pcm_objective!

end