"""
# DataReader.jl - Standardized Data Loading System
# 
# This module provides unified data loading capabilities for HOPE models,
# handling CSV, Excel, and other data formats with validation and preprocessing.
"""

using DataFrames
using CSV
using XLSX
using YAML

"""
Data reader structure for managing input data loading
"""
struct HOPEDataReader
    case_path::String
    data_path::String
    settings_path::String
    
    function HOPEDataReader(case_path::String)
        data_path = joinpath(case_path, "Data_100RPS")  # Default data folder
        if !isdir(data_path)
            data_path = joinpath(case_path, "Data_PCM2035")
        end
        if !isdir(data_path)
            data_path = joinpath(case_path, "Data_PJM_GTEP_subzones")
        end
        if !isdir(data_path)
            data_path = joinpath(case_path, "Data_PJM_PCM_subzones")
        end
        
        settings_path = joinpath(case_path, "Settings")
        
        new(case_path, data_path, settings_path)
    end
end

"""
Main data loading function with validation and preprocessing
"""
function load_hope_data(reader::HOPEDataReader)::Dict
    println("📂 Loading HOPE data from: $(reader.case_path)")
    
    # Load configuration
    config = load_configuration(reader)
    
    # Load all data tables
    data = Dict{String, Any}()
    
    # Core network and technology data
    data["Zonedata"] = load_zone_data(reader)
    data["Linedata"] = load_line_data(reader)
    data["Gendata"] = load_generator_data(reader)
    data["Storagedata"] = load_storage_data(reader)
    
    # Time series data
    data["Loaddata"] = load_load_timeseries(reader)
    data["Winddata"] = load_wind_timeseries(reader)
    data["Solardata"] = load_solar_timeseries(reader)
    data["NIdata"] = load_net_interchange_data(reader)
    
    # Policy data
    data["CBPdata"] = load_carbon_policy_data(reader)
    data["RPSdata"] = load_rps_policy_data(reader)
    
    # Single parameters
    data["Singlepar"] = load_single_parameters(reader)
    
    # Load candidate data for GTEP mode
    if config["model_mode"] == "GTEP"
        data["Gendata_candidate"] = load_candidate_generator_data(reader)
        data["Linedata_candidate"] = load_candidate_line_data(reader)
        data["Estoragedata_candidate"] = load_candidate_storage_data(reader)
    end
    
    # Load demand response data if enabled
    if get(config, "flexible_demand", false)
        data["Flexddata"] = load_demand_response_data(reader)
    end
    
    # Process and validate data
    processed_data = process_raw_data(data, config)
    validated_data = validate_input_data(processed_data, config)
    
    println("✅ Data loading completed successfully")
    print_data_summary(validated_data)
    
    return validated_data
end

"""
Load model configuration from YAML settings
"""
function load_configuration(reader::HOPEDataReader)::Dict
    settings_file = joinpath(reader.settings_path, "HOPE_model_settings.yml")
    
    if !isfile(settings_file)
        throw(ArgumentError("Settings file not found: $settings_file"))
    end
    
    config = YAML.load(open(settings_file))
    
    # Validate required settings
    required_settings = ["model_mode", "solver"]
    for setting in required_settings
        if !haskey(config, setting)
            throw(ArgumentError("Required setting missing: $setting"))
        end
    end
    
    # Set default values for optional settings
    defaults = Dict(
        "unit_commitment" => 0,
        "flexible_demand" => 0,
        "generator_retirement" => 0,
        "investment_binary" => 1,
        "debug" => 0,
        "target_year" => 2035
    )
    
    for (key, default_value) in defaults
        if !haskey(config, key)
            config[key] = default_value
        end
    end
    
    return config
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
    
    # Create index sets from data
    processed["I"] = unique(data["Zonedata"][!, :Zone])  # Zones
    processed["W"] = unique(data["Zonedata"][!, :State])  # States (if available)
    if isempty(processed["W"])
        processed["W"] = ["State1"]  # Default state
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

# Export main functions and types
export HOPEDataReader, load_hope_data
export load_configuration, process_raw_data, validate_input_data
