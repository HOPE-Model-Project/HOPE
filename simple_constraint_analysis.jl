#!/usr/bin/env julia
"""
Simple Constraint Analysis - Compare Old vs New PCM Structure
============================================================
Based on the proven test_new_pcm_validation.jl pattern.
This script builds both models (without solving) and compares constraints.
"""

using Pkg
Pkg.activate(".")

# Import JuMP first (needed for PCM.jl)
using JuMP
using Printf
using YAML
using Gurobi

# Import the new HOPE framework
include("src_new/HOPE_New.jl")
using .HOPE_New

# Don't include old PCM.jl directly (causes JuMP issues)
# Instead read it as text for constraint analysis

function build_old_pcm_model()
    """Build old PCM model using the standard approach"""
    
    println("📊 Building OLD PCM model...")
    
    case_path = "ModelCases/MD_PCM_Excel_case"
    config_file = joinpath(case_path, "Settings", "HOPE_model_settings.yml")
    
    # Load config and ensure UC=0
    config_set = YAML.load_file(config_file)
    config_set["unit_commitment"] = 0
    
    # Load data using old method
    input_data = HOPE.load_data(config_set, case_path)
    
    # Create optimizer (simple one for structure analysis)
    optimizer = optimizer_with_attributes(Gurobi.Optimizer, "OutputFlag" => 0)
    
    # Build old model
    old_model = create_PCM_model(config_set, input_data, optimizer)
    
    println("   ✅ OLD model built successfully")
    return old_model, input_data, config_set
end

function build_new_pcm_model()
    """Build new PCM model using the validated pattern"""
    
    println("📊 Building NEW PCM model...")
    
    case_path = "ModelCases/MD_PCM_Excel_case"
    
    # Load data using SimpleDataReader (matches old PCM exactly)
    reader = HOPE_New.SimpleHOPEDataReader(case_path)
    input_data, config = HOPE_New.load_simple_case_data(reader, case_path)
    
    # Ensure UC=0
    config["unit_commitment"] = 0
    
    # Setup time management
    time_manager = HOPE_New.HOPETimeManager()
    HOPE_New.setup_time_structure!(time_manager, input_data, config)
    
    # Create optimizer (simple one for structure analysis)
    optimizer = optimizer_with_attributes(Gurobi.Optimizer, "OutputFlag" => 0)
    
    # Build new PCM model
    pcm_model = HOPE_New.PCM.PCMModel()
    HOPE_New.PCM.build_pcm_model!(pcm_model, input_data, config, time_manager, optimizer)
    
    println("   ✅ NEW model built successfully")
    return pcm_model.model, pcm_model, input_data, config
end

function compare_constraint_counts(old_model, new_model)
    """Compare constraint counts between models"""
    
    println("\n🔍 CONSTRAINT COUNT COMPARISON")
    println("=" ^ 50)
    
    # Get basic counts
    old_vars = num_variables(old_model)
    new_vars = num_variables(new_model)
    old_cons = num_constraints(old_model; count_variable_in_set_constraints=false)
    new_cons = num_constraints(new_model; count_variable_in_set_constraints=false)
    
    println("📊 Model Statistics:")
    println("   Variables:   OLD=$old_vars, NEW=$new_vars, DIFF=$(new_vars - old_vars)")
    println("   Constraints: OLD=$old_cons, NEW=$new_cons, DIFF=$(new_cons - old_cons)")
    
    # Check if counts match
    vars_match = (old_vars == new_vars)
    cons_match = (old_cons == new_cons)
    
    println("\n📋 Match Analysis:")
    println("   Variables:   $(vars_match ? "✅ MATCH" : "❌ MISMATCH")")
    println("   Constraints: $(cons_match ? "✅ MATCH" : "❌ MISMATCH")")
    
    return vars_match, cons_match
end

function analyze_constraint_types(old_model, new_model)
    """Analyze constraint types in both models"""
    
    println("\n🔍 CONSTRAINT TYPE ANALYSIS")
    println("=" ^ 50)
    
    # Get constraint types for old model
    old_types = list_of_constraint_types(old_model)
    new_types = list_of_constraint_types(new_model)
    
    println("📊 Constraint Types:")
    println("   OLD model: $(length(old_types)) types")
    println("   NEW model: $(length(new_types)) types")
    
    println("\n📋 OLD Model Constraint Types:")
    for (i, (F, S)) in enumerate(old_types)
        count = num_constraints(old_model, F, S)
        println("   $i. $F in $S: $count constraints")
        if i > 10
            println("   ... (showing first 10)")
            break
        end
    end
    
    println("\n📋 NEW Model Constraint Types:")
    for (i, (F, S)) in enumerate(new_types)
        count = num_constraints(new_model, F, S)
        println("   $i. $F in $S: $count constraints")
        if i > 10
            println("   ... (showing first 10)")
            break
        end
    end
    
    return old_types, new_types
end

function run_constraint_analysis()
    """Run the complete constraint analysis"""
    
    println("🔍 SIMPLE CONSTRAINT ANALYSIS")
    println("=" ^ 60)
    println("Goal: Compare constraint structure between old and new PCM")
    println("Pattern: Based on validated test_new_pcm_validation.jl")
    println()
    
    try
        # Build both models
        old_model, old_input_data, old_config = build_old_pcm_model()
        new_model, pcm_model, new_input_data, new_config = build_new_pcm_model()
        
        # Compare constraint counts
        vars_match, cons_match = compare_constraint_counts(old_model, new_model)
        
        # Analyze constraint types
        old_types, new_types = analyze_constraint_types(old_model, new_model)
        
        # Summary
        println("\n🎯 ANALYSIS SUMMARY")
        println("=" ^ 30)
        
        overall_match = vars_match && cons_match
        println("📊 Overall Structure: $(overall_match ? "✅ MATCH" : "❌ MISMATCH")")
        
        if overall_match
            println("\n🎉 SUCCESS! Model structures match perfectly.")
            println("The constraint counts are identical between old and new PCM.")
        else
            println("\n⚠️  STRUCTURAL DIFFERENCES FOUND!")
            if !vars_match
                println("🔍 Variable counts differ - check variable creation logic")
            end
            if !cons_match
                println("🔍 Constraint counts differ - check constraint implementation")
            end
        end
        
    catch e
        println("❌ Error during analysis: $e")
        println("Stacktrace:")
        for (exc, bt) in Base.catch_stack()
            showerror(stdout, exc, bt)
            println()
        end
    end
end

# Run the analysis
if abspath(PROGRAM_FILE) == @__FILE__
    run_constraint_analysis()
end
