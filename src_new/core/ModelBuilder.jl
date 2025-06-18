"""
# ModelBuilder.jl - Unified Model Construction Framework
# 
# This module provides a unified framework for building HOPE models
# using the modular constraint pool and time management systems.
"""

using JuMP
using DataFrames

# Note: ConstraintPool, ConstraintImplementations, and TimeManager 
# are included by the parent module HOPE_New.jl

"""
Main model builder structure
"""
mutable struct HOPEModelBuilder
    constraint_pool::ConstraintPool
    time_manager::TimeManager
    config::Dict
    input_data::Dict
    model::Union{JuMP.Model, Nothing}
    variables::Dict{Symbol, Any}
    expressions::Dict{Symbol, Any}
    
    function HOPEModelBuilder()
        new(
            initialize_hope_constraint_pool(),
            TimeManager(),
            Dict(),
            Dict(),
            nothing,
            Dict{Symbol, Any}(),
            Dict{Symbol, Any}()
        )
    end
end

"""
Initialize the model builder with configuration and data
"""
function initialize!(
    builder::HOPEModelBuilder,
    config::Dict,
    input_data::Dict,
    optimizer
)
    builder.config = config
    builder.input_data = input_data
    
    # Create JuMP model
    builder.model = Model(optimizer)
    
    # Set up time structure based on model mode
    setup_time_structure!(builder)
    
    println("🏗️  Model builder initialized for mode: $(config["model_mode"])")
    return builder
end

"""
Set up time structure based on model configuration
"""
function setup_time_structure!(builder::HOPEModelBuilder)
    mode = builder.config["model_mode"]
    
    if mode == "GTEP"
        # Create GTEP time structure from clustering data
        if haskey(builder.input_data, "representative_days")
            cluster_data = builder.input_data["representative_days"]
            days_per_cluster = builder.input_data["days_per_cluster"]
            time_structure = create_gtep_time_structure(cluster_data, days_per_cluster)
        else
            # Default GTEP structure (4 seasons, 24 hours each)
            time_structure = GTEPTimeStructure(
                [1, 2, 3, 4],  # 4 seasons
                Dict(1 => collect(1:24), 2 => collect(1:24), 3 => collect(1:24), 4 => collect(1:24)),
                Dict(1 => 90, 2 => 92, 3 => 92, 4 => 91),  # Days per season
                Dict(1 => 0.25, 2 => 0.25, 3 => 0.25, 4 => 0.25)
            )
        end
        
    elseif mode == "PCM"
        # Create PCM time structure for full year
        year = get(builder.config, "target_year", 2035)
        time_structure = create_pcm_time_structure(year)
        
    elseif mode == "HOLISTIC"
        # Create combined structure for holistic modeling
        # This requires both GTEP and PCM structures
        gtep_structure = create_gtep_time_structure(
            builder.input_data["gtep_representative_days"],
            builder.input_data["gtep_days_per_cluster"]
        )
        pcm_structure = create_pcm_time_structure()
        cluster_mapping = builder.input_data["cluster_mapping"]
        time_structure = create_holistic_time_structure(gtep_structure, pcm_structure, cluster_mapping)
    end
    
    set_time_structure!(builder.time_manager, time_structure)
      # Store time indices in input_data for constraint functions
    time_indices = get_time_indices(builder.time_manager)
    time_indices_dict = Dict(string(k) => v for (k, v) in pairs(time_indices))
    merge!(builder.input_data, time_indices_dict)
    
    println("✅ Time structure configured: $(get_time_summary(builder.time_manager))")
end

"""
Create all model variables based on model mode and configuration
"""
function create_variables!(builder::HOPEModelBuilder)
    model = builder.model
    config = builder.config
    input_data = builder.input_data
    mode = config["model_mode"]
    
    println("🔧 Creating variables for $(mode) model...")
    
    # Get time indices
    time_indices = get_time_indices(builder.time_manager)
    
    if mode == "GTEP"
        create_gtep_variables!(builder, time_indices)
    elseif mode == "PCM"
        create_pcm_variables!(builder, time_indices)
    elseif mode == "HOLISTIC"
        create_holistic_variables!(builder, time_indices)
    end
    
    println("✅ Created $(length(builder.variables)) variable groups")
end

"""
Create GTEP model variables
"""
function create_gtep_variables!(builder::HOPEModelBuilder, time_indices)
    model = builder.model
    input_data = builder.input_data
    
    T = time_indices[:T]
    H_T = time_indices[:H_T]
    
    # Sets
    G = input_data["G"]        # Existing generators
    G_new = input_data["G_new"] # Candidate generators
    L = input_data["L"]        # Existing lines
    L_new = input_data["L_new"] # Candidate lines
    S = input_data["S"]        # Existing storage
    S_new = input_data["S_new"] # Candidate storage
    I = input_data["I"]        # Zones
    W = input_data["W"]        # States
    
    # Generator variables
    @variable(model, p[union(G, G_new), T, vcat(values(H_T)...)] >= 0, base_name = "power_generation")
    builder.variables[:p] = model[:p]
    
    # Investment decision variables
    if get(builder.config, "investment_binary", true)
        @variable(model, x[G_new], Bin, base_name = "generator_investment")
        @variable(model, y[L_new], Bin, base_name = "transmission_investment")
        @variable(model, z[S_new], Bin, base_name = "storage_investment")
    else
        @variable(model, 0 <= x[G_new] <= 1, base_name = "generator_investment")
        @variable(model, 0 <= y[L_new] <= 1, base_name = "transmission_investment")
        @variable(model, 0 <= z[S_new] <= 1, base_name = "storage_investment")
    end
    builder.variables[:x] = model[:x]
    builder.variables[:y] = model[:y]
    builder.variables[:z] = model[:z]
    
    # Transmission flow
    @variable(model, f[union(L, L_new), T, vcat(values(H_T)...)], base_name = "transmission_flow")
    builder.variables[:f] = model[:f]
    
    # Storage variables
    @variable(model, soc[union(S, S_new), T, vcat(values(H_T)...)] >= 0, base_name = "storage_soc")
    @variable(model, c[union(S, S_new), T, vcat(values(H_T)...)] >= 0, base_name = "storage_charge")
    @variable(model, dc[union(S, S_new), T, vcat(values(H_T)...)] >= 0, base_name = "storage_discharge")
    builder.variables[:soc] = model[:soc]
    builder.variables[:c] = model[:c]
    builder.variables[:dc] = model[:dc]
    
    # Load shedding
    @variable(model, p_LS[I, T, vcat(values(H_T)...)] >= 0, base_name = "load_shedding")
    builder.variables[:p_LS] = model[:p_LS]
    
    # Policy variables
    @variable(model, pt_rps[W] >= 0, base_name = "rps_penalty")
    @variable(model, em_emis[W] >= 0, base_name = "emission_violation")
    builder.variables[:pt_rps] = model[:pt_rps]
    builder.variables[:em_emis] = model[:em_emis]
      # Conditional variables
    if get(builder.config, "flexible_demand", false)
        D = input_data["D"]  # Demand response resources
        @variable(model, dr[D, T, vcat(values(H_T)...)] >= 0, base_name = "demand_response")
        @variable(model, dr_UP[D, T, vcat(values(H_T)...)] >= 0, base_name = "demand_response_up")
        @variable(model, dr_DN[D, T, vcat(values(H_T)...)] >= 0, base_name = "demand_response_down")
        @variable(model, dr_reduce[I, T, vcat(values(H_T)...)] >= 0, base_name = "demand_response_reduce")
        @variable(model, dr_increase[I, T, vcat(values(H_T)...)] >= 0, base_name = "demand_response_increase")
        builder.variables[:dr] = model[:dr]
        builder.variables[:dr_UP] = model[:dr_UP]
        builder.variables[:dr_DN] = model[:dr_DN]
        builder.variables[:dr_reduce] = model[:dr_reduce]
        builder.variables[:dr_increase] = model[:dr_increase]
    end
end

"""
Create PCM model variables
"""
function create_pcm_variables!(builder::HOPEModelBuilder, time_indices)
    model = builder.model
    input_data = builder.input_data
    
    H = time_indices[:H]
    
    # Sets
    G = input_data["G"]  # Generators
    L = input_data["L"]  # Lines
    S = input_data["S"]  # Storage
    I = input_data["I"]  # Zones
    W = input_data["W"]  # States
    
    # Generator variables
    @variable(model, p[G, H] >= 0, base_name = "power_generation")
    builder.variables[:p] = model[:p]
    
    # Transmission flow
    @variable(model, f[L, H], base_name = "transmission_flow")
    builder.variables[:f] = model[:f]
    
    # Storage variables
    @variable(model, soc[S, H] >= 0, base_name = "storage_soc")
    @variable(model, c[S, H] >= 0, base_name = "storage_charge")
    @variable(model, dc[S, H] >= 0, base_name = "storage_discharge")
    builder.variables[:soc] = model[:soc]
    builder.variables[:c] = model[:c]
    builder.variables[:dc] = model[:dc]
    
    # Load shedding
    @variable(model, p_LS[I, H] >= 0, base_name = "load_shedding")
    builder.variables[:p_LS] = model[:p_LS]
    
    # Policy variables
    @variable(model, pt_rps[W, H] >= 0, base_name = "rps_penalty")
    @variable(model, em_emis[W] >= 0, base_name = "emission_violation")
    builder.variables[:pt_rps] = model[:pt_rps]
    builder.variables[:em_emis] = model[:em_emis]
      # Unit commitment variables (conditional)
    if get(builder.config, "unit_commitment", 0) > 0
        G_UC = input_data["G_UC"]  # Units with commitment constraints
        
        if builder.config["unit_commitment"] == 1
            @variable(model, u[G_UC, H], Bin, base_name = "unit_online")
            @variable(model, v[G_UC, H], Bin, base_name = "unit_startup")
            @variable(model, w[G_UC, H], Bin, base_name = "unit_shutdown")
        else
            @variable(model, 0 <= u[G_UC, H] <= 1, base_name = "unit_online")
            @variable(model, 0 <= v[G_UC, H] <= 1, base_name = "unit_startup")
            @variable(model, 0 <= w[G_UC, H] <= 1, base_name = "unit_shutdown")
        end
        
        @variable(model, pmin[G_UC, H] >= 0, base_name = "unit_min_power")
        
        builder.variables[:u] = model[:u]
        builder.variables[:v] = model[:v]
        builder.variables[:w] = model[:w]
        builder.variables[:pmin] = model[:pmin]
    end
      # Conditional demand response variables
    if get(builder.config, "flexible_demand", false)
        D = input_data["D"]
        @variable(model, dr[D, H] >= 0, base_name = "demand_response")
        @variable(model, dr_UP[D, H] >= 0, base_name = "demand_response_up")
        @variable(model, dr_DN[D, H] >= 0, base_name = "demand_response_down")
        @variable(model, dr_reduce[input_data["I"], H] >= 0, base_name = "demand_response_reduce")
        @variable(model, dr_increase[input_data["I"], H] >= 0, base_name = "demand_response_increase")
        builder.variables[:dr] = model[:dr]
        builder.variables[:dr_UP] = model[:dr_UP]
        builder.variables[:dr_DN] = model[:dr_DN]
        builder.variables[:dr_reduce] = model[:dr_reduce]
        builder.variables[:dr_increase] = model[:dr_increase]
    end
end

"""
Create holistic model variables (combination of GTEP and PCM)
"""
function create_holistic_variables!(builder::HOPEModelBuilder, time_indices)
    # For holistic modeling, create both GTEP and PCM variables
    # This allows for seamless transition between planning and operation
    
    # Implementation would combine elements from both GTEP and PCM variable creation
    # with appropriate time index mapping
end

"""
Create objective function expressions
"""
function create_objective!(builder::HOPEModelBuilder)
    model = builder.model
    config = builder.config
    mode = config["model_mode"]
    
    if mode == "GTEP"
        create_gtep_objective!(builder)
    elseif mode == "PCM"
        create_pcm_objective!(builder)
    elseif mode == "HOLISTIC"
        create_holistic_objective!(builder)
    end
    
    println("✅ Objective function created for $(mode) model")
end

"""
Create GTEP objective function
"""
function create_gtep_objective!(builder::HOPEModelBuilder)
    model = builder.model
    input_data = builder.input_data
    time_indices = get_time_indices(builder.time_manager)
    
    T = time_indices[:T]
    H_T = time_indices[:H_T]
    period_weights = time_indices[:period_weights]
    
    # Investment costs
    inv_cost_expr = @expression(model, INVCost,
        sum(input_data["Gendata_candidate"][g, Symbol("INV (\$/MW)")] * 
            input_data["Gendata_candidate"][g, Symbol("Pmax (MW)")] * 
            model[:x][g] for g in input_data["G_new"]) +
        sum(input_data["Linedata_candidate"][l, Symbol("INV (\$/MW)")] * 
            input_data["Linedata_candidate"][l, Symbol("Pmax (MW)")] * 
            model[:y][l] for l in input_data["L_new"]) +
        sum(input_data["Storagedata_candidate"][s, Symbol("INV (\$/MWh)")] * 
            input_data["Storagedata_candidate"][s, Symbol("Capacity (MWh)")] * 
            model[:z][s] for s in input_data["S_new"])
    )
    
    # Operation costs
    op_cost_expr = @expression(model, OPCost,
        sum(period_weights[t] * 365 * 
            sum(input_data["Gendata"][g, Symbol("Cost (\$/MWh)")] * model[:p][g,t,h]
                for g in input_data["G"], h in H_T[t])
            for t in T)
    )
    
    # Penalty costs
    penalty_expr = @expression(model, PenaltyCost,
        sum(model[:p_LS][i,t,h] * 1000  # VOLL
            for i in input_data["I"], t in T, h in H_T[t]) +
        sum(model[:pt_rps][w] * 50  # RPS penalty
            for w in input_data["W"]) +
        sum(model[:em_emis][w] * 100  # Carbon penalty
            for w in input_data["W"])
    )
    
    # Store expressions
    builder.expressions[:INVCost] = inv_cost_expr
    builder.expressions[:OPCost] = op_cost_expr
    builder.expressions[:PenaltyCost] = penalty_expr
    
    # Set objective
    @objective(model, Min, inv_cost_expr + op_cost_expr + penalty_expr)
end

"""
Create PCM objective function
"""
function create_pcm_objective!(builder::HOPEModelBuilder)
    model = builder.model
    input_data = builder.input_data
    
    H = input_data["H"]
    
    # Operation costs
    op_cost_expr = @expression(model, OPCost,
        sum(input_data["Gendata"][g, Symbol("Cost (\$/MWh)")] * model[:p][g,h]
            for g in input_data["G"], h in H)
    )
      # Startup costs (if unit commitment is enabled)
    if get(builder.config, "unit_commitment", 0) > 0
        startup_cost_expr = @expression(model, STCost,
            sum(input_data["Gendata"][g, Symbol("STC (\$/MW)")] * 
                input_data["Gendata"][g, Symbol("Pmax (MW)")] * 
                model[:v][g,h]
                for g in input_data["G_UC"], h in H)
        )
        builder.expressions[:STCost] = startup_cost_expr
    else
        startup_cost_expr = 0
    end
    
    # Penalty costs
    penalty_expr = @expression(model, PenaltyCost,
        sum(model[:p_LS][i,h] * 1000  # VOLL
            for i in input_data["I"], h in H) +
        sum(model[:pt_rps][w,h] * 50  # RPS penalty
            for w in input_data["W"], h in H) +
        sum(model[:em_emis][w] * 100  # Carbon penalty
            for w in input_data["W"])
    )
    
    # Store expressions
    builder.expressions[:OPCost] = op_cost_expr
    builder.expressions[:PenaltyCost] = penalty_expr
    
    # Set objective
    @objective(model, Min, op_cost_expr + startup_cost_expr + penalty_expr)
end

"""
Create holistic objective function
"""
function create_holistic_objective!(builder::HOPEModelBuilder)
    # Combine GTEP and PCM objectives with appropriate weighting
end

"""
Apply all constraints using the constraint pool
"""
function apply_constraints!(builder::HOPEModelBuilder)
    mode_map = Dict(
        "GTEP" => GTEP_MODE,
        "PCM" => PCM_MODE,
        "HOLISTIC" => HOLISTIC_MODE
    )
    
    mode = mode_map[builder.config["model_mode"]]
    
    apply_constraints!(
        builder.constraint_pool,
        builder.model,
        mode,
        builder.config,
        builder.input_data
    )
    
    println("✅ All constraints applied successfully")
end

"""
Build the complete model
"""
function build_model!(builder::HOPEModelBuilder)
    println("🏗️  Building HOPE model...")
    
    # Create variables
    create_variables!(builder)
    
    # Create objective function
    create_objective!(builder)
    
    # Apply constraints
    apply_constraints!(builder)
    
    println("✅ Model building completed successfully!")
    println("📊 Model summary:")
    println("   Variables: $(num_variables(builder.model))")
    println("   Constraints: $(num_constraints(builder.model; count_variable_in_set_constraints=false))")
    
    return builder.model
end

"""
Get model building report
"""
function get_model_report(builder::HOPEModelBuilder)::Dict
    if builder.model === nothing
        return Dict("status" => "Model not built")
    end
    
    # Get constraint report
    constraint_report = get_constraint_report(builder.constraint_pool)
    
    # Get time structure summary
    time_summary = get_time_summary(builder.time_manager)
    
    return Dict(
        "model_mode" => builder.config["model_mode"],
        "num_variables" => num_variables(builder.model),
        "num_constraints" => num_constraints(builder.model; count_variable_in_set_constraints=false),
        "time_structure" => time_summary,
        "constraint_report" => constraint_report,
        "variable_groups" => collect(keys(builder.variables)),
        "expression_groups" => collect(keys(builder.expressions))
    )
end

# Export main functions and types
export HOPEModelBuilder
export initialize!, build_model!, get_model_report
export create_variables!, create_objective!, apply_constraints!
