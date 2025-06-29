"""
# ConstraintPool.jl - Direct Constraint Functions for HOPE Models
# 
# This module provides direct, clearly-named constraint functions that match
# the order and structure of the original PCM for transparent, one-to-one mapping.
# 
# Design principles:
# - Direct function calls (no registration system)
# - Clear, descriptive function names (e.g., add_power_balance_con!)
# - Functions follow the same order and comments as original PCM
# - Transparent and easily debuggable
# - Reusable across PCM, GTEP, and other HOPE models
"""

module ConstraintPool

using JuMP
using DataFrames

# ============================================================================
# DIRECT CONSTRAINT FUNCTIONS - PCM ORDER
# ============================================================================

"""
    add_power_balance_con!(model, sets, parameters, variables)

Power balance constraint (Main constraint #1 from original PCM):
Generation + Storage discharge + Net imports = Load + Storage charge + Load shedding
"""
function add_power_balance_con!(model::JuMP.Model, sets::Dict, parameters::Dict, variables::Dict)::Vector{JuMP.ConstraintRef}
    refs = JuMP.ConstraintRef[]
    
    p = variables["p"]              # Generation
    f = variables["f"]              # Transmission flow
    p_LS = variables["p_LS"]        # Load shedding
    ni = get(variables, "ni", nothing)      # Net imports (if they exist)
    
    # Storage variables (if they exist)
    c = get(variables, "c", nothing)     # Charging
    dc = get(variables, "dc", nothing)   # Discharging
    
    # Power balance at each zone for each hour
    for i in sets["I"], h in sets["H"]
        # Generation in zone i
        gen_total = sum(p[g, h] for g in sets["G_i"][i]; init=0)
        
        # Storage net output in zone i (if storage exists)
        storage_net = if c !== nothing && dc !== nothing && !isempty(sets["S_i"][i])
            sum(dc[s, h] - c[s, h] for s in sets["S_i"][i]; init=0)
        else
            0
        end
        
        # Net imports for zone i (if they exist)
        net_imports = if ni !== nothing
            ni[h, i]
        else
            0
        end
        
        # Transmission net inflow
        trans_net = sum(f[l, h] for l in sets["LR_i"][i]; init=0) - sum(f[l, h] for l in sets["LS_i"][i]; init=0)
        
        # Load demand
        load_demand = parameters["P_load"][i][h] * parameters["PK"][i]
        
        # Power balance constraint (matching original PCM)
        con_ref = @constraint(model, 
            gen_total + storage_net + net_imports + trans_net == load_demand - p_LS[i, h],
            base_name = "power_balance_$(i)_$(h)"
        )
        push!(refs, con_ref)
    end
    
    return refs
end

"""
    add_generator_capacity_con!(model, sets, parameters, variables, config)

Generator capacity constraints (Constraint #2 from original PCM):
P_min <= p[g,h] <= (1-FOR) * P_max for non-UC generators
"""
function add_generator_capacity_con!(model::JuMP.Model, sets::Dict, parameters::Dict, variables::Dict, config::Dict)::Vector{JuMP.ConstraintRef}
    refs = JuMP.ConstraintRef[]
    
    p = variables["p"]
    
    # Determine which generators to constrain (exclude UC generators if UC is enabled)
    uc_setting = get(config, "unit_commitment", 0)
    generators_to_constrain = if uc_setting != 0 && haskey(sets, "G_UC")
        setdiff(sets["G_exist"], sets["G_UC"])  # Non-UC generators
    else
        sets["G_exist"]  # All generators if no UC
    end
    
    for g in generators_to_constrain, h in sets["H"]
        # Lower bound
        con_ref_lower = @constraint(model,
            p[g, h] >= parameters["P_min"][g],
            base_name = "gen_capacity_lower_$(g)_$(h)"
        )
        push!(refs, con_ref_lower)
        
        # Upper bound  
        con_ref_upper = @constraint(model,
            p[g, h] <= (1 - parameters["FOR"][g]) * parameters["P_max"][g],
            base_name = "gen_capacity_upper_$(g)_$(h)"
        )
        push!(refs, con_ref_upper)
    end
    
    return refs
end

"""
    add_renewable_availability_con!(model, sets, parameters, variables)

Renewable availability constraints (Constraint #3 from original PCM):
p[g,h] <= AFRE[g,h] * P_max[g] for wind and solar generators
"""
function add_renewable_availability_con!(model::JuMP.Model, sets::Dict, parameters::Dict, variables::Dict)::Vector{JuMP.ConstraintRef}
    refs = JuMP.ConstraintRef[]
    
    p = variables["p"]
    
    # Wind and solar availability limits
    renewable_gens = union(get(sets, "G_wind", []), get(sets, "G_solar", []))
    
    for g in renewable_gens, h in sets["H"]
        # Get availability for this generator at this hour (fixed structure)
        zone_id = parameters["G_zone"][g]  # Zone where generator g is located
        zone_idx = findfirst(x -> x == zone_id, sets["mappings"]["ordered_zones"])
        if zone_idx !== nothing && haskey(parameters["AFRE"], g) && haskey(parameters["AFRE"][g], (h, zone_idx))
            availability = parameters["AFRE"][g][(h, zone_idx)]
        else
            availability = 0.0
        end
        
        con_ref = @constraint(model,
            p[g, h] <= availability * parameters["P_max"][g],
            base_name = "renewable_availability_$(g)_$(h)"
        )
        push!(refs, con_ref)
    end
    
    return refs
end

"""
    add_transmission_capacity_con!(model, sets, parameters, variables)

Transmission capacity constraints (Constraint #4 from original PCM):
-F_max[l] <= f[l,h] <= F_max[l]
"""
function add_transmission_capacity_con!(model::JuMP.Model, sets::Dict, parameters::Dict, variables::Dict)::Vector{JuMP.ConstraintRef}
    refs = JuMP.ConstraintRef[]
    
    f = variables["f"]
    
    for l in sets["L_exist"], h in sets["H"]
        con_ref = @constraint(model,
            -parameters["F_max"][l] <= f[l, h] <= parameters["F_max"][l],
            base_name = "transmission_capacity_$(l)_$(h)"
        )
        push!(refs, con_ref)
    end
    
    return refs
end

"""
    add_storage_soc_evolution_con!(model, sets, parameters, variables)

Storage state-of-charge evolution constraints (Constraint #5 from original PCM):
soc[s,h] = soc[s,h-1] + e_ch[s]*c[s,h] - dc[s,h]/e_dis[s]
"""
function add_storage_soc_evolution_con!(model::JuMP.Model, sets::Dict, parameters::Dict, variables::Dict)::Vector{JuMP.ConstraintRef}
    refs = JuMP.ConstraintRef[]
    
    if !haskey(variables, "soc") || isempty(sets["S_exist"])
        return refs
    end
    
    soc = variables["soc"]
    c = variables["c"]
    dc = variables["dc"]
    
    # State of charge evolution
    for s in sets["S_exist"], h in sets["H"][2:end]
        con_ref = @constraint(model,
            soc[s, h] == soc[s, h-1] + 
            parameters["e_ch"][s] * c[s, h] - dc[s, h] / parameters["e_dis"][s],
            base_name = "storage_soc_evolution_$(s)_$(h)"
        )
        push!(refs, con_ref)
    end
    
    return refs
end

"""
    add_storage_cyclic_con!(model, sets, parameters, variables)

Storage cyclic constraints (Constraint #6 from original PCM):
Initial = Final SOC
"""
function add_storage_cyclic_con!(model::JuMP.Model, sets::Dict, parameters::Dict, variables::Dict)::Vector{JuMP.ConstraintRef}
    refs = JuMP.ConstraintRef[]
    
    if !haskey(variables, "soc") || isempty(sets["S_exist"])
        return refs
    end
    
    soc = variables["soc"]
    
    # Initial = Final (cyclic constraint)
    for s in sets["S_exist"]
        con_ref = @constraint(model,
            soc[s, 1] == soc[s, length(sets["H"])],
            base_name = "storage_cyclic_$(s)"
        )
        push!(refs, con_ref)
    end
    
    return refs
end

"""
    add_storage_capacity_con!(model, sets, parameters, variables)

Storage capacity constraints (Constraint #7 from original PCM):
Energy and power capacity limits
"""
function add_storage_capacity_con!(model::JuMP.Model, sets::Dict, parameters::Dict, variables::Dict)::Vector{JuMP.ConstraintRef}
    refs = JuMP.ConstraintRef[]
    
    if !haskey(variables, "soc") || isempty(sets["S_exist"])
        return refs
    end
    
    soc = variables["soc"]
    c = variables["c"]
    dc = variables["dc"]
    
    for s in sets["S_exist"], h in sets["H"]
        # Energy capacity
        con_ref_energy = @constraint(model,
            0 <= soc[s, h] <= parameters["SECAP"][s],
            base_name = "storage_energy_capacity_$(s)_$(h)"
        )
        push!(refs, con_ref_energy)
        
        # Power capacity (simplified)
        con_ref_power = @constraint(model,
            c[s, h] + dc[s, h] <= parameters["SCAP"][s],
            base_name = "storage_power_capacity_$(s)_$(h)"
        )
        push!(refs, con_ref_power)
    end
    
    return refs
end

"""
    add_load_shedding_limit_con!(model, sets, parameters, variables)

Load shedding limits (Constraint #8 from original PCM):
0 <= p_LS[i,h] <= Load[i,h]
"""
function add_load_shedding_limit_con!(model::JuMP.Model, sets::Dict, parameters::Dict, variables::Dict)::Vector{JuMP.ConstraintRef}
    refs = JuMP.ConstraintRef[]
    
    p_LS = variables["p_LS"]
    
    for i in sets["I"], h in sets["H"]
        max_load = parameters["P_load"][i][h] * parameters["PK"][i]
        con_ref = @constraint(model,
            0 <= p_LS[i, h] <= max_load,
            base_name = "load_shedding_limit_$(i)_$(h)"
        )
        push!(refs, con_ref)
    end
    
    return refs
end

# ============================================================================
# UNIT COMMITMENT CONSTRAINTS (only when UC > 0)
# ============================================================================

"""
    add_uc_capacity_con!(model, sets, parameters, variables)

Unit commitment capacity constraints (UC Constraint #1):
P_min * o[g,h] <= p[g,h] <= P_max * o[g,h] for UC generators
"""
function add_uc_capacity_con!(model::JuMP.Model, sets::Dict, parameters::Dict, variables::Dict)::Vector{JuMP.ConstraintRef}
    refs = JuMP.ConstraintRef[]
    
    if !haskey(sets, "G_UC") || isempty(sets["G_UC"])
        return refs
    end
    
    p = variables["p"]
    o = variables["o"]
    
    for g in sets["G_UC"], h in sets["H"]
        # Upper bound: generation <= capacity * online status
        con_ref_upper = @constraint(model,
            p[g, h] <= (1 - parameters["FOR"][g]) * parameters["P_max"][g] * o[g, h],
            base_name = "uc_capacity_upper_$(g)_$(h)"
        )
        push!(refs, con_ref_upper)
        
        # Lower bound: generation >= min when online
        con_ref_lower = @constraint(model,
            p[g, h] >= parameters["P_min"][g] * o[g, h],
            base_name = "uc_capacity_lower_$(g)_$(h)"
        )
        push!(refs, con_ref_lower)
    end
    
    return refs
end

"""
    add_uc_transition_con!(model, sets, parameters, variables)

Unit commitment state transition constraints (UC Constraint #2):
o[g,h] - o[g,h-1] = su[g,h] - sd[g,h]
"""
function add_uc_transition_con!(model::JuMP.Model, sets::Dict, parameters::Dict, variables::Dict)::Vector{JuMP.ConstraintRef}
    refs = JuMP.ConstraintRef[]
    
    if !haskey(sets, "G_UC") || isempty(sets["G_UC"])
        return refs
    end
    
    o = variables["o"]
    su = variables["su"]
    sd = variables["sd"]
    
    for g in sets["G_UC"], h in sets["H"][2:end]
        con_ref = @constraint(model,
            o[g, h] - o[g, h-1] == su[g, h] - sd[g, h],
            base_name = "uc_transition_$(g)_$(h)"
        )
        push!(refs, con_ref)
    end
    
    return refs
end

"""
    add_uc_min_up_time_con!(model, sets, parameters, variables)

Minimum up time constraints (UC Constraint #3):
"""
function add_uc_min_up_time_con!(model::JuMP.Model, sets::Dict, parameters::Dict, variables::Dict)::Vector{JuMP.ConstraintRef}
    refs = JuMP.ConstraintRef[]
    
    if !haskey(sets, "G_UC") || isempty(sets["G_UC"]) || !haskey(parameters, "Min_up_time")
        return refs
    end
    
    o = variables["o"] 
    su = variables["su"]
    
    for g in sets["G_UC"]
        # FIX: Properly convert Min_up_time to integer
        min_up_time = Int(round(parameters["Min_up_time"][g]))
        
        for h in sets["H"]
            if h >= min_up_time + 1
                con_ref = @constraint(model,
                    sum(su[g, hh] for hh in max(1, h - min_up_time + 1):h) <= o[g, h],
                    base_name = "uc_min_up_time_$(g)_$(h)"
                )
                push!(refs, con_ref)
            end
        end
    end
    
    return refs
end

"""
    add_uc_min_down_time_con!(model, sets, parameters, variables)

Minimum down time constraints (UC Constraint #4):
"""
function add_uc_min_down_time_con!(model::JuMP.Model, sets::Dict, parameters::Dict, variables::Dict)::Vector{JuMP.ConstraintRef}
    refs = JuMP.ConstraintRef[]
    
    if !haskey(sets, "G_UC") || isempty(sets["G_UC"]) || !haskey(parameters, "Min_down_time")
        return refs
    end
    
    o = variables["o"]
    sd = variables["sd"]
    
    for g in sets["G_UC"]
        # FIX: Properly convert Min_down_time to integer
        min_down_time = Int(round(parameters["Min_down_time"][g]))
        
        for h in sets["H"]
            if h >= min_down_time + 1
                con_ref = @constraint(model,
                    sum(sd[g, hh] for hh in max(1, h - min_down_time + 1):h) <= 1 - o[g, h],
                    base_name = "uc_min_down_time_$(g)_$(h)"
                )
                push!(refs, con_ref)
            end
        end
    end
    
    return refs
end

# ============================================================================
# ADDITIONAL PCM CONSTRAINTS (Previously missing)
# ============================================================================

"""
    add_net_imports_con!(model, sets, parameters, variables)

Net imports constraints (Constraint #9 from original PCM):
ni[h,i] <= NI[h,i]
"""
function add_net_imports_con!(model::JuMP.Model, sets::Dict, parameters::Dict, variables::Dict)::Vector{JuMP.ConstraintRef}
    refs = JuMP.ConstraintRef[]
    
    if !haskey(variables, "ni") || !haskey(parameters, "NI")
        return refs
    end
    
    ni = variables["ni"]
    
    for h in sets["H"], i in sets["I"]
        if haskey(parameters["NI"], (h, i))
            con_ref = @constraint(model,
                ni[h, i] <= parameters["NI"][(h, i)],
                base_name = "net_imports_$(h)_$(i)"
            )
            push!(refs, con_ref)
        end
    end
    
    return refs
end

"""
    add_spinning_reserve_con!(model, sets, parameters, variables)

Spinning reserve constraints (Constraint #10 from original PCM):
r_G[g,h] <= RM_SPIN[g] * (1-FOR[g]) * P_max[g]
"""
function add_spinning_reserve_con!(model::JuMP.Model, sets::Dict, parameters::Dict, variables::Dict)::Vector{JuMP.ConstraintRef}
    refs = JuMP.ConstraintRef[]
    
    if !haskey(variables, "r_G") || !haskey(parameters, "RM_SPIN")
        return refs
    end
    
    r_G = variables["r_G"]
    
    for g in sets["G_exist"], h in sets["H"]
        con_ref = @constraint(model,
            r_G[g, h] <= parameters["RM_SPIN"][g] * (1 - parameters["FOR"][g]) * parameters["P_max"][g],
            base_name = "spinning_reserve_$(g)_$(h)"
        )
        push!(refs, con_ref)
    end
    
    return refs
end

"""
    add_ramping_up_con!(model, sets, parameters, variables)

Ramping up constraints (Constraint #11 from original PCM):
p[g,h] + r_G[g,h] - p[g,h-1] <= RU[g] * (1-FOR[g]) * P_max[g]
"""
function add_ramping_up_con!(model::JuMP.Model, sets::Dict, parameters::Dict, variables::Dict)::Vector{JuMP.ConstraintRef}
    refs = JuMP.ConstraintRef[]
    
    if !haskey(variables, "r_G") || !haskey(parameters, "RU")
        return refs
    end
    
    p = variables["p"]
    r_G = variables["r_G"]
    
    for g in sets["G_exist"], h in sets["H"][2:end]
        con_ref = @constraint(model,
            p[g, h] + r_G[g, h] - p[g, h-1] <= parameters["RU"][g] * (1 - parameters["FOR"][g]) * parameters["P_max"][g],
            base_name = "ramping_up_$(g)_$(h)"
        )
        push!(refs, con_ref)
    end
    
    return refs
end

"""
    add_ramping_down_con!(model, sets, parameters, variables)

Ramping down constraints (Constraint #12 from original PCM):
p[g,h] + r_G[g,h] - p[g,h-1] >= -RD[g] * (1-FOR[g]) * P_max[g]
"""
function add_ramping_down_con!(model::JuMP.Model, sets::Dict, parameters::Dict, variables::Dict)::Vector{JuMP.ConstraintRef}
    refs = JuMP.ConstraintRef[]
    
    if !haskey(variables, "r_G") || !haskey(parameters, "RD")
        return refs
    end
    
    p = variables["p"]
    r_G = variables["r_G"]
    
    for g in sets["G_exist"], h in sets["H"][2:end]
        con_ref = @constraint(model,
            p[g, h] + r_G[g, h] - p[g, h-1] >= -parameters["RD"][g] * (1 - parameters["FOR"][g]) * parameters["P_max"][g],
            base_name = "ramping_down_$(g)_$(h)"
        )
        push!(refs, con_ref)
    end
    
    return refs
end

"""
    add_must_run_con!(model, sets, parameters, variables)

Must-run constraints (Constraint #13 from original PCM):
p[g,h] == (1-FOR[g]) * P_max[g] for must-run generators
"""
function add_must_run_con!(model::JuMP.Model, sets::Dict, parameters::Dict, variables::Dict)::Vector{JuMP.ConstraintRef}
    refs = JuMP.ConstraintRef[]
    
    if !haskey(sets, "G_mustrun") || isempty(sets["G_mustrun"])
        return refs
    end
    
    p = variables["p"]
    
    for g in sets["G_mustrun"], h in sets["H"]
        con_ref = @constraint(model,
            p[g, h] == (1 - parameters["FOR"][g]) * parameters["P_max"][g],
            base_name = "must_run_$(g)_$(h)"
        )
        push!(refs, con_ref)
    end
    
    return refs
end

"""
    add_rps_annual_con!(model, sets, parameters, variables)

RPS annual constraints (Policy Constraint #1):
Annual renewable generation by state
"""
function add_rps_annual_con!(model::JuMP.Model, sets::Dict, parameters::Dict, variables::Dict)::Vector{JuMP.ConstraintRef}
    refs = JuMP.ConstraintRef[]
    
    if !haskey(variables, "pw") || !haskey(sets, "G_renewable") || isempty(sets["G_renewable"])
        return refs
    end
    
    p = variables["p"]
    pw = variables["pw"]
    
    # Use proper JuMP variable indexing for multi-dimensional arrays
    for g in sets["G_renewable"], w in sets["W"]
        try
            # Check if this variable exists by attempting to access it
            pw_var = pw[g, w]
            con_ref = @constraint(model,
                pw_var == sum(p[g, h] for h in sets["H"]),
                base_name = "rps_annual_$(g)_$(w)"
            )
            push!(refs, con_ref)
        catch BoundsError
            # Variable doesn't exist for this (g,w) combination, skip
            continue
        end
    end
    
    return refs
end

"""
    add_rps_state_requirement_con!(model, sets, parameters, variables)

RPS state requirement constraints (Policy Constraint #2):
Meet RPS requirements by state
"""
function add_rps_state_requirement_con!(model::JuMP.Model, sets::Dict, parameters::Dict, variables::Dict)::Vector{JuMP.ConstraintRef}
    refs = JuMP.ConstraintRef[]
    
    if !haskey(variables, "pw") || !haskey(parameters, "RPS") || !haskey(sets, "I_w")
        return refs
    end
    
    pw = variables["pw"]
    pwi = get(variables, "pwi", nothing)
    pt_rps = variables["pt_rps"]
    p_load = parameters["P_load"]
    pk = parameters["PK"]
    
    for w in sets["W"]
        if haskey(parameters["RPS"], w) && haskey(sets["I_w"], w) && !isempty(sets["I_w"][w])
            # Total load in state w - with proper bounds checking
            total_load = sum(sum(p_load[i][h] * pk[i] for h in sets["H"]) for i in sets["I_w"][w]; init=0)
            
            # RPS requirement
            rps_requirement = parameters["RPS"][w] * total_load
            
            # Renewable generation in state w - use safe access
            renewable_supply = @expression(model, sum(
                begin
                    try
                        pw[g, w]
                    catch BoundsError
                        0
                    end
                end for g in sets["G_renewable"]))
            
            # Add imports and exports if pwi exists
            if pwi !== nothing
                renewable_supply += sum(
                    begin
                        try
                            pwi[g, ww, w]
                        catch BoundsError
                            0
                        end
                    end for g in sets["G_renewable"], ww in sets["W"] if ww != w)
                renewable_supply -= sum(
                    begin
                        try
                            pwi[g, w, ww]
                        catch BoundsError
                            0
                        end
                    end for g in sets["G_renewable"], ww in sets["W"] if ww != w)
            end
            
            con_ref = @constraint(model,
                renewable_supply + sum(pt_rps[w, h] for h in sets["H"]) >= rps_requirement,
                base_name = "rps_state_requirement_$(w)"
            )
            push!(refs, con_ref)
        end
    end
    
    return refs
end

"""
    add_emissions_limit_con!(model, sets, parameters, variables)

Emissions limit constraints (Policy Constraint #3):
Total emissions <= emission limit by state
"""
function add_emissions_limit_con!(model::JuMP.Model, sets::Dict, parameters::Dict, variables::Dict)::Vector{JuMP.ConstraintRef}
    refs = JuMP.ConstraintRef[]
    
    if !haskey(variables, "em_emis") || !haskey(parameters, "ELMT") || !haskey(sets, "I_w")
        return refs
    end
    
    p = variables["p"]
    em_emis = variables["em_emis"]
    
    for w in sets["W"]
        if haskey(parameters["ELMT"], w) && haskey(sets["I_w"], w) && !isempty(sets["I_w"][w])
            # Total emissions in state w - with proper initialization
            total_emissions = @expression(model,
                sum(parameters["EF"][g] * p[g, h] 
                    for i in sets["I_w"][w] 
                    for g in sets["G_i"][i] 
                    for h in sets["H"]; init=0)
            )
            
            con_ref = @constraint(model,
                total_emissions - em_emis[w] <= parameters["ELMT"][w],
                base_name = "emissions_limit_$(w)"
            )
            push!(refs, con_ref)
        end
    end
    
    return refs
end

# Export all direct constraint functions
export add_power_balance_con!,
       add_generator_capacity_con!,
       add_renewable_availability_con!,
       add_transmission_capacity_con!,
       add_storage_soc_evolution_con!,
       add_storage_cyclic_con!,
       add_storage_capacity_con!,
       add_load_shedding_limit_con!,
       add_net_imports_con!,
       add_spinning_reserve_con!,
       add_ramping_up_con!,
       add_ramping_down_con!,
       add_must_run_con!,
       add_rps_annual_con!,
       add_rps_state_requirement_con!,
       add_emissions_limit_con!,
       add_uc_capacity_con!,
       add_uc_transition_con!,
       add_uc_min_up_time_con!,
       add_uc_min_down_time_con!

end
