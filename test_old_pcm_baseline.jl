#!/usr/bin/env julia
"""
Old PCM Baseline Test for MD_PCM_Excel_case UC=0
===============================================
This test establishes the baseline performance metrics for the old PCM
with UC=0 (no unit commitment) using MD_PCM_Excel_case.
"""

using Pkg
Pkg.activate(".")
using HOPE
using JuMP

const TEST_CASE = "MD_PCM_Excel_case"
const UC_SETTING = 0

println("🔍 OLD PCM BASELINE TEST")
println("=" ^ 50)
println("📋 Test Case: $TEST_CASE") 
println("🔧 Unit Commitment: $UC_SETTING")

case_path = joinpath("ModelCases", TEST_CASE)

try
    println("🚀 Running old PCM...")
    
    # Temporarily modify the configuration file to set UC=0
    config_file = joinpath(case_path, "Settings", "HOPE_model_settings.yml")
    
    # Read the original config
    using YAML
    original_config = YAML.load_file(config_file)
    println("📋 Original UC setting: $(original_config["unit_commitment"])")
    
    # Create backup and modify config
    backup_file = config_file * ".backup"
    cp(config_file, backup_file)
    
    # Set UC=0 and save
    modified_config = copy(original_config)
    modified_config["unit_commitment"] = UC_SETTING
    YAML.write_file(config_file, modified_config)
    println("📋 Temporarily set UC to: $UC_SETTING")
    
    start_time = time()
    result = HOPE.run_hope(case_path)
    execution_time = time() - start_time
    
    # Restore original config
    rm(config_file)
    mv(backup_file, config_file)
    println("📋 Restored original configuration")
    
    if haskey(result, "solved_model") && result["solved_model"] !== nothing
        model = result["solved_model"]
        
        # Get metrics
        obj_val = JuMP.objective_value(model)
        num_vars = JuMP.num_variables(model)
        num_cons = JuMP.num_constraints(model; count_variable_in_set_constraints=false)
        
        println("✅ OLD PCM BASELINE RESULTS:")
        println("   💰 Objective Value: \$$(round(obj_val, digits=2))")
        println("   📊 Variables: $num_vars")
        println("   📊 Constraints: $num_cons")
        println("   ⏱️  Execution Time: $(round(execution_time, digits=2)) seconds")
        
        # Store results for BENCHMARK_RESULTS.md
        global baseline_results = Dict(
            "objective_value" => obj_val,
            "num_variables" => num_vars,
            "num_constraints" => num_cons,
            "execution_time" => execution_time,
            "status" => "SUCCESS"
        )
        
    else
        println("❌ Could not extract model from result")
        exit(1)
    end
    
catch e
    println("❌ Old PCM failed: $e")
    exit(1)
end

println("✅ Baseline established successfully!")
