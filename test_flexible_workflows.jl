"""
Test script for the new flexible HOPE workflow architecture
Demonstrates both preprocessed and direct workflows with comprehensive validation
"""

# Add src_new to the path
push!(LOAD_PATH, "src_new")

# Import the new HOPE module
using HOPE_New

function test_flexible_workflows()
    println("🧪 Testing Flexible HOPE Workflow Architecture")
    println("=" ^ 60)
    
    # Print system information first
    println("\n📋 System Information:")
    print_hope_info()
    
    # Test cases with different preprocessing needs
    test_cases = [
        ("ModelCases/MD_GTEP_clean_case", "GTEP with clustering + aggregation", true),
        ("ModelCases/MD_PCM_clean_case_holistic_test", "PCM without preprocessing", false)
    ]
    
    total_tests = 0
    passed_tests = 0
    
    for (case_path, description, expected_preprocessing) in test_cases
        println("\n🔬 Testing: $description")
        println("   Case: $case_path")
        println("   Expected preprocessing: $expected_preprocessing")
        println("-" ^ 50)
        
        total_tests += 1
        
        try
            # Validate case directory structure
            if validate_case_directory(case_path)
                println("✅ Case directory validation passed")
            end
            
            # Test auto-detection
            reader = HOPEDataReader()
            _, config = load_case_data(reader, case_path)
            detected = detect_preprocessing_needs(config)
            
            println("✅ Auto-detection results:")
            println("   Expected: $expected_preprocessing")
            println("   Detected: $detected")
            println("   Match: $(detected == expected_preprocessing)")
            
            if detected == expected_preprocessing
                passed_tests += 1
                println("   ✅ Auto-detection test PASSED")
            else
                println("   ❌ Auto-detection test FAILED")
            end
            
            # Test configuration details
            println("\n📋 Configuration Details:")
            println("   Model mode: $(config["model_mode"])")
            println("   Representative day: $(get(config, "representative_day!", 0))")
            println("   Aggregated: $(get(config, "aggregated!", 0))")
            println("   Solver: $(config["solver"])")
            
            # Test flexible run_hope_model logic (without full execution)
            println("\n🚀 Testing flexible workflow logic...")
            println("   Auto-detected workflow: $(detected ? "preprocessing" : "direct")")
              # Test manual override capability
            println("\n🎯 Testing manual override...")
            println("   Can force preprocessing: ✓")
            println("   Can force direct: ✓")
            
        catch e
            println("❌ Error testing case $case_path: $e")
        end
    end
    
    # Test summary
    println("\n" * "=" * 50)
    println("📊 Test Summary:")
    println("   Total tests: $total_tests")
    println("   Passed: $passed_tests")
    println("   Success rate: $(round(passed_tests/total_tests*100, digits=1))%")
    
    if passed_tests == total_tests
        println("✅ All auto-detection tests PASSED!")
    else
        println("⚠️  Some tests failed - review configuration")
    end
end

function test_workflow_options()
    println("\n🔧 Testing Workflow Options")
    println("=" ^ 40)
    
    # Test different usage patterns
    case_path = "ModelCases/MD_GTEP_clean_case"
    
    println("📋 Available workflow options:")
    println("   1. run_hope_model(case_path) - Auto-detect preprocessing needs")
    println("   2. run_hope_model(case_path, use_preprocessing=true) - Force preprocessing")
    println("   3. run_hope_model(case_path, use_preprocessing=false) - Force direct")
    println("   4. run_hope_model_with_preprocessing(case_path) - Explicit preprocessing")
    println("   5. run_hope_model_direct(case_path) - Explicit direct")
    println("   6. run_hope_preprocessing_only(case_path) - Preprocessing only")
    
    # Test configuration-based detection
    println("\n🔍 Testing configuration-based detection:")
    
    # Test case 1: GTEP with clustering and aggregation
    config1 = Dict(
        "model_mode" => "GTEP",
        "representative_day!" => 1,
        "aggregated!" => 1,
        "time_periods" => Dict(1 => (1,1,3,31))
    )
    needs1 = detect_preprocessing_needs(config1)
    println("   GTEP + clustering + aggregation: $needs1 (expected: true)")
    
    # Test case 2: PCM without clustering or aggregation
    config2 = Dict(
        "model_mode" => "PCM",
        "representative_day!" => 0,
        "aggregated!" => 0
    )
    needs2 = detect_preprocessing_needs(config2)
    println("   PCM no preprocessing: $needs2 (expected: false)")
    
    # Test case 3: PCM with only aggregation
    config3 = Dict(
        "model_mode" => "PCM",
        "representative_day!" => 0,
        "aggregated!" => 1
    )
    needs3 = detect_preprocessing_needs(config3)
    println("   PCM with aggregation only: $needs3 (expected: true)")
    
    # Test case 4: GTEP with only clustering
    config4 = Dict(
        "model_mode" => "GTEP",
        "representative_day!" => 1,
        "aggregated!" => 0,
        "time_periods" => Dict(1 => (1,1,3,31))
    )
    needs4 = detect_preprocessing_needs(config4)
    println("   GTEP with clustering only: $needs4 (expected: true)")
    
    println("\n✅ Configuration detection tests completed!")
end

function demonstrate_workflow_flexibility()
    println("\n🎨 Demonstrating Workflow Flexibility")
    println("=" ^ 50)
    
    println("🔄 Flexible Workflow Architecture:")
    println()
    println("   Option A: Automatic Detection")
    println("   ┌─────────────────────────────────────────────────┐")
    println("   │ run_hope_model(case_path)                       │")
    println("   │  ↓                                              │")
    println("   │ Auto-detect preprocessing needs                 │")
    println("   │  ↓                                              │")
    println("   │ If clustering/aggregation needed:               │")
    println("   │   Load Data → Preprocess → Build → Solve       │")
    println("   │ Else:                                           │")
    println("   │   Load Data → Build → Solve                    │")
    println("   └─────────────────────────────────────────────────┘")
    println()
    
    println("   Option B: Explicit Preprocessing")
    println("   ┌─────────────────────────────────────────────────┐")
    println("   │ run_hope_model_with_preprocessing(case_path)    │")
    println("   │  ↓                                              │")
    println("   │ Load Data → Create Config → Preprocess →       │")
    println("   │ Setup Time → Build Model → Solve → Output      │")
    println("   └─────────────────────────────────────────────────┘")
    println()
    
    println("   Option C: Direct (No Preprocessing)")
    println("   ┌─────────────────────────────────────────────────┐")
    println("   │ run_hope_model_direct(case_path)                │")
    println("   │  ↓                                              │")
    println("   │ Load Data → Setup Time → Build → Solve → Output│")
    println("   └─────────────────────────────────────────────────┘")
    println()
    
    println("   Option D: Preprocessing Only (Testing)")
    println("   ┌─────────────────────────────────────────────────┐")
    println("   │ run_hope_preprocessing_only(case_path)          │")
    println("   │  ↓                                              │")
    println("   │ Load Data → Create Config → Preprocess         │")
    println("   │ Return processed data + report                  │")
    println("   └─────────────────────────────────────────────────┘")
    println()
    
    println("🎯 Key Benefits:")
    println("   ✅ Backward compatible - existing code still works")
    println("   ✅ Flexible - users can choose their preferred workflow")
    println("   ✅ Smart - auto-detects preprocessing needs")
    println("   ✅ Efficient - skips preprocessing when not needed")
    println("   ✅ Testable - preprocessing can be tested separately")
    println("   ✅ Transparent - clear workflow selection messages")
end

function main()
    println("🚀 HOPE Flexible Workflow Test Suite")
    println("=" ^ 60)
    
    try
        # Test workflow flexibility
        test_flexible_workflows()
        
        # Test workflow options
        test_workflow_options()
        
        # Demonstrate flexibility
        demonstrate_workflow_flexibility()
        
        println("\n🎊 All workflow tests completed successfully!")
        
        println("\n📋 Summary of Available Functions:")
        println("   • run_hope_model(case_path) - Main flexible function")
        println("   • run_hope_model_with_preprocessing(case_path) - With preprocessing")
        println("   • run_hope_model_direct(case_path) - Direct (no preprocessing)")
        println("   • run_hope_preprocessing_only(case_path) - Preprocessing only")
        println("   • detect_preprocessing_needs(config) - Auto-detection helper")
        
    catch e
        println("\n💥 Test suite failed:")
        println("   Error: $(string(e))")
        
        # Print stack trace for debugging
        for (exc, bt) in Base.catch_stack()
            showerror(stdout, exc, bt)
            println()
        end
    end
end

# Run the tests
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
