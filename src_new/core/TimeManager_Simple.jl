"""
# TimeManager.jl - Simplified Time Index Management for Preprocessed Data
# 
# This module provides time index management for HOPE models using preprocessed data.
# The heavy lifting (clustering, representative day extraction) is done by DataPreprocessor.
# This module focuses on creating the right time indices for model building.
"""

using DataFrames

"""
Simplified time structure for preprocessed data
"""
struct TimeStructure
    # Universal time indices (always available)
    hours::Vector{Int}              # H: Universal hour index (1:8760)
    
    # Time period structure (for clustered models)
    time_periods::Vector{Int}       # T: Time periods/clusters
    hours_per_period::Dict{Int, Vector{Int}}  # H_T: Representative hours per period
    
    # Scaling and mapping information
    period_weights::Dict{Int, Float64}        # Period weights for scaling
    is_clustered::Bool                        # Whether data is clustered
    
    # Model compatibility
    model_mode::String                        # "PCM", "GTEP", "HOLISTIC"
end

"""
Simple time manager for preprocessed data
"""
mutable struct TimeManager
    current_structure::Union{TimeStructure, Nothing}
    
    function TimeManager()
        new(nothing)
    end
end

"""
Create time structure from preprocessed data
"""
function create_time_structure_from_preprocessed(processed_data::Dict)::TimeStructure
    # Extract time structure information from preprocessed data
    if haskey(processed_data, "time_structure") && processed_data["time_structure"]["is_clustered"]
        # Clustered time structure
        ts_info = processed_data["time_structure"]
        
        return TimeStructure(
            collect(1:8760),  # Full hour set always available
            ts_info["time_periods"],
            ts_info["hours_per_period"], 
            ts_info["period_weights"],
            true,
            get(processed_data["preprocessing_metadata"]["config"], "target_model_mode", "GTEP")
        )
    else
        # Full resolution time structure
        hours = get(processed_data, "H", collect(1:8760))
        
        return TimeStructure(
            hours,
            [1],  # Single time period
            Dict(1 => hours),
            Dict(1 => 1.0),
            false,
            get(processed_data.get("preprocessing_metadata", Dict()).get("config", Dict()), "target_model_mode", "PCM")
        )
    end
end

"""
Setup time structure from preprocessed data
"""
function setup_time_structure!(manager::TimeManager, processed_data::Dict)
    println("⏰ Setting up time structure from preprocessed data...")
    
    # Create time structure
    time_structure = create_time_structure_from_preprocessed(processed_data)
    manager.current_structure = time_structure
    
    # Ensure time indices are available in processed data
    if !haskey(processed_data, "H")
        processed_data["H"] = time_structure.hours
    end
    
    if !haskey(processed_data, "T")
        processed_data["T"] = time_structure.time_periods
    end
    
    if !haskey(processed_data, "H_T")
        processed_data["H_T"] = time_structure.hours_per_period
    end
    
    # Add period weights for scaling
    processed_data["period_weights"] = time_structure.period_weights
    
    if time_structure.is_clustered
        total_periods = length(time_structure.time_periods)
        total_rep_hours = sum(length(hours) for hours in values(time_structure.hours_per_period))
        println("✅ Clustered time structure: $total_periods periods, $total_rep_hours representative hours")
    else
        println("✅ Full resolution time structure: $(length(time_structure.hours)) hours")
    end
    
    println("📊 Model mode: $(time_structure.model_mode)")
end

"""
Get time indices for model building
"""
function get_time_indices(manager::TimeManager)
    if manager.current_structure === nothing
        throw(ArgumentError("No time structure set"))
    end
    
    structure = manager.current_structure
    
    return (
        H = structure.hours,                    # Universal hour index
        T = structure.time_periods,             # Time periods  
        H_T = structure.hours_per_period,       # Hours per period
        period_weights = structure.period_weights,  # Scaling weights
        is_clustered = structure.is_clustered,      # Clustering flag
        model_mode = structure.model_mode           # Model compatibility
    )
end

"""
Get effective time indices for model variables
For clustered models: returns (period, hour) tuples
For full models: returns hour indices
"""
function get_effective_time_indices(manager::TimeManager)
    if manager.current_structure === nothing
        throw(ArgumentError("No time structure set"))
    end
    
    structure = manager.current_structure
    
    if structure.is_clustered
        # Return (period, hour) tuples for clustered models
        indices = []
        for (period, hours) in structure.hours_per_period
            for hour in hours
                push!(indices, (period, hour))
            end
        end
        return indices
    else
        # Return simple hour indices for full resolution
        return structure.hours
    end
end

"""
Scale clustered results to annual values
"""
function scale_to_annual(
    manager::TimeManager, 
    values::Dict, 
    variable_type::Symbol = :energy
)::Dict
    
    if manager.current_structure === nothing || !manager.current_structure.is_clustered
        return values  # No scaling needed for full resolution
    end
    
    structure = manager.current_structure
    scaled_values = Dict()
    
    for (key, value) in values
        if isa(key, Tuple) && length(key) >= 2
            period = key[1]
            weight = get(structure.period_weights, period, 1.0)
            
            # Scale based on variable type
            if variable_type == :energy
                # Energy scaled by weight and 365 days
                scaled_values[key] = value * weight * 365
            elseif variable_type == :cost
                # Costs scaled by weight and annual factor
                scaled_values[key] = value * weight * 365
            elseif variable_type == :capacity
                # Capacity typically not scaled temporally
                scaled_values[key] = value
            else
                # Default scaling
                scaled_values[key] = value * weight
            end
        else
            scaled_values[key] = value
        end
    end
    
    return scaled_values
end

"""
Create simple summary of time structure
"""
function get_time_summary(manager::TimeManager)::Dict
    if manager.current_structure === nothing
        return Dict("status" => "No time structure set")
    end
    
    structure = manager.current_structure
    
    summary = Dict(
        "model_mode" => structure.model_mode,
        "is_clustered" => structure.is_clustered,
        "total_hours" => length(structure.hours),
        "num_periods" => length(structure.time_periods)
    )
    
    if structure.is_clustered
        summary["representative_hours"] = sum(length(hours) for hours in values(structure.hours_per_period))
        summary["period_weights"] = structure.period_weights
    end
    
    return summary
end

# Export functions
export TimeStructure, TimeManager
export create_time_structure_from_preprocessed, setup_time_structure!
export get_time_indices, get_effective_time_indices
export scale_to_annual, get_time_summary
