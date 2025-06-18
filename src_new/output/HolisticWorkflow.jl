"""
# HolisticWorkflow.jl - Integrated GTEP→PCM Workflow
# 
# This module provides the holistic workflow that combines GTEP planning
# and PCM operational modeling in a unified framework.
"""

using JuMP
using DataFrames
using CSV
using Dates

# Import from other modules
include("SolverInterface.jl")
include("OutputWriter.jl")
include("PlotGenerator.jl")

"""
Holistic workflow configuration
"""
struct HolisticConfig
    gtep_config::Dict
    pcm_config::Dict
    coupling_method::String  # "sequential", "iterative", "integrated"
    max_iterations::Int
    convergence_tolerance::Float64
    
    function HolisticConfig(;
                           gtep_config::Dict=Dict(),
                           pcm_config::Dict=Dict(),
                           coupling_method::String="sequential",
                           max_iterations::Int=5,
                           convergence_tolerance::Float64=0.01)
        new(gtep_config, pcm_config, coupling_method, max_iterations, convergence_tolerance)
    end
end

"""
Holistic workflow results
"""
mutable struct HolisticResults
    gtep_results::Union{Dict, Nothing}
    pcm_results::Union{Dict, Nothing}
    iterations::Vector{Dict}
    convergence_achieved::Bool
    total_solve_time::Float64
    
    function HolisticResults()
        new(nothing, nothing, Dict[], false, 0.0)
    end
end

"""
Run complete holistic workflow
"""
function run_holistic_workflow!(
    case_path::String,
    output_path::String,
    config::HolisticConfig,
    solver_config::SolverConfig
)::HolisticResults
    
    println("🔄 Starting Holistic GTEP→PCM Workflow")
    println("   Case: $case_path")
    println("   Method: $(config.coupling_method)")
    
    start_time = time()
    results = HolisticResults()
    
    try
        if config.coupling_method == "sequential"
            run_sequential_workflow!(case_path, output_path, config, solver_config, results)
        elseif config.coupling_method == "iterative"
            run_iterative_workflow!(case_path, output_path, config, solver_config, results)
        elseif config.coupling_method == "integrated"
            run_integrated_workflow!(case_path, output_path, config, solver_config, results)
        else
            error("Unknown coupling method: $(config.coupling_method)")
        end
        
        results.total_solve_time = time() - start_time
        
        println("✅ Holistic workflow completed successfully!")
        println("   Total time: $(round(results.total_solve_time, digits=2)) seconds")
        
    catch e
        println("❌ Holistic workflow failed: $e")
        results.total_solve_time = time() - start_time
        rethrow(e)
    end
    
    return results
end

"""
Run sequential GTEP→PCM workflow
"""
function run_sequential_workflow!(
    case_path::String,
    output_path::String,
    config::HolisticConfig,
    solver_config::SolverConfig,
    results::HolisticResults
)
    println("\n📋 Step 1: GTEP Planning Model")
    
    # Load and solve GTEP model
    gtep_builder = HOPEModelBuilder()
    gtep_config = merge(config.gtep_config, Dict("model_mode" => "GTEP"))
    
    # Load GTEP data
    gtep_reader = HOPEDataReader(case_path)
    gtep_data = load_hope_data(gtep_reader)
    
    # Initialize and build GTEP model
    initialize!(gtep_builder, gtep_config, gtep_data, create_optimizer(solver_config))
    gtep_model = build_model!(gtep_builder)
    
    # Solve GTEP
    gtep_solution = solve_workflow!(gtep_model, solver_config)
    
    # Extract investment decisions
    investment_decisions = extract_investment_decisions(gtep_builder)
    
    # Write GTEP results
    gtep_output_path = joinpath(output_path, "GTEP_results")
    mkpath(gtep_output_path)
    gtep_writer = HOPEOutputWriter(gtep_output_path, "GTEP", gtep_config)
    write_results!(gtep_writer, gtep_builder, solution_info_to_dict(gtep_solution))
    
    # Generate GTEP plots
    gtep_plotter = HOPEPlotGenerator(gtep_output_path, "GTEP", gtep_config)
    generate_all_plots!(gtep_plotter, gtep_output_path)
    
    results.gtep_results = Dict(
        "solution_info" => solution_info_to_dict(gtep_solution),
        "investment_decisions" => investment_decisions
    )
    
    println("\n📋 Step 2: PCM Operational Model")
    
    # Load and solve PCM model with GTEP investments
    pcm_builder = HOPEModelBuilder()
    pcm_config = merge(config.pcm_config, Dict("model_mode" => "PCM"))
    
    # Load PCM data and incorporate GTEP results
    pcm_data = load_hope_data(gtep_reader)  # Reuse reader, will find PCM data
    pcm_data = incorporate_gtep_investments!(pcm_data, investment_decisions)
    
    # Initialize and build PCM model
    initialize!(pcm_builder, pcm_config, pcm_data, create_optimizer(solver_config))
    pcm_model = build_model!(pcm_builder)
    
    # Solve PCM
    pcm_solution = solve_workflow!(pcm_model, solver_config)
    
    # Write PCM results
    pcm_output_path = joinpath(output_path, "PCM_results")
    mkpath(pcm_output_path)
    pcm_writer = HOPEOutputWriter(pcm_output_path, "PCM", pcm_config)
    write_results!(pcm_writer, pcm_builder, solution_info_to_dict(pcm_solution))
    
    # Generate PCM plots
    pcm_plotter = HOPEPlotGenerator(pcm_output_path, "PCM", pcm_config)
    generate_all_plots!(pcm_plotter, pcm_output_path)
    
    results.pcm_results = Dict(
        "solution_info" => solution_info_to_dict(pcm_solution)
    )
    
    # Generate combined analysis
    generate_holistic_analysis!(results, output_path)
    
    results.convergence_achieved = true  # Sequential always "converges" in one iteration
end

"""
Run iterative GTEP↔PCM workflow
"""
function run_iterative_workflow!(
    case_path::String,
    output_path::String,
    config::HolisticConfig,
    solver_config::SolverConfig,
    results::HolisticResults
)
    println("\n🔄 Starting Iterative GTEP↔PCM Workflow")
    
    # Initialize data readers
    gtep_reader = HOPEDataReader(case_path)
    gtep_data = load_hope_data(gtep_reader)
    pcm_data = copy(gtep_data)  # Start with same data
    
    prev_investments = Dict()
    
    for iteration in 1:config.max_iterations
        println("\n📋 Iteration $iteration")
        
        # GTEP Step
        println("   Running GTEP...")
        gtep_builder = HOPEModelBuilder()
        gtep_config = merge(config.gtep_config, Dict("model_mode" => "GTEP"))
        
        # Use operational feedback to update GTEP (if available from previous PCM run)
        if !isempty(prev_investments) && haskey(results, :pcm_results)
            gtep_data = incorporate_operational_feedback!(gtep_data, results.pcm_results)
        end
        
        initialize!(gtep_builder, gtep_config, gtep_data, create_optimizer(solver_config))
        gtep_model = build_model!(gtep_builder)
        gtep_solution = solve_workflow!(gtep_model, solver_config)
        
        investment_decisions = extract_investment_decisions(gtep_builder)
        
        # PCM Step
        println("   Running PCM...")
        pcm_builder = HOPEModelBuilder()
        pcm_config = merge(config.pcm_config, Dict("model_mode" => "PCM"))
        
        pcm_data_updated = incorporate_gtep_investments!(copy(pcm_data), investment_decisions)
        
        initialize!(pcm_builder, pcm_config, pcm_data_updated, create_optimizer(solver_config))
        pcm_model = build_model!(pcm_builder)
        pcm_solution = solve_workflow!(pcm_model, solver_config)
        
        # Check convergence
        if !isempty(prev_investments)
            convergence_metrics = calculate_convergence_metrics(prev_investments, investment_decisions)
            
            iteration_result = Dict(
                "iteration" => iteration,
                "gtep_objective" => gtep_solution.objective_value,
                "pcm_objective" => pcm_solution.objective_value,
                "convergence_metrics" => convergence_metrics
            )
            
            push!(results.iterations, iteration_result)
            
            if convergence_metrics["max_change"] < config.convergence_tolerance
                println("✅ Convergence achieved after $iteration iterations")
                results.convergence_achieved = true
                break
            end
        end
        
        prev_investments = investment_decisions
        
        # Store latest results
        results.gtep_results = Dict(
            "solution_info" => solution_info_to_dict(gtep_solution),
            "investment_decisions" => investment_decisions
        )
        results.pcm_results = Dict(
            "solution_info" => solution_info_to_dict(pcm_solution)
        )
    end
    
    if !results.convergence_achieved
        println("⚠️  Maximum iterations reached without convergence")
    end
    
    # Write final results
    write_iterative_results!(results, output_path, config)
end

"""
Run integrated GTEP+PCM workflow (single model)
"""
function run_integrated_workflow!(
    case_path::String,
    output_path::String,
    config::HolisticConfig,
    solver_config::SolverConfig,
    results::HolisticResults
)
    println("\n📋 Running Integrated GTEP+PCM Model")
    
    # Load combined data
    reader = HOPEDataReader(case_path)
    combined_data = load_hope_data(reader)
    
    # Build integrated model
    builder = HOPEModelBuilder()
    integrated_config = merge(config.gtep_config, config.pcm_config, Dict("model_mode" => "HOLISTIC"))
    
    initialize!(builder, integrated_config, combined_data, create_optimizer(solver_config))
    integrated_model = build_model!(builder)
    
    # Solve integrated model
    solution = solve_workflow!(integrated_model, solver_config)
    
    # Extract both GTEP and PCM results from integrated solution
    investment_decisions = extract_investment_decisions(builder)
    operational_results = extract_operational_results(builder)
    
    # Write results
    integrated_output_path = joinpath(output_path, "integrated_results")
    mkpath(integrated_output_path)
    writer = HOPEOutputWriter(integrated_output_path, "HOLISTIC", integrated_config)
    write_results!(writer, builder, solution_info_to_dict(solution))
    
    # Generate plots
    plotter = HOPEPlotGenerator(integrated_output_path, "HOLISTIC", integrated_config)
    generate_all_plots!(plotter, integrated_output_path)
    
    results.gtep_results = Dict(
        "solution_info" => solution_info_to_dict(solution),
        "investment_decisions" => investment_decisions
    )
    results.pcm_results = Dict(
        "solution_info" => solution_info_to_dict(solution),
        "operational_results" => operational_results
    )
    
    results.convergence_achieved = true  # Integrated model is always "converged"
end

"""
Extract investment decisions from GTEP solution
"""
function extract_investment_decisions(builder::HOPEModelBuilder)::Dict
    model = builder.model
    input_data = builder.input_data
    decisions = Dict()
    
    # Generator investments
    if haskey(builder.variables, :x)
        gen_investments = Dict()
        for g in input_data["G_new"]
            inv_value = value(model[:x][g])
            if inv_value > 1e-6
                gen_investments[g] = inv_value
            end
        end
        decisions["generators"] = gen_investments
    end
    
    # Transmission investments
    if haskey(builder.variables, :y)
        line_investments = Dict()
        for l in input_data["L_new"]
            inv_value = value(model[:y][l])
            if inv_value > 1e-6
                line_investments[l] = inv_value
            end
        end
        decisions["transmission"] = line_investments
    end
    
    # Storage investments
    if haskey(builder.variables, :z)
        storage_investments = Dict()
        for s in input_data["S_new"]
            inv_value = value(model[:z][s])
            if inv_value > 1e-6
                storage_investments[s] = inv_value
            end
        end
        decisions["storage"] = storage_investments
    end
    
    return decisions
end

"""
Extract operational results from PCM solution
"""
function extract_operational_results(builder::HOPEModelBuilder)::Dict
    # Extract operational metrics like capacity factors, utilization rates, etc.
    results = Dict()
    
    # This would extract key operational metrics for feedback to GTEP
    # Implementation depends on specific requirements
    
    return results
end

"""
Incorporate GTEP investment decisions into PCM data
"""
function incorporate_gtep_investments!(pcm_data::Dict, investments::Dict)::Dict
    # Add invested generators to existing fleet
    if haskey(investments, "generators") && haskey(pcm_data, "Gendata_candidate")
        for (gen_id, investment_level) in investments["generators"]
            if investment_level > 1e-6
                # Add to existing generators with scaled capacity
                gen_data = copy(pcm_data["Gendata_candidate"][gen_id, :])
                gen_data[Symbol("Pmax (MW)")] *= investment_level
                
                # Add to main generation data
                if !haskey(pcm_data, "Gendata")
                    pcm_data["Gendata"] = DataFrame()
                end
                push!(pcm_data["Gendata"], gen_data, cols=:subset)
                push!(pcm_data["G"], gen_id)
            end
        end
    end
    
    # Similar for transmission and storage...
    
    return pcm_data
end

"""
Incorporate operational feedback into GTEP data
"""
function incorporate_operational_feedback!(gtep_data::Dict, pcm_results::Dict)::Dict
    # Use PCM operational results to update GTEP parameters
    # This could include updating capacity factors, availability, etc.
    
    return gtep_data
end

"""
Calculate convergence metrics between iterations
"""
function calculate_convergence_metrics(prev_investments::Dict, current_investments::Dict)::Dict
    metrics = Dict()
    
    # Calculate maximum change in investment decisions
    max_change = 0.0
    
    for category in ["generators", "transmission", "storage"]
        if haskey(prev_investments, category) && haskey(current_investments, category)
            prev_cat = prev_investments[category]
            curr_cat = current_investments[category]
            
            # Check all investment variables
            all_vars = union(keys(prev_cat), keys(curr_cat))
            for var in all_vars
                prev_val = get(prev_cat, var, 0.0)
                curr_val = get(curr_cat, var, 0.0)
                change = abs(curr_val - prev_val)
                max_change = max(max_change, change)
            end
        end
    end
    
    metrics["max_change"] = max_change
    
    return metrics
end

"""
Write results from iterative workflow
"""
function write_iterative_results!(results::HolisticResults, output_path::String, config::HolisticConfig)
    # Write convergence history
    if !isempty(results.iterations)
        conv_df = DataFrame(results.iterations)
        CSV.write(joinpath(output_path, "convergence_history.csv"), conv_df)
    end
    
    # Write final GTEP and PCM results in separate directories
    if results.gtep_results !== nothing
        gtep_output_path = joinpath(output_path, "final_GTEP")
        mkpath(gtep_output_path)
        # Write GTEP results...
    end
    
    if results.pcm_results !== nothing
        pcm_output_path = joinpath(output_path, "final_PCM")
        mkpath(pcm_output_path)
        # Write PCM results...
    end
end

"""
Generate holistic analysis combining GTEP and PCM results
"""
function generate_holistic_analysis!(results::HolisticResults, output_path::String)
    println("📊 Generating holistic analysis...")
    
    analysis_path = joinpath(output_path, "holistic_analysis")
    mkpath(analysis_path)
    
    # Create summary report
    summary_data = []
    
    if results.gtep_results !== nothing
        gtep_info = results.gtep_results["solution_info"]
        push!(summary_data, ("GTEP Objective Value", get(gtep_info, "objective_value", "N/A")))
        push!(summary_data, ("GTEP Solve Time", get(gtep_info, "solve_time", "N/A")))
        push!(summary_data, ("GTEP Status", get(gtep_info, "status", "N/A")))
    end
    
    if results.pcm_results !== nothing
        pcm_info = results.pcm_results["solution_info"]
        push!(summary_data, ("PCM Objective Value", get(pcm_info, "objective_value", "N/A")))
        push!(summary_data, ("PCM Solve Time", get(pcm_info, "solve_time", "N/A")))
        push!(summary_data, ("PCM Status", get(pcm_info, "status", "N/A")))
    end
    
    push!(summary_data, ("Total Workflow Time", results.total_solve_time))
    push!(summary_data, ("Convergence Achieved", results.convergence_achieved))
    
    summary_df = DataFrame(Metric = first.(summary_data), Value = last.(summary_data))
    CSV.write(joinpath(analysis_path, "holistic_summary.csv"), summary_df)
    
    println("✅ Holistic analysis completed")
end

# Export main functions and types
export HolisticConfig, HolisticResults
export run_holistic_workflow!
