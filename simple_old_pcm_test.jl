#!/usr/bin/env julia
"""
Simple Old PCM Benchmark Test - UC=0
====================================
Run old PCM with current config (UC=0) to establish baseline
"""

using Pkg
Pkg.activate(".")
using HOPE
using Printf

const TEST_CASE = "MD_PCM_Excel_case"

function run_old_pcm_benchmark()
    println("🔍 OLD PCM BENCHMARK TEST")
    println("=" ^ 50)
    println("📋 Test Case: $TEST_CASE") 
    println("🔧 Current config will be used (should be UC=0)")
    println()

    case_path = joinpath("ModelCases", TEST_CASE)
    
    println("🚀 Running old PCM...")
    start_time = time()
    
    try
        HOPE.run_hope(case_path)
        execution_time = time() - start_time
        
        println()
        println("✅ OLD PCM BENCHMARK COMPLETED")
        println("=" ^ 50)
        println("📊 Execution Time: $(Printf.@sprintf("%.2f", execution_time)) seconds")
        println()
        println("💡 Results above should be recorded in BENCHMARK_RESULTS.md")
        
    catch e
        execution_time = time() - start_time
        println("❌ Error during benchmark: $e")
        println("📊 Execution Time: $(Printf.@sprintf("%.2f", execution_time)) seconds")
        rethrow(e)
    end
    
    return nothing
end

# Run the benchmark
if abspath(PROGRAM_FILE) == @__FILE__
    println("Starting Old PCM Benchmark...")
    run_old_pcm_benchmark()
end
