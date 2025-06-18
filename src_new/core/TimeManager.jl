"""
# TimeManager.jl - Unified Time Index Management
# 
# This module provides consistent time index management across HOPE models,
# handling the differences between GTEP (representative days) and PCM (full year) time structures.
"""

using DataFrames
using Dates

# Time structure types
abstract type TimeStructure end

struct GTEPTimeStructure <: TimeStructure
    time_periods::Vector{Int}  # T: planning time periods (e.g., seasons)
    hours_per_period::Dict{Int, Vector{Int}}  # H_T: representative hours for each period
    days_per_period::Dict{Int, Int}  # Number of days each representative day represents
    period_weights::Dict{Int, Float64}  # Weight of each time period for scaling
end

struct PCMTimeStructure <: TimeStructure
    hours::Vector{Int}  # H: all hours in the year (1:8760)
    days::Vector{Int}   # Days (1:365)
    months::Vector{Int} # Months (1:12)
    hour_to_day::Dict{Int, Int}  # Mapping from hour to day
    hour_to_month::Dict{Int, Int}  # Mapping from hour to month
end

struct HolisticTimeStructure <: TimeStructure
    gtep_structure::GTEPTimeStructure
    pcm_structure::PCMTimeStructure
    gtep_to_pcm_mapping::Dict{Tuple{Int,Int}, Vector{Int}}  # Map (period, rep_hour) to actual hours
end

"""
Time index manager for coordinating different time structures
"""
mutable struct TimeManager
    current_structure::Union{TimeStructure, Nothing}
    gtep_structure::Union{GTEPTimeStructure, Nothing}
    pcm_structure::Union{PCMTimeStructure, Nothing}
    holistic_structure::Union{HolisticTimeStructure, Nothing}
    
    function TimeManager()
        new(nothing, nothing, nothing, nothing)
    end
end

"""
Create GTEP time structure from representative day clustering
"""
function create_gtep_time_structure(
    cluster_data::Dict,
    days_per_cluster::Dict{Int, Int}
)::GTEPTimeStructure
    
    time_periods = sort(collect(keys(cluster_data)))
    hours_per_period = Dict{Int, Vector{Int}}()
    period_weights = Dict{Int, Float64}()
    
    total_days = sum(values(days_per_cluster))
    
    for t in time_periods
        # Each representative day has 24 hours
        hours_per_period[t] = collect(1:24)
        
        # Weight is proportional to number of days represented
        period_weights[t] = days_per_cluster[t] / total_days
    end
    
    return GTEPTimeStructure(
        time_periods,
        hours_per_period,
        days_per_cluster,
        period_weights
    )
end

"""
Create PCM time structure for full year simulation
"""
function create_pcm_time_structure(year::Int = 2035)::PCMTimeStructure
    hours = collect(1:8760)
    days = collect(1:365)
    months = collect(1:12)
    
    # Create hour-to-day and hour-to-month mappings
    hour_to_day = Dict{Int, Int}()
    hour_to_month = Dict{Int, Int}()
    
    days_in_month = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    if isleapyear(year)
        days_in_month[2] = 29
    end
    
    current_day = 1
    current_month = 1
    days_passed_in_month = 0
    
    for hour in hours
        hour_to_day[hour] = current_day
        hour_to_month[hour] = current_month
        
        # Advance to next hour
        if hour % 24 == 0  # End of day
            current_day += 1
            days_passed_in_month += 1
            
            # Check if month ended
            if days_passed_in_month >= days_in_month[current_month]
                current_month += 1
                days_passed_in_month = 0
            end
        end
    end
    
    return PCMTimeStructure(
        hours,
        days,
        months,
        hour_to_day,
        hour_to_month
    )
end

"""
Create holistic time structure that maps between GTEP and PCM
"""
function create_holistic_time_structure(
    gtep_structure::GTEPTimeStructure,
    pcm_structure::PCMTimeStructure,
    cluster_mapping::Dict  # Maps actual days to representative periods
)::HolisticTimeStructure
    
    # Create mapping from (period, rep_hour) to actual hours
    gtep_to_pcm_mapping = Dict{Tuple{Int,Int}, Vector{Int}}()
    
    for (period, rep_hours) in gtep_structure.hours_per_period
        for rep_hour in rep_hours
            actual_hours = Int[]
            
            # Find all actual days that belong to this representative period
            for (day, rep_period) in cluster_mapping
                if rep_period == period
                    # Add corresponding hour from this day
                    actual_hour = (day - 1) * 24 + rep_hour
                    if actual_hour <= 8760
                        push!(actual_hours, actual_hour)
                    end
                end
            end
            
            gtep_to_pcm_mapping[(period, rep_hour)] = actual_hours
        end
    end
    
    return HolisticTimeStructure(
        gtep_structure,
        pcm_structure,
        gtep_to_pcm_mapping
    )
end

"""
Set the active time structure for the manager
"""
function set_time_structure!(manager::TimeManager, structure::TimeStructure)
    manager.current_structure = structure
    
    if isa(structure, GTEPTimeStructure)
        manager.gtep_structure = structure
    elseif isa(structure, PCMTimeStructure)
        manager.pcm_structure = structure
    elseif isa(structure, HolisticTimeStructure)
        manager.holistic_structure = structure
        manager.gtep_structure = structure.gtep_structure
        manager.pcm_structure = structure.pcm_structure
    end
end

"""
Get time indices for model variables based on current structure
"""
function get_time_indices(manager::TimeManager)
    if manager.current_structure === nothing
        throw(ArgumentError("No time structure set"))
    end
    
    structure = manager.current_structure
    
    if isa(structure, GTEPTimeStructure)
        return (
            T = structure.time_periods,
            H_T = structure.hours_per_period,
            period_weights = structure.period_weights
        )
    elseif isa(structure, PCMTimeStructure)
        return (
            H = structure.hours,
            D = structure.days,
            M = structure.months,
            hour_to_day = structure.hour_to_day,
            hour_to_month = structure.hour_to_month
        )
    elseif isa(structure, HolisticTimeStructure)
        return (
            T = structure.gtep_structure.time_periods,
            H_T = structure.gtep_structure.hours_per_period,
            H = structure.pcm_structure.hours,
            gtep_to_pcm = structure.gtep_to_pcm_mapping,
            period_weights = structure.gtep_structure.period_weights
        )
    end
end

"""
Scale GTEP results to annual values using time weights
"""
function scale_to_annual(
    manager::TimeManager,
    gtep_values::Dict,  # Values indexed by (period, hour)
    variable_type::Symbol  # :energy, :capacity, :cost, etc.
)::Dict
    
    if manager.gtep_structure === nothing
        throw(ArgumentError("No GTEP time structure available"))
    end
    
    structure = manager.gtep_structure
    annual_values = Dict()
    
    for (key, value) in gtep_values
        if isa(key, Tuple) && length(key) >= 2
            period = key[1]
            
            # Scale based on period weight and days represented
            if variable_type == :energy
                # Energy values scaled by number of days and hours
                scale_factor = structure.days_per_period[period] * 365 / sum(values(structure.days_per_period))
            elseif variable_type == :capacity
                # Capacity values don't need temporal scaling
                scale_factor = 1.0
            elseif variable_type == :cost
                # Costs scaled by period weight
                scale_factor = structure.period_weights[period] * 365
            else
                # Default scaling
                scale_factor = structure.period_weights[period]
            end
            
            annual_values[key] = value * scale_factor
        else
            annual_values[key] = value
        end
    end
    
    return annual_values
end

"""
Map GTEP representative results to PCM hourly values
"""
function map_gtep_to_pcm(
    manager::TimeManager,
    gtep_values::Dict,  # GTEP results indexed by (period, rep_hour, ...)
    fill_method::Symbol = :repeat  # :repeat, :interpolate, :zero
)::Dict
    
    if manager.holistic_structure === nothing
        throw(ArgumentError("No holistic time structure available"))
    end
    
    structure = manager.holistic_structure
    pcm_values = Dict()
    
    for (gtep_key, gtep_value) in gtep_values
        if isa(gtep_key, Tuple) && length(gtep_key) >= 2
            period = gtep_key[1]
            rep_hour = gtep_key[2]
            other_indices = gtep_key[3:end]
            
            # Get corresponding actual hours
            actual_hours = get(structure.gtep_to_pcm_mapping, (period, rep_hour), Int[])
            
            # Map to PCM structure
            for actual_hour in actual_hours
                pcm_key = tuple(actual_hour, other_indices...)
                
                if fill_method == :repeat
                    pcm_values[pcm_key] = gtep_value
                elseif fill_method == :zero
                    pcm_values[pcm_key] = 0.0
                # Additional interpolation methods can be added here
                end
            end
        end
    end
    
    return pcm_values
end

"""
Create time series DataFrame with proper time indexing
"""
function create_time_series_df(
    manager::TimeManager,
    data::Dict,
    column_name::String = "value"
)::DataFrame
    
    if manager.current_structure === nothing
        throw(ArgumentError("No time structure set"))
    end
    
    structure = manager.current_structure
    
    if isa(structure, PCMTimeStructure)
        # Create DataFrame with hourly timestamps
        df = DataFrame()
        hours = Int[]
        values = Float64[]
        
        for hour in structure.hours
            if haskey(data, hour)
                push!(hours, hour)
                push!(values, data[hour])
            end
        end
        
        df.Hour = hours
        df[!, Symbol(column_name)] = values
        
        # Add date information
        df.Day = [structure.hour_to_day[h] for h in df.Hour]
        df.Month = [structure.hour_to_month[h] for h in df.Hour]
        
        return df
        
    elseif isa(structure, GTEPTimeStructure)
        # Create DataFrame with period and representative hour structure
        df = DataFrame()
        periods = Int[]
        rep_hours = Int[]
        values = Float64[]
        weights = Float64[]
        
        for (key, value) in data
            if isa(key, Tuple) && length(key) >= 2
                push!(periods, key[1])
                push!(rep_hours, key[2])
                push!(values, value)
                push!(weights, structure.period_weights[key[1]])
            end
        end
        
        df.Period = periods
        df.RepHour = rep_hours
        df[!, Symbol(column_name)] = values
        df.Weight = weights
        
        return df
    end
    
    return DataFrame()
end

"""
Get time summary information
"""
function get_time_summary(manager::TimeManager)::Dict
    if manager.current_structure === nothing
        return Dict("status" => "No time structure set")
    end
    
    structure = manager.current_structure
    
    if isa(structure, GTEPTimeStructure)
        return Dict(
            "type" => "GTEP",
            "num_periods" => length(structure.time_periods),
            "total_rep_hours" => sum(length(hours) for hours in values(structure.hours_per_period)),
            "total_days_represented" => sum(values(structure.days_per_period)),
            "periods" => structure.time_periods
        )
    elseif isa(structure, PCMTimeStructure)
        return Dict(
            "type" => "PCM",
            "total_hours" => length(structure.hours),
            "total_days" => length(structure.days),
            "total_months" => length(structure.months)
        )
    elseif isa(structure, HolisticTimeStructure)
        return Dict(
            "type" => "Holistic",
            "gtep_periods" => length(structure.gtep_structure.time_periods),
            "pcm_hours" => length(structure.pcm_structure.hours),
            "mapping_size" => length(structure.gtep_to_pcm_mapping)
        )
    end
end

# Export main types and functions
export TimeStructure, GTEPTimeStructure, PCMTimeStructure, HolisticTimeStructure
export TimeManager
export create_gtep_time_structure, create_pcm_time_structure, create_holistic_time_structure
export set_time_structure!, get_time_indices, scale_to_annual, map_gtep_to_pcm
export create_time_series_df, get_time_summary
