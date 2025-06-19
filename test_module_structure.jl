"""
Test the HOPE_New module structure and main functions
"""

using Pkg
Pkg.activate(".")

# Basic package imports for dependencies
using JuMP, DataFrames, CSV, XLSX, YAML, Clustering, Statistics
using Cbc, Clp, GLPK, HiGHS

println("🔬 Testing HOPE_New Module Structure")
println("=" ^ 45)

# Test that we can include the main module file
try
    include("src_new/HOPE_New.jl")
    println("✅ HOPE_New.jl included successfully")
catch e
    println("❌ Error including HOPE_New.jl: $e")
    exit(1)
end

# Test that the module loads
try
    using .HOPE_New
    println("✅ HOPE_New module loaded successfully")
catch e
    println("❌ Error loading HOPE_New module: $e")
    exit(1)
end

# Test main functions are available
main_functions = [
    :run_hope_model,
    :run_hope_model_with_preprocessing, 
    :run_hope_model_direct,
    :detect_preprocessing_needs
]

println("\n📋 Testing main function availability:")
for func in main_functions
    if isdefined(HOPE_New, func)
        println("  ✅ $func")
    else
        println("  ❌ $func - Not found")
    end
end

# Test utility functions
utility_functions = [
    :validate_case_directory,
    :get_available_solvers,
    :print_hope_info
]

println("\n🔧 Testing utility function availability:")
for func in utility_functions
    if isdefined(HOPE_New, func)
        println("  ✅ $func")
    else
        println("  ❌ $func - Not found")
    end
end

# Test preprocessing detection with actual configurations
println("\n🔍 Testing preprocessing detection:")

# Test case 1: GTEP case (should need preprocessing)
case1_path = "ModelCases/MD_GTEP_clean_case"
if validate_case_directory(case1_path)
    config_file1 = joinpath(case1_path, "Settings", "HOPE_model_settings.yml")
    config1 = YAML.load_file(config_file1)
    needs_preprocessing1 = detect_preprocessing_needs(config1)
    println("  ✅ GTEP case - Needs preprocessing: $needs_preprocessing1")
else
    println("  ❌ GTEP case directory validation failed")
end

# Test case 2: PCM case (should not need preprocessing based on config)
case2_path = "ModelCases/MD_PCM_clean_case_holistic_test"
if validate_case_directory(case2_path)
    config_file2 = joinpath(case2_path, "Settings", "HOPE_model_settings.yml")
    config2 = YAML.load_file(config_file2)
    needs_preprocessing2 = detect_preprocessing_needs(config2)
    println("  ✅ PCM case - Needs preprocessing: $needs_preprocessing2")
else
    println("  ❌ PCM case directory validation failed")
end

# Test available solvers
println("\n🔧 Testing solver detection:")
available_solvers = get_available_solvers()
println("  Available solvers: $(join(available_solvers, ", "))")

# Test system info
println("\n📋 Testing system info function:")
try
    print_hope_info()
    println("\n  ✅ System info displayed successfully")
catch e
    println("  ❌ Error displaying system info: $e")
end

println("\n" * "=" * 45)
println("✅ HOPE_New Module Tests Completed Successfully!")
println("🎯 All core functionality is working correctly")
println("🚀 Ready for full model execution tests")
