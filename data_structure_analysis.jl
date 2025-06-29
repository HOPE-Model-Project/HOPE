"""
Data Structure Analysis - Compare Old vs New PCM Data Organization
================================================================
Goal: Understand exactly how parameters are structured differently
between old and new data loading systems
"""

using Pkg
Pkg.activate(".")

# Load modules
include("src/HOPE.jl")
using .HOPE

include("src_new/HOPE_New.jl")
using .HOPE_New

function analyze_data_structures()
    println("🔍 DATA STRUCTURE ANALYSIS")
    println("="^80)
    println("Understanding parameter organization differences")
    println()
    
    case_folder = "ModelCases/MD_PCM_Excel_case"
    
    # Load with NEW system
    println("📊 Loading data with NEW system...")
    new_reader = HOPE_New.SimpleHOPEDataReader(case_folder)
    new_input_data, new_config = HOPE_New.load_simple_case_data(new_reader, case_folder)
    
    # Load with OLD system  
    println("📊 Loading data with OLD system...")
    old_config_file = joinpath(case_folder, "Settings", "HOPE_model_settings.yml")
    old_config = YAML.load_file(old_config_file)
    old_input_data = HOPE.load_data(old_config, case_folder)
    
    println("\n🔍 DATA STRUCTURE COMPARISON")
    println("="^50)
    
    # Compare top-level keys
    println("\n📋 Top-level data keys:")
    println("   OLD data keys: $(sort(collect(keys(old_input_data))))")
    println("   NEW data keys: $(sort(collect(keys(new_input_data))))")
    
    # Analyze generator parameters
    analyze_generator_parameters(old_input_data, new_input_data)
    
    # Analyze load parameters
    analyze_load_parameters(old_input_data, new_input_data)
    
    # Analyze transmission parameters
    analyze_transmission_parameters(old_input_data, new_input_data)
    
    # Analyze storage parameters
    analyze_storage_parameters(old_input_data, new_input_data)
end

function analyze_generator_parameters(old_data, new_data)
    println("\n🔧 GENERATOR PARAMETER ANALYSIS")
    println("="^40)
    
    # Look for generator-related keys
    old_gen_keys = filter(k -> contains(string(k), "gen") || contains(string(k), "G") || contains(string(k), "P_"), keys(old_data))
    new_gen_keys = filter(k -> contains(string(k), "gen") || contains(string(k), "G") || contains(string(k), "P_"), keys(new_data))
    
    println("   OLD generator-related keys: $old_gen_keys")
    println("   NEW generator-related keys: $new_gen_keys")
    
    # Check specific parameters
    parameters_to_check = ["P_max", "P_min", "VCG", "gendata", "technology"]
    
    for param in parameters_to_check
        old_has = haskey(old_data, param)
        new_has = haskey(new_data, param)
        
        if old_has && new_has
            println("   ✅ $param: Both have it")
            old_type = typeof(old_data[param])
            new_type = typeof(new_data[param])
            println("      OLD type: $old_type, NEW type: $new_type")
            
            if old_type != new_type
                println("      ⚠️ Type mismatch!")
            end
            
        elseif old_has
            println("   ❌ $param: Only OLD has it (type: $(typeof(old_data[param])))")
        elseif new_has
            println("   ❌ $param: Only NEW has it (type: $(typeof(new_data[param])))")
        else
            println("   ❌ $param: Neither has it")
        end
    end
end

function analyze_load_parameters(old_data, new_data)
    println("\n💡 LOAD PARAMETER ANALYSIS")
    println("="^40)
    
    # Look for load-related keys
    old_load_keys = filter(k -> contains(string(k), "load") || contains(string(k), "Load") || contains(string(k), "demand"), keys(old_data))
    new_load_keys = filter(k -> contains(string(k), "load") || contains(string(k), "Load") || contains(string(k), "demand"), keys(new_data))
    
    println("   OLD load-related keys: $old_load_keys")
    println("   NEW load-related keys: $new_load_keys")
    
    # Check specific parameters
    load_parameters = ["P_load", "load_timeseries", "zonedata"]
    
    for param in load_parameters
        old_has = haskey(old_data, param)
        new_has = haskey(new_data, param)
        
        if old_has && new_has
            println("   ✅ $param: Both have it")
            
            # Check structure
            if isa(old_data[param], Dict) && isa(new_data[param], Dict)
                old_keys = collect(keys(old_data[param]))
                new_keys = collect(keys(new_data[param]))
                println("      OLD sub-keys: $(old_keys[1:min(3, length(old_keys))])...")
                println("      NEW sub-keys: $(new_keys[1:min(3, length(new_keys))])...")
            end
            
        elseif old_has
            println("   ❌ $param: Only OLD has it")
        elseif new_has
            println("   ❌ $param: Only NEW has it")
        else
            println("   ❌ $param: Neither has it")
        end
    end
end

function analyze_transmission_parameters(old_data, new_data)
    println("\n🌐 TRANSMISSION PARAMETER ANALYSIS")
    println("="^40)
    
    # Look for transmission-related keys
    old_trans_keys = filter(k -> contains(string(k), "line") || contains(string(k), "trans") || contains(string(k), "F_"), keys(old_data))
    new_trans_keys = filter(k -> contains(string(k), "line") || contains(string(k), "trans") || contains(string(k), "F_"), keys(new_data))
    
    println("   OLD transmission-related keys: $old_trans_keys")
    println("   NEW transmission-related keys: $new_trans_keys")
end

function analyze_storage_parameters(old_data, new_data)
    println("\n🔋 STORAGE PARAMETER ANALYSIS")
    println("="^40)
    
    # Look for storage-related keys
    old_storage_keys = filter(k -> contains(string(k), "storage") || contains(string(k), "SCAP") || contains(string(k), "soc"), keys(old_data))
    new_storage_keys = filter(k -> contains(string(k), "storage") || contains(string(k), "SCAP") || contains(string(k), "soc"), keys(new_data))
    
    println("   OLD storage-related keys: $old_storage_keys")
    println("   NEW storage-related keys: $new_storage_keys")
end

# Run the analysis
if abspath(PROGRAM_FILE) == @__FILE__
    analyze_data_structures()
end
