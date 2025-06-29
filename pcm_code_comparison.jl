"""
PCM Code Structure Comparison - Direct Code Analysis
==================================================
This script directly analyzes the constraint definitions in both old and new PCM
by reading the source code files and comparing the constraint structures.

Goal: Ensure each constraint type has equivalent implementation
"""

using Pkg
Pkg.activate(".")

function extract_old_pcm_constraints()
    """Extract constraint definitions from old PCM.jl"""
    
    println("📖 Reading OLD PCM constraints from src/PCM.jl...")
    
    # Read the old PCM file
    old_pcm_content = read("src/PCM.jl", String)
    
    # Find all @constraint lines
    constraints = []
    lines = split(old_pcm_content, '\n')
    
    for (i, line) in enumerate(lines)
        if contains(line, "@constraint")
            # Extract constraint info
            constraint_match = match(r"@constraint\s*\([^,]+,\s*([^,]+),.*base_name\s*=\s*\"([^\"]+)\"", line)
            if constraint_match !== nothing
                indices = constraint_match.captures[1]
                name = constraint_match.captures[2]
                push!(constraints, (name=name, indices=indices, line=i, code=strip(line)))
            end
        end
    end
    
    println("   ✅ Found $(length(constraints)) constraints in old PCM")
    return constraints
end

function extract_new_pcm_constraints()
    """Extract constraint function calls from new PCM.jl"""
    
    println("📖 Reading NEW PCM constraint calls from src_new/models/PCM.jl...")
    
    # Read the new PCM file
    new_pcm_content = read("src_new/models/PCM.jl", String)
    
    # Find all ConstraintPool function calls
    constraints = []
    lines = split(new_pcm_content, '\n')
    
    for (i, line) in enumerate(lines)
        if contains(line, "ConstraintPool.add_") && contains(line, "!")
            # Extract function name
            func_match = match(r"ConstraintPool\.add_([^!]+)!", line)
            if func_match !== nothing
                func_name = func_match.captures[1]
                push!(constraints, (name=func_name, line=i, code=strip(line)))
            end
        end
    end
    
    println("   ✅ Found $(length(constraints)) constraint functions in new PCM")
    return constraints
end

function analyze_constraint_mapping()
    """Analyze how old constraints map to new constraint functions"""
    
    println("\n" * "="^80)
    println("🔍 CONSTRAINT MAPPING ANALYSIS")
    println("="^80)
    
    old_constraints = extract_old_pcm_constraints()
    new_constraints = extract_new_pcm_constraints()
    
    println("\n📊 Constraint Count Comparison:")
    println("   OLD PCM: $(length(old_constraints)) @constraint definitions")
    println("   NEW PCM: $(length(new_constraints)) ConstraintPool function calls")
    
    # List old constraints
    println("\n📋 OLD PCM Constraints:")
    for (i, constraint) in enumerate(old_constraints)
        println("   $i. $(constraint.name) - $(constraint.indices)")
    end
    
    # List new constraints
    println("\n📋 NEW PCM Constraint Functions:")
    for (i, constraint) in enumerate(new_constraints)
        println("   $i. $(constraint.name)")
    end
    
    # Try to map them
    println("\n🔗 CONSTRAINT MAPPING ANALYSIS:")
    
    # Define expected mappings based on constraint types
    expected_mappings = [
        ("PB_con", "power_balance_con"),
        ("CLe_con", "generator_capacity_con"), 
        ("CLe_MR_con", "must_run_con"),
        ("TLe_con", "transmission_capacity_con"),
        ("SB_con", "storage_soc_evolution_con"),
        ("SC_con", "storage_cyclic_con"),
        ("SCap_con", "storage_capacity_con"),
        ("NI_con", "net_imports_con"),
        ("SPIN_con", "spinning_reserve_con"),
        ("RP_UP_con", "ramping_up_con"),
        ("RP_DN_con", "ramping_down_con"),
        ("RPS_AN_con", "rps_annual_con"),
        ("RPS_ST_con", "rps_state_requirement_con"),
        ("EL_con", "emissions_limit_con"),
        # UC constraints
        ("MRL_con", "uc_capacity_con"),
        ("STT_con", "uc_transition_con"),
        ("MUT_con", "uc_min_up_time_con"),
        ("MDT_con", "uc_min_down_time_con"),
        ("PMINB_con", "uc_capacity_con"),
        ("CLeL_con", "uc_capacity_con"),
        ("CLeU_con", "uc_capacity_con")
    ]
    
    old_names = [c.name for c in old_constraints]
    new_names = [c.name for c in new_constraints]
    
    println("\n🔍 Mapping Analysis:")
    for (old_name, expected_new) in expected_mappings
        if old_name in old_names
            if expected_new in new_names
                println("   ✅ $old_name → $expected_new")
            else
                println("   ❌ $old_name → $expected_new (MISSING)")
            end
        end
    end
    
    # Check for unmapped constraints
    mapped_old = [mapping[1] for mapping in expected_mappings]
    mapped_new = [mapping[2] for mapping in expected_mappings]
    
    unmapped_old = [name for name in old_names if !(name in mapped_old)]
    unmapped_new = [name for name in new_names if !(name in mapped_new)]
    
    if !isempty(unmapped_old)
        println("\n⚠️  Unmapped OLD constraints:")
        for name in unmapped_old
            println("   • $name")
        end
    end
    
    if !isempty(unmapped_new)
        println("\n⚠️  Extra NEW constraint functions:")
        for name in unmapped_new
            println("   • $name")
        end
    end
    
    return old_constraints, new_constraints
end

function analyze_constraint_details(old_constraints, new_constraints)
    """Analyze specific constraint details"""
    
    println("\n" * "="^80)
    println("🔍 DETAILED CONSTRAINT ANALYSIS")
    println("="^80)
    
    # Focus on key constraints that should match exactly
    key_constraints = [
        "PB_con",     # Power balance - most important
        "CLe_con",    # Generator capacity
        "TLe_con",    # Transmission capacity
        "NI_con",     # Net imports
    ]
    
    for constraint_name in key_constraints
        println("\n📊 Analyzing: $constraint_name")
        
        # Find in old constraints
        old_constraint = nothing
        for c in old_constraints
            if c.name == constraint_name
                old_constraint = c
                break
            end
        end
        
        if old_constraint !== nothing
            println("   ✅ Found in OLD PCM:")
            println("      Indices: $(old_constraint.indices)")
            println("      Code: $(old_constraint.code)")
        else
            println("   ❌ Not found in OLD PCM")
        end
        
        # Check if corresponding function exists in new PCM
        expected_new_name = ""
        if constraint_name == "PB_con"
            expected_new_name = "power_balance_con"
        elseif constraint_name == "CLe_con"
            expected_new_name = "generator_capacity_con"
        elseif constraint_name == "TLe_con"
            expected_new_name = "transmission_capacity_con"
        elseif constraint_name == "NI_con"
            expected_new_name = "net_imports_con"
        end
        
        new_constraint = nothing
        for c in new_constraints
            if c.name == expected_new_name
                new_constraint = c
                break
            end
        end
        
        if new_constraint !== nothing
            println("   ✅ Corresponding function in NEW PCM: $(new_constraint.name)")
        else
            println("   ❌ No corresponding function found in NEW PCM")
        end
    end
end

function run_code_comparison()
    """Run the complete code structure comparison"""
    
    println("🔍 PCM CODE STRUCTURE COMPARISON")
    println("="^80)
    println("Direct analysis of constraint definitions in source code")
    println("Goal: Ensure structural equivalence between old and new PCM")
    println("")
    
    try
        # Extract and analyze constraints
        old_constraints, new_constraints = analyze_constraint_mapping()
        
        # Detailed analysis of key constraints
        analyze_constraint_details(old_constraints, new_constraints)
        
        # Summary
        println("\n" * "="^80)
        println("📊 SUMMARY")
        println("="^80)
        
        old_count = length(old_constraints)
        new_count = length(new_constraints)
        
        println("\n🔍 Key Findings:")
        println("   • OLD PCM has $old_count explicit @constraint definitions")
        println("   • NEW PCM has $new_count ConstraintPool function calls")
        
        if old_count == new_count
            println("   ✅ Constraint counts match!")
        else
            println("   ❌ Constraint counts differ")
        end
        
        println("\n🎯 NEXT STEPS:")
        println("   1. Verify each ConstraintPool function implements the correct constraint")
        println("   2. Check constraint indices/sets match between old and new")
        println("   3. Verify parameter usage is consistent")
        println("   4. Compare constraint coefficients and structure")
        
    catch e
        println("❌ Error: $e")
        for (exc, bt) in Base.catch_stack()
            showerror(stdout, exc, bt)
            println()
        end
    end
end

# Run the comparison
if abspath(PROGRAM_FILE) == @__FILE__
    run_code_comparison()
end
