"""
Mathematical Constraint Comparison - Old vs New PCM
=================================================
Since both implementations have all constraints, let's compare:
1. Mathematical formulations 
2. Parameter values
3. Index sets
"""

using Pkg
Pkg.activate(".")

function compare_power_balance_formulations()
    """Compare the mathematical formulation of power balance constraints"""
    
    println("🔍 POWER BALANCE MATHEMATICAL COMPARISON")
    println("="^60)
    
    # Read old PCM power balance
    old_pcm = read("src/PCM.jl", String)
    old_lines = split(old_pcm, '\n')
    
    println("📊 OLD PCM Power Balance:")
    for (i, line) in enumerate(old_lines)
        if contains(line, "PB_con") && contains(line, "@constraint")
            # Find the complete constraint (may span multiple lines)
            start_line = i
            constraint_lines = [line]
            
            # Look for continuation lines
            for j in (i+1):min(i+10, length(old_lines))
                if contains(old_lines[j], "base_name") || contains(old_lines[j], ")")
                    push!(constraint_lines, old_lines[j])
                    break
                else
                    push!(constraint_lines, old_lines[j])
                end
            end
            
            println("   Lines $start_line-$(start_line + length(constraint_lines) - 1):")
            for constraint_line in constraint_lines
                println("      $(strip(constraint_line))")
            end
            break
        end
    end
    
    # Read new PCM power balance
    new_constraint_pool = read("src_new/core/ConstraintPool.jl", String)
    new_lines = split(new_constraint_pool, '\n')
    
    println("\n📊 NEW PCM Power Balance:")
    in_power_balance = false
    constraint_found = false
    
    for (i, line) in enumerate(new_lines)
        if contains(line, "function add_power_balance_con!")
            in_power_balance = true
            println("   Function starts at line $i")
        elseif in_power_balance && contains(line, "@constraint")
            # Found the constraint in power balance function
            constraint_found = true
            start_line = i
            constraint_lines = [line]
            
            # Look for continuation lines
            for j in (i+1):min(i+10, length(new_lines))
                if contains(new_lines[j], "base_name") || contains(new_lines[j], ")")
                    push!(constraint_lines, new_lines[j])
                    break
                else
                    push!(constraint_lines, new_lines[j])
                end
            end
            
            println("   Lines $start_line-$(start_line + length(constraint_lines) - 1):")
            for constraint_line in constraint_lines
                println("      $(strip(constraint_line))")
            end
            break
        elseif in_power_balance && contains(line, "end") && constraint_found
            break
        end
    end
end

function compare_generator_capacity_formulations()
    """Compare generator capacity constraint formulations"""
    
    println("\n🔍 GENERATOR CAPACITY MATHEMATICAL COMPARISON")
    println("="^60)
    
    # Read old PCM generator capacity
    old_pcm = read("src/PCM.jl", String)
    old_lines = split(old_pcm, '\n')
    
    println("📊 OLD PCM Generator Capacity:")
    for (i, line) in enumerate(old_lines)
        if contains(line, "CLe_con") && contains(line, "@constraint")
            println("   Line $i: $(strip(line))")
            break
        end
    end
    
    # Read new PCM generator capacity
    new_constraint_pool = read("src_new/core/ConstraintPool.jl", String)
    new_lines = split(new_constraint_pool, '\n')
    
    println("\n📊 NEW PCM Generator Capacity:")
    in_generator_capacity = false
    
    for (i, line) in enumerate(new_lines)
        if contains(line, "function add_generator_capacity_con!")
            in_generator_capacity = true
            println("   Function starts at line $i")
        elseif in_generator_capacity && contains(line, "@constraint")
            println("   Line $i: $(strip(line))")
            # Look for the next line which might have the constraint expression
            if i < length(new_lines)
                println("   Line $(i+1): $(strip(new_lines[i+1]))")
            end
        elseif in_generator_capacity && contains(line, "end") && length(strip(line)) == 3
            break
        end
    end
end

function analyze_key_differences()
    """Analyze key mathematical and structural differences"""
    
    println("\n🔍 KEY DIFFERENCE ANALYSIS")
    println("="^60)
    
    println("🎯 Potential Sources of Objective Value Differences:")
    println("   1. Parameter value differences")
    println("   2. Index set differences (G_i vs G_exist)")
    println("   3. Variable coefficient differences")
    println("   4. Constraint right-hand-side values")
    println("   5. Unit commitment vs non-UC formulation differences")
    
    println("\n🔍 Critical Questions to Investigate:")
    println("   • Are P_max, P_min, VCG parameters identical?")
    println("   • Do G_i and G_exist contain same generators?")
    println("   • Are load values P_load identical?")
    println("   • Do transmission limits F_max match?")
    println("   • Are availability factors AFRE the same?")
    
    println("\n🎯 Next Investigation Steps:")
    println("   1. Compare parameter values between old/new data loading")
    println("   2. Compare index sets (generators, zones, lines)")
    println("   3. Compare constraint coefficients term-by-term")
    println("   4. Check objective function coefficient consistency")
end

function run_mathematical_comparison()
    """Run the complete mathematical comparison"""
    
    println("🔍 MATHEMATICAL CONSTRAINT COMPARISON")
    println("="^80)
    println("Goal: Compare mathematical formulations between old and new PCM")
    println("Since both have all constraints, differences must be in formulation details")
    println("")
    
    try
        compare_power_balance_formulations()
        compare_generator_capacity_formulations() 
        analyze_key_differences()
        
        println("\n" * "="^80)
        println("📊 MATHEMATICAL COMPARISON COMPLETE")
        println("="^80)
        println("Both models have complete constraint implementations.")
        println("Objective value differences likely due to parameter/formulation differences.")
        
    catch e
        println("❌ Error during mathematical comparison: $e")
        for (exc, bt) in Base.catch_stack()
            showerror(stdout, exc, bt)
            println()
        end
    end
end

# Run the mathematical comparison
if abspath(PROGRAM_FILE) == @__FILE__
    run_mathematical_comparison()
end
