#!/usr/bin/env julia
"""
New PCM Validation Test - UC=0 (No Unit Commitment)
==================================================
Tests the new ConstraintPool-based PCM implementation against 
the old PCM baseline for UC=0.

Target: MD_PCM_Excel_case with UC=2
Expected Results (from BENCHMARK_RESULTS.md):
- Objective Value: 5.070470565979868e17
- Variables: 2,050,290
- Constraints: 2,645,324
- Status: Optimal
- Execution Time: 3,322.58 seconds
"""

using Pkg
Pkg.activate(".")

# Import the new HOPE framework
include("src_new/HOPE_New.jl")
using .HOPE_New

using Printf
using JuMP
using YAML
using Gurobi

const TEST_CASE = "MD_PCM_Excel_case"
const UC_SETTING = 0

# Old PCM benchmark values for UC=0
const BENCHMARK_OBJECTIVE = 5.070470565979917e17
const BENCHMARK_VARIABLES = 1472130
const BENCHMARK_CONSTRAINTS = 1489232
const BENCHMARK_TIME = 130.48
const TOLERANCE = 1e12  # Tolerance for very large objective values

function run_new_pcm_uc0_validation()
    println("🧪 NEW PCM VALIDATION TEST - UC=0")
    println("=" ^ 50)
    println("📋 Test Case: $TEST_CASE")
    println("🔧 Unit Commitment: $UC_SETTING (No Unit Commitment)")
    println("🎯 Target: Match old PCM baseline results")
    println()
    
    case_path = "ModelCases/$TEST_CASE"
    
    # Check configuration
    config_file = joinpath(case_path, "Settings", "HOPE_model_settings.yml")
    config_check = YAML.load_file(config_file)
    current_uc = get(config_check, "unit_commitment", "NOT_FOUND")
    
    if current_uc != UC_SETTING
        println("⚠️  Config UC setting ($current_uc) doesn't match test UC setting ($UC_SETTING)")
        println("   Please set unit_commitment: $UC_SETTING in the config file")
        return
    end
    
    println("✅ Config verified: UC=$current_uc")
    println()
    
    # Run the new PCM test
    println("🚀 Running new PCM with UC=$UC_SETTING...")
    start_time = time()
    
    try
        # Load data using SimpleDataReader (matches old PCM exactly)
        reader = SimpleHOPEDataReader(case_path)
        input_data, config = load_simple_case_data(reader, case_path)
        
        # Setup time management
        time_manager = HOPETimeManager()
        setup_time_structure!(time_manager, input_data, config)
        
        # Create Gurobi optimizer (same settings as old PCM)
        solver_settings_path = joinpath(case_path, "Settings", "gurobi_settings.yml")
        solver_settings = isfile(solver_settings_path) ? YAML.load_file(solver_settings_path) : Dict()
        
        gurobi_optimizer = optimizer_with_attributes(Gurobi.Optimizer,
            "OptimalityTol" => get(solver_settings, "Optimal_Tol", 1e-4),
            "FeasibilityTol" => get(solver_settings, "Feasib_Tol", 1e-6),
            "Presolve" => get(solver_settings, "Pre_Solve", -1),
            "AggFill" => get(solver_settings, "AggFill", -1),
            "PreDual" => get(solver_settings, "PreDual", -1),
            "TimeLimit" => get(solver_settings, "TimeLimit", Inf),
            "MIPGap" => get(solver_settings, "MIPGap", 1e-3),
            "Method" => get(solver_settings, "Method", -1),
            "BarConvTol" => get(solver_settings, "BarConvTol", 1e-8),
            "NumericFocus" => get(solver_settings, "NumericFocus", 0),
            "Crossover" => get(solver_settings, "Crossover", -1),
            "OutputFlag" => get(solver_settings, "OutputFlag", 1)
        )
        
        # Build new PCM model
        pcm_model = HOPE_New.PCM.PCMModel()
        HOPE_New.PCM.build_pcm_model!(pcm_model, input_data, config, time_manager, gurobi_optimizer)
        
        # Solve the model
        optimize!(pcm_model.model)
        
        end_time = time()
        execution_time = end_time - start_time
        
        # Extract results
        status = termination_status(pcm_model.model)
        obj_value = has_values(pcm_model.model) ? objective_value(pcm_model.model) : NaN
        
        # Get model statistics
        model_vars = num_variables(pcm_model.model)
        model_cons = num_constraints(pcm_model.model; count_variable_in_set_constraints=false)
        
        # Display results
        println()
        println("📊 NEW PCM UC=2 RESULTS")
        println("=" ^ 40)
        println("Status: $status")
        println("Objective Value: \$$(Printf.@sprintf("%.2f", obj_value))")
        println("Variables: $model_vars")
        println("Constraints: $model_cons")
        println("Execution Time: $(Printf.@sprintf("%.2f", execution_time)) seconds")
        println()
        
        # Validation against benchmark
        println("🎯 VALIDATION AGAINST OLD PCM BASELINE")
        println("=" ^ 45)
        
        # Check optimization status
        status_match = (status == MOI.OPTIMAL)
        println("Status Match: $(status_match ? "✅" : "❌") (Expected: OPTIMAL, Got: $status)")
        
        # Check objective value
        obj_diff = abs(obj_value - BENCHMARK_OBJECTIVE)
        obj_match = obj_diff < TOLERANCE
        obj_percent_diff = (obj_diff / BENCHMARK_OBJECTIVE) * 100
        println("Objective Match: $(obj_match ? "✅" : "❌")")
        println("  Expected: \$$(Printf.@sprintf("%.2e", BENCHMARK_OBJECTIVE))")
        println("  Got:      \$$(Printf.@sprintf("%.2e", obj_value))")
        println("  Diff:     \$$(Printf.@sprintf("%.2e", obj_diff)) ($(Printf.@sprintf("%.6f", obj_percent_diff))%)")
        
        # Check variable count (allow some tolerance for different formulations)
        var_diff = abs(model_vars - BENCHMARK_VARIABLES)
        var_match = var_diff <= 100000  # Allow difference due to formulation variations
        println("Variable Count: $(var_match ? "✅" : "❌")")
        println("  Expected: $BENCHMARK_VARIABLES")
        println("  Got:      $model_vars")
        println("  Diff:     $var_diff")
        
        # Check constraint count (allow some tolerance)
        const_diff = abs(model_cons - BENCHMARK_CONSTRAINTS)
        const_match = const_diff <= 150000  # Allow difference due to formulation variations
        println("Constraint Count: $(const_match ? "✅" : "❌")")
        println("  Expected: $BENCHMARK_CONSTRAINTS")
        println("  Got:      $model_cons")
        println("  Diff:     $const_diff")
        
        # Check execution time (should be competitive)
        time_ratio = execution_time / BENCHMARK_TIME
        time_competitive = time_ratio <= 2.0  # Allow up to 2x slower
        println("Execution Time: $(time_competitive ? "✅" : "⚠️")")
        println("  Expected: $(Printf.@sprintf("%.2f", BENCHMARK_TIME))s")
        println("  Got:      $(Printf.@sprintf("%.2f", execution_time))s") 
        println("  Ratio:    $(Printf.@sprintf("%.2f", time_ratio))x $(time_ratio <= 1.0 ? "(faster)" : time_ratio <= 2.0 ? "(acceptable)" : "(slower)")")
        
        # Overall validation
        all_pass = status_match && obj_match && var_match && const_match
        
        println()
        println("🏆 OVERALL VALIDATION: $(all_pass ? "✅ PASSED" : "❌ FAILED")")
        
        if all_pass
            println()
            println("🎉 SUCCESS! New PCM matches the old PCM baseline for UC=2.")
            println("The ConstraintPool architecture is validated for UC=2.")
        else
            println()
            println("⚠️  VALIDATION FAILED! New PCM does not match baseline.")
            
            # Provide debugging hints
            if !status_match
                println("🔍 Debug: Check solver configuration and model feasibility")
            end
            if !obj_match
                println("🔍 Debug: Check objective function formulation and cost coefficients") 
            end
            if !var_match || !const_match
                println("🔍 Debug: Check constraint generation and variable creation logic")
            end
        end
        
        return pcm_model
        
    catch e
        end_time = time()
        execution_time = end_time - start_time
        
        println()
        println("❌ NEW PCM UC=2 TEST FAILED")
        println("=" ^ 40)
        println("Error: $e")
        println("Execution Time: $(Printf.@sprintf("%.2f", execution_time)) seconds")
        
        rethrow(e)
    end
end

# Run the validation test
if abspath(PROGRAM_FILE) == @__FILE__
    println("Starting New PCM UC=0 Validation Test...")
    run_new_pcm_uc0_validation()
end
