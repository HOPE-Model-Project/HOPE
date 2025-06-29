#!/usr/bin/env julia
"""
Old PCM Benchmark Test - UC=2 (Convexified Unit Commitment)
==========================================================
Establishes baseline performance metrics for the old PCM
with UC=2 using MD_PCM_Excel_case.

This will create/update the benchmark results in BENCHMARK_RESULTS.md
"""

using Pkg
Pkg.activate(".")
using HOPE
using JuMP
using YAML
using Printf

const TEST_CASE = "MD_PCM_Excel_case"
const UC_SETTING = 2

function run_old_pcm_uc2_benchmark()
    println("🔍 OLD PCM BENCHMARK TEST - UC=2")
    println("=" ^ 50)
    println("📋 Test Case: $TEST_CASE") 
    println("🔧 Unit Commitment: $UC_SETTING (Convexified Unit Commitment)")
    println()

    case_path = joinpath("ModelCases", TEST_CASE)
    config_file = joinpath(case_path, "Settings", "HOPE_model_settings.yml")
    
    # Check current UC setting
    config = YAML.load_file(config_file)
    current_uc = get(config, "unit_commitment", "NOT_FOUND")
    println("📋 Current UC setting in config: $current_uc")
    
    if current_uc != UC_SETTING
        println("⚠️  Config UC setting ($current_uc) doesn't match test UC setting ($UC_SETTING)")
        println("   Please manually set unit_commitment: $UC_SETTING in the config file")
        return
    end
    
    println("✅ Config matches test setting")
    println()
    
    # Run old PCM
    println("🚀 Running old PCM with UC=$UC_SETTING...")
    start_time = time()
    
    try
        HOPE.run_hope(case_path)
        execution_time = time() - start_time
        
        println()
        println("✅ OLD PCM UC=2 BENCHMARK COMPLETED")
        println("=" ^ 50)
        println("📊 Execution Time: $(Printf.@sprintf("%.2f", execution_time)) seconds")
        println()
        println("� Please record the results above in BENCHMARK_RESULTS.md")
        
    catch e
        execution_time = time() - start_time
        println("❌ Error during UC=2 benchmark: $e")
        println("📊 Execution Time: $(Printf.@sprintf("%.2f", execution_time)) seconds")
        rethrow(e)
    end
    
    return nothing
end

# Run the benchmark
if abspath(PROGRAM_FILE) == @__FILE__
    println("Starting Old PCM UC=2 Benchmark...")
    run_old_pcm_uc2_benchmark()
end
