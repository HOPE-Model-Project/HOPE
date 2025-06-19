"""
# DataPreprocessor.jl - Integrated Data Preprocessing Module
# 
# This module handles time clustering and generator aggregation as an integral part
# of the HOPE model workflow, controlled by preprocessing settings.
"""

module DataPreprocessor

using DataFrames
using Clustering
using Statistics

"""
Data preprocessing configuration structure
"""
struct PreprocessingConfig
    # Time clustering settings
    enable_time_clustering::Bool
    time_periods::Dict{Int, Tuple{Int,Int,Int,Int}}  # period => (start_month, start_day, end_month, end_day)
    clustering_method::String  # "kmeans", "representative_day"
    num_clusters::Int
    
    # Generator aggregation settings
    enable_gen_aggregation::Bool
    aggregation_method::String  # "by_zone_type", "by_technology", "none"
    unit_commitment_mode::Bool
    
    # Data processing settings
    model_mode::String  # "PCM", "GTEP"
    data_validation::Bool
    fill_missing_data::Bool
    
    function PreprocessingConfig(config_dict::Dict)
        new(
            get(config_dict, "enable_time_clustering", false),
            get(config_dict, "time_periods", Dict{Int, Tuple{Int,Int,Int,Int}}()),
            get(config_dict, "clustering_method", "representative_day"),
            get(config_dict, "num_clusters", 1),
            get(config_dict, "enable_gen_aggregation", false),
            get(config_dict, "aggregation_method", "by_zone_type"),
            get(config_dict, "unit_commitment_mode", false),
            get(config_dict, "model_mode", "PCM"),
            get(config_dict, "data_validation", true),
            get(config_dict, "fill_missing_data", true)
        )
    end
end

"""
Main data preprocessor
"""
mutable struct HOPEDataPreprocessor
    config::PreprocessingConfig
    original_data::Dict{String, Any}
    processed_data::Dict{String, Any}
    preprocessing_report::Dict{String, Any}
    
    function HOPEDataPreprocessor(config::PreprocessingConfig)
        new(config, Dict(), Dict(), Dict())
    end
end

"""
Create preprocessing config from HOPE model settings
"""
function create_preprocessing_config_from_hope_settings(hope_config::Dict)::PreprocessingConfig
    # Map HOPE settings to preprocessing config
    # Debug: show the time_periods value
    time_periods_raw = get(hope_config, "time_periods", Dict())
    println("   🔍 Raw time_periods: $(typeof(time_periods_raw)) = $time_periods_raw")
    
    # Convert time_periods to the expected format if needed
    time_periods_converted = Dict{Int, Tuple{Int,Int,Int,Int}}()
    if isa(time_periods_raw, Dict)
        for (k, v) in time_periods_raw
            period_key = isa(k, Int) ? k : parse(Int, string(k))
            if isa(v, String)
                # Parse string like "(12, 21, 3, 19)" to tuple
                v_cleaned = replace(replace(v, "(" => ""), ")" => "")
                values = [parse(Int, strip(x)) for x in split(v_cleaned, ",")]
                if length(values) == 4
                    time_periods_converted[period_key] = (values[1], values[2], values[3], values[4])
                else
                    @warn "Invalid time period format: $v"
                end
            elseif isa(v, Tuple) && length(v) == 4
                time_periods_converted[period_key] = v
            elseif isa(v, Vector) && length(v) == 4
                time_periods_converted[period_key] = (v[1], v[2], v[3], v[4])
            else
                @warn "Unsupported time period format: $(typeof(v)) = $v"
            end
        end
    end
    
    preprocessing_dict = Dict(
        "enable_time_clustering" => get(hope_config, "representative_day!", 0) == 1,
        "time_periods" => time_periods_converted,
        "clustering_method" => "representative_day",
        "num_clusters" => 1,
        "enable_gen_aggregation" => get(hope_config, "aggregated!", 0) == 1,
        "aggregation_method" => "by_zone_type",
        "unit_commitment_mode" => get(hope_config, "unit_commitment", 0) == 1,
        "model_mode" => get(hope_config, "model_mode", "PCM"),
        "data_validation" => true,
        "fill_missing_data" => true
    )
    
    return PreprocessingConfig(preprocessing_dict)
end

"""
Process input data according to preprocessing configuration
"""
function preprocess_data!(preprocessor::HOPEDataPreprocessor, input_data::Dict)
    println("🔄 Starting integrated data preprocessing...")
    
    # Store original data
    preprocessor.original_data = deepcopy(input_data)
    preprocessor.processed_data = deepcopy(input_data)
    
    # Initialize preprocessing report
    preprocessor.preprocessing_report = Dict(
        "original_data_summary" => summarize_data(input_data),
        "preprocessing_steps" => String[],
        "time_structure" => Dict(),
        "aggregation_info" => Dict()
    )
    
    # Step 1: Generator aggregation (if enabled)
    if preprocessor.config.enable_gen_aggregation
        process_generator_aggregation!(preprocessor)
    end
    
    # Step 2: Time clustering (if enabled)
    if preprocessor.config.enable_time_clustering
        process_time_clustering!(preprocessor)
    else
        setup_full_time_structure!(preprocessor)
    end
    
    # Step 3: Data validation and cleanup
    if preprocessor.config.data_validation
        validate_processed_data!(preprocessor)
    end
    
    # Update input_data with processed results
    merge!(input_data, preprocessor.processed_data)
    
    print_preprocessing_summary(preprocessor)
    println("✅ Integrated data preprocessing completed")
    
    return preprocessor.processed_data
end

"""
Process generator aggregation
"""
function process_generator_aggregation!(preprocessor::HOPEDataPreprocessor)
    println("🔧 Processing generator aggregation...")
    push!(preprocessor.preprocessing_report["preprocessing_steps"], "generator_aggregation")
    
    config = preprocessor.config
    data = preprocessor.processed_data
    
    if haskey(data, "Gendata") && !isempty(data["Gendata"])
        original_gen_count = nrow(data["Gendata"])
        
        if config.aggregation_method == "by_zone_type"
            if config.model_mode == "GTEP"
                data["Gendata"] = aggregate_gendata_gtep(data["Gendata"])
            else  # PCM
                data["Gendata"] = aggregate_gendata_pcm(data["Gendata"], Dict(
                    "unit_commitment" => config.unit_commitment_mode ? 1 : 0
                ))
            end
            
            aggregated_gen_count = nrow(data["Gendata"])
            
            preprocessor.preprocessing_report["aggregation_info"] = Dict(
                "original_generators" => original_gen_count,
                "aggregated_generators" => aggregated_gen_count,
                "aggregation_ratio" => round(original_gen_count / aggregated_gen_count, digits=2),
                "method" => config.aggregation_method
            )
            
            println("   ✓ Generator aggregation: $original_gen_count → $aggregated_gen_count generators")
        end
    else
        println("   ⚠️ No generator data found for aggregation")
    end
end

"""
Process time clustering based on configuration
"""
function process_time_clustering!(preprocessor::HOPEDataPreprocessor)
    println("⏰ Processing time clustering...")
    push!(preprocessor.preprocessing_report["preprocessing_steps"], "time_clustering")
    
    config = preprocessor.config
    data = preprocessor.processed_data
    
    if config.clustering_method == "representative_day"
        # Use representative day clustering (legacy method)
        time_structure = create_representative_day_structure(
            config.time_periods,
            data,
            config.model_mode
        )
    else
        throw(ArgumentError("Unknown clustering method: $(config.clustering_method)"))
    end
    
    # Update processed data with time structure
    merge!(data, time_structure)
    preprocessor.preprocessing_report["time_structure"] = time_structure
    
    println("   ✓ Time clustering completed: $(length(get(time_structure, "T", [1]))) periods")
end

"""
Setup full time structure (no clustering)
"""
function setup_full_time_structure!(preprocessor::HOPEDataPreprocessor)
    println("⏰ Setting up full time structure...")
    push!(preprocessor.preprocessing_report["preprocessing_steps"], "full_time_structure")
    
    data = preprocessor.processed_data
    
    # Create full 8760-hour structure
    hours = collect(1:8760)
    time_structure = Dict(
        "H" => hours,
        "T" => [1],
        "H_T" => Dict(1 => hours),
        "is_clustered" => false,
        "period_weights" => Dict(1 => 1.0),
        "days_per_period" => Dict(1 => 365)
    )
    
    merge!(data, time_structure)
    preprocessor.preprocessing_report["time_structure"] = time_structure
    
    println("   ✓ Full time structure: $(length(hours)) hours")
end

"""
Create representative day time structure (legacy method)
"""
function create_representative_day_structure(time_periods::Dict, data::Dict, model_mode::String)
    if isempty(time_periods)
        # No time periods defined, use full structure
        return Dict(
            "H" => collect(1:8760),
            "T" => [1],
            "H_T" => Dict(1 => collect(1:8760)),
            "is_clustered" => false
        )
    end
    
    # Get representative time series using legacy function
    if haskey(data, "Loaddata") && !isempty(data["Loaddata"])
        zone_cols = names(data["Loaddata"])[4:end]
        ordered_zones = [col for col in zone_cols if col != "NI"]
        
        rep_data, ndays = get_representative_ts(
            data["Loaddata"],
            time_periods,
            ordered_zones
        )
        
        # Process other time series data
        if haskey(data, "Winddata") && !isempty(data["Winddata"])
            wind_rep, _ = get_representative_ts(data["Winddata"], time_periods, ordered_zones)
            for (tp, wind_data) in wind_rep
                if haskey(rep_data, tp)
                    rep_data[tp] = merge(rep_data[tp], Dict("wind" => wind_data))
                end
            end
        end
        
        if haskey(data, "Solardata") && !isempty(data["Solardata"])
            solar_rep, _ = get_representative_ts(data["Solardata"], time_periods, ordered_zones)
            for (tp, solar_data) in solar_rep
                if haskey(rep_data, tp)
                    rep_data[tp] = merge(rep_data[tp], Dict("solar" => solar_data))
                end
            end
        end
        
        # Create time structure
        periods = sort(collect(keys(time_periods)))
        total_days = sum(values(ndays))
        
        return Dict(
            "T" => periods,
            "H_T" => Dict(tp => collect(1:24) for tp in periods),
            "H" => collect(1:8760),  # Full hours still available
            "is_clustered" => true,
            "period_weights" => Dict(tp => ndays[tp]/total_days for tp in periods),
            "days_per_period" => ndays,
            "representative_data" => rep_data
        )
    else
        # No load data available, create basic structure
        periods = sort(collect(keys(time_periods)))
        return Dict(
            "T" => periods,
            "H_T" => Dict(tp => collect(1:24) for tp in periods),
            "H" => collect(1:8760),
            "is_clustered" => true,
            "period_weights" => Dict(tp => 1.0/length(periods) for tp in periods),
            "days_per_period" => Dict(tp => 90 for tp in periods)
        )
    end
end

"""
Validate processed data
"""
function validate_processed_data!(preprocessor::HOPEDataPreprocessor)
    println("✅ Validating processed data...")
    push!(preprocessor.preprocessing_report["preprocessing_steps"], "data_validation")
    
    data = preprocessor.processed_data
    issues = String[]
    
    # Check required time indices
    if !haskey(data, "H") || isempty(data["H"])
        push!(issues, "Missing or empty hour index H")
    end
    
    if !haskey(data, "T") || isempty(data["T"])
        push!(issues, "Missing or empty time period index T")
    end
    
    # Check data consistency
    if haskey(data, "H_T") && haskey(data, "T")
        for t in data["T"]
            if !haskey(data["H_T"], t)
                push!(issues, "Missing hours for time period $t")
            end
        end
    end
    
    # Check generator data
    if haskey(data, "Gendata")
        required_cols = ["Zone", "Type", "Pmax (MW)", "Pmin (MW)"]
        missing_cols = [col for col in required_cols if !(col in names(data["Gendata"]))]
        if !isempty(missing_cols)
            push!(issues, "Missing generator data columns: $(join(missing_cols, ", "))")
        end
    end
    
    if !isempty(issues)
        println("   ⚠️ Data validation issues found:")
        for issue in issues
            println("     - $issue")
        end
    else
        println("   ✓ Data validation passed")
    end
    
    preprocessor.preprocessing_report["validation_issues"] = issues
end

"""
Summarize original data
"""
function summarize_data(data::Dict)
    summary = Dict{String, Any}()
    
    for (key, value) in data
        if isa(value, DataFrame)
            summary[key] = Dict(
                "type" => "DataFrame",
                "rows" => nrow(value),
                "columns" => ncol(value),
                "column_names" => names(value)
            )
        elseif isa(value, Dict)
            summary[key] = Dict(
                "type" => "Dict",
                "keys" => collect(keys(value))
            )
        elseif isa(value, Vector)
            summary[key] = Dict(
                "type" => "Vector",
                "length" => length(value),
                "element_type" => eltype(value)
            )
        else
            summary[key] = Dict(
                "type" => string(typeof(value)),
                "value" => string(value)
            )
        end
    end
    
    return summary
end

"""
Print preprocessing summary
"""
function print_preprocessing_summary(preprocessor::HOPEDataPreprocessor)
    println("\n📊 PREPROCESSING SUMMARY")
    println("=" ^ 50)
    
    report = preprocessor.preprocessing_report
    
    println("📋 Steps completed: $(join(report["preprocessing_steps"], " → "))")
    
    if haskey(report, "time_structure") && haskey(report["time_structure"], "is_clustered")
        if report["time_structure"]["is_clustered"]
            periods = length(get(report["time_structure"], "T", []))
            println("⏰ Time structure: $periods clustered periods")
        else
            hours = length(get(report["time_structure"], "H", []))
            println("⏰ Time structure: $hours full hours")
        end
    end
    
    if haskey(report, "aggregation_info") && !isempty(report["aggregation_info"])
        agg_info = report["aggregation_info"]
        println("🔧 Generator aggregation: $(agg_info["original_generators"]) → $(agg_info["aggregated_generators"]) ($(agg_info["aggregation_ratio"])x reduction)")
    end
    
    if haskey(report, "validation_issues")
        issues = report["validation_issues"]
        if isempty(issues)
            println("✅ Validation: All checks passed")
        else
            println("⚠️  Validation: $(length(issues)) issues found")
        end
    end
    
    println("=" ^ 50)
end

# Legacy aggregation functions (integrated from read_input_data.jl)
function aggregate_gendata_gtep(df::DataFrame)
    agg_df = combine(groupby(df, [:Zone, :Type]),
        Symbol("Pmax (MW)") => sum,
        Symbol("Pmin (MW)") => sum,
        Symbol("Cost (\$/MWh)") => mean,
        :EF => mean,
        :CC => mean,
        :AF => mean,
        :Flag_thermal => mean,
        :Flag_VRE => mean,
        :Flag_RET => mean,
        :Flag_mustrun => mean
    )
    
    rename!(agg_df, [Symbol("Pmax (MW)_sum"), Symbol("Pmin (MW)_sum"), Symbol("Cost (\$/MWh)_mean"), 
                     :EF_mean, :CC_mean, :AF_mean, :Flag_thermal_mean, :Flag_VRE_mean, 
                     :Flag_RET_mean, :Flag_mustrun_mean] .=> 
                    [Symbol("Pmax (MW)"), Symbol("Pmin (MW)"), Symbol("Cost (\$/MWh)"), 
                     :EF, :CC, :AF, :Flag_thermal, :Flag_VRE, :Flag_RET, :Flag_mustrun])
    
    # Convert flags to binary
    agg_df[agg_df.Flag_thermal .> 0, :Flag_thermal] .= 1
    agg_df[agg_df.Flag_VRE .> 0, :Flag_VRE] .= 1
    agg_df[agg_df.Flag_RET .> 0, :Flag_RET] .= 1
    agg_df[agg_df.Flag_mustrun .> 0, :Flag_mustrun] .= 1
    
    return agg_df
end

function aggregate_gendata_pcm(df::DataFrame, config_dict::Dict)
    unit_commitment = get(config_dict, "unit_commitment", 0)
    
    if unit_commitment == 0
        # Simple aggregation without unit commitment
        agg_df = combine(groupby(df, [:Zone, :Type]),
            Symbol("Pmax (MW)") => sum,
            Symbol("Pmin (MW)") => sum,
            Symbol("Cost (\$/MWh)") => mean,
            :EF => mean,
            :CC => mean,
            :FOR => mean,
            :RM_SPIN => mean,
            :RU => mean,
            :RD => mean,
            :Flag_thermal => mean,
            :Flag_VRE => mean,
            :Flag_mustrun => mean
        )
        
        rename!(agg_df, [Symbol("Pmax (MW)_sum"), Symbol("Pmin (MW)_sum"), Symbol("Cost (\$/MWh)_mean"),
                         :EF_mean, :CC_mean, :FOR_mean, :RM_SPIN_mean, :RU_mean, :RD_mean,
                         :Flag_thermal_mean, :Flag_VRE_mean, :Flag_mustrun_mean] .=>
                        [Symbol("Pmax (MW)"), Symbol("Pmin (MW)"), Symbol("Cost (\$/MWh)"),
                         :EF, :CC, :FOR, :RM_SPIN, :RU, :RD, :Flag_thermal, :Flag_VRE, :Flag_mustrun])
    else
        # Aggregation with unit commitment parameters
        agg_df = combine(groupby(df, [:Zone, :Type]),
            Symbol("Pmax (MW)") => sum,
            Symbol("Pmin (MW)") => sum,
            Symbol("Cost (\$/MWh)") => mean,
            :EF => mean,
            :CC => mean,
            :FOR => mean,
            :RM_SPIN => mean,
            :RU => mean,
            :RD => mean,
            :Flag_thermal => mean,
            :Flag_VRE => mean,
            :Flag_UC => mean,
            :Flag_mustrun => mean,
            Symbol("Start_up_cost (\$/MW)") => mean,
            :Min_down_time => mean,
            :Min_up_time => mean
        )
        
        rename!(agg_df, [Symbol("Pmax (MW)_sum"), Symbol("Pmin (MW)_sum"), Symbol("Cost (\$/MWh)_mean"),
                         :EF_mean, :CC_mean, :FOR_mean, :RM_SPIN_mean, :RU_mean, :RD_mean,
                         :Flag_thermal_mean, :Flag_VRE_mean, :Flag_UC_mean, :Flag_mustrun_mean,
                         Symbol("Start_up_cost (\$/MW)_mean"), :Min_down_time_mean, :Min_up_time_mean] .=>
                        [Symbol("Pmax (MW)"), Symbol("Pmin (MW)"), Symbol("Cost (\$/MWh)"),
                         :EF, :CC, :FOR, :RM_SPIN, :RU, :RD, :Flag_thermal, :Flag_VRE, :Flag_UC, 
                         :Flag_mustrun, Symbol("Start_up_cost (\$/MW)"), :Min_down_time, :Min_up_time])
        
        agg_df[agg_df.Flag_UC .> 0, :Flag_UC] .= 1
    end
    
    # Convert all flags to binary
    agg_df[agg_df.Flag_thermal .> 0, :Flag_thermal] .= 1
    agg_df[agg_df.Flag_VRE .> 0, :Flag_VRE] .= 1
    agg_df[agg_df.Flag_mustrun .> 0, :Flag_mustrun] .= 1
    
    return agg_df
end

# Legacy time series clustering function (from GTEP.jl)
function get_representative_ts(df::DataFrame, time_periods::Dict, ordered_zones::Vector{String}, k::Int=1)
    function filter_time_period(time_period, row)
        return (row.Month == time_period[1] && row.Day >= time_period[2]) || 
               (row.Month == time_period[3] && row.Day <= time_period[4]) || 
               (row.Month > time_period[1] && row.Month < time_period[3]) || 
               (time_period[1] > time_period[3] && row.Month < time_period[3])
    end
    
    rep_data_dict = Dict()
    ndays_dict = Dict()
    
    for (tp, dates) in time_periods
        if isa(dates, String)
            dates = eval(Meta.parse(dates))
        end
        
        tp_df = filter(row -> filter_time_period(dates, row), df)
        n_days = Int(size(tp_df, 1) / 24)
        representative_day_df = DataFrame()
        
        for zone_name in names(tp_df)[4:end]
            col_data = tp_df[!, zone_name]
            col_matrix = reshape(col_data, (24, n_days))
            col_matrix = parse.(Float64, string.(col_matrix))
            
            clustering_result = kmeans(col_matrix, k)
            representative_day_df[!, zone_name] = clustering_result.centers'[1, :]
        end
        
        if "NI" in names(df)
            representative_day_df_ordered = select(representative_day_df, [ordered_zones; "NI"])
        else
            representative_day_df_ordered = select(representative_day_df, ordered_zones)
        end
        
        representative_day_df.Hour = 1:24
        rep_data_dict[tp] = representative_day_df_ordered
        ndays_dict[tp] = n_days
    end
    
    return (rep_data_dict, ndays_dict)
end

# Export functions
export PreprocessingConfig, HOPEDataPreprocessor
export create_preprocessing_config_from_hope_settings, preprocess_data!
export process_time_clustering!, process_generator_aggregation!
export aggregate_gendata_gtep, aggregate_gendata_pcm, get_representative_ts

end # module DataPreprocessor
