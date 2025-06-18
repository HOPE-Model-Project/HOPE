"""
# Utils.jl - Utility Functions for HOPE
# 
# This module contains common utility functions used throughout the HOPE system.
"""

using DataFrames
using CSV
using YAML
using Dates

"""
Load configuration from YAML file with defaults
"""
function load_config_with_defaults(config_path::String)::Dict
    default_config = Dict(
        "model_mode" => "PCM",
        "solver" => "HiGHS",
        "time_limit" => 3600.0,
        "gap_tolerance" => 0.01,
        "threads" => 0,
        "unit_commitment" => 0,
        "flexible_demand" => false,
        "investment_binary" => true,
        "debug" => 0,
        "output_format" => "csv"
    )
    
    if !isfile(config_path)
        println("⚠️  Config file not found: $config_path, using defaults")
        return default_config
    end
    
    try
        file_config = YAML.load_file(config_path)
        return merge(default_config, file_config)
    catch e
        println("⚠️  Error loading config file: $e, using defaults")
        return default_config
    end
end

"""
Validate input data structure
"""
function validate_input_data(data::Dict)::Vector{String}
    issues = String[]
    
    # Check required keys
    required_keys = ["I", "W", "G", "H"]
    for key in required_keys
        if !haskey(data, key)
            push!(issues, "Missing required key: $key")
        end
    end
    
    # Check data consistency
    if haskey(data, "I") && haskey(data, "Loaddata")
        zones = data["I"]
        load_df = data["Loaddata"]
        
        for zone in zones
            if !hasproperty(load_df, Symbol(zone))
                push!(issues, "Load data missing for zone: $zone")
            end
        end
    end
    
    if haskey(data, "G") && haskey(data, "Gendata")
        generators = data["G"]
        gen_df = data["Gendata"]
        
        if nrow(gen_df) != length(generators)
            push!(issues, "Generator count mismatch: $(length(generators)) vs $(nrow(gen_df))")
        end
    end
    
    return issues
end

"""
Create standardized time indices for different model modes
"""
function create_time_indices(mode::String, year::Int=2035)::Dict
    if mode == "PCM"
        # Full year hourly
        hours = collect(1:8760)
        return Dict(
            "H" => hours,
            "type" => "hourly",
            "total_hours" => length(hours)
        )
        
    elseif mode == "GTEP"
        # Representative periods
        periods = [1, 2, 3, 4]  # 4 seasons
        hours_per_period = Dict(p => collect(1:24) for p in periods)
        period_weights = Dict(1 => 0.25, 2 => 0.25, 3 => 0.25, 4 => 0.25)
        
        return Dict(
            "T" => periods,
            "H_T" => hours_per_period,
            "period_weights" => period_weights,
            "type" => "representative"
        )
        
    else
        error("Unknown model mode: $mode")
    end
end

"""
Convert DataFrame to dictionary format for easy access
"""
function df_to_dict(df::DataFrame, key_col::Symbol)::Dict
    result = Dict()
    for row in eachrow(df)
        key = row[key_col]
        result[key] = Dict(n => row[n] for n in names(df) if n != key_col)
    end
    return result
end

"""
Aggregate hourly data to representative periods
"""
function aggregate_to_periods(hourly_data::Vector{Float64}, period_mapping::Dict)::Dict
    period_data = Dict()
    
    for (period, hours) in period_mapping
        period_values = []
        for hour in hours
            if hour <= length(hourly_data)
                push!(period_values, hourly_data[hour])
            end
        end
        period_data[period] = period_values
    end
    
    return period_data
end

"""
Format numbers for output display
"""
function format_number(x::Union{Float64, Nothing}; digits::Int=2)::String
    if x === nothing
        return "N/A"
    elseif abs(x) >= 1e9
        return "$(round(x/1e9, digits=digits))B"
    elseif abs(x) >= 1e6
        return "$(round(x/1e6, digits=digits))M"
    elseif abs(x) >= 1e3
        return "$(round(x/1e3, digits=digits))K"
    else
        return string(round(x, digits=digits))
    end
end

"""
Create summary statistics for model results
"""
function create_result_summary(model_results::Dict)::DataFrame
    summary_data = []
    
    # Extract key metrics
    if haskey(model_results, "objective_value")
        push!(summary_data, ("Objective Value", format_number(model_results["objective_value"])))
    end
    
    if haskey(model_results, "solve_time")
        push!(summary_data, ("Solve Time (s)", format_number(model_results["solve_time"])))
    end
    
    if haskey(model_results, "num_variables")
        push!(summary_data, ("Variables", format_number(model_results["num_variables"], digits=0)))
    end
    
    if haskey(model_results, "num_constraints")
        push!(summary_data, ("Constraints", format_number(model_results["num_constraints"], digits=0)))
    end
    
    return DataFrame(Metric = first.(summary_data), Value = last.(summary_data))
end

"""
Check file permissions and create directories if needed
"""
function ensure_output_path(path::String)::Bool
    try
        if !isdir(path)
            mkpath(path)
        end
        
        # Test write permission
        test_file = joinpath(path, "test_write.tmp")
        touch(test_file)
        rm(test_file)
        
        return true
    catch e
        println("⚠️  Cannot write to output path: $path - $e")
        return false
    end
end

"""
Log function with timestamp
"""
function log_message(message::String, level::String="INFO")
    timestamp = Dates.format(now(), "yyyy-mm-dd HH:MM:SS")
    println("[$timestamp][$level] $message")
end

"""
Performance timing utility
"""
mutable struct PerformanceTimer
    start_time::Float64
    checkpoints::Dict{String, Float64}
    
    function PerformanceTimer()
        new(time(), Dict{String, Float64}())
    end
end

function checkpoint!(timer::PerformanceTimer, name::String)
    timer.checkpoints[name] = time() - timer.start_time
    println("⏱️  Checkpoint '$name': $(round(timer.checkpoints[name], digits=2))s")
end

function total_time(timer::PerformanceTimer)::Float64
    return time() - timer.start_time
end

function get_timing_report(timer::PerformanceTimer)::DataFrame
    timing_data = []
    
    sorted_checkpoints = sort(collect(timer.checkpoints), by=x->x[2])
    
    prev_time = 0.0
    for (name, total_time) in sorted_checkpoints
        elapsed = total_time - prev_time
        push!(timing_data, (
            Checkpoint = name,
            Elapsed_Time = round(elapsed, digits=2),
            Total_Time = round(total_time, digits=2)
        ))
        prev_time = total_time
    end
    
    return DataFrame(timing_data)
end

"""
Memory usage tracking
"""
function get_memory_usage()::Dict
    gc_stats = Base.gc_num()
    return Dict(
        "total_bytes" => gc_stats.total_time,
        "allocd_bytes" => gc_stats.allocd,
        "freed_bytes" => gc_stats.freed
    )
end

"""
Model size analysis
"""
function analyze_model_size(model)::Dict
    stats = Dict(
        "variables" => num_variables(model),
        "constraints" => num_constraints(model; count_variable_in_set_constraints=false),
        "nonzeros" => 0  # Would need to compute constraint matrix
    )
    
    # Categorize variables
    binary_vars = 0
    integer_vars = 0
    continuous_vars = 0
    
    for var in all_variables(model)
        if is_binary(var)
            binary_vars += 1
        elseif is_integer(var)
            integer_vars += 1
        else
            continuous_vars += 1
        end
    end
    
    stats["binary_variables"] = binary_vars
    stats["integer_variables"] = integer_vars
    stats["continuous_variables"] = continuous_vars
    
    return stats
end

# Export all utility functions
export load_config_with_defaults, validate_input_data
export create_time_indices, df_to_dict, aggregate_to_periods
export format_number, create_result_summary
export ensure_output_path, log_message
export PerformanceTimer, checkpoint!, get_timing_report
export get_memory_usage, analyze_model_size
