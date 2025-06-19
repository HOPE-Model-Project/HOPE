"""
# DataReader.jl - Standardized Data Loading System
# 
# This module provides unified data loading capabilities for HOPE models,
# handling CSV, Excel, and other data formats with validation and preprocessing.
# Supports flexible data sources: multi-sheet Excel files OR individual CSV files
"""

module DataReader

using DataFrames
using CSV
using XLSX
using YAML
using Statistics

"""
Data reader structure for managing input data loading with flexible format support
"""
struct HOPEDataReader
    case_path::String
    data_path::String
    settings_path::String
    use_excel::Bool
    excel_file::Union{String, Nothing}
    
    function HOPEDataReader(case_path::String)
        settings_path = joinpath(case_path, "Settings")
        
        # Load configuration to get DataCase
        settings_file = joinpath(settings_path, "HOPE_model_settings.yml")
        if !isfile(settings_file)
            throw(ArgumentError("Settings file not found: $settings_file"))
        end
        
        config = YAML.load(open(settings_file))
        data_case = get(config, "DataCase", "Data/")
        
        # Remove trailing slash if present
        data_case = rstrip(data_case, '/')
        
        # Construct data path using DataCase from config
        data_path = joinpath(case_path, data_case)
        
        if !isdir(data_path)
            throw(ArgumentError("Data directory not found: $data_path"))
        end
        
        # Auto-detect whether to use Excel or CSV
        files = readdir(data_path)
        excel_files = filter(f -> endswith(f, ".xlsx"), files)
        
        use_excel = length(excel_files) > 0
        excel_file = use_excel ? excel_files[1] : nothing  # Use first Excel file found
        
        println("📁 Data source detected:")
        println("   Case path: $case_path")
        println("   Data path: $data_path") 
        println("   Format: $(use_excel ? "Excel ($excel_file)" : "CSV files")")
        
        new(case_path, data_path, settings_path, use_excel, excel_file)
    end
end

"""
Aggregation function for generation data in GTEP mode (from original code)
"""
function aggregate_gendata_gtep(df)
    agg_df = combine(groupby(df, [:Zone,:Type]),
        Symbol("Pmax (MW)") .=> sum,
        Symbol("Pmin (MW)") .=> sum,
        Symbol("Cost (\$/MWh)") .=> mean,
        :EF .=> mean,
        :CC .=> mean,
        :AF .=> mean,
        :Flag_thermal .=> mean,
        :Flag_VRE .=> mean,
        :Flag_RET .=> mean,
        :Flag_mustrun .=> mean,)
    rename!(agg_df, [Symbol("Pmax (MW)_sum"), Symbol("Pmin (MW)_sum"),Symbol("Cost (\$/MWh)_mean"),:EF_mean,:CC_mean,:AF_mean,:Flag_thermal_mean,:Flag_VRE_mean,:Flag_RET_mean,:Flag_mustrun_mean] .=>  [Symbol("Pmax (MW)"), Symbol("Pmin (MW)"), Symbol("Cost (\$/MWh)"),:EF,:CC,:AF,:Flag_thermal,:Flag_VRE,:Flag_RET,:Flag_mustrun] )
    agg_df[agg_df.Flag_thermal .> 0, :Flag_thermal] .=1
    agg_df[agg_df.Flag_VRE .> 0, :Flag_VRE] .=1
    agg_df[agg_df.Flag_RET .> 0, :Flag_RET] .=1
    agg_df[agg_df.Flag_mustrun .> 0, :Flag_mustrun] .=1
    return agg_df
end

"""
Aggregation function for generation data in PCM mode (from original code)
"""
function aggregate_gendata_pcm(df::DataFrame, config_set::Dict)
    if get(config_set, "unit_commitment", 0) == 0
        agg_df = combine(groupby(df, [:Zone,:Type]),
            Symbol("Pmax (MW)") .=> sum,
            Symbol("Pmin (MW)") .=> sum,
            Symbol("Cost (\$/MWh)") .=> mean,
            :EF .=> mean,
            :CC .=> mean,
            :FOR .=> mean,
            :RM_SPIN .=> mean,
            :RU .=> mean,
            :RD .=> mean,
            :Flag_thermal .=> mean,
            :Flag_VRE .=> mean,
            :Flag_mustrun .=> mean)
        rename!(agg_df, [Symbol("Pmax (MW)_sum"), Symbol("Pmin (MW)_sum"),Symbol("Cost (\$/MWh)_mean"),:EF_mean,:CC_mean,:FOR_mean,:RM_SPIN_mean,:RU_mean,:RD_mean,:Flag_thermal_mean,:Flag_VRE_mean,:Flag_mustrun_mean] 
            .=> [Symbol("Pmax (MW)"), Symbol("Pmin (MW)"), Symbol("Cost (\$/MWh)"),:EF,:CC,:FOR,:RM_SPIN,:RU,:RD,:Flag_thermal,:Flag_VRE,:Flag_mustrun])
        agg_df[agg_df.Flag_thermal .> 0, :Flag_thermal] .=1
        agg_df[agg_df.Flag_VRE .> 0, :Flag_VRE] .=1
        agg_df[agg_df.Flag_mustrun .> 0, :Flag_mustrun] .=1
        return agg_df
    else
        # Include unit commitment parameters
        agg_df = combine(groupby(df, [:Zone,:Type]),
            Symbol("Pmax (MW)") .=> sum,
            Symbol("Pmin (MW)") .=> sum,
            Symbol("Cost (\$/MWh)") .=> mean,
            :EF .=> mean,
            :CC .=> mean,
            :FOR .=> mean,
            :RM_SPIN .=> mean,
            :RU .=> mean,
            :RD .=> mean,
            :Min_run_hour .=> mean,
            :Min_up_hour .=> mean,
            :Min_down_hour .=> mean,
            :Flag_thermal .=> mean,
            :Flag_VRE .=> mean,
            :Flag_mustrun .=> mean,
            :Flag_UC .=> mean)
        rename!(agg_df, [Symbol("Pmax (MW)_sum"), Symbol("Pmin (MW)_sum"),Symbol("Cost (\$/MWh)_mean"),:EF_mean,:CC_mean,:FOR_mean,:RM_SPIN_mean,:RU_mean,:RD_mean,:Min_run_hour_mean,:Min_up_hour_mean,:Min_down_hour_mean,:Flag_thermal_mean,:Flag_VRE_mean,:Flag_mustrun_mean,:Flag_UC_mean] 
            .=> [Symbol("Pmax (MW)"), Symbol("Pmin (MW)"), Symbol("Cost (\$/MWh)"),:EF,:CC,:FOR,:RM_SPIN,:RU,:RD,:Min_run_hour,:Min_up_hour,:Min_down_hour,:Flag_thermal,:Flag_VRE,:Flag_mustrun,:Flag_UC])
        agg_df[agg_df.Flag_thermal .> 0, :Flag_thermal] .=1
        agg_df[agg_df.Flag_VRE .> 0, :Flag_VRE] .=1
        agg_df[agg_df.Flag_mustrun .> 0, :Flag_mustrun] .=1
        agg_df[agg_df.Flag_UC .> 0, :Flag_UC] .=1
        return agg_df
    end
end

"""
Main function to load HOPE input data with flexible Excel/CSV support
"""
function load_hope_data(reader::HOPEDataReader, config::Dict)::Dict
    model_mode = config["model_mode"]
    println("📊 Loading input data for $model_mode mode...")
    println("   Data source: $(reader.use_excel ? "Excel" : "CSV")")
    
    input_data = Dict()
    
    if model_mode == "GTEP"
        input_data = load_gtep_data(reader, config)
    elseif model_mode == "PCM"
        input_data = load_pcm_data(reader, config)
    elseif model_mode == "HOLISTIC"
        input_data = load_holistic_data(reader, config)
    else
        throw(ArgumentError("Unknown model mode: $model_mode"))
    end
    
    # Process and validate data
    processed_data = process_raw_data(input_data, config)
    validated_data = validate_input_data(processed_data, config)
    
    println("✅ Data loading completed successfully")
    print_data_summary(validated_data)
    
    return validated_data
end

"""
Load model configuration from YAML settings with full settings structure support
"""
function load_configuration(reader::HOPEDataReader)::Dict
    settings_file = joinpath(reader.settings_path, "HOPE_model_settings.yml")
    
    if !isfile(settings_file)
        throw(ArgumentError("Settings file not found: $settings_file"))
    end
    
    config = YAML.load(open(settings_file))
    
    # Validate required settings
    required_settings = ["model_mode", "solver", "DataCase"]
    for setting in required_settings
        if !haskey(config, setting)
            throw(ArgumentError("Required setting missing: $setting"))
        end
    end
    
    # Set default values for optional settings based on real examples
    defaults = Dict(
        "unit_commitment" => 0,
        "flexible_demand" => 0,
        "aggregated!" => 1,
        "representative_day!" => 0,
        "inv_dcs_bin" => 0,
        "debug" => 0,
        "time_periods" => Dict(
            1 => (3, 20, 6, 20),    # Spring
            2 => (6, 21, 9, 21),    # Summer  
            3 => (9, 22, 12, 20),   # Fall
            4 => (12, 21, 3, 19)    # Winter
        )
    )
    
    for (key, default_value) in defaults
        if !haskey(config, key)
            config[key] = default_value
        end
    end
    
    println("📋 Configuration loaded:")
    println("   Model mode: $(config["model_mode"])")
    println("   Data case: $(config["DataCase"])")
    println("   Solver: $(config["solver"])")
    println("   Aggregated: $(config["aggregated!"])")
    println("   Flexible demand: $(config["flexible_demand"])")
    println("   Representative days: $(config["representative_day!"])")
    
    return config
end

"""
Load solver-specific configuration
"""
function load_solver_configuration(reader::HOPEDataReader, solver_name::String)::Dict
    solver_file = joinpath(reader.settings_path, "$(solver_name)_settings.yml")
    
    if !isfile(solver_file)
        println("⚠️  Solver settings file not found: $solver_file, using defaults")
        return Dict{String, Any}()
    end
    
    solver_config = YAML.load(open(solver_file))
    println("🔧 Solver configuration loaded for $solver_name")
    
    return solver_config
end

"""
Load zone/region data
"""
function load_zone_data(reader::HOPEDataReader)::DataFrame
    zone_file = joinpath(reader.data_path, "zonedata.csv")
    
    if isfile(zone_file)
        df = CSV.read(zone_file, DataFrame)
    else
        # Create minimal zone data if file doesn't exist
        df = DataFrame(
            Zone = ["Zone1"],
            State = ["State1"],
            Country = ["USA"]
        )
        @warn "Zone data file not found, using default single zone"
    end
    
    # Validate required columns
    required_cols = [:Zone]
    validate_required_columns(df, required_cols, "zonedata")
    
    return df
end

"""
Load transmission line data
"""
function load_line_data(reader::HOPEDataReader)::DataFrame
    line_file = joinpath(reader.data_path, "linedata.csv")
    
    if isfile(line_file)
        df = CSV.read(line_file, DataFrame)
    else
        # Empty transmission data if no file
        df = DataFrame(
            Zone_from = String[],
            Zone_to = String[],
            Symbol("Pmax (MW)") => Float64[],
            Symbol("Length (miles)") => Float64[]
        )
        @warn "Line data file not found, assuming no transmission lines"
    end
    
    # Validate and process
    if nrow(df) > 0
        required_cols = [:Zone_from, :Zone_to, Symbol("Pmax (MW)")]
        validate_required_columns(df, required_cols, "linedata")
    end
    
    return df
end

"""
Load generator data
"""
function load_generator_data(reader::HOPEDataReader)::DataFrame
    gen_file = joinpath(reader.data_path, "gendata.csv")
    
    if !isfile(gen_file)
        throw(ArgumentError("Generator data file not found: $gen_file"))
    end
    
    df = CSV.read(gen_file, DataFrame)
    
    # Validate required columns
    required_cols = [:Zone, :Type, Symbol("Pmax (MW)"), Symbol("Cost (\$/MWh)")]
    validate_required_columns(df, required_cols, "gendata")
    
    # Add default values for missing columns
    if !hasproperty(df, Symbol("Pmin (MW)"))
        df[!, Symbol("Pmin (MW)")] .= 0.0
    end
    
    if !hasproperty(df, Symbol("FOR"))
        df[!, Symbol("FOR")] .= 0.05  # Default forced outage rate
    end
    
    return df
end

"""
Load storage data
"""
function load_storage_data(reader::HOPEDataReader)::DataFrame
    storage_file = joinpath(reader.data_path, "storagedata.csv")
    
    if isfile(storage_file)
        df = CSV.read(storage_file, DataFrame)
        
        # Validate required columns
        required_cols = [:Zone, :Type, Symbol("Capacity (MWh)"), Symbol("Max Power (MW)")]
        validate_required_columns(df, required_cols, "storagedata")
        
        # Add default efficiency if missing
        if !hasproperty(df, Symbol("Eff_c"))
            df[!, Symbol("Eff_c")] .= 0.9  # Default charging efficiency
        end
        if !hasproperty(df, Symbol("Eff_dc"))
            df[!, Symbol("Eff_dc")] .= 0.9  # Default discharging efficiency
        end
    else
        # Empty storage data if no file
        df = DataFrame(
            Zone = String[],
            Type = String[],
            Symbol("Capacity (MWh)") => Float64[],
            Symbol("Max Power (MW)") => Float64[],
            Symbol("Eff_c") => Float64[],
            Symbol("Eff_dc") => Float64[]
        )
        @warn "Storage data file not found, assuming no storage"
    end
    
    return df
end

"""
Load load time series data
"""
function load_load_timeseries(reader::HOPEDataReader)::DataFrame
    load_file = joinpath(reader.data_path, "load_timeseries_regional.csv")
    
    if !isfile(load_file)
        throw(ArgumentError("Load timeseries file not found: $load_file"))
    end
    
    df = CSV.read(load_file, DataFrame)
    
    # Validate that we have numeric load data
    numeric_cols = filter(name -> name != :Hour && eltype(df[!, name]) <: Number, names(df))
    
    if isempty(numeric_cols)
        throw(ArgumentError("No numeric load data columns found in load timeseries"))
    end
    
    # Ensure positive load values
    for col in numeric_cols
        df[!, col] = max.(df[!, col], 0.0)
    end
    
    return df
end

"""
Load wind time series data
"""
function load_wind_timeseries(reader::HOPEDataReader)::DataFrame
    wind_file = joinpath(reader.data_path, "wind_timeseries_regional.csv")
    
    if isfile(wind_file)
        df = CSV.read(wind_file, DataFrame)
        
        # Validate wind capacity factors (should be between 0 and 1)
        numeric_cols = filter(name -> name != :Hour && eltype(df[!, name]) <: Number, names(df))
        for col in numeric_cols
            df[!, col] = clamp.(df[!, col], 0.0, 1.0)
        end
    else
        # Create default wind data (zero generation)
        df = DataFrame(Hour = 1:8760)
        @warn "Wind timeseries file not found, assuming no wind generation"
    end
    
    return df
end

"""
Load solar time series data
"""
function load_solar_timeseries(reader::HOPEDataReader)::DataFrame
    solar_file = joinpath(reader.data_path, "solar_timeseries_regional.csv")
    
    if isfile(solar_file)
        df = CSV.read(solar_file, DataFrame)
        
        # Validate solar capacity factors (should be between 0 and 1)
        numeric_cols = filter(name -> name != :Hour && eltype(df[!, name]) <: Number, names(df))
        for col in numeric_cols
            df[!, col] = clamp.(df[!, col], 0.0, 1.0)
        end
    else
        # Create default solar data (zero generation)
        df = DataFrame(Hour = 1:8760)
        @warn "Solar timeseries file not found, assuming no solar generation"
    end
    
    return df
end

"""
Load net interchange data
"""
function load_net_interchange_data(reader::HOPEDataReader)::DataFrame
    ni_file = joinpath(reader.data_path, "dr_timeseries_regional.csv")
    
    if isfile(ni_file)
        df = CSV.read(ni_file, DataFrame)
    else
        # Create default NI data (zero interchange)
        df = DataFrame(Hour = 1:8760)
        for zone in ["Zone1"]  # Default single zone
            df[!, Symbol(zone)] .= 0.0
        end
        @warn "Net interchange file not found, assuming zero interchange"
    end
    
    return df
end

"""
Load carbon policy data
"""
function load_carbon_policy_data(reader::HOPEDataReader)::DataFrame
    carbon_file = joinpath(reader.data_path, "carbonpolicies.csv")
    
    if isfile(carbon_file)
        df = CSV.read(carbon_file, DataFrame)
        
        # Validate required columns
        if hasproperty(df, :State) && hasproperty(df, Symbol("Allowance (tons)"))
            # Valid carbon policy data
        else
            @warn "Carbon policy file has unexpected format"
        end
    else
        # Create default (no carbon policy)
        df = DataFrame(
            State = String[],
            Symbol("Allowance (tons)") => Float64[]
        )
        @warn "Carbon policy file not found, assuming no carbon constraints"
    end
    
    return df
end

"""
Load RPS policy data
"""
function load_rps_policy_data(reader::HOPEDataReader)::DataFrame
    rps_file = joinpath(reader.data_path, "rpspolicies.csv")
    
    if isfile(rps_file)
        df = CSV.read(rps_file, DataFrame)
    else
        # Create default (no RPS policy)
        df = DataFrame(
            From_state = String[],
            RPS = Float64[]
        )
        @warn "RPS policy file not found, assuming no RPS requirements"
    end
    
    return df
end

"""
Load single parameters
"""
function load_single_parameters(reader::HOPEDataReader)::DataFrame
    param_file = joinpath(reader.data_path, "single_parameter.csv")
    
    if isfile(param_file)
        df = CSV.read(param_file, DataFrame)
    else
        # Create default parameters
        df = DataFrame(
            Symbol("IBG (\$)") => [1e9],      # Generator investment budget
            Symbol("IBL (\$)") => [1e9],      # Line investment budget
            Symbol("IBS (\$)") => [1e9],      # Storage investment budget
            Symbol("PRM") => [0.15],          # Planning reserve margin
            Symbol("VOLL (\$/MWh)") => [1000] # Value of lost load
        )
        @warn "Single parameter file not found, using default values"
    end
    
    return df
end

"""
Load candidate generator data for GTEP
"""
function load_candidate_generator_data(reader::HOPEDataReader)::DataFrame
    cand_file = joinpath(reader.data_path, "gendata_candidate.csv")
    
    if isfile(cand_file)
        df = CSV.read(cand_file, DataFrame)
        
        # Validate required columns for candidates
        required_cols = [:Zone, :Type, Symbol("Pmax (MW)"), Symbol("INV (\$/MW)")]
        validate_required_columns(df, required_cols, "gendata_candidate")
    else
        # Empty candidate data
        df = DataFrame(
            Zone = String[],
            Type = String[],
            Symbol("Pmax (MW)") => Float64[],
            Symbol("INV (\$/MW)") => Float64[]
        )
        @warn "Candidate generator file not found, no expansion options available"
    end
    
    return df
end

"""
Load candidate transmission data for GTEP
"""
function load_candidate_line_data(reader::HOPEDataReader)::DataFrame
    cand_file = joinpath(reader.data_path, "linedata_candidate.csv")
    
    if isfile(cand_file)
        df = CSV.read(cand_file, DataFrame)
    else
        # Empty candidate data
        df = DataFrame(
            Zone_from = String[],
            Zone_to = String[],
            Symbol("Pmax (MW)") => Float64[],
            Symbol("INV (\$/MW)") => Float64[]
        )
        @warn "Candidate line file not found, no transmission expansion options"
    end
    
    return df
end

"""
Load candidate storage data for GTEP
"""
function load_candidate_storage_data(reader::HOPEDataReader)::DataFrame
    cand_file = joinpath(reader.data_path, "storagedata_candidate.csv")
    
    if isfile(cand_file)
        df = CSV.read(cand_file, DataFrame)
    else
        # Empty candidate data
        df = DataFrame(
            Zone = String[],
            Type = String[],
            Symbol("Capacity (MWh)") => Float64[],
            Symbol("Max Power (MW)") => Float64[],
            Symbol("INV (\$/MWh)") => Float64[]
        )
        @warn "Candidate storage file not found, no storage expansion options"
    end
    
    return df
end

"""
Load demand response data
"""
function load_demand_response_data(reader::HOPEDataReader)::DataFrame
    dr_file = joinpath(reader.data_path, "flexddata.csv")
    
    if isfile(dr_file)
        df = CSV.read(dr_file, DataFrame)
    else
        # Empty DR data
        df = DataFrame(
            Zone = String[],
            Symbol("Max Power (MW)") => Float64[],
            Symbol("Cost (\$/MWh)") => Float64[]
        )
        @warn "Demand response file not found, no DR resources available"
    end
    
    return df
end

"""
Validate that required columns exist in dataframe
"""
function validate_required_columns(df::DataFrame, required_cols::Vector{Symbol}, table_name::String)
    missing_cols = setdiff(required_cols, names(df))
    if !isempty(missing_cols)
        throw(ArgumentError("Missing required columns in $table_name: $missing_cols"))
    end
end

"""
Process raw data into model-ready format
"""
function process_raw_data(data::Dict, config::Dict)::Dict
    processed = copy(data)
    
    # Debug: Check what columns exist in zone data
    println("🔍 Zone data columns: $(names(data["Zonedata"]))")
    println("🔍 Zone data sample:")
    println(first(data["Zonedata"], 3))
      # Create index sets from data - be flexible with column names
    if hasproperty(data["Zonedata"], :Zone)
        processed["I"] = unique(data["Zonedata"][!, :Zone])  # Zones
    elseif hasproperty(data["Zonedata"], :zone)
        processed["I"] = unique(data["Zonedata"][!, :zone])  # Zones (lowercase)
    elseif hasproperty(data["Zonedata"], :Zone_id)
        processed["I"] = unique(data["Zonedata"][!, :Zone_id])  # Zone_id column
        println("⚠️  Using column 'Zone_id' as zone identifier")
    elseif hasproperty(data["Zonedata"], Symbol("Zone ID"))
        processed["I"] = unique(data["Zonedata"][!, Symbol("Zone ID")])  # Alternative name
    else
        # Use first string column as zone identifier
        string_cols = filter(col -> eltype(data["Zonedata"][!, col]) <: AbstractString, names(data["Zonedata"]))
        if !isempty(string_cols)
            processed["I"] = unique(data["Zonedata"][!, string_cols[1]])
            println("⚠️  Using column '$(string_cols[1])' as zone identifier")
        else
            throw(ArgumentError("Cannot find zone identifier column in Zonedata"))
        end
    end
    
    # Similarly for states
    if hasproperty(data["Zonedata"], :State)
        processed["W"] = unique(data["Zonedata"][!, :State])  # States (if available)
    elseif hasproperty(data["Zonedata"], :state)
        processed["W"] = unique(data["Zonedata"][!, :state])  # States (lowercase)
    else
        processed["W"] = ["State1"]  # Default state
        println("⚠️  No State column found, using default")
    end
      if isempty(processed["W"])
        processed["W"] = ["State1"]  # Default state
    end
    
    # Standardize generator data zone column
    if haskey(data, "Gendata")
        gen_df = data["Gendata"]
        gen_zone_col_candidates = [:Zone, :Zone_id, "Zone", "Zone_id"]
        gen_zone_col = nothing
        
        for col in gen_zone_col_candidates
            if hasproperty(gen_df, col)
                gen_zone_col = col
                break
            end
        end
        
        if gen_zone_col !== nothing && gen_zone_col != :Zone
            if !hasproperty(gen_df, :Zone)
                rename!(gen_df, gen_zone_col => :Zone)
            end
        end
        
        processed["Gendata"] = gen_df
    end
    
    # Generator sets
    processed["G"] = 1:nrow(data["Gendata"])  # Existing generators
    if haskey(data, "Gendata_candidate")
        processed["G_new"] = 1:nrow(data["Gendata_candidate"])  # Candidate generators
    else
        processed["G_new"] = Int[]
    end
    
    # Storage sets
    processed["S"] = 1:nrow(data["Storagedata"])  # Existing storage
    if haskey(data, "Estoragedata_candidate")
        processed["S_new"] = 1:nrow(data["Estoragedata_candidate"])  # Candidate storage
    else
        processed["S_new"] = Int[]
    end
    
    # Transmission sets
    processed["L"] = 1:nrow(data["Linedata"])  # Existing lines
    if haskey(data, "Linedata_candidate")
        processed["L_new"] = 1:nrow(data["Linedata_candidate"])  # Candidate lines
    else
        processed["L_new"] = Int[]
    end
    
    # Time sets (will be updated by TimeManager)
    if config["model_mode"] == "GTEP"
        # Default representative periods (will be overridden by clustering if available)
        processed["T"] = [1, 2, 3, 4]  # Seasons
        processed["H_T"] = Dict(t => collect(1:24) for t in processed["T"])
    else  # PCM
        processed["H"] = collect(1:nrow(data["Loaddata"]))  # All hours
    end
    
    return processed
end

"""
Validate input data consistency and completeness
"""
function validate_input_data(data::Dict, config::Dict)::Dict
    println("🔍 Validating input data...")
    
    # Check zone consistency
    all_zones = Set(data["I"])
    
    # Validate generator zones
    gen_zones = Set(data["Gendata"][!, :Zone])
    invalid_gen_zones = setdiff(gen_zones, all_zones)
    if !isempty(invalid_gen_zones)
        @warn "Generators reference unknown zones: $invalid_gen_zones"
    end
    
    # Validate load data zones
    load_zones = Set(filter(name -> name != :Hour, names(data["Loaddata"])))
    if !issubset(all_zones, load_zones)
        missing_load_zones = setdiff(all_zones, load_zones)
        @warn "Missing load data for zones: $missing_load_zones"
    end
    
    # Check data consistency
    load_hours = nrow(data["Loaddata"])
    wind_hours = nrow(data["Winddata"])
    solar_hours = nrow(data["Solardata"])
    
    if config["model_mode"] == "PCM"
        expected_hours = 8760
        if load_hours != expected_hours
            @warn "Load data has $load_hours hours, expected $expected_hours for annual simulation"
        end
    end
    
    # Validate time series alignment
    if wind_hours != load_hours
        @warn "Wind timeseries ($wind_hours hrs) doesn't match load timeseries ($load_hours hrs)"
    end
    if solar_hours != load_hours
        @warn "Solar timeseries ($solar_hours hrs) doesn't match load timeseries ($load_hours hrs)"
    end
    
    println("✅ Input data validation completed")
    return data
end

"""
Print summary of loaded data
"""
function print_data_summary(data::Dict)
    println("📊 Data Summary:")
    println("   Zones: $(length(data["I"]))")
    println("   Existing Generators: $(length(data["G"]))")
    println("   Candidate Generators: $(length(data["G_new"]))")
    println("   Existing Storage: $(length(data["S"]))")
    println("   Candidate Storage: $(length(data["S_new"]))")
    println("   Existing Lines: $(length(data["L"]))")
    println("   Candidate Lines: $(length(data["L_new"]))")
    
    if haskey(data, "H")
        println("   Time Hours: $(length(data["H"]))")
    elseif haskey(data, "T")
        total_hours = sum(length(hours) for hours in values(data["H_T"]))
        println("   Time Periods: $(length(data["T"])), Total Rep Hours: $total_hours")
    end
end

"""
Load data for GTEP mode with flexible Excel/CSV support
"""
function load_gtep_data(reader::HOPEDataReader, config::Dict)::Dict
    data = Dict()
    aggregated = get(config, "aggregated!", 0) == 1
    flexible_demand = get(config, "flexible_demand", 0) == 1
    
    if reader.use_excel
        println("📄 Reading from Excel file: $(reader.excel_file)")
        excel_path = joinpath(reader.data_path, reader.excel_file)
        
        # Network data
        println("Reading network data...")
        data["Zonedata"] = DataFrame(XLSX.readtable(excel_path, "zonedata"))
        data["Linedata"] = DataFrame(XLSX.readtable(excel_path, "linedata"))
        
        # Technology data
        println("Reading technology data...")
        gendata_raw = DataFrame(XLSX.readtable(excel_path, "gendata"))
        data["Gendata"] = aggregated ? aggregate_gendata_gtep(gendata_raw) : gendata_raw
        data["Storagedata"] = DataFrame(XLSX.readtable(excel_path, "storagedata"))
        
        # Time series data
        println("Reading time series...")
        data["Winddata"] = DataFrame(XLSX.readtable(excel_path, "wind_timeseries_regional"))
        data["Solardata"] = DataFrame(XLSX.readtable(excel_path, "solar_timeseries_regional"))
        data["Loaddata"] = DataFrame(XLSX.readtable(excel_path, "load_timeseries_regional"))
        data["NIdata"] = data["Loaddata"][:, "NI"]
          # Candidate data
        println("Reading candidate resources...")
        data["Estoragedata_candidate"] = DataFrame(XLSX.readtable(excel_path, "storagedata_candidate"))
        data["Linedata_candidate"] = DataFrame(XLSX.readtable(excel_path, "linedata_candidate"))
        data["Gendata_candidate"] = DataFrame(XLSX.readtable(excel_path, "gendata_candidate"))
        
        # Policy data
        println("Reading policies...")
        data["CBPdata"] = DataFrame(XLSX.readtable(excel_path, "carbonpolicies"))
        data["RPSdata"] = DataFrame(XLSX.readtable(excel_path, "rpspolicies"))
        
        # Single parameters
        println("Reading single parameters...")
        data["Singlepar"] = DataFrame(XLSX.readtable(excel_path, "single_parameter"))
        
        # Optional demand response data
        if flexible_demand
            try
                data["DRdata"] = DataFrame(XLSX.readtable(excel_path, "flexddata"))
                data["DRtsdata"] = DataFrame(XLSX.readtable(excel_path, "dr_timeseries_regional"))
            catch e
                println("⚠️  Warning: Could not load demand response data: $e")
            end
        end
        
        println("✅ Excel files successfully loaded from $(reader.data_path)")
        
    else
        println("📄 Reading from CSV files...")
        
        # Network data
        println("Reading network data...")
        data["Zonedata"] = CSV.read(joinpath(reader.data_path, "zonedata.csv"), DataFrame)
        data["Linedata"] = CSV.read(joinpath(reader.data_path, "linedata.csv"), DataFrame)
        
        # Technology data
        println("Reading technology data...")
        gendata_raw = CSV.read(joinpath(reader.data_path, "gendata.csv"), DataFrame)
        data["Gendata"] = aggregated ? aggregate_gendata_gtep(gendata_raw) : gendata_raw
        data["Storagedata"] = CSV.read(joinpath(reader.data_path, "storagedata.csv"), DataFrame)
        
        # Time series data
        println("Reading time series...")
        data["Winddata"] = CSV.read(joinpath(reader.data_path, "wind_timeseries_regional.csv"), DataFrame)
        data["Solardata"] = CSV.read(joinpath(reader.data_path, "solar_timeseries_regional.csv"), DataFrame)
        data["Loaddata"] = CSV.read(joinpath(reader.data_path, "load_timeseries_regional.csv"), DataFrame)
        data["NIdata"] = data["Loaddata"][:, "NI"]
        
        # Candidate data
        println("Reading candidate resources...")
        data["Estoragedata_candidate"] = CSV.read(joinpath(reader.data_path, "storagedata_candidate.csv"), DataFrame)
        data["Linedata_candidate"] = CSV.read(joinpath(reader.data_path, "linedata_candidate.csv"), DataFrame)
        data["Gendata_candidate"] = CSV.read(joinpath(reader.data_path, "gendata_candidate.csv"), DataFrame)
        
        # Policy data
        println("Reading policies...")
        data["CBPdata"] = CSV.read(joinpath(reader.data_path, "carbonpolicies.csv"), DataFrame)
        data["RPSdata"] = CSV.read(joinpath(reader.data_path, "rpspolicies.csv"), DataFrame)
        
        # Single parameters
        println("Reading single parameters...")
        data["Singlepar"] = CSV.read(joinpath(reader.data_path, "single_parameter.csv"), DataFrame)
        
        # Optional demand response data
        if flexible_demand
            try
                data["DRdata"] = CSV.read(joinpath(reader.data_path, "flexddata.csv"), DataFrame)
                data["DRtsdata"] = CSV.read(joinpath(reader.data_path, "dr_timeseries_regional.csv"), DataFrame)
            catch e
                println("⚠️  Warning: Could not load demand response data: $e")
            end
        end
        
        println("✅ CSV files successfully loaded from $(reader.data_path)")
    end
    
    return data
end

"""
Load data for PCM mode with flexible Excel/CSV support
"""
function load_pcm_data(reader::HOPEDataReader, config::Dict)::Dict
    data = Dict()
    aggregated = get(config, "aggregated!", 0) == 1
    flexible_demand = get(config, "flexible_demand", 0) == 1
    
    if reader.use_excel
        println("📄 Reading from Excel file: $(reader.excel_file)")
        excel_path = joinpath(reader.data_path, reader.excel_file)
        
        # Network data
        println("Reading network data...")
        data["Zonedata"] = DataFrame(XLSX.readtable(excel_path, "zonedata"))
        data["Linedata"] = DataFrame(XLSX.readtable(excel_path, "linedata"))
        
        # Technology data
        println("Reading technology data...")
        gendata_raw = DataFrame(XLSX.readtable(excel_path, "gendata"))
        data["Gendata"] = aggregated ? aggregate_gendata_pcm(gendata_raw, config) : gendata_raw
        data["Storagedata"] = DataFrame(XLSX.readtable(excel_path, "storagedata"))
        
        # Time series data
        println("Reading time series...")
        data["Winddata"] = DataFrame(XLSX.readtable(excel_path, "wind_timeseries_regional"))
        data["Solardata"] = DataFrame(XLSX.readtable(excel_path, "solar_timeseries_regional"))
        data["Loaddata"] = DataFrame(XLSX.readtable(excel_path, "load_timeseries_regional"))
        data["NIdata"] = data["Loaddata"][:, "NI"]
        
        # Policy data
        println("Reading policies...")
        data["CBPdata"] = DataFrame(XLSX.readtable(excel_path, "carbonpolicies"))
        data["RPSdata"] = DataFrame(XLSX.readtable(excel_path, "rpspolicies"))
        
        # Single parameters
        println("Reading single parameters...")
        data["Singlepar"] = DataFrame(XLSX.readtable(excel_path, "single_parameter"))
        
        # Optional demand response data
        if flexible_demand
            try
                data["DRdata"] = DataFrame(XLSX.readtable(excel_path, "flexddata"))
                data["DRtsdata"] = DataFrame(XLSX.readtable(excel_path, "dr_timeseries_regional"))
            catch e
                println("⚠️  Warning: Could not load demand response data: $e")
            end
        end
        
        println("✅ Excel files successfully loaded from $(reader.data_path)")
        
    else
        println("📄 Reading from CSV files...")
        
        # Network data
        println("Reading network data...")
        data["Zonedata"] = CSV.read(joinpath(reader.data_path, "zonedata.csv"), DataFrame)
        data["Linedata"] = CSV.read(joinpath(reader.data_path, "linedata.csv"), DataFrame)
        
        # Technology data
        println("Reading technology data...")
        gendata_raw = CSV.read(joinpath(reader.data_path, "gendata.csv"), DataFrame)
        data["Gendata"] = aggregated ? aggregate_gendata_pcm(gendata_raw, config) : gendata_raw
        data["Storagedata"] = CSV.read(joinpath(reader.data_path, "storagedata.csv"), DataFrame)
        
        # Time series data
        println("Reading time series...")
        data["Winddata"] = CSV.read(joinpath(reader.data_path, "wind_timeseries_regional.csv"), DataFrame)
        data["Solardata"] = CSV.read(joinpath(reader.data_path, "solar_timeseries_regional.csv"), DataFrame)
        data["Loaddata"] = CSV.read(joinpath(reader.data_path, "load_timeseries_regional.csv"), DataFrame)
        data["NIdata"] = data["Loaddata"][:, "NI"]
        
        # Policy data
        println("Reading policies...")
        data["CBPdata"] = CSV.read(joinpath(reader.data_path, "carbonpolicies.csv"), DataFrame)
        data["RPSdata"] = CSV.read(joinpath(reader.data_path, "rpspolicies.csv"), DataFrame)
        
        # Single parameters
        println("Reading single parameters...")
        data["Singlepar"] = CSV.read(joinpath(reader.data_path, "single_parameter.csv"), DataFrame)
        
        # Optional demand response data
        if flexible_demand
            try
                data["DRdata"] = CSV.read(joinpath(reader.data_path, "flexddata.csv"), DataFrame)
                data["DRtsdata"] = CSV.read(joinpath(reader.data_path, "dr_timeseries_regional.csv"), DataFrame)
            catch e
                println("⚠️  Warning: Could not load demand response data: $e")
            end
        end
        
        println("✅ CSV files successfully loaded from $(reader.data_path)")
    end
    
    return data
end

"""
Load data for holistic mode (combines GTEP and PCM requirements)
"""
function load_holistic_data(reader::HOPEDataReader, config::Dict)::Dict
    # Start with GTEP data (more comprehensive)
    data = load_gtep_data(reader, config)
    
    # Add any additional PCM-specific requirements
    # This can be extended as needed
      return data
end

"""
Load case data and configuration (wrapper function for compatibility)
"""
function load_case_data(reader::HOPEDataReader, case_path::String)
    # Load configuration
    config_file = joinpath(case_path, "Settings", "HOPE_model_settings.yml")
    config = YAML.load_file(config_file)
    
    # Load data using the reader
    data = load_hope_data(reader, config)
    
    return data, config
end

# Export main functions and types
export HOPEDataReader, load_hope_data, load_case_data
export load_configuration, load_solver_configuration
export process_raw_data, validate_input_data

end # module DataReader
