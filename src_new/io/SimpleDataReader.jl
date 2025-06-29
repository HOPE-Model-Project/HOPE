"""
# SimpleDataReader.jl - Direct port of old PCM data reading logic
# 
# This module replicates the exact data reading logic from the old PCM 
# to ensure identical data loading and parameter values.
"""

module SimpleDataReader

using DataFrames
using CSV
using XLSX
using YAML
using Statistics

export SimpleHOPEDataReader, load_simple_case_data

"""
Direct port of old PCM data aggregation functions
"""
function aggregate_gendata_pcm(df::DataFrame, config_set::Dict)
    if config_set["unit_commitment"] == 0
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
        .=>  [Symbol("Pmax (MW)"), Symbol("Pmin (MW)"), Symbol("Cost (\$/MWh)"),:EF,:CC,:FOR,:RM_SPIN,:RU,:RD,:Flag_thermal,:Flag_VRE,:Flag_mustrun])
        agg_df[agg_df.Flag_thermal .> 0, :Flag_thermal] .=1
        agg_df[agg_df.Flag_VRE .> 0, :Flag_VRE] .=1
        agg_df[agg_df.Flag_mustrun .> 0, :Flag_mustrun] .=1
        return agg_df
    else
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
        :Flag_UC .=> mean,
        :Flag_mustrun .=> mean,
        Symbol("Start_up_cost (\$/MW)") .=> mean,
        :Min_down_time .=> mean,
        :Min_up_time .=> mean
        )
        rename!(agg_df, [Symbol("Pmax (MW)_sum"), Symbol("Pmin (MW)_sum"),Symbol("Cost (\$/MWh)_mean"),:EF_mean,:CC_mean,:FOR_mean,:RM_SPIN_mean,:RU_mean,:RD_mean,:Flag_thermal_mean,:Flag_VRE_mean,:Flag_mustrun_mean,:Flag_UC_mean,Symbol("Start_up_cost (\$/MW)_mean"),:Min_down_time_mean,:Min_up_time_mean] 
        .=>  [Symbol("Pmax (MW)"), Symbol("Pmin (MW)"), Symbol("Cost (\$/MWh)"),:EF,:CC,:FOR,:RM_SPIN,:RU,:RD,:Flag_thermal,:Flag_VRE,:Flag_mustrun,:Flag_UC,Symbol("Start_up_cost (\$/MW)"),:Min_down_time,:Min_up_time])
        agg_df[agg_df.Flag_thermal .> 0, :Flag_thermal] .=1
        agg_df[agg_df.Flag_VRE .> 0, :Flag_VRE] .=1
        agg_df[agg_df.Flag_mustrun .> 0, :Flag_mustrun] .=1
        agg_df[agg_df.Flag_UC .> 0, :Flag_UC] .=1
        return agg_df
    end
end

"""
Simple data reader that exactly replicates old PCM data loading
"""
struct SimpleHOPEDataReader
    case_path::String
end

"""
Direct port of old PCM load_data function for PCM mode
"""
function load_simple_case_data(reader::SimpleHOPEDataReader, case_path::String)
    # Load configuration
    settings_file = joinpath(case_path, "Settings", "HOPE_model_settings.yml")
    if !isfile(settings_file)
        throw(ArgumentError("Settings file not found: $settings_file"))
    end
    
    config_set = YAML.load(open(settings_file))
    
    # Set default values to match old PCM
    config_set["model_mode"] = "PCM"
    if !haskey(config_set, "aggregated!")
        config_set["aggregated!"] = 0
    end
    if !haskey(config_set, "flexible_demand")
        config_set["flexible_demand"] = 0
    end
    
    # Extract DataCase
    Data_case = get(config_set, "DataCase", "Data_PCM2035/")
    Data_case = rstrip(Data_case, '/')  # Remove trailing slash
    
    # This is the EXACT logic from old PCM load_data function for PCM mode
    input_data = Dict()
    println("📊 Loading input data for PCM mode...")
    folderpath = joinpath(case_path, Data_case)
    files = readdir(folderpath)
    
    if any(endswith.(files, ".xlsx"))
        println("   Data source: Excel")
        println("📄 Reading from Excel file: PCM_input_total.xlsx")
        
        excel_path = joinpath(folderpath, "PCM_input_total.xlsx")
        if !isfile(excel_path)
            throw(ArgumentError("Excel file not found: $excel_path"))
        end
        
        # Network data
        println("Reading network data...")
        input_data["Zonedata"] = DataFrame(XLSX.readtable(excel_path, "zonedata"))
        input_data["Linedata"] = DataFrame(XLSX.readtable(excel_path, "linedata"))
        
        # Technology data
        println("Reading technology data...")
        if config_set["aggregated!"] == 1
            input_data["Gendata"] = aggregate_gendata_pcm(DataFrame(XLSX.readtable(excel_path, "gendata")), config_set)
        else
            input_data["Gendata"] = DataFrame(XLSX.readtable(excel_path, "gendata"))
        end
        
        input_data["Storagedata"] = DataFrame(XLSX.readtable(excel_path, "storagedata"))
        
        if config_set["flexible_demand"] == 1
            input_data["DRdata"] = DataFrame(XLSX.readtable(excel_path, "flexddata"))
        end
        
        # Time series data
        println("Reading time series...")
        input_data["Winddata"] = DataFrame(XLSX.readtable(excel_path, "wind_timeseries_regional"))
        input_data["Solardata"] = DataFrame(XLSX.readtable(excel_path, "solar_timeseries_regional"))
        input_data["Loaddata"] = DataFrame(XLSX.readtable(excel_path, "load_timeseries_regional"))
        input_data["NIdata"] = input_data["Loaddata"][:, "NI"]
        
        if config_set["flexible_demand"] == 1
            input_data["DRtsdata"] = DataFrame(XLSX.readtable(excel_path, "dr_timeseries_regional"))
        end
        
        # Policy data
        println("Reading policies...")
        input_data["CBPdata"] = DataFrame(XLSX.readtable(excel_path, "carbonpolicies"))
        input_data["RPSdata"] = DataFrame(XLSX.readtable(excel_path, "rpspolicies"))
        
        # Single parameters
        println("Reading single parameters...")
        input_data["Singlepar"] = DataFrame(XLSX.readtable(excel_path, "single_parameter"))
        
        println("✅ Excel files successfully loaded from $folderpath")
        
    else
        println("   Data source: CSV")
        println("📄 Reading from CSV files...")
        
        # Network data
        println("Reading network data...")
        input_data["Zonedata"] = CSV.read(joinpath(folderpath, "zonedata.csv"), DataFrame)
        input_data["Linedata"] = CSV.read(joinpath(folderpath, "linedata.csv"), DataFrame)
        
        # Technology data
        println("Reading technology data...")
        if config_set["aggregated!"] == 1
            input_data["Gendata"] = aggregate_gendata_pcm(CSV.read(joinpath(folderpath, "gendata.csv"), DataFrame), config_set)
        else
            input_data["Gendata"] = CSV.read(joinpath(folderpath, "gendata.csv"), DataFrame)
        end
        
        input_data["Storagedata"] = CSV.read(joinpath(folderpath, "storagedata.csv"), DataFrame)
        
        if config_set["flexible_demand"] == 1
            input_data["DRdata"] = CSV.read(joinpath(folderpath, "flexddata.csv"), DataFrame)
        end
        
        # Time series data
        println("Reading time series...")
        input_data["Winddata"] = CSV.read(joinpath(folderpath, "wind_timeseries_regional.csv"), DataFrame)
        input_data["Solardata"] = CSV.read(joinpath(folderpath, "solar_timeseries_regional.csv"), DataFrame)
        input_data["Loaddata"] = CSV.read(joinpath(folderpath, "load_timeseries_regional.csv"), DataFrame)
        input_data["NIdata"] = input_data["Loaddata"][:, "NI"]
        
        if config_set["flexible_demand"] == 1
            input_data["DRtsdata"] = CSV.read(joinpath(folderpath, "dr_timeseries_regional.csv"), DataFrame)
        end
        
        # Policy data
        println("Reading policies...")
        input_data["CBPdata"] = CSV.read(joinpath(folderpath, "carbonpolicies.csv"), DataFrame)
        input_data["RPSdata"] = CSV.read(joinpath(folderpath, "rpspolicies.csv"), DataFrame)
        
        # Single parameters
        println("Reading single parameters...")
        input_data["Singlepar"] = CSV.read(joinpath(folderpath, "single_parameter.csv"), DataFrame)
        
        println("✅ CSV files successfully loaded from $folderpath")
    end
    
    return input_data, config_set
end

end # module
