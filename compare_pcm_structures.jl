#!/usr/bin/env julia
# Compare variable and constraint counts between old and new PCM

using Pkg
Pkg.activate(".")

# Import both old and new frameworks
using HOPE
include("src_new/HOPE_New.jl")
using .HOPE_New

using JuMP
using YAML
using Gurobi

function compare_pcm_structures()
    println("🔍 PCM Structure Comparison")
    println("=" ^ 60)
    
    case_path = "ModelCases/MD_PCM_Excel_case"
    
    # Configuration for UC=0
    config_override = Dict(
        "model" => "PCM",
        "unit_commitment" => 0,
        "Demand_response" => 0
    )
    
    println("📊 Building NEW PCM model...")
    # Create new PCM model
    reader = HOPE_New.SimpleHOPEDataReader(case_path)
    input_data, config = HOPE_New.load_simple_case_data(reader, case_path)
    merge!(config, config_override)
    
    time_manager = HOPE_New.HOPETimeManager()
    HOPE_New.setup_time_structure!(time_manager, input_data, config)
    
    gurobi_optimizer = Gurobi.Optimizer()
    pcm_model = HOPE_New.PCM.PCMModel()
    HOPE_New.PCM.build_pcm_model!(pcm_model, input_data, config, time_manager, gurobi_optimizer)
    
    new_model = pcm_model.model
    new_vars = JuMP.num_variables(new_model)
    new_cons = JuMP.num_constraints(new_model; count_variable_in_set_constraints=false)
    
    println("   Variables: $new_vars")
    println("   Constraints: $new_cons")
    
    # Analyze new PCM variable types
    all_new_vars = JuMP.all_variables(new_model)
    new_var_types = Dict{String, Int}()
    
    for var in all_new_vars
        var_str = string(var)
        if startswith(var_str, "power_generation[")
            new_var_types["power_generation"] = get(new_var_types, "power_generation", 0) + 1
        elseif startswith(var_str, "charging_power[")
            new_var_types["charging_power"] = get(new_var_types, "charging_power", 0) + 1
        elseif startswith(var_str, "discharging_power[")
            new_var_types["discharging_power"] = get(new_var_types, "discharging_power", 0) + 1
        elseif startswith(var_str, "state_of_charge[")
            new_var_types["state_of_charge"] = get(new_var_types, "state_of_charge", 0) + 1
        elseif startswith(var_str, "transmission_flow[")
            new_var_types["transmission_flow"] = get(new_var_types, "transmission_flow", 0) + 1
        elseif startswith(var_str, "spinning_reserve_gen[")
            new_var_types["spinning_reserve_gen"] = get(new_var_types, "spinning_reserve_gen", 0) + 1
        elseif startswith(var_str, "spinning_reserve_storage[")
            new_var_types["spinning_reserve_storage"] = get(new_var_types, "spinning_reserve_storage", 0) + 1
        elseif startswith(var_str, "load_shedding[")
            new_var_types["load_shedding"] = get(new_var_types, "load_shedding", 0) + 1
        elseif contains(var_str, "rps")
            new_var_types["rps_related"] = get(new_var_types, "rps_related", 0) + 1
        elseif contains(var_str, "emission")
            new_var_types["emission_related"] = get(new_var_types, "emission_related", 0) + 1
        else
            new_var_types["other"] = get(new_var_types, "other", 0) + 1
        end
    end
    
    println("\\n📋 NEW PCM Variable Breakdown:")
    total_check = 0
    for (var_type, count) in sort(collect(new_var_types))
        println("   $var_type: $count")
        total_check += count
    end
    println("   TOTAL: $total_check (should equal $new_vars)")
    
    # Analyze constraints
    println("\\n📋 NEW PCM Constraint Analysis:")
    all_new_cons = JuMP.all_constraints(new_model; include_variable_in_set_constraints=false)
    println("   Total constraint references: $(length(all_new_cons))")
    
    # Expected variable counts based on sets
    sets = pcm_model.sets
    println("\\n📊 SET SIZES:")
    println("   G (Generators): $(length(sets["G"]))")
    println("   I (Zones): $(length(sets["I"]))")
    println("   S (Storage): $(length(sets["S"]))")
    println("   L (Lines): $(length(sets["L"]))")
    println("   H (Hours): $(length(sets["H"]))")
    println("   W (States): $(length(sets["W"]))")
    
    # Calculate expected minimums
    expected_p = length(sets["G"]) * length(sets["H"])
    expected_storage = length(sets["S"]) * length(sets["H"]) * 3  # c, dc, soc
    expected_transmission = length(sets["L"]) * length(sets["H"])
    expected_reserves = (length(sets["G"]) + length(sets["S"])) * length(sets["H"])
    expected_load_shed = length(sets["I"]) * length(sets["H"])
    
    println("\\n🧮 EXPECTED VARIABLE COUNTS:")
    println("   Power generation (G×H): $expected_p")
    println("   Storage (S×H×3): $expected_storage")
    println("   Transmission (L×H): $expected_transmission")
    println("   Reserves ((G+S)×H): $expected_reserves")
    println("   Load shedding (I×H): $expected_load_shed")
    
    expected_core = expected_p + expected_storage + expected_transmission + expected_reserves + expected_load_shed
    println("   Core variables subtotal: $expected_core")
    println("   Additional (RPS, emissions, etc): $(new_vars - expected_core)")
    
    return pcm_model
end

# Run the comparison
try
    compare_pcm_structures()
    println("\\n✅ Structure comparison completed")
catch e
    println("❌ Error: $e")
    rethrow(e)
end
