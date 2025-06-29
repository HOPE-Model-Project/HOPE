#!/usr/bin/env julia

"""
Old PCM Baseline Test (UC=0)
============================
This test runs the OLD PCM (src/PCM.jl) with UC=0 to establish 
the baseline benchmark results for MD_PCM_Excel_case.

This is the reference implementation that the new PCM should match.
"""

using Pkg
Pkg.activate(".")

using HOPE
using JuMP

# Test configuration
const TEST_CASE = "MD_PCM_Excel_case"
const UC_SETTING = 0  # No Unit Commitment
const SOLVER_NAME = "gurobi"

println("="^70)
println("🔍 OLD PCM BASELINE TEST (UC=$UC_SETTING)")
println("="^70)
println("📋 Test Case: $TEST_CASE")
println("🔧 Unit Commitment: $UC_SETTING (disabled)")
println("⚙️  Solver: $SOLVER_NAME")
println("🎯 Goal: Establish baseline benchmark for comparison")
println()

# Test case path validation
case_path = joinpath("ModelCases", TEST_CASE)
if !isdir(case_path)
    println("❌ ERROR: Test case directory not found: $case_path")
    exit(1)
end

println("📁 Case Path: $case_path")
println("📂 Contents:")
for item in readdir(case_path)
    item_path = joinpath(case_path, item)
    if isdir(item_path)
        println("   📁 $item/")
    else
        println("   📄 $item")
    end
end
println()

# Storage for results
results = Dict()

"""Run the old PCM and capture detailed results"""
function run_old_pcm_baseline()
    println("🚀 RUNNING OLD PCM BASELINE TEST")
    println("   📈 Starting execution...")
    
    success = false
    
    try
        start_time = time()
        
        # Run the old PCM with explicit case path
        println("   🔧 Calling HOPE.run_hope(\"$case_path\")")
        result = HOPE.run_hope(case_path)
        
        execution_time = time() - start_time
        results["execution_time"] = execution_time
        
        println("   ⏱️  Execution time: $(round(execution_time, digits=2)) seconds")
        
        # Analyze the result
        println("\n📊 ANALYZING RESULTS:")
        println("   Result type: $(typeof(result))")
        
        if isa(result, Dict)
            println("   Result keys: $(collect(keys(result)))")
            
            # Check for model object - the run_hope function returns "solved_model" key
            if haskey(result, "solved_model") && result["solved_model"] !== nothing
                model = result["solved_model"]
                println("   ✅ Model object found")
                
                # Get model statistics
                results["num_variables"] = JuMP.num_variables(model)
                results["num_constraints"] = JuMP.num_constraints(model; count_variable_in_set_constraints=false)
                
                println("   📊 Variables: $(results["num_variables"])")
                println("   📊 Constraints: $(results["num_constraints"])")
                
                # Get solver status
                try
                    status = JuMP.termination_status(model)
                    results["termination_status"] = status
                    println("   🎯 Termination Status: $status")
                catch e
                    println("   ⚠️  Could not get termination status: $e")
                end
                
                # Get objective value
                try
                    obj_val = JuMP.objective_value(model)
                    results["objective_value"] = obj_val
                    println("   💰 Objective Value: \$$(round(obj_val, digits=2))")
                    
                    # Break down objective components if available
                    try
                        if haskey(model.obj_dict, :OPCost)
                            op_cost = JuMP.value(model[:OPCost])
                            results["operation_cost"] = op_cost
                            println("   💸 Operation Cost: \$$(round(op_cost, digits=2))")
                        end
                        
                        if haskey(model.obj_dict, :LoadShedding)
                            load_shed = JuMP.value(model[:LoadShedding])
                            results["load_shedding"] = load_shed
                            println("   ⚡ Load Shedding: \$$(round(load_shed, digits=2))")
                        end
                        
                        if haskey(model.obj_dict, :RPSPenalty)
                            rps_penalty = JuMP.value(model[:RPSPenalty])
                            results["rps_penalty"] = rps_penalty
                            println("   🌱 RPS Penalty: \$$(round(rps_penalty, digits=2))")
                        end
                        
                        if haskey(model.obj_dict, :CarbonCapPenalty)
                            carbon_penalty = JuMP.value(model[:CarbonCapPenalty])
                            results["carbon_penalty"] = carbon_penalty
                            println("   🌍 Carbon Penalty: \$$(round(carbon_penalty, digits=2))")
                        end
                    catch e
                        println("   ⚠️  Could not get objective components: $e")
                    end
                    
                catch e
                    println("   ⚠️  Could not retrieve objective value: $e")
                end
                
                # Get primal status
                try
                    primal_status = JuMP.primal_status(model)
                    results["primal_status"] = primal_status
                    println("   ✅ Primal Status: $primal_status")
                catch e
                    println("   ⚠️  Could not get primal status: $e")
                end
                
                success = true
                results["status"] = "SUCCESS"
                
            else
                println("   ❌ No model object found in result")
                results["status"] = "NO_MODEL"
            end
            
        else
            println("   ❌ Result is not a dictionary")
            results["status"] = "INVALID_RESULT"
        end
        
    catch e
        execution_time = time() - start_time
        results["execution_time"] = execution_time
        results["status"] = "FAILED"
        results["error"] = string(e)
        
        println("   ❌ OLD PCM FAILED after $(round(execution_time, digits=2)) seconds")
        println("   Error type: $(typeof(e))")
        println("   Error message: $e")
        
        # Print stack trace for debugging
        println("\n📋 Stack Trace:")
        for (i, frame) in enumerate(stacktrace(catch_backtrace()))
            println("   $i. $frame")
            if i > 10  # Limit stack trace length
                println("   ... (truncated)")
                break
            end
        end
    end
    
    return success
end

"""Generate baseline benchmark report"""
function generate_baseline_report(success)
    println("\n" * "="^70)
    println("📋 OLD PCM BASELINE BENCHMARK REPORT")
    println("="^70)
    
    if success
        println("🎉 OLD PCM BASELINE ESTABLISHED!")
        println("✅ Model solved successfully")
        
        println("\n📊 BENCHMARK METRICS:")
        println("   Test Case: $TEST_CASE")
        println("   Unit Commitment: UC=$UC_SETTING")
        println("   Execution Time: $(round(get(results, "execution_time", 0.0), digits=2)) seconds")
        println("   Status: $(get(results, "status", "UNKNOWN"))")
        
        if haskey(results, "num_variables")
            println("   Variables: $(results["num_variables"])")
        end
        if haskey(results, "num_constraints")
            println("   Constraints: $(results["num_constraints"])")
        end
        if haskey(results, "termination_status")
            println("   Termination: $(results["termination_status"])")
        end
        if haskey(results, "primal_status")
            println("   Primal Status: $(results["primal_status"])")
        end
        if haskey(results, "objective_value")
            println("   💰 Total Cost: \$$(round(results["objective_value"], digits=2))")
        end
        
        # Detailed cost breakdown
        if haskey(results, "operation_cost")
            println("   💸 Operation Cost: \$$(round(results["operation_cost"], digits=2))")
        end
        if haskey(results, "load_shedding")
            println("   ⚡ Load Shedding: \$$(round(results["load_shedding"], digits=2))")
        end
        if haskey(results, "rps_penalty")
            println("   🌱 RPS Penalty: \$$(round(results["rps_penalty"], digits=2))")
        end
        if haskey(results, "carbon_penalty")
            println("   🌍 Carbon Penalty: \$$(round(results["carbon_penalty"], digits=2))")
        end
        
    else
        println("❌ OLD PCM BASELINE FAILED!")
        println("💥 Could not establish baseline benchmark")
        println("🔧 Check error details above")
        
        println("\n📊 FAILURE INFO:")
        println("   Status: $(get(results, "status", "UNKNOWN"))")
        if haskey(results, "error")
            println("   Error: $(results["error"])")
        end
    end
    
    println("\n🎯 NEXT STEPS:")
    if success
        println("   1. ✅ Baseline established for UC=$UC_SETTING")
        println("   2. 📝 Record these metrics for new PCM comparison")
        println("   3. 🚀 Ready to test new PCM against this baseline")
    else
        println("   1. 🔧 Fix issues with old PCM execution")
        println("   2. 🔍 Check case data and configuration")
        println("   3. 🧪 Rerun baseline test")
    end
    
    println("="^70)
    
    return success
end

# Main execution
println("🔄 Starting Old PCM Baseline Test...")
println("📈 Julia version: $(VERSION)")
println()

# Run the baseline test
baseline_success = run_old_pcm_baseline()

# Generate the report
final_result = generate_baseline_report(baseline_success)

# Save results to file for later comparison
if baseline_success
    results_file = "old_pcm_uc0_baseline_results.json"
    try
        using JSON
        open(results_file, "w") do f
            JSON.print(f, results, 2)
        end
        println("\n💾 Baseline results saved to: $results_file")
    catch e
        println("\n⚠️  Could not save results to file: $e")
    end
end

# Exit with appropriate code
if final_result
    println("\n🎊 SUCCESS: Old PCM baseline established!")
    exit(0)
else
    println("\n💥 FAILED: Could not establish baseline!")
    exit(1)
end
