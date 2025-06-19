#!/usr/bin/env julia

"""
Test script for HOPE_New main workflow functions
Tests the integrated preprocessing and direct workflows
"""

using Pkg
Pkg.activate(".")

# Load the main HOPE module
include("src_new/HOPE_New.jl")
using .HOPE_New

println("🧪 Testing HOPE_New Main Workflows")
println("=" ^ 50)

# Test case path
case_path = "ModelCases/MD_PCM_clean_case_holistic_test"

println("\n📋 Test Plan:")
println("1. Test environment and solver availability")
println("2. Test case directory validation")
println("3. Test preprocessing detection")
println("4. Test preprocessing-only workflow")
println("5. Test direct workflow")
println("6. Test main flexible workflow")

# Test 1: Environment and solver availability
println("\n" * repeat("=", 50))
println("Test 1: Environment and Solver Availability")
println(repeat("=", 50))

try
    available_solvers = get_available_solvers()
    println("✅ Available solvers: $(join(available_solvers, ", "))")
    
    if isempty(available_solvers)
        println("⚠️  Warning: No solvers detected!")
        test_solver = "cbc"  # Default fallback
    else
        test_solver = available_solvers[1]
        println("   Using solver: $test_solver")
    end
    
    print_hope_info()
    
catch e
    println("❌ Error in environment test:")
    println("   $(string(e))")
end

# Test 2: Case directory validation
println("\n" * repeat("=", 50))
println("Test 2: Case Directory Validation")
println(repeat("=", 50))

try
    validate_case_directory(case_path)
    println("✅ Case directory validation passed: $case_path")
catch e
    println("❌ Case directory validation failed:")
    println("   $(string(e))")
    
    # Try alternative case
    case_path = "ModelCases/MD_GTEP_clean_case"
    try
        validate_case_directory(case_path)
        println("✅ Using alternative case: $case_path")
    catch e2
        println("❌ Alternative case also failed:")
        println("   $(string(e2))")
        return
    end
end

# Test 3: Preprocessing detection
println("\n" * repeat("=", 50))
println("Test 3: Preprocessing Detection")
println(repeat("=", 50))

try    # Load configuration for detection test
    reader = HOPEDataReader(case_path)
    _, config = load_case_data(reader, case_path)
    
    # Test auto-detection
    needs_preprocessing = detect_preprocessing_needs(config)
    println("✅ Preprocessing detection: $needs_preprocessing")
    
    # Show relevant config settings
    println("   Configuration settings:")
    println("     representative_day!: $(get(config, "representative_day!", "not set"))")
    println("     aggregated!: $(get(config, "aggregated!", "not set"))")
    println("     time_periods: $(haskey(config, "time_periods") ? length(config["time_periods"]) : "not set") periods")
    
catch e
    println("❌ Error in preprocessing detection:")
    println("   $(string(e))")
end

# Test 4: Preprocessing-only workflow
println("\n" * repeat("=", 50))
println("Test 4: Preprocessing-Only Workflow")
println(repeat("=", 50))

try
    processed_data, preprocessing_report = run_hope_preprocessing_only(case_path)
    println("✅ Preprocessing-only workflow completed")
    println("   Processed data keys: $(join(keys(processed_data), ", "))")
    if haskey(preprocessing_report, "summary")
        println("   Summary: $(preprocessing_report["summary"])")
    end
catch e
    println("❌ Error in preprocessing-only workflow:")
    println("   $(string(e))")
    if isa(e, ErrorException) || isa(e, MethodError)
        println("   Stack trace:")
        for (exc, bt) in Base.catch_stack()
            showerror(stdout, exc, bt)
            println()
        end
    end
end

# Test 5: Direct workflow (small test)
println("\n" * repeat("=", 50))
println("Test 5: Direct Workflow (Structure Test)")
println(repeat("=", 50))

try
    # Just test the workflow setup, not full execution    println("📂 Testing data loading...")
    reader = HOPEDataReader(case_path)
    input_data, config = load_case_data(reader, case_path)
    println("   ✅ Data loaded successfully")
      println("⏰ Testing time manager setup...")
    time_manager = HOPETimeManager()
    setup_time_structure!(time_manager, input_data, config)
    println("   ✅ Time structure setup successful")
    
    println("🏗️  Testing model builder initialization...")
    builder = HOPEModelBuilder()
    ModelBuilder.initialize!(builder, input_data, config, time_manager)
    println("   ✅ Model builder initialized")
    
    println("✅ Direct workflow structure test passed")
    
catch e
    println("❌ Error in direct workflow structure test:")
    println("   $(string(e))")
    if isa(e, ErrorException) || isa(e, MethodError)
        println("   Stack trace:")
        for (exc, bt) in Base.catch_stack()
            showerror(stdout, exc, bt)
            println()
        end
    end
end

# Test 6: Main flexible workflow (auto-detection)
println("\n" * repeat("=", 50))
println("Test 6: Main Flexible Workflow (Auto-Detection)")
println(repeat("=", 50))

try    # Test auto-detection without full execution
    reader = HOPEDataReader(case_path)
    _, config = load_case_data(reader, case_path)
    
    # Test detection logic
    needs_preprocessing = detect_preprocessing_needs(config)
    println("✅ Auto-detection result: $needs_preprocessing")
    
    # Test workflow selection logic
    if needs_preprocessing
        println("   Would use: run_hope_model_with_preprocessing")
    else
        println("   Would use: run_hope_model_direct")
    end
    
    println("✅ Main workflow auto-detection test passed")
    
catch e
    println("❌ Error in main workflow test:")
    println("   $(string(e))")
end

# Summary
println("\n" * repeat("=", 50))
println("🏁 Test Summary")
println(repeat("=", 50))
println("Completed structure and workflow logic tests for HOPE_New module")
println("The module architecture appears ready for full integration testing")
println("\n📝 Next Steps:")
println("1. Run full model execution tests with small datasets")
println("2. Test solver integration and optimization")
println("3. Validate output generation")
println("4. Performance testing and optimization")

println("\n✅ HOPE_New workflow testing completed!")
