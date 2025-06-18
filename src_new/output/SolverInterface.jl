"""
# SolverInterface.jl - Unified Solver Interface
# 
# This module provides a standardized interface for solving HOPE models
# with different optimizers and extracting solution information.
"""

using JuMP
using YAML
using Dates
using JuMP: MOI

# Conditional solver imports
const HAS_GUROBI = try
    using Gurobi
    true
catch
    false
end

const HAS_CPLEX = try
    using CPLEX
    true
catch
    false
end

const HAS_HIGHS = try
    using HiGHS
    true
catch
    false
end

const HAS_CBC = try
    using Cbc
    true
catch
    false
end

const HAS_SCIP = try
    using SCIP
    true
catch
    false
end

const HAS_CLP = try
    using Clp
    true
catch
    false
end

"""
Solver configuration structure
"""
struct SolverConfig
    name::String
    time_limit::Float64
    gap_tolerance::Float64
    threads::Int
    other_params::Dict{String, Any}
    
    function SolverConfig(name::String; 
                         time_limit::Float64=3600.0,
                         gap_tolerance::Float64=0.01,
                         threads::Int=0,
                         other_params::Dict{String, Any}=Dict())
        new(name, time_limit, gap_tolerance, threads, other_params)
    end
end

"""
Solution information structure
"""
struct SolutionInfo
    status::String
    objective_value::Union{Float64, Nothing}
    solve_time::Float64
    gap::Union{Float64, Nothing}
    optimizer::String
    model_stats::Dict{String, Any}
    
    function SolutionInfo(model::JuMP.Model, solver_config::SolverConfig, solve_time::Float64)
        status = string(termination_status(model))
        
        obj_val = nothing
        if has_values(model)
            try
                obj_val = objective_value(model)
            catch
                obj_val = nothing
            end
        end
        
        gap = nothing
        if status in ["OPTIMAL", "TIME_LIMIT"]
            try
                gap = relative_gap(model) * 100  # Convert to percentage
            catch
                gap = nothing
            end
        end
        
        model_stats = Dict(
            "num_variables" => num_variables(model),
            "num_constraints" => num_constraints(model; count_variable_in_set_constraints=false),
            "num_linear_constraints" => num_constraints(model, LinearRef),
            "num_binary_variables" => length([v for v in all_variables(model) if is_binary(v)]),
            "num_integer_variables" => length([v for v in all_variables(model) if is_integer(v)])
        )
        
        new(status, obj_val, solve_time, gap, solver_config.name, model_stats)
    end
end

"""
Get available solvers on the system
"""
function get_available_solvers()::Vector{String}
    available = String[]
    
    # Check for commercial solvers
    if HAS_GUROBI
        try
            Gurobi.Optimizer()
            push!(available, "Gurobi")
        catch
        end
    end
    
    if HAS_CPLEX
        try
            CPLEX.Optimizer()
            push!(available, "CPLEX")
        catch
        end
    end
    
    # Check for open-source solvers
    if HAS_HIGHS
        try
            HiGHS.Optimizer()
            push!(available, "HiGHS")
        catch
        end
    end
    
    if HAS_CBC
        try
            Cbc.Optimizer()
            push!(available, "Cbc")
        catch
        end
    end
    
    if HAS_SCIP
        try
            SCIP.Optimizer()
            push!(available, "SCIP")
        catch
        end
    end
    
    if HAS_CLP
        try
            Clp.Optimizer()
            push!(available, "Clp")
        catch
        end
    end
    
    return available
end

"""
Create optimizer constructor function from configuration
"""
function create_optimizer(config::SolverConfig)
    if config.name == "Gurobi" && HAS_GUROBI
        return () -> begin
            optimizer = Gurobi.Optimizer()
            
            # Set common Gurobi parameters
            if config.time_limit < Inf
                MOI.set(optimizer, MOI.TimeLimitSec(), config.time_limit)
            end
            MOI.set(optimizer, MOI.RelativeGapTolerance(), config.gap_tolerance)
            if config.threads > 0
                MOI.set(optimizer, MOI.NumberOfThreads(), config.threads)
            end
            
            # Set additional parameters
            for (param, value) in config.other_params
                try
                    MOI.set(optimizer, MOI.RawOptimizerAttribute(param), value)
                catch
                    # Ignore parameters that don't work
                end
            end
            
            return optimizer
        end
        
    elseif config.name == "CPLEX" && HAS_CPLEX
        return () -> begin
            optimizer = CPLEX.Optimizer()
            
            # Set common CPLEX parameters
            if config.time_limit < Inf
                MOI.set(optimizer, MOI.TimeLimitSec(), config.time_limit)
            end
            MOI.set(optimizer, MOI.RelativeGapTolerance(), config.gap_tolerance)
            if config.threads > 0
                MOI.set(optimizer, MOI.NumberOfThreads(), config.threads)
            end
            
            # Set additional parameters
            for (param, value) in config.other_params
                try
                    MOI.set(optimizer, MOI.RawOptimizerAttribute(param), value)
                catch
                    # Ignore parameters that don't work
                end
            end
            
            return optimizer
        end        
    elseif config.name == "HiGHS" && HAS_HIGHS
        return () -> begin
            optimizer = HiGHS.Optimizer()
            
            # Set common HiGHS parameters
            if config.time_limit < Inf
                MOI.set(optimizer, MOI.TimeLimitSec(), config.time_limit)
            end
            MOI.set(optimizer, MOI.RelativeGapTolerance(), config.gap_tolerance)
            if config.threads > 0
                MOI.set(optimizer, MOI.NumberOfThreads(), config.threads)
            end
            
            # Set additional parameters
            for (param, value) in config.other_params
                try
                    MOI.set(optimizer, MOI.RawOptimizerAttribute(param), value)
                catch
                    # Ignore parameters that don't work
                end
            end
            
            return optimizer
        end
        
    elseif config.name == "Cbc" && HAS_CBC
        return () -> begin
            optimizer = Cbc.Optimizer()
            
            # Set common Cbc parameters
            if config.time_limit < Inf
                MOI.set(optimizer, MOI.TimeLimitSec(), config.time_limit)
            end
            MOI.set(optimizer, MOI.RelativeGapTolerance(), config.gap_tolerance)
            if config.threads > 0
                MOI.set(optimizer, MOI.NumberOfThreads(), config.threads)
            end
            
            # Set additional parameters
            for (param, value) in config.other_params
                try
                    MOI.set(optimizer, MOI.RawOptimizerAttribute(param), value)
                catch
                    # Ignore parameters that don't work
                end
            end
            
            return optimizer
        end
        
    elseif config.name == "SCIP" && HAS_SCIP
        return () -> begin
            optimizer = SCIP.Optimizer()
            
            # Set common SCIP parameters
            if config.time_limit < Inf
                MOI.set(optimizer, MOI.TimeLimitSec(), config.time_limit)
            end
            MOI.set(optimizer, MOI.RelativeGapTolerance(), config.gap_tolerance)
            if config.threads > 0
                MOI.set(optimizer, MOI.NumberOfThreads(), config.threads)
            end
            
            # Set additional parameters
            for (param, value) in config.other_params
                try
                    MOI.set(optimizer, MOI.RawOptimizerAttribute(param), value)
                catch
                    # Ignore parameters that don't work
                end
            end
              return optimizer
        end
        
    elseif config.name == "Clp" && HAS_CLP
        return () -> begin
            optimizer = Clp.Optimizer()
            
            # Set common Clp parameters
            if config.time_limit < Inf
                MOI.set(optimizer, MOI.TimeLimitSec(), config.time_limit)
            end
            
            # Set additional parameters
            for (param, value) in config.other_params
                try
                    MOI.set(optimizer, MOI.RawOptimizerAttribute(param), value)
                catch
                    # Ignore parameters that don't work
                end
            end
              return optimizer
        end
        
    else
        error("Unsupported or unavailable solver: $(config.name)")
    end
end

"""
Load solver configuration from YAML file
"""
function load_solver_config(config_path::String, solver_name::String)::SolverConfig
    if !isfile(config_path)
        println("⚠️  Solver config file not found: $config_path")
        return SolverConfig(solver_name)  # Return default config
    end
    
    try
        config_data = YAML.load_file(config_path)
        
        time_limit = get(config_data, "time_limit", 3600.0)
        gap_tolerance = get(config_data, "gap_tolerance", 0.01)
        threads = get(config_data, "threads", 0)
        other_params = get(config_data, "parameters", Dict())
        
        return SolverConfig(
            solver_name,
            time_limit=time_limit,
            gap_tolerance=gap_tolerance,
            threads=threads,
            other_params=other_params
        )
    catch e
        println("⚠️  Error loading solver config: $e")
        return SolverConfig(solver_name)  # Return default config
    end
end

"""
Choose best available solver automatically
"""
function choose_best_solver()::String
    available = get_available_solvers()
    
    if isempty(available)
        error("No supported solvers are available!")
    end
    
    # Preference order: commercial first, then open-source
    preference_order = ["Gurobi", "CPLEX", "HiGHS", "Cbc", "SCIP", "Clp"]
    
    for solver in preference_order
        if solver in available
            return solver
        end
    end
    
    return first(available)  # Fallback to first available
end

"""
Solve HOPE model with specified solver configuration
"""
function solve_hope_model!(model::JuMP.Model, config::SolverConfig)::SolutionInfo
    println("🔧 Setting up optimizer: $(config.name)")
    
    # Create and set optimizer
    optimizer = create_optimizer(config)
    set_optimizer(model, optimizer)
    
    println("⚡ Solving model...")
    println("   Variables: $(num_variables(model))")
    println("   Constraints: $(num_constraints(model; count_variable_in_set_constraints=false))")
    
    # Record solve time
    start_time = time()
    optimize!(model)
    solve_time = time() - start_time
    
    # Create solution info
    solution_info = SolutionInfo(model, config, solve_time)
    
    # Print solution summary
    print_solution_summary(solution_info)
    
    return solution_info
end

"""
Print solution summary
"""
function print_solution_summary(info::SolutionInfo)
    println("\n📊 Solution Summary:")
    println("   Status: $(info.status)")
    if info.objective_value !== nothing
        println("   Objective Value: \$$(round(info.objective_value, digits=2))")
    end
    println("   Solve Time: $(round(info.solve_time, digits=2)) seconds")
    if info.gap !== nothing
        println("   Optimality Gap: $(round(info.gap, digits=4))%")
    end
    println("   Optimizer: $(info.optimizer)")
    
    if info.status == "OPTIMAL"
        println("✅ Model solved to optimality!")
    elseif info.status == "TIME_LIMIT"
        println("⏱️  Time limit reached")
    elseif info.status in ["INFEASIBLE", "DUAL_INFEASIBLE"]
        println("❌ Model is infeasible")
    else
        println("⚠️  Solve completed with status: $(info.status)")
    end
end

"""
Convert solution info to dictionary for output
"""
function solution_info_to_dict(info::SolutionInfo)::Dict
    return Dict(
        "status" => info.status,
        "objective_value" => info.objective_value,
        "solve_time" => info.solve_time,
        "gap" => info.gap,
        "optimizer" => info.optimizer,
        "model_stats" => info.model_stats
    )
end

"""
Validate model before solving
"""
function validate_model(model::JuMP.Model)::Vector{String}
    issues = String[]
    
    # Check for variables
    if num_variables(model) == 0
        push!(issues, "Model has no variables")
    end
    
    # Check for constraints
    if num_constraints(model; count_variable_in_set_constraints=false) == 0
        push!(issues, "Model has no constraints")
    end
    
    # Check for objective
    if objective_function(model) == zero(AffExpr)
        push!(issues, "Model has no objective function")
    end
    
    # Check for unbounded variables
    unbounded_vars = []
    for var in all_variables(model)
        if !has_lower_bound(var) && !has_upper_bound(var) && !is_binary(var) && !is_integer(var)
            push!(unbounded_vars, var)
        end
    end
    
    if length(unbounded_vars) > 10  # Arbitrary threshold
        push!(issues, "Model has $(length(unbounded_vars)) potentially unbounded variables")
    end
    
    return issues
end

"""
Run full solve workflow
"""
function solve_workflow!(
    model::JuMP.Model,
    solver_config::SolverConfig;
    validate::Bool=true
)::SolutionInfo
    
    if validate
        issues = validate_model(model)
        if !isempty(issues)
            println("⚠️  Model validation issues:")
            for issue in issues
                println("   - $issue")
            end
        end
    end
    
    solution_info = solve_hope_model!(model, solver_config)
    
    return solution_info
end

# Export main functions and types
export SolverConfig, SolutionInfo
export get_available_solvers, choose_best_solver
export create_optimizer, load_solver_config
export solve_hope_model!, solve_workflow!
export solution_info_to_dict, validate_model
