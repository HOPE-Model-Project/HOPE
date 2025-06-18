"""
# ConstraintImplementations.jl - Specific constraint implementations
# 
# This module contains the actual JuMP constraint implementations 
# that are called by the ConstraintPool system.
"""

using JuMP

"""
Power balance constraint: Generation = Load + Storage charging + Transmission outflow
"""
function apply_power_balance!(model::JuMP.Model, config::Dict, input_data::Dict)::Vector{JuMP.ConstraintRef}
    refs = JuMP.ConstraintRef[]
    
    # Get data based on model mode
    mode = config["model_mode"]
    
    if mode == "GTEP"
        # GTEP mode: with time periods and representative hours
        T = input_data["T"]  # Time periods  
        H_T = input_data["H_T"]  # Hours per time period
        I = input_data["I"]  # Zones
        G = input_data["G"]  # Generators
        S = input_data["S"]  # Storage
        L = input_data["L"]  # Transmission lines
        
        # Power balance for each zone, time period, and hour
        for i in I, t in T, h in H_T[t]
            # Generation in zone i
            gen_expr = @expression(model, 
                sum(model[:p][g,t,h] for g in G if input_data["Gendata"][g, :Zone] == i))
            
            # Storage discharge - charge in zone i  
            storage_expr = @expression(model,
                sum(model[:dc][s,t,h] - model[:c][s,t,h] for s in S if input_data["Storagedata"][s, :Zone] == i))
            
            # Net transmission flow into zone i
            trans_expr = @expression(model,
                sum(model[:f][l,t,h] for l in L if input_data["Linedata"][l, :Zone_to] == i) -
                sum(model[:f][l,t,h] for l in L if input_data["Linedata"][l, :Zone_from] == i))
            
            # Load in zone i
            load_expr = input_data["Loaddata"][h, i]
            
            # Power balance constraint
            con_ref = @constraint(model, 
                gen_expr + storage_expr + trans_expr + model[:p_LS][i,t,h] == load_expr,
                base_name = "power_balance_$(i)_$(t)_$(h)")
            
            push!(refs, con_ref)
        end
        
    elseif mode == "PCM" 
        # PCM mode: hourly operation
        H = input_data["H"]  # All hours
        I = input_data["I"]  # Zones
        G = input_data["G"]  # Generators
        S = input_data["S"]  # Storage  
        L = input_data["L"]  # Transmission lines
        
        # Power balance for each zone and hour
        for i in I, h in H
            # Generation in zone i
            gen_expr = @expression(model,
                sum(model[:p][g,h] for g in G if input_data["Gendata"][g, :Zone] == i))
            
            # Storage discharge - charge in zone i
            storage_expr = @expression(model,
                sum(model[:dc][s,h] - model[:c][s,h] for s in S if input_data["Storagedata"][s, :Zone] == i))
            
            # Net transmission flow into zone i
            trans_expr = @expression(model,
                sum(model[:f][l,h] for l in L if input_data["Linedata"][l, :Zone_to] == i) -
                sum(model[:f][l,h] for l in L if input_data["Linedata"][l, :Zone_from] == i))
            
            # Load in zone i (including demand response if enabled)
            load_expr = input_data["Loaddata"][h, i]
            if config["flexible_demand"] != 0
                load_expr += sum(model[:dr][d,h] for d in input_data["D_i"][i])
            end
            
            # Power balance constraint
            con_ref = @constraint(model,
                gen_expr + storage_expr + trans_expr + model[:p_LS][i,h] == load_expr,
                base_name = "power_balance_$(i)_$(h)")
                
            push!(refs, con_ref)
        end
    end
    
    return refs
end

"""
Generator capacity limit constraints
"""
function apply_generator_capacity_limit!(model::JuMP.Model, config::Dict, input_data::Dict)::Vector{JuMP.ConstraintRef}
    refs = JuMP.ConstraintRef[]
    mode = config["model_mode"]
    
    if mode == "GTEP"
        T = input_data["T"]
        H_T = input_data["H_T"] 
        G = input_data["G"]
        G_new = input_data["G_new"]
        
        # Existing generator limits
        for g in G, t in T, h in H_T[t]
            p_max = input_data["Gendata"][g, Symbol("Pmax (MW)")]
            availability = get(input_data, "availability", Dict())
            avail_factor = get(availability, (g,t,h), 1.0)
            
            con_ref = @constraint(model,
                model[:p][g,t,h] <= p_max * avail_factor,
                base_name = "gen_cap_limit_$(g)_$(t)_$(h)")
            push!(refs, con_ref)
        end
        
        # Candidate generator limits (with investment decision)
        for g in G_new, t in T, h in H_T[t]
            p_max = input_data["Gendata_candidate"][g, Symbol("Pmax (MW)")]
            availability = get(input_data, "availability", Dict())
            avail_factor = get(availability, (g,t,h), 1.0)
            
            con_ref = @constraint(model,
                model[:p][g,t,h] <= p_max * avail_factor * model[:x][g],
                base_name = "gen_cap_limit_new_$(g)_$(t)_$(h)")
            push!(refs, con_ref)
        end
        
    elseif mode == "PCM"
        H = input_data["H"]
        G = input_data["G"]
        
        # Generator capacity limits
        for g in G, h in H
            p_max = input_data["Gendata"][g, Symbol("Pmax (MW)")]
            availability = get(input_data, "availability", Dict())
            avail_factor = get(availability, (g,h), 1.0)
            
            con_ref = @constraint(model,
                model[:p][g,h] <= p_max * avail_factor,
                base_name = "gen_cap_limit_$(g)_$(h)")
            push!(refs, con_ref)
        end
    end
    
    return refs
end

"""
Transmission flow limit constraints
"""
function apply_transmission_flow_limit!(model::JuMP.Model, config::Dict, input_data::Dict)::Vector{JuMP.ConstraintRef}
    refs = JuMP.ConstraintRef[]
    mode = config["model_mode"]
    
    if mode == "GTEP"
        T = input_data["T"]
        H_T = input_data["H_T"]
        L = input_data["L"]
        L_new = input_data["L_new"]
        
        # Existing line limits
        for l in L, t in T, h in H_T[t]
            flow_max = input_data["Linedata"][l, Symbol("Pmax (MW)")]
            
            # Upper bound
            con_ref1 = @constraint(model,
                model[:f][l,t,h] <= flow_max,
                base_name = "line_flow_max_$(l)_$(t)_$(h)")
            push!(refs, con_ref1)
            
            # Lower bound  
            con_ref2 = @constraint(model,
                model[:f][l,t,h] >= -flow_max,
                base_name = "line_flow_min_$(l)_$(t)_$(h)")
            push!(refs, con_ref2)
        end
        
        # Candidate line limits (with investment decision)
        for l in L_new, t in T, h in H_T[t]
            flow_max = input_data["Linedata_candidate"][l, Symbol("Pmax (MW)")]
            
            # Upper bound
            con_ref1 = @constraint(model,
                model[:f][l,t,h] <= flow_max * model[:y][l],
                base_name = "line_flow_max_new_$(l)_$(t)_$(h)")
            push!(refs, con_ref1)
            
            # Lower bound
            con_ref2 = @constraint(model,
                model[:f][l,t,h] >= -flow_max * model[:y][l],
                base_name = "line_flow_min_new_$(l)_$(t)_$(h)")
            push!(refs, con_ref2)
        end
        
    elseif mode == "PCM"
        H = input_data["H"]
        L = input_data["L"]
        
        # Line flow limits
        for l in L, h in H
            flow_max = input_data["Linedata"][l, Symbol("Pmax (MW)")]
            
            # Upper bound
            con_ref1 = @constraint(model,
                model[:f][l,h] <= flow_max,
                base_name = "line_flow_max_$(l)_$(h)")
            push!(refs, con_ref1)
            
            # Lower bound
            con_ref2 = @constraint(model,
                model[:f][l,h] >= -flow_max,
                base_name = "line_flow_min_$(l)_$(h)")
            push!(refs, con_ref2)
        end
    end
    
    return refs
end

"""
Storage energy balance constraints
"""
function apply_storage_energy_balance!(model::JuMP.Model, config::Dict, input_data::Dict)::Vector{JuMP.ConstraintRef}
    refs = JuMP.ConstraintRef[]
    mode = config["model_mode"]
    
    if mode == "GTEP"
        T = input_data["T"]
        H_T = input_data["H_T"]
        S = input_data["S"]
        
        for s in S, t in T
            hours = H_T[t]
            eff_charge = input_data["Storagedata"][s, Symbol("Eff_c")]
            eff_discharge = input_data["Storagedata"][s, Symbol("Eff_dc")]
            
            for (i, h) in enumerate(hours)
                if i == 1
                    # First hour: SOC depends on previous period's final SOC
                    if t == 1
                        # First period: assume starting SOC = 0
                        con_ref = @constraint(model,
                            model[:soc][s,t,h] == 
                            model[:c][s,t,h] * eff_charge - model[:dc][s,t,h] / eff_discharge,
                            base_name = "storage_balance_$(s)_$(t)_$(h)")
                    else
                        prev_t = t - 1
                        last_h = H_T[prev_t][end]
                        con_ref = @constraint(model,
                            model[:soc][s,t,h] == model[:soc][s,prev_t,last_h] +
                            model[:c][s,t,h] * eff_charge - model[:dc][s,t,h] / eff_discharge,
                            base_name = "storage_balance_$(s)_$(t)_$(h)")
                    end
                else
                    # Other hours: SOC depends on previous hour
                    prev_h = hours[i-1]
                    con_ref = @constraint(model,
                        model[:soc][s,t,h] == model[:soc][s,t,prev_h] +
                        model[:c][s,t,h] * eff_charge - model[:dc][s,t,h] / eff_discharge,
                        base_name = "storage_balance_$(s)_$(t)_$(h)")
                end
                push!(refs, con_ref)
            end
        end
        
    elseif mode == "PCM"
        H = input_data["H"]
        S = input_data["S"]
        
        for s in S, h in H
            eff_charge = input_data["Storagedata"][s, Symbol("Eff_c")]
            eff_discharge = input_data["Storagedata"][s, Symbol("Eff_dc")]
            
            if h == 1
                # First hour: assume starting SOC = 0
                con_ref = @constraint(model,
                    model[:soc][s,h] == 
                    model[:c][s,h] * eff_charge - model[:dc][s,h] / eff_discharge,
                    base_name = "storage_balance_$(s)_$(h)")
            else
                con_ref = @constraint(model,
                    model[:soc][s,h] == model[:soc][s,h-1] +
                    model[:c][s,h] * eff_charge - model[:dc][s,h] / eff_discharge,
                    base_name = "storage_balance_$(s)_$(h)")
            end
            push!(refs, con_ref)
        end
    end
    
    return refs
end

"""
Investment budget constraints for generators (GTEP only)
"""
function apply_investment_budget_generator!(model::JuMP.Model, config::Dict, input_data::Dict)::Vector{JuMP.ConstraintRef}
    refs = JuMP.ConstraintRef[]
    
    if config["model_mode"] == "GTEP"
        G_new = input_data["G_new"]
        IBG = input_data["SinglePardata"][1, Symbol("IBG (\$)")]
        
        investment_expr = @expression(model,
            sum(input_data["Gendata_candidate"][g, Symbol("INV (\$/MW)")] * 
                input_data["Gendata_candidate"][g, Symbol("Pmax (MW)")] * 
                model[:x][g] for g in G_new))
        
        con_ref = @constraint(model,
            investment_expr <= IBG,
            base_name = "investment_budget_generator")
        push!(refs, con_ref)
    end
    
    return refs
end

"""
Investment budget constraints for transmission (GTEP only)  
"""
function apply_investment_budget_transmission!(model::JuMP.Model, config::Dict, input_data::Dict)::Vector{JuMP.ConstraintRef}
    refs = JuMP.ConstraintRef[]
    
    if config["model_mode"] == "GTEP"
        L_new = input_data["L_new"]
        IBL = input_data["SinglePardata"][1, Symbol("IBL (\$)")]
        
        investment_expr = @expression(model,
            sum(input_data["Linedata_candidate"][l, Symbol("INV (\$/MW)")] * 
                input_data["Linedata_candidate"][l, Symbol("Pmax (MW)")] * 
                model[:y][l] for l in L_new))
        
        con_ref = @constraint(model,
            investment_expr <= IBL,
            base_name = "investment_budget_transmission")
        push!(refs, con_ref)
    end
    
    return refs
end

"""
RPS compliance constraints
"""
function apply_rps_compliance!(model::JuMP.Model, config::Dict, input_data::Dict)::Vector{JuMP.ConstraintRef}
    refs = JuMP.ConstraintRef[]
    mode = config["model_mode"]
    
    if mode == "GTEP"
        T = input_data["T"]
        H_T = input_data["H_T"]
        I = input_data["I"]  # Zones
        G = input_data["G"]  # All generators
        
        # Check if RPS policy data exists
        if haskey(input_data, "RPSdata") && !isempty(input_data["RPSdata"])
            rps_data = input_data["RPSdata"]
            
            # RPS constraint for each zone and time period
            for i in I, t in T
                # Get RPS requirement for this zone and time period
                rps_req = 0.0
                try
                    rps_req = rps_data[findfirst(row -> row[:Zone] == i && row[:Time_period] == t, eachrow(rps_data)), :RPS_requirement]
                catch
                    # If no specific RPS requirement found, skip this constraint
                    continue
                end
                
                if rps_req > 0
                    # Total renewable generation in zone i during time period t
                    renewable_expr = @expression(model,
                        sum(input_data["Loaddata"][h, i] * model[:p][g,t,h] 
                            for g in G if input_data["Gendata"][g, :Zone] == i && 
                                         input_data["Gendata"][g, :Technology] in ["Wind", "Solar", "Hydro"]
                            for h in H_T[t]))
                    
                    # Total generation in zone i during time period t
                    total_expr = @expression(model,
                        sum(input_data["Loaddata"][h, i] * model[:p][g,t,h]
                            for g in G if input_data["Gendata"][g, :Zone] == i
                            for h in H_T[t]))
                    
                    # RPS constraint: renewable generation >= RPS_requirement * total generation
                    con_ref = @constraint(model,
                        renewable_expr >= rps_req * total_expr,
                        base_name = "rps_compliance_$(i)_$(t)")
                    push!(refs, con_ref)
                end
            end
        end
        
    elseif mode == "PCM"
        H = input_data["H"]
        I = input_data["I"]
        G = input_data["G"]
        
        # Check if RPS policy data exists
        if haskey(input_data, "RPSdata") && !isempty(input_data["RPSdata"])
            rps_data = input_data["RPSdata"]
            
            # Annual RPS constraint for each zone
            for i in I
                # Get RPS requirement for this zone
                rps_req = 0.0
                try
                    rps_req = rps_data[findfirst(row -> row[:Zone] == i, eachrow(rps_data)), :RPS_requirement]
                catch
                    continue
                end
                
                if rps_req > 0
                    # Total renewable generation in zone i
                    renewable_expr = @expression(model,
                        sum(model[:p][g,h] for g in G, h in H 
                            if input_data["Gendata"][g, :Zone] == i && 
                               input_data["Gendata"][g, :Technology] in ["Wind", "Solar", "Hydro"]))
                    
                    # Total generation in zone i  
                    total_expr = @expression(model,
                        sum(model[:p][g,h] for g in G, h in H 
                            if input_data["Gendata"][g, :Zone] == i))
                    
                    # RPS constraint
                    con_ref = @constraint(model,
                        renewable_expr >= rps_req * total_expr,
                        base_name = "rps_compliance_$(i)")
                    push!(refs, con_ref)
                end
            end
        end
    end
    
    return refs
end

"""
Carbon emission limit constraints
"""
function apply_carbon_emission_limit!(model::JuMP.Model, config::Dict, input_data::Dict)::Vector{JuMP.ConstraintRef}
    refs = JuMP.ConstraintRef[]
    mode = config["model_mode"]
    
    if mode == "GTEP"
        T = input_data["T"]
        H_T = input_data["H_T"]
        I = input_data["I"]  # Zones
        G = input_data["G"]  # All generators
        
        # Check if carbon policy data exists
        if haskey(input_data, "Carbondata") && !isempty(input_data["Carbondata"])
            carbon_data = input_data["Carbondata"]
            
            # Carbon emission constraint for each zone and time period
            for i in I, t in T
                # Get carbon emission limit for this zone and time period
                carbon_limit = 0.0
                try
                    carbon_limit = carbon_data[findfirst(row -> row[:Zone] == i && row[:Time_period] == t, eachrow(carbon_data)), :Emission_limit]
                catch
                    # If no specific carbon limit found, skip this constraint
                    continue
                end
                
                if carbon_limit > 0
                    # Total emissions in zone i during time period t
                    emission_expr = @expression(model,
                        sum(input_data["Gendata"][g, Symbol("Emission Rate (ton CO2/MWh)")] * 
                            model[:p][g,t,h] * input_data["Loaddata"][h, i]
                            for g in G if input_data["Gendata"][g, :Zone] == i
                            for h in H_T[t]))
                    
                    # Carbon emission constraint
                    con_ref = @constraint(model,
                        emission_expr <= carbon_limit,
                        base_name = "carbon_emission_limit_$(i)_$(t)")
                    push!(refs, con_ref)
                end
            end
        end
        
    elseif mode == "PCM"
        H = input_data["H"]
        I = input_data["I"]
        G = input_data["G"]
        
        # Check if carbon policy data exists
        if haskey(input_data, "Carbondata") && !isempty(input_data["Carbondata"])
            carbon_data = input_data["Carbondata"]
            
            # Annual carbon emission constraint for each zone
            for i in I
                # Get carbon emission limit for this zone
                carbon_limit = 0.0
                try
                    carbon_limit = carbon_data[findfirst(row -> row[:Zone] == i, eachrow(carbon_data)), :Emission_limit]
                catch
                    continue
                end
                
                if carbon_limit > 0
                    # Total emissions in zone i
                    emission_expr = @expression(model,
                        sum(input_data["Gendata"][g, Symbol("Emission Rate (ton CO2/MWh)")] * 
                            model[:p][g,h]
                            for g in G, h in H 
                            if input_data["Gendata"][g, :Zone] == i))
                    
                    # Carbon emission constraint
                    con_ref = @constraint(model,
                        emission_expr <= carbon_limit,
                        base_name = "carbon_emission_limit_$(i)")
                    push!(refs, con_ref)
                end
            end
        end
    end
    
    return refs
end

"""
Planning reserve margin constraints (GTEP only)
"""
function apply_planning_reserve_margin!(model::JuMP.Model, config::Dict, input_data::Dict)::Vector{JuMP.ConstraintRef}
    refs = JuMP.ConstraintRef[]
    
    if config["model_mode"] == "GTEP"
        G_exist = input_data["G_exist"]
        G_new = input_data["G_new"]
        S_exist = input_data["S_exist"]  
        S_new = input_data["S_new"]
        D = input_data["D"]
        
        # Planning reserve margin requirement
        RM = input_data["SinglePardata"][1, Symbol("planning _reserve_margin")]
        
        # Generator capacity contributions
        existing_gen_capacity = @expression(model,
            sum(input_data["Gendata"][g, Symbol("CC")] * 
                input_data["Gendata"][g, Symbol("Pmax (MW)")] for g in G_exist))
        
        new_gen_capacity = @expression(model,
            sum(input_data["Gendata_candidate"][g, Symbol("CC")] * 
                input_data["Gendata_candidate"][g, Symbol("Pmax (MW)")] * 
                model[:x][g] for g in G_new))
        
        # Storage capacity contributions  
        existing_storage_capacity = @expression(model,
            sum(input_data["Storagedata"][s, Symbol("CC")] * 
                input_data["Storagedata"][s, Symbol("Max Power (MW)")] for s in S_exist))
        
        new_storage_capacity = @expression(model,
            sum(input_data["Storagedata_candidate"][s, Symbol("CC")] * 
                input_data["Storagedata_candidate"][s, Symbol("Max Power (MW)")] * 
                model[:z][s] for s in S_new))
        
        # Peak demand
        peak_demand = sum(input_data["Demanddata"][d, Symbol("Peak (MW)")] for d in D)
        
        # Resource adequacy constraint
        con_ref = @constraint(model,
            existing_gen_capacity + new_gen_capacity + existing_storage_capacity + new_storage_capacity >= 
            (1 + RM) * peak_demand,
            base_name = "planning_reserve_margin")
        push!(refs, con_ref)
    end
    
    return refs
end

"""
Storage capacity limit constraints (charging/discharging power limits)
"""
function apply_storage_capacity_limit!(model::JuMP.Model, config::Dict, input_data::Dict)::Vector{JuMP.ConstraintRef}
    refs = JuMP.ConstraintRef[]
    mode = config["model_mode"]
    
    if mode == "GTEP"
        T = input_data["T"]
        H_T = input_data["H_T"]
        S = input_data["S"]
        S_exist = input_data["S_exist"]  
        S_new = input_data["S_new"]
        
        # Existing storage charging/discharging limits
        for s in S_exist, t in T, h in H_T[t]
            scap = input_data["Storagedata"][s, Symbol("Max Power (MW)")]
            sc_rate = input_data["Storagedata"][s, Symbol("Charging Rate")]
            sd_rate = input_data["Storagedata"][s, Symbol("Discharging Rate")]
            
            # Charging rate limit
            con_ref1 = @constraint(model,
                model[:c][s,t,h] / sc_rate <= scap,
                base_name = "storage_charge_limit_$(s)_$(t)_$(h)")
            push!(refs, con_ref1)
            
            # Discharging rate limit (combined charging + discharging)
            con_ref2 = @constraint(model,
                model[:c][s,t,h] / sc_rate + model[:dc][s,t,h] / sd_rate <= scap,
                base_name = "storage_power_limit_$(s)_$(t)_$(h)")
            push!(refs, con_ref2)
            
            # Energy capacity limit
            secap = input_data["Storagedata"][s, Symbol("Capacity (MWh)")]
            con_ref3 = @constraint(model,
                model[:soc][s,t,h] <= secap,
                base_name = "storage_energy_limit_$(s)_$(t)_$(h)")
            push!(refs, con_ref3)
        end
        
        # New storage limits (with investment decision)
        for s in S_new, t in T, h in H_T[t]
            scap = input_data["Storagedata_candidate"][s, Symbol("Max Power (MW)")]
            sc_rate = input_data["Storagedata_candidate"][s, Symbol("Charging Rate")]
            sd_rate = input_data["Storagedata_candidate"][s, Symbol("Discharging Rate")]
            
            # Charging rate limit
            con_ref1 = @constraint(model,
                model[:c][s,t,h] / sc_rate <= scap * model[:z][s],
                base_name = "storage_charge_limit_new_$(s)_$(t)_$(h)")
            push!(refs, con_ref1)
            
            # Discharging rate limit
            con_ref2 = @constraint(model,
                model[:c][s,t,h] / sc_rate + model[:dc][s,t,h] / sd_rate <= scap * model[:z][s],
                base_name = "storage_power_limit_new_$(s)_$(t)_$(h)")
            push!(refs, con_ref2)
            
            # Energy capacity limit
            secap = input_data["Storagedata_candidate"][s, Symbol("Capacity (MWh)")]
            con_ref3 = @constraint(model,
                model[:soc][s,t,h] <= secap * model[:z][s],
                base_name = "storage_energy_limit_new_$(s)_$(t)_$(h)")
            push!(refs, con_ref3)
        end
        
    elseif mode == "PCM"
        H = input_data["H"]
        S = input_data["S"]
        
        for s in S, h in H
            scap = input_data["Storagedata"][s, Symbol("Max Power (MW)")]
            sc_rate = input_data["Storagedata"][s, Symbol("Charging Rate")]
            sd_rate = input_data["Storagedata"][s, Symbol("Discharging Rate")]
            
            # Charging rate limit
            con_ref1 = @constraint(model,
                model[:c][s,h] / sc_rate <= scap,
                base_name = "storage_charge_limit_$(s)_$(h)")
            push!(refs, con_ref1)
            
            # Discharging rate limit
            con_ref2 = @constraint(model,
                model[:c][s,h] / sc_rate + model[:dc][s,h] / sd_rate <= scap,
                base_name = "storage_power_limit_$(s)_$(h)")
            push!(refs, con_ref2)
            
            # Energy capacity limit
            secap = input_data["Storagedata"][s, Symbol("Capacity (MWh)")]
            con_ref3 = @constraint(model,
                model[:soc][s,h] <= secap,
                base_name = "storage_energy_limit_$(s)_$(h)")
            push!(refs, con_ref3)
        end
    end
    
    return refs
end

"""
Investment budget constraints for storage (GTEP only)  
"""
function apply_investment_budget_storage!(model::JuMP.Model, config::Dict, input_data::Dict)::Vector{JuMP.ConstraintRef}
    refs = JuMP.ConstraintRef[]
    
    if config["model_mode"] == "GTEP"
        S_new = input_data["S_new"]
        IBS = input_data["SinglePardata"][1, Symbol("IBS (\$)")]
        
        investment_expr = @expression(model,
            sum(input_data["Storagedata_candidate"][s, Symbol("INV (\$/MW)")] * 
                input_data["Storagedata_candidate"][s, Symbol("Max Power (MW)")] * 
                model[:z][s] for s in S_new))
        
        con_ref = @constraint(model,
            investment_expr <= IBS,
            base_name = "investment_budget_storage")
        push!(refs, con_ref)
    end
      return refs
end

"""
Minimum run limit constraints (Unit Commitment)
"""
function apply_minimum_run_limit!(model::JuMP.Model, config::Dict, input_data::Dict)::Vector{JuMP.ConstraintRef}
    refs = JuMP.ConstraintRef[]
    mode = config["model_mode"]
    
    if mode == "PCM"  # Unit commitment typically used in PCM
        H = input_data["H"]
        G = input_data["G"]
        
        # Check if unit commitment data exists
        if haskey(input_data, "UCdata") && !isempty(input_data["UCdata"])
            uc_data = input_data["UCdata"]
            
            for g in G, h in H
                # Get minimum run level for generator g
                min_run = 0.0
                try
                    min_run = uc_data[findfirst(row -> row[:Generator] == g, eachrow(uc_data)), :Min_run_level]
                catch
                    # If no UC data for this generator, skip
                    continue
                end
                
                if min_run > 0
                    # Get generator maximum capacity
                    pmax = input_data["Gendata"][g, Symbol("Pmax (MW)")]
                      # Minimum run constraint: if online, must run at least min_run * capacity
                    if haskey(model, :u)  # Check if binary variables exist
                        con_ref = @constraint(model,
                            model[:p][g,h] >= min_run * pmax * model[:u][g,h],
                            base_name = "minimum_run_$(g)_$(h)")
                        push!(refs, con_ref)
                    end
                end
            end
        end
    end
    
    return refs
end

"""
Minimum up time constraints (Unit Commitment)
"""
function apply_minimum_up_time!(model::JuMP.Model, config::Dict, input_data::Dict)::Vector{JuMP.ConstraintRef}
    refs = JuMP.ConstraintRef[]
    mode = config["model_mode"]
    
    if mode == "PCM"
        H = input_data["H"]
        G = input_data["G"]
        
        # Check if unit commitment data exists
        if haskey(input_data, "UCdata") && !isempty(input_data["UCdata"])
            uc_data = input_data["UCdata"]
            
            for g in G
                # Get minimum up time for generator g
                min_up_time = 0
                try
                    min_up_time = uc_data[findfirst(row -> row[:Generator] == g, eachrow(uc_data)), :Min_up_time]
                catch
                    continue
                end
                
                if min_up_time > 1 && haskey(model, :u) && haskey(model, :v)  # Binary variables exist
                    for h in H
                        if h + min_up_time - 1 <= length(H)
                            # If started up at hour h, must stay online for min_up_time hours
                            con_ref = @constraint(model,
                                sum(model[:u][g,h_prime] for h_prime in h:min(h+min_up_time-1, length(H))) >= 
                                min_up_time * model[:v][g,h],
                                base_name = "minimum_up_time_$(g)_$(h)")
                            push!(refs, con_ref)
                        end
                    end
                end
            end
        end
    end
    
    return refs
end

"""
Minimum down time constraints (Unit Commitment)
"""
function apply_minimum_down_time!(model::JuMP.Model, config::Dict, input_data::Dict)::Vector{JuMP.ConstraintRef}
    refs = JuMP.ConstraintRef[]
    mode = config["model_mode"]
    
    if mode == "PCM"
        H = input_data["H"]
        G = input_data["G"]
        
        # Check if unit commitment data exists
        if haskey(input_data, "UCdata") && !isempty(input_data["UCdata"])
            uc_data = input_data["UCdata"]
            
            for g in G
                # Get minimum down time for generator g
                min_down_time = 0
                try
                    min_down_time = uc_data[findfirst(row -> row[:Generator] == g, eachrow(uc_data)), :Min_down_time]
                catch
                    continue
                end
                
                if min_down_time > 1 && haskey(model, :u) && haskey(model, :w)  # Binary variables exist
                    for h in H
                        if h + min_down_time - 1 <= length(H)
                            # If shut down at hour h, must stay offline for min_down_time hours
                            con_ref = @constraint(model,
                                sum(1 - model[:u][g,h_prime] for h_prime in h:min(h+min_down_time-1, length(H))) >= 
                                min_down_time * model[:w][g,h],
                                base_name = "minimum_down_time_$(g)_$(h)")
                            push!(refs, con_ref)
                        end
                    end
                end
            end
        end
    end
    
    return refs
end

"""
Demand response balance constraints
"""
function apply_demand_response_balance!(model::JuMP.Model, config::Dict, input_data::Dict)::Vector{JuMP.ConstraintRef}
    refs = JuMP.ConstraintRef[]
    mode = config["model_mode"]
    
    if mode == "PCM" || mode == "GTEP"
        # Get appropriate time structure
        H = mode == "PCM" ? input_data["H"] : 
            [h for t in input_data["T"] for h in input_data["H_T"][t]]
        
        I = input_data["I"]  # Zones
        
        # Check if demand response data exists
        if haskey(input_data, "DRdata") && !isempty(input_data["DRdata"])
            dr_data = input_data["DRdata"]
            
            for i in I
                # Check if there are DR resources in this zone
                dr_resources = filter(row -> row[:Zone] == i, eachrow(dr_data))
                
                if !isempty(dr_resources)
                    for h in H
                        # Energy conservation constraint for demand response
                        # Total DR reduction must equal total DR increase over time
                        if haskey(model, :dr_reduce) && haskey(model, :dr_increase)
                            # Daily energy balance for DR
                            daily_hours = 24  # Assuming hourly time steps
                            if h % daily_hours == 1  # Start of a new day
                                day_end = min(h + daily_hours - 1, length(H))
                                
                                con_ref = @constraint(model,
                                    sum(model[:dr_reduce][i,h_day] for h_day in h:day_end) == 
                                    sum(model[:dr_increase][i,h_day] for h_day in h:day_end),
                                    base_name = "dr_energy_balance_$(i)_day_$(div(h-1,daily_hours)+1)")
                                push!(refs, con_ref)
                            end
                        end
                    end
                end
            end
        end
    end
    
    return refs
end

"""
Unit commitment transition constraints (linking u, v, w variables)
"""
function apply_unit_commitment_transition!(model::JuMP.Model, config::Dict, input_data::Dict)::Vector{JuMP.ConstraintRef}
    refs = JuMP.ConstraintRef[]
    mode = config["model_mode"]
    
    if mode == "PCM" && get(config, "unit_commitment", 0) > 0
        H = input_data["H"]
        G_UC = input_data["G_UC"]
        
        if haskey(model, :u) && haskey(model, :v) && haskey(model, :w)
            for g in G_UC, h in H
                if h == 1
                    # First hour: assume units start offline
                    con_ref = @constraint(model,
                        model[:u][g,h] == model[:v][g,h],
                        base_name = "uc_transition_$(g)_$(h)")
                    push!(refs, con_ref)
                else
                    # Transition constraint: u[t] = u[t-1] + v[t] - w[t]
                    con_ref = @constraint(model,
                        model[:u][g,h] == model[:u][g,h-1] + model[:v][g,h] - model[:w][g,h],
                        base_name = "uc_transition_$(g)_$(h)")
                    push!(refs, con_ref)
                end
            end
        end
    end
    
    return refs
end

# Export constraint implementation functions
export apply_power_balance!, apply_generator_capacity_limit!, apply_transmission_flow_limit!
export apply_storage_energy_balance!, apply_storage_capacity_limit!, apply_investment_budget_generator!
export apply_investment_budget_transmission!, apply_investment_budget_storage!
export apply_rps_compliance!, apply_carbon_emission_limit!, apply_planning_reserve_margin!
export apply_minimum_run_limit!, apply_minimum_up_time!, apply_minimum_down_time!
export apply_demand_response_balance!, apply_unit_commitment_transition!
