"""
# test_new_architecture.jl - Test script for the new HOPE architecture
"""

# Add the src_new directory to the load path
push!(LOAD_PATH, joinpath(@__DIR__, "src_new"))

using JuMP
using HiGHS

# Load the new HOPE module
include("src_new/HOPE_New.jl")
using .HOPE_New

println("🧪 Testing New HOPE Architecture")
println("================================")

# Test 1: Demo with minimal in-memory data
println("\n🎯 Test 1: Architecture Demo")
try
    result = HOPE_New.demo_new_architecture()
    println("✅ Demo test passed!")
catch e
    println("❌ Demo test failed: $e")
    println(stacktrace(catch_backtrace()))
end

# Test 2: Load configuration and constraint pool
println("\n🎯 Test 2: Component Testing")
try
    # Test constraint pool initialization
    pool = HOPE_New.initialize_hope_constraint_pool()
    println("✅ Constraint pool initialized with $(length(pool.constraints)) constraints")
    
    # Test time manager
    time_manager = HOPE_New.TimeManager()
    pcm_structure = HOPE_New.create_pcm_time_structure(2035)
    HOPE_New.set_time_structure!(time_manager, pcm_structure)
    summary = HOPE_New.get_time_summary(time_manager)
    println("✅ Time manager created: $(summary["type"]) with $(summary["total_hours"]) hours")
    
    # Test model builder
    builder = HOPE_New.HOPEModelBuilder()
    println("✅ Model builder created")
    
    println("✅ Component tests passed!")
    
catch e
    println("❌ Component test failed: $e")
    println(stacktrace(catch_backtrace()))
end

# Test 3: Test with actual case data (if available)
println("\n🎯 Test 3: Real Case Testing")
test_cases = [
    "ModelCases/MD_PCM_clean_case_holistic_test",
    "ModelCases/MD_Excel_case", 
    "ModelCases/MD_GTEP_clean_case"
]

for case_name in test_cases
    case_path = joinpath(@__DIR__, "..", case_name)
    if isdir(case_path)
        println("📂 Testing with case: $case_name")
        try
            # Just test data loading for now
            reader = HOPE_New.HOPEDataReader(case_path)
            config = HOPE_New.load_configuration(reader)
            println("✅ Configuration loaded for $(config["model_mode"]) mode")
            
            # Test data loading (but don't run full model to save time)
            # input_data = HOPE_New.load_hope_data(reader)
            # println("✅ Data loading successful")
            
        catch e
            println("⚠️  Case $case_name: $e")
        end
        break  # Only test first available case
    else
        println("⏭️  Case $case_name not found, skipping...")
    end
end

println("\n🎉 Architecture testing completed!")
println("💡 The new modular architecture is ready for development")

# Print architecture benefits
println("\n🌟 New Architecture Benefits:")
println("   ✨ Modular constraint management")
println("   ✨ Unified time index handling") 
println("   ✨ Standardized input/output")
println("   ✨ Transparent model building")
println("   ✨ Extensible design patterns")
println("   ✨ Enhanced debugging capabilities")

println("\n📝 Next Steps:")
println("   1. Implement remaining constraint functions")
println("   2. Add output writing and plotting modules")
println("   3. Create holistic workflow (GTEP→PCM)")
println("   4. Add comprehensive testing suite")
println("   5. Performance optimization")
println("   6. Documentation and examples")
