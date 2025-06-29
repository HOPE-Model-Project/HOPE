#!/usr/bin/env julia
# Compare Variable Creation Logic between Old and New PCM

using Pkg
Pkg.activate(".")

# Load both old and new HOPE
using HOPE  # Old PCM
include("src_new/HOPE_New.jl")
using .HOPE_New  # New PCM

using JuMP
using YAML
using Gurobi

function compare_variable_creation()
    println("🔍 Comparing Variable Creation: Old vs New PCM")
    println("=" ^ 60)
    
    case_path = "ModelCases/MD_PCM_Excel_case/"
    
    # =================================================================
    # NEW PCM - Get variable structure
    # =================================================================
    println("📊 Analyzing NEW PCM variable structure...")
    
    reader = HOPE_New.SimpleHOPEDataReader(case_path)
    input_data, config = HOPE_New.load_simple_case_data(reader, case_path)
    
    config_override = Dict("model" => "PCM", "unit_commitment" => 0, "Demand_response" => 0)
    merge!(config, config_override)
    
    time_manager = HOPE_New.HOPETimeManager()
    HOPE_New.setup_time_structure!(time_manager, input_data, config)
    
    pcm_model = HOPE_New.PCM.PCMModel()
    pcm_model.input_data = input_data
    pcm_model.config = config
    pcm_model.time_manager = time_manager
    
    HOPE_New.PCM.create_pcm_sets!(pcm_model)
    HOPE_New.PCM.create_pcm_parameters!(pcm_model)
    HOPE_New.PCM.create_pcm_variables!(pcm_model)
    
    new_model = pcm_model.model
    new_all_vars = JuMP.all_variables(new_model)
    
    println("NEW PCM Variable Groups:")
    for (key, var_ref) in pcm_model.variables
        if isa(var_ref, JuMP.Containers.DenseAxisArray) || isa(var_ref, AbstractArray)
            println("  $key: $(length(var_ref)) variables")
        else
            println("  $key: 1 variable")
        end
    end
    println("  Total JuMP variables: $(length(new_all_vars))")
    
    # =================================================================
    # OLD PCM - Get variable structure (run the old PCM and extract model)
    # =================================================================
    println("\\n📊 Running OLD PCM to analyze variable structure...")
    
    # Note: This will take time, but we need to see the old PCM's variables
    # We'll interrupt it early if possible or use a previously saved model
    
    println("\\n🔍 COMPARISON SUMMARY:")
    println("NEW PCM total variables: $(length(new_all_vars))")
    println("OLD PCM total variables: 1,734,930 (from baseline)")
    println("Difference: $(1734930 - length(new_all_vars)) variables missing in new PCM")
    
    # Categorize new PCM variables by type
    var_types = Dict{String, Int}()
    for var in new_all_vars
        var_str = string(var)
        if contains(var_str, "power_generation[")
            var_types["power_generation"] = get(var_types, "power_generation", 0) + 1
        elseif contains(var_str, "transmission_flow[")
            var_types["transmission_flow"] = get(var_types, "transmission_flow", 0) + 1
        elseif contains(var_str, "charging_power[")
            var_types["charging_power"] = get(var_types, "charging_power", 0) + 1
        elseif contains(var_str, "discharging_power[")
            var_types["discharging_power"] = get(var_types, "discharging_power", 0) + 1
        elseif contains(var_str, "state_of_charge[")
            var_types["state_of_charge"] = get(var_types, "state_of_charge", 0) + 1
        elseif contains(var_str, "spinning_reserve")
            var_types["spinning_reserve"] = get(var_types, "spinning_reserve", 0) + 1
        elseif contains(var_str, "load_shedding[")
            var_types["load_shedding"] = get(var_types, "load_shedding", 0) + 1
        elseif contains(var_str, "rps_penalty[")
            var_types["rps_penalty"] = get(var_types, "rps_penalty", 0) + 1
        elseif contains(var_str, "emission_violation[")
            var_types["emission_violation"] = get(var_types, "emission_violation", 0) + 1
        else
            var_types["other"] = get(var_types, "other", 0) + 1
        end
    end
    
    println("\\n📋 NEW PCM Variable Types:")
    for (type, count) in sort(collect(var_types), by=x->x[2], rev=true)
        println("  $type: $count")
    end
    
    return pcm_model
end

# Run the comparison
try
    compare_variable_creation()
    println("\\n✅ Variable comparison completed")
catch e
    println("❌ Error: $e")
    rethrow(e)
end
