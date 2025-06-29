#!/usr/bin/env julia
"""
Simple Constraint Analysis - Text-Based Comparison
=================================================
Analyzes constraints by reading source files as text.
Avoids JuMP import issues by not including old PCM.jl directly.
"""

using Pkg
Pkg.activate(".")

using JuMP
using YAML

# Import the new HOPE framework only
include("src_new/HOPE_New.jl")
using .HOPE_New

function analyze_old_pcm_constraints()
    """Extract constraint info from old PCM by reading file as text"""
    
    println("📖 Reading OLD PCM constraints from src/PCM.jl...")
    
    pcm_content = read("src/PCM.jl", String)
    lines = split(pcm_content, '\n')
    
    constraints = []
    for (i, line) in enumerate(lines)
        if contains(line, "@constraint")
            constraint_info = Dict(
                "line" => i,
                "content" => strip(line),
                "name" => extract_constraint_name(line)
            )
            push!(constraints, constraint_info)
        end
    end
    
    println("   ✅ Found $(length(constraints)) @constraint statements")
    return constraints
end

function extract_constraint_name(line)
    """Extract constraint name from @constraint line"""
    # Look for pattern like "constraint_name = @constraint" or "@constraint(model, constraint_name[..."
    if contains(line, "= @constraint")
        parts = split(line, "= @constraint")
        return strip(parts[1])
    elseif contains(line, "@constraint(")
        # Try to extract from @constraint(model, name[...
        match_result = match(r"@constraint\([^,]+,\s*([^[,\s]+)", line)
        if match_result !== nothing
            return match_result.captures[1]
        end
    end
    return "unknown"
end

function analyze_new_pcm_constraint_functions()
    """Analyze new PCM constraint functions from ConstraintPool"""
    
    println("📖 Reading NEW PCM constraint functions from ConstraintPool...")
    
    pool_content = read("src_new/core/ConstraintPool.jl", String)
    lines = split(pool_content, '\n')
    
    functions = []
    current_function = nothing
    constraint_count = 0
    
    for (i, line) in enumerate(lines)
        # Look for function definitions
        if contains(line, "function add_") && contains(line, "_con!")
            if current_function !== nothing
                current_function["constraint_count"] = constraint_count
                push!(functions, current_function)
            end
            
            func_name = extract_function_name(line)
            current_function = Dict(
                "name" => func_name,
                "line" => i,
                "content" => line
            )
            constraint_count = 0
        end
        
        # Count @constraint statements in current function
        if current_function !== nothing && contains(line, "@constraint")
            constraint_count += 1
        end
        
        # Function ends
        if current_function !== nothing && contains(line, "end") && length(strip(line)) == 3
            current_function["constraint_count"] = constraint_count
            push!(functions, current_function)
            current_function = nothing
            constraint_count = 0
        end
    end
    
    println("   ✅ Found $(length(functions)) constraint functions")
    return functions
end

function extract_function_name(line)
    """Extract function name from function definition line"""
    match_result = match(r"function\s+(add_[^!]+_con!)", line)
    if match_result !== nothing
        return match_result.captures[1]
    end
    return "unknown"
end

function build_new_pcm_for_testing()
    """Build new PCM model to test constraint generation"""
    
    println("🔧 Building NEW PCM model for constraint analysis...")
    
    case_path = "ModelCases/MD_PCM_Excel_case"
    
    try
        # Load data using SimpleDataReader
        reader = HOPE_New.SimpleHOPEDataReader(case_path)
        input_data, config = HOPE_New.load_simple_case_data(reader, case_path)
        
        # Ensure UC=0
        config["unit_commitment"] = 0
        
        # Setup time management
        time_manager = HOPE_New.HOPETimeManager()
        HOPE_New.setup_time_structure!(time_manager, input_data, config)
        
        # Create simple optimizer for testing
        optimizer = optimizer_with_attributes(
            HOPE_New.Gurobi.Optimizer,
            "OutputFlag" => 0,
            "OptimalityTol" => 1e-4
        )
        
        # Build new PCM model
        pcm_model = HOPE_New.PCM.PCMModel()
        HOPE_New.PCM.build_pcm_model!(pcm_model, input_data, config, time_manager, optimizer)
        
        println("   ✅ NEW model built successfully")
        println("   Variables: $(num_variables(pcm_model.model))")
        println("   Constraints: $(num_constraints(pcm_model.model))")
        
        return pcm_model
        
    catch e
        println("   ❌ Error building NEW model: $e")
        return nothing
    end
end

function compare_constraint_structures()
    """Main comparison function"""
    
    println("🔍 CONSTRAINT STRUCTURE COMPARISON")
    println("=" ^ 80)
    println("Comparing old PCM @constraint statements vs new PCM constraint functions")
    println("")
    
    # Analyze old PCM constraints
    old_constraints = analyze_old_pcm_constraints()
    
    # Analyze new PCM constraint functions
    new_functions = analyze_new_pcm_constraint_functions()
    
    # Build new model to test constraint generation
    new_model = build_new_pcm_for_testing()
    
    println("\n📊 COMPARISON SUMMARY:")
    println("=" ^ 50)
    
    # Basic counts
    println("📋 Constraint Counts:")
    println("   OLD PCM: $(length(old_constraints)) @constraint statements")
    println("   NEW PCM: $(length(new_functions)) constraint functions")
    
    if new_model !== nothing
        actual_new_constraints = num_constraints(new_model.model)
        println("   NEW PCM: $actual_new_constraints actual constraints generated")
        
        if length(old_constraints) == actual_new_constraints
            println("   ✅ Constraint counts match!")
        else
            diff = actual_new_constraints - length(old_constraints)
            println("   ❌ Constraint count difference: $(diff > 0 ? "+" : "")$diff")
        end
    end
    
    # Show old constraint details
    println("\n📋 OLD PCM Constraints:")
    for (i, constraint) in enumerate(old_constraints[1:min(10, length(old_constraints))])
        println("   $i. $(constraint["name"]) (line $(constraint["line"]))")
    end
    if length(old_constraints) > 10
        println("   ... ($(length(old_constraints) - 10) more)")
    end
    
    # Show new function details
    println("\n📋 NEW PCM Constraint Functions:")
    for (i, func) in enumerate(new_functions)
        count_info = func["constraint_count"] > 0 ? " - $(func["constraint_count"]) @constraints" : " - ❌ NO @constraints"
        println("   $i. $(func["name"])$count_info")
    end
    
    # Analysis summary
    incomplete_functions = count(f -> f["constraint_count"] == 0, new_functions)
    complete_functions = length(new_functions) - incomplete_functions
    
    println("\n🔍 NEW PCM Function Analysis:")
    println("   ✅ Complete functions: $complete_functions")
    println("   ❌ Incomplete functions: $incomplete_functions")
    
    if incomplete_functions > 0
        println("   ⚠️  Incomplete functions may explain objective value differences!")
        println("\n❌ Functions missing @constraint statements:")
        for func in new_functions
            if func["constraint_count"] == 0
                println("      • $(func["name"])")
            end
        end
    end
    
    println("\n🎯 NEXT STEPS:")
    if incomplete_functions == 0
        println("   1. ✅ All constraint functions appear complete")
        println("   2. Verify mathematical equivalence of constraint formulations")
        println("   3. Check parameter and variable mappings")
    else
        println("   1. ❌ Fix incomplete constraint functions")
        println("   2. Add missing @constraint statements")
        println("   3. Test constraint generation")
        println("   4. Re-run numerical comparison")
    end
end

# Run the comparison
if abspath(PROGRAM_FILE) == @__FILE__
    compare_constraint_structures()
end
