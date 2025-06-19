"""
# ConstraintPool.jl - Unified Constraint Management System
# 
# This module provides a centralized constraint pool for HOPE models,
# enabling modular, transparent, and extensible constraint management.
# 
# Key Features:
# - Unified constraint registration and management
# - Automatic constraint categorization and grouping
# - Model-agnostic constraint definitions
# - Transparent constraint application and reporting
"""

module ConstraintPool

using JuMP
using DataFrames

# Constraint types and categories
@enum ConstraintCategory begin
    POWER_BALANCE
    GENERATOR_OPERATION
    TRANSMISSION_FLOW
    STORAGE_OPERATION
    INVESTMENT_BUDGET
    POLICY_COMPLIANCE
    SYSTEM_RELIABILITY
    DEMAND_RESPONSE
    UNIT_COMMITMENT
    DEBUG_SLACK
end

@enum ModelMode begin
    GTEP_MODE
    PCM_MODE
    HOLISTIC_MODE
end

# Constraint metadata structure
struct ConstraintMetadata
    name::Symbol
    category::ConstraintCategory
    description::String
    applicable_modes::Set{ModelMode}
    dependencies::Vector{Symbol}  # Other constraints this depends on
    variables_used::Vector{Symbol}  # Variables this constraint uses
    parameters_used::Vector{Symbol}  # Parameters this constraint needs
    is_conditional::Bool  # Whether constraint is conditionally applied
    condition_setting::Union{String, Nothing}  # Config setting that controls this constraint
end

# Main ConstraintPool structure
mutable struct HOPEConstraintPool
    constraints::Dict{Symbol, ConstraintMetadata}
    constraint_refs::Dict{Symbol, Vector{JuMP.ConstraintRef}}  # Store actual constraint references
    model_ref::Union{JuMP.Model, Nothing}
    applied_constraints::Set{Symbol}
    constraint_violations::Dict{Symbol, Float64}
    debug_mode::Bool
    
    function HOPEConstraintPool()
        new(
            Dict{Symbol, ConstraintMetadata}(),
            Dict{Symbol, Vector{JuMP.ConstraintRef}}(),
            nothing,
            Set{Symbol}(),
            Dict{Symbol, Float64}(),
            false
        )
    end
end

"""
Register a new constraint type in the pool
"""
function register_constraint!(
    pool::HOPEConstraintPool,
    name::Symbol,
    category::ConstraintCategory,
    description::String,
    applicable_modes::Vector{ModelMode},
    dependencies::Vector{Symbol} = Symbol[],
    variables_used::Vector{Symbol} = Symbol[],
    parameters_used::Vector{Symbol} = Symbol[],
    is_conditional::Bool = false,
    condition_setting::Union{String, Nothing} = nothing
)
    metadata = ConstraintMetadata(
        name,
        category,
        description,
        Set(applicable_modes),
        dependencies,
        variables_used,
        parameters_used,
        is_conditional,
        condition_setting
    )
    
    pool.constraints[name] = metadata
    pool.constraint_refs[name] = JuMP.ConstraintRef[]
    
    println("✓ Registered constraint: $(name) [$(category)]")
    return metadata
end

"""
Apply constraints to a model based on configuration and mode
"""
function apply_constraints!(
    pool::HOPEConstraintPool,
    model::JuMP.Model,
    mode::ModelMode,
    config::Dict,
    input_data::Dict
)
    pool.model_ref = model
    applied_count = 0
    skipped_count = 0
    
    println("🔧 Applying constraints for mode: $(mode)")
    
    for (name, metadata) in pool.constraints
        # Check if constraint applies to this model mode
        if mode ∉ metadata.applicable_modes
            continue
        end
          # Check conditional constraints
        if metadata.is_conditional && metadata.condition_setting !== nothing
            condition_value = get(config, metadata.condition_setting, false)
            # Convert to boolean (handle case where config values are integers)
            is_enabled = if condition_value isa Number
                condition_value > 0
            else
                Bool(condition_value)
            end
            if !is_enabled
                skipped_count += 1
                continue
            end
        end
        
        # Check dependencies
        if !all(dep ∈ pool.applied_constraints for dep in metadata.dependencies)
            missing_deps = setdiff(metadata.dependencies, pool.applied_constraints)
            println("⚠️  Skipping $(name): missing dependencies $(missing_deps)")
            skipped_count += 1
            continue
        end
        
        # Apply the constraint
        try
            constraint_refs = apply_single_constraint!(pool, name, model, config, input_data)
            pool.constraint_refs[name] = constraint_refs
            push!(pool.applied_constraints, name)
            applied_count += 1
            
            if pool.debug_mode
                println("✓ Applied constraint: $(name)")
            end
        catch e
            println("❌ Failed to apply constraint $(name): $(e)")
            skipped_count += 1
        end
    end
    
    println("📊 Applied $(applied_count) constraints, skipped $(skipped_count)")
    return pool
end

"""
Apply a single constraint to the model
This function dispatches to specific constraint implementations
"""
function apply_single_constraint!(
    pool::HOPEConstraintPool,
    constraint_name::Symbol,
    model::JuMP.Model,
    config::Dict,
    input_data::Dict
)::Vector{JuMP.ConstraintRef}
    # This will dispatch to specific constraint functions
    # Each constraint type has its own implementation function
    
    if constraint_name == :power_balance
        return apply_power_balance!(model, config, input_data)
    elseif constraint_name == :generator_capacity_limit
        return apply_generator_capacity_limit!(model, config, input_data)
    elseif constraint_name == :transmission_flow_limit
        return apply_transmission_flow_limit!(model, config, input_data)
    elseif constraint_name == :storage_energy_balance
        return apply_storage_energy_balance!(model, config, input_data)
    elseif constraint_name == :storage_capacity_limit
        return apply_storage_capacity_limit!(model, config, input_data)
    elseif constraint_name == :investment_budget_generator
        return apply_investment_budget_generator!(model, config, input_data)
    elseif constraint_name == :investment_budget_transmission
        return apply_investment_budget_transmission!(model, config, input_data)
    elseif constraint_name == :investment_budget_storage
        return apply_investment_budget_storage!(model, config, input_data)
    elseif constraint_name == :rps_compliance
        return apply_rps_compliance!(model, config, input_data)
    elseif constraint_name == :carbon_emission_limit
        return apply_carbon_emission_limit!(model, config, input_data)
    elseif constraint_name == :planning_reserve_margin
        return apply_planning_reserve_margin!(model, config, input_data)
    elseif constraint_name == :minimum_run_limit
        return apply_minimum_run_limit!(model, config, input_data)    elseif constraint_name == :minimum_up_time
        return apply_minimum_up_time!(model, config, input_data)
    elseif constraint_name == :minimum_down_time
        return apply_minimum_down_time!(model, config, input_data)
    elseif constraint_name == :unit_commitment_transition
        return apply_unit_commitment_transition!(model, config, input_data)
    elseif constraint_name == :demand_response_balance
        return apply_demand_response_balance!(model, config, input_data)
    else
        throw(ArgumentError("Unknown constraint: $(constraint_name)"))
    end
end

"""
Get constraint status and violations report
"""
function get_constraint_report(pool::HOPEConstraintPool)::DataFrame
    if pool.model_ref === nothing
        return DataFrame()
    end
    
    report_data = []
    
    for constraint_name in pool.applied_constraints
        metadata = pool.constraints[constraint_name]
        refs = pool.constraint_refs[constraint_name]
        
        # Calculate violations for solved model
        max_violation = 0.0
        if !isempty(refs) && has_values(pool.model_ref)
            for ref in refs
                try
                    # For equality constraints: |value|
                    # For inequality constraints: max(0, value)
                    violation = abs(JuMP.normalized_rhs(ref) - JuMP.value(ref))
                    max_violation = max(max_violation, violation)
                catch
                    # Skip if constraint evaluation fails
                end
            end
        end
        
        push!(report_data, (
            Constraint = constraint_name,
            Category = metadata.category,
            Description = metadata.description,
            NumConstraints = length(refs),
            MaxViolation = max_violation,
            Status = max_violation > 1e-6 ? "VIOLATED" : "SATISFIED"
        ))
    end
    
    return DataFrame(report_data)
end

"""
Initialize the constraint pool with all HOPE constraints
"""
function initialize_hope_constraint_pool()::HOPEConstraintPool
    pool = HOPEConstraintPool()
    
    println("🏗️  Initializing HOPE Constraint Pool...")
    
    # Power Balance Constraints
    register_constraint!(pool, :power_balance, POWER_BALANCE,
        "Power balance constraint for each zone and time period",
        [GTEP_MODE, PCM_MODE, HOLISTIC_MODE])
    
    # Generator Operation Constraints
    register_constraint!(pool, :generator_capacity_limit, GENERATOR_OPERATION,
        "Generator capacity limits and availability",
        [GTEP_MODE, PCM_MODE, HOLISTIC_MODE])
    
    # Transmission Flow Constraints
    register_constraint!(pool, :transmission_flow_limit, TRANSMISSION_FLOW,
        "Transmission line flow limits",
        [GTEP_MODE, PCM_MODE, HOLISTIC_MODE])
    
    # Storage Operation Constraints  
    register_constraint!(pool, :storage_energy_balance, STORAGE_OPERATION,
        "Energy storage charge/discharge balance",
        [GTEP_MODE, PCM_MODE, HOLISTIC_MODE])
    
    register_constraint!(pool, :storage_capacity_limit, STORAGE_OPERATION,
        "Energy storage capacity limits",
        [GTEP_MODE, PCM_MODE, HOLISTIC_MODE])
    
    # Investment Budget Constraints (GTEP only)
    register_constraint!(pool, :investment_budget_generator, INVESTMENT_BUDGET,
        "Generator investment budget constraint",
        [GTEP_MODE, HOLISTIC_MODE])
    
    register_constraint!(pool, :investment_budget_transmission, INVESTMENT_BUDGET,
        "Transmission investment budget constraint", 
        [GTEP_MODE, HOLISTIC_MODE])
    
    register_constraint!(pool, :investment_budget_storage, INVESTMENT_BUDGET,
        "Storage investment budget constraint",
        [GTEP_MODE, HOLISTIC_MODE])
    
    # Policy Compliance Constraints
    register_constraint!(pool, :rps_compliance, POLICY_COMPLIANCE,
        "Renewable Portfolio Standard compliance",
        [GTEP_MODE, PCM_MODE, HOLISTIC_MODE])
    
    register_constraint!(pool, :carbon_emission_limit, POLICY_COMPLIANCE,
        "Carbon emission limitation",
        [GTEP_MODE, PCM_MODE, HOLISTIC_MODE])
    
    # System Reliability Constraints
    register_constraint!(pool, :planning_reserve_margin, SYSTEM_RELIABILITY,
        "Planning reserve margin requirement",
        [GTEP_MODE, HOLISTIC_MODE])
    
    # Unit Commitment Constraints (conditional)
    register_constraint!(pool, :minimum_run_limit, UNIT_COMMITMENT,
        "Generator minimum run limit",
        [PCM_MODE], Symbol[], Symbol[], Symbol[], true, "unit_commitment")
      register_constraint!(pool, :minimum_up_time, UNIT_COMMITMENT,
        "Generator minimum up time",
        [PCM_MODE], Symbol[], Symbol[], Symbol[], true, "unit_commitment")
    
    register_constraint!(pool, :minimum_down_time, UNIT_COMMITMENT,
        "Generator minimum down time", 
        [PCM_MODE], Symbol[], Symbol[], Symbol[], true, "unit_commitment")
    
    register_constraint!(pool, :unit_commitment_transition, UNIT_COMMITMENT,
        "Unit commitment state transitions (linking u, v, w variables)",
        [PCM_MODE], Symbol[], Symbol[], Symbol[], true, "unit_commitment")
    
    # Demand Response Constraints (conditional)
    register_constraint!(pool, :demand_response_balance, DEMAND_RESPONSE,
        "Demand response energy balance",
        [GTEP_MODE, PCM_MODE], Symbol[], Symbol[], Symbol[], true, "flexible_demand")
    
    println("✅ Constraint pool initialized with $(length(pool.constraints)) constraint types")
    return pool
end

# Export main functions and types
export HOPEConstraintPool, ConstraintCategory, ModelMode
export register_constraint!, apply_constraints!, get_constraint_report
export initialize_hope_constraint_pool

end # module ConstraintPool
