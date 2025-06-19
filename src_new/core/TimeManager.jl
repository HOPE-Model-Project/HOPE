"""
# TimeManager.jl - Simplified Time Index Management for HOPE
# 
# This module provides simplified time index management that works with preprocessed data.
# The preprocessing module handles time clustering, and this manager provides access to time indices.
"""

module TimeManager

using DataFrames
using Dates

"""
Unified time structure that handles both clustered and full resolution time indices
"""
struct UnifiedTimeStructure
    hours::Vector{Int}                      # Universal hour index (H)
    time_periods::Vector{Int}               # Time periods (T)
    hours_per_period::Dict{Int, Vector{Int}} # Hours per period mapping (H_T)
    period_weights::Dict{Int, Float64}      # Weights for scaling
    days_per_period::Dict{Int, Int}         # Days represented by each period
    is_clustered::Bool                      # Whether using time clustering
    cluster_mapping::Dict{Int, Int}         # Day to period mapping
    representative_data::Dict               # Representative time series data
    hour_to_day::Dict{Int, Int}            # Hour to day mapping
    hour_to_month::Dict{Int, Int}          # Hour to month mapping
    model_mode::String                      # GTEP or PCM
end

"""
Create unified time structure from configuration and input data
"""
function create_unified_time_structure(config::Dict, input_data::Dict=Dict())::UnifiedTimeStructure
    # Default to full resolution (8760 hours)
    hours = collect(1:8760)
    time_periods = [1]
    hours_per_period = Dict(1 => hours)
    period_weights = Dict(1 => 1.0)
    days_per_period = Dict(1 => 365)
    is_clustered = false
    cluster_mapping = Dict{Int, Int}()
    representative_data = Dict()
    
    # Create basic calendar mappings
    hour_to_day = Dict(h => div(h-1, 24) + 1 for h in 1:8760)
    hour_to_month = Dict{Int, Int}()
    
    # Simple month assignment (30-day months for simplicity)
    for h in 1:8760
        day = hour_to_day[h]
        month = min(12, div(day-1, 30) + 1)
        hour_to_month[h] = month
    end
    
    model_mode = get(config, "model_mode", "PCM")
    
    # Check if clustering is enabled
    if get(config, "representative_day!", 0) == 1 && haskey(config, "time_periods")
        is_clustered = true
        time_periods_config = config["time_periods"]
        
        # Create clustered structure based on time_periods configuration
        time_periods = collect(keys(time_periods_config))
        hours_per_period = Dict{Int, Vector{Int}}()
        period_weights = Dict{Int, Float64}()
        days_per_period = Dict{Int, Int}()
        
        # Simple clustering: assign 24 hours per period
        for (period, period_def) in time_periods_config
            hours_per_period[period] = collect(1:24)  # Representative day hours
            period_weights[period] = 0.25  # Equal weight for 4 periods
            days_per_period[period] = 91   # ~3 months per period
        end
        
        println("   ✓ Created clustered time structure with $(length(time_periods)) periods")
    else
        println("   ✓ Created full resolution time structure")
    end
    
    return UnifiedTimeStructure(
        hours, time_periods, hours_per_period, period_weights, days_per_period,
        is_clustered, cluster_mapping, representative_data,
        hour_to_day, hour_to_month, model_mode
    )
end

"""
Simplified time index manager that works with preprocessed data
"""
mutable struct HOPETimeManager
    input_data::Dict  # Preprocessed data containing time indices
    current_structure::Union{UnifiedTimeStructure, Nothing}  # Current time structure
    
    function HOPETimeManager()
        new(Dict(), nothing)
    end
end

"""
Initialize time manager with preprocessed data
"""
function initialize_time_manager!(manager::HOPETimeManager, preprocessed_data::Dict)
    manager.input_data = preprocessed_data
end

"""
Get time indices from preprocessed data
"""
function get_time_indices(manager::HOPETimeManager)
    data = manager.input_data
    
    # Ensure required indices exist
    if !haskey(data, "H") || !haskey(data, "T") || !haskey(data, "H_T")
        error("Preprocessed data missing required time indices (H, T, H_T)")
    end
    
    return (
        H = data["H"],  # Universal hour index (1:8760)
        T = data["T"],  # Time periods
        H_T = data["H_T"],  # Hours per period mapping
        period_weights = get(data, "period_weights", Dict(1 => 1.0)),
        hour_to_day = get(data, "hour_to_day", Dict()),
        hour_to_month = get(data, "hour_to_month", Dict()),
        is_clustered = length(data["T"]) > 1 && haskey(data, "representative_data")
    )
end

"""
Check if using clustered time structure
"""
function is_clustered(manager::HOPETimeManager)::Bool
    data = manager.input_data
    return length(get(data, "T", [1])) > 1 && haskey(data, "representative_data")
end

"""
Get representative data for time series (if available)
"""
function get_representative_data(manager::HOPETimeManager, data_type::String="Loaddata")
    data = manager.input_data
    
    if haskey(data, "representative_data")
        rep_data = data["representative_data"]
        
        # Map data_type to the expected key in representative_data
        data_key = lowercase(replace(data_type, "data" => ""))  # "Loaddata" -> "load"
        
        if haskey(rep_data, data_key)
            return rep_data[data_key]
        end
    end
    
    return nothing
end

"""
Scale clustered results to annual values
"""
function scale_to_annual(manager::HOPETimeManager, clustered_values::Dict, variable_type::Symbol=:energy)
    data = manager.input_data
    
    if !is_clustered(manager)
        return clustered_values  # No scaling needed for full resolution
    end
    
    if !haskey(data, "period_weights") || !haskey(data, "days_per_period")
        @warn "Missing period weights or days_per_period for scaling"
        return clustered_values
    end
    
    period_weights = data["period_weights"]
    days_per_period = data["days_per_period"]
    annual_values = Dict()
    
    for (key, value) in clustered_values
        if isa(key, Tuple) && length(key) >= 1
            period = key[1]
            
            if haskey(period_weights, period) && haskey(days_per_period, period)
                if variable_type == :energy
                    # Scale energy by number of days represented
                    scale_factor = days_per_period[period]
                elseif variable_type == :cost
                    # Scale costs by period weight and annualize
                    scale_factor = period_weights[period] * 365
                else
                    # Default scaling by period weight
                    scale_factor = period_weights[period]
                end
                
                annual_values[key] = value * scale_factor
            else
                annual_values[key] = value
            end
        else
            annual_values[key] = value
        end
    end
    
    return annual_values
end

"""
Get effective time indices for model building
Returns appropriate time structure based on whether clustering is used
"""
function get_effective_time_structure(manager::HOPETimeManager)
    time_indices = get_time_indices(manager)
    
    if time_indices.is_clustered
        # For clustered models, return period-hour combinations
        effective_hours = []
        for t in time_indices.T
            for h in time_indices.H_T[t]
                push!(effective_hours, (t, h))
            end
        end
        return (
            time_type = :clustered,
            T = time_indices.T,
            H_T = time_indices.H_T,
            effective_hours = effective_hours,
            period_weights = time_indices.period_weights
        )
    else
        # For full resolution models, return all hours
        return (
            time_type = :full,
            H = time_indices.H,
            T = time_indices.T,  # [1]
            H_T = time_indices.H_T,  # {1 => 1:8760}
            effective_hours = time_indices.H
        )
    end
end

"""
Get time summary for reporting
"""
function get_time_summary(manager::HOPETimeManager)
    if isempty(manager.input_data)
        return Dict("status" => "No data loaded")
    end
    
    time_indices = get_time_indices(manager)
    
    summary = Dict(
        "total_hours_available" => length(time_indices.H),
        "time_periods" => length(time_indices.T),
        "is_clustered" => time_indices.is_clustered
    )
    
    if time_indices.is_clustered
        total_rep_hours = sum(length(hours) for hours in values(time_indices.H_T))
        summary["representative_hours"] = total_rep_hours
        summary["periods"] = time_indices.T
        
        if haskey(manager.input_data, "days_per_period")
            total_days = sum(values(manager.input_data["days_per_period"]))
            summary["total_days_represented"] = total_days
        end
    else
        summary["mode"] = "full_resolution"
    end
    
    return summary
end

# Export main functions
export TimeManager, initialize_time_manager!, get_time_indices
export is_clustered, get_representative_data, scale_to_annual
export get_effective_time_structure, get_time_summary

"""
Set the active time structure for the manager
"""
function set_time_structure!(manager::HOPETimeManager, structure::UnifiedTimeStructure)
    manager.current_structure = structure
end

"""
Setup time structure based on model mode and configuration
Enhanced to support unified time indexing with flexible clustering
"""
function setup_time_structure!(manager::HOPETimeManager, input_data::Dict, config::Dict)
    println("⏰ Setting up unified time structure...")
    
    # Create unified time structure
    time_structure = create_unified_time_structure(config, input_data)
    set_time_structure!(manager, time_structure)
    
    # Add time indices to input data based on structure
    if time_structure.is_clustered
        # Clustered mode: both T and H_T available
        input_data["T"] = time_structure.time_periods
        input_data["H_T"] = time_structure.hours_per_period
        input_data["H"] = time_structure.hours  # Full hour set still available
        input_data["period_weights"] = time_structure.period_weights
        input_data["days_per_period"] = time_structure.days_per_period
        
        total_rep_hours = sum(length(hours) for hours in values(time_structure.hours_per_period))
        println("✅ Clustered time structure: $(length(time_structure.time_periods)) periods, $total_rep_hours representative hours")
    else
        # Full resolution mode: single period with all hours
        input_data["H"] = time_structure.hours
        input_data["T"] = time_structure.time_periods  # [1]
        input_data["H_T"] = time_structure.hours_per_period  # {1 => 1:8760}
        
        println("✅ Full resolution time structure: $(length(time_structure.hours)) hours")
    end
    
    # Add calendar mappings for both modes
    input_data["hour_to_day"] = time_structure.hour_to_day
    input_data["hour_to_month"] = time_structure.hour_to_month
    
    # Store representative data if available
    if !isempty(time_structure.representative_data)
        input_data["representative_data"] = time_structure.representative_data
    end
    
    println("📊 Model mode: $(time_structure.model_mode)")
    println("🔄 Clustering: $(time_structure.is_clustered ? "enabled" : "disabled")")
end

"""
Get time indices for model variables based on current structure
"""
function get_time_indices(manager::HOPETimeManager)
    if manager.current_structure === nothing
        throw(ArgumentError("No time structure set"))
    end
    
    structure = manager.current_structure
    
    return (
        H = structure.hours,  # Universal hour index
        T = structure.time_periods,  # Time periods
        H_T = structure.hours_per_period,  # Hours per period
        period_weights = structure.period_weights,  # Period weights
        is_clustered = structure.is_clustered,  # Clustering flag
        hour_to_day = structure.hour_to_day,  # Calendar mappings
        hour_to_month = structure.hour_to_month,
        model_mode = structure.model_mode
    )
end

"""
Scale clustered results to annual values using time weights
"""
function scale_to_annual(
    manager::HOPETimeManager,
    clustered_values::Dict,  # Values indexed by (period, hour) or similar
    variable_type::Symbol  # :energy, :capacity, :cost, etc.
)::Dict
    
    if manager.current_structure === nothing
        throw(ArgumentError("No time structure available"))
    end
    
    structure = manager.current_structure
    
    if !structure.is_clustered
        # No scaling needed for full resolution
        return clustered_values
    end
    
    annual_values = Dict()
    
    for (key, value) in clustered_values
        if isa(key, Tuple) && length(key) >= 2
            period = key[1]
            if haskey(structure.period_weights, period)
                weight = structure.period_weights[period]
                
                if variable_type == :energy
                    # Scale energy by number of days represented
                    annual_values[key] = value * structure.days_per_period[period]
                elseif variable_type == :cost
                    # Scale costs by period weight
                    annual_values[key] = value * weight * 365
                else
                    # Default scaling by period weight
                    annual_values[key] = value * weight
                end
            else
                annual_values[key] = value
            end
        else
            annual_values[key] = value
        end
    end
    
    return annual_values
end

"""
Map representative hours to actual hours (for output expansion)
"""
function map_representative_to_actual(
    manager::HOPETimeManager,
    representative_values::Dict  # Values indexed by (period, rep_hour)
)::Dict
    
    if manager.current_structure === nothing || !manager.current_structure.is_clustered
        return representative_values
    end
    
    structure = manager.current_structure
    actual_values = Dict()
    
    for ((period, rep_hour), value) in representative_values
        if haskey(structure.cluster_mapping, period)
            # Find all actual days that belong to this period
            actual_days = [day for (day, mapped_period) in structure.cluster_mapping if mapped_period == period]
            
            for day in actual_days
                actual_hour = (day - 1) * 24 + rep_hour
                if actual_hour <= 8760
                    actual_values[actual_hour] = value
                end
            end
        end
    end
    
    return actual_values
end

"""
Create time structure mapping for holistic models
"""
function create_holistic_mapping(
    gtep_structure::UnifiedTimeStructure,
    pcm_structure::UnifiedTimeStructure
)::Dict
    
    mapping = Dict()
    
    if gtep_structure.is_clustered && !pcm_structure.is_clustered
        # Map GTEP periods to PCM hours
        for (period, rep_hours) in gtep_structure.hours_per_period
            for rep_hour in rep_hours
                # Find corresponding actual hours in PCM
                actual_hours = Int[]
                
                for (day, mapped_period) in gtep_structure.cluster_mapping
                    if mapped_period == period
                        actual_hour = (day - 1) * 24 + rep_hour
                        if actual_hour <= 8760
                            push!(actual_hours, actual_hour)
                        end
                    end
                end
                
                mapping[(period, rep_hour)] = actual_hours
            end
        end
    end
    
    return mapping
end

"""
Utility function to get effective hours for model building
For clustered models: returns representative hours
For full models: returns all hours
"""
function get_effective_hours(manager::HOPETimeManager)
    if manager.current_structure === nothing
        throw(ArgumentError("No time structure set"))
    end
    
    structure = manager.current_structure
    
    if structure.is_clustered
        # Return all representative hours across all periods
        all_rep_hours = []
        for (period, hours) in structure.hours_per_period
            for hour in hours
                push!(all_rep_hours, (period, hour))
            end
        end
        return all_rep_hours
    else
        # Return all actual hours
        return structure.hours
    end
end

"""
Legacy compatibility function - create GTEP time structure from config
Maintained for backward compatibility but uses new unified structure
"""
function create_gtep_time_structure_from_config(time_periods_config::Dict)
    println("⚠️  Using legacy GTEP time structure function. Consider using create_unified_time_structure instead.")
    
    config = Dict(
        "model_mode" => "GTEP",
        "representative_day!" => 1,
        "time_periods" => time_periods_config
    )
      return create_unified_time_structure(config)
end

# Export main types and functions
export UnifiedTimeStructure, HOPETimeManager
export create_unified_time_structure, set_time_structure!, get_time_indices
export setup_time_structure!, get_effective_hours

end # module TimeManager
