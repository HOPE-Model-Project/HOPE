"""
Quick Constraint Test - Verify constraint functions work correctly
================================================================
This script builds a small PCM model and counts actual constraints generated
"""

using Pkg
Pkg.activate(".")

using JuMP
using Gurobi

include("src_new/HOPE_New.jl")
using .HOPE_New

function test_constraint_generation()
    println("🔧 QUICK CONSTRAINT GENERATION TEST")
    println("="^60)
    
    try
        # Load minimal data
        case_path = "ModelCases/MD_PCM_Excel_case"
        
        # Load data using the new framework
        reader = HOPE_New.SimpleHOPEDataReader(case_path)
        input_data, config = HOPE_New.load_simple_case_data(reader, case_path)
        
        # Ensure UC=0 for comparison
        config["unit_commitment"] = 0
        
        # Setup time management  
        time_manager = HOPE_New.HOPETimeManager()
        HOPE_New.setup_time_structure!(time_manager, input_data, config)
        
        # Build PCM model
        pcm_model = HOPE_New.PCM.PCMModel()
        
        # Use proper optimizer setup
        optimizer = optimizer_with_attributes(Gurobi.Optimizer,
            "OptimalityTol" => 1e-4,
            "FeasibilityTol" => 1e-6,
            "OutputFlag" => 0
        )
        
        println("🔧 Building PCM model...")
        HOPE_New.PCM.build_pcm_model!(pcm_model, input_data, config, time_manager, optimizer)
        
        # Count constraints
        model = pcm_model.model
        total_constraints = 0
        
        constraint_types = list_of_constraint_types(model)
        println("\n📊 CONSTRAINT COUNT BY TYPE:")
        
        for (F, S) in constraint_types
            count = num_constraints(model, F, S)
            total_constraints += count
            println("   $F in $S: $count constraints")
        end
        
        println("\n📋 SUMMARY:")
        println("   Total constraints: $total_constraints")
        println("   Total variables: $(num_variables(model))")
        
        if total_constraints > 0
            println("   ✅ Constraints are being generated correctly!")
        else
            println("   ❌ No constraints found - there's still an issue")
        end
        
    catch e
        println("❌ Error: $e")
        println("Stacktrace:")
        for (exc, bt) in Base.catch_stack()
            showerror(stdout, exc, bt)
            println()
        end
    end
end

# Run the test
test_constraint_generation()
