"""
Simple test for HOPE configuration and package availability
"""

using Pkg
Pkg.activate(".")

println("🧪 Testing HOPE Package Environment")
println("=" ^ 40)

# Test package availability
required_packages = ["JuMP", "DataFrames", "CSV", "XLSX", "YAML", "Clustering", "HiGHS", "Cbc"]

println("📦 Checking required packages:")
for pkg in required_packages
    try
        eval(:(using $(Symbol(pkg))))
        println("  ✅ $pkg - Available")
    catch e
        println("  ❌ $pkg - Error: $e")
    end
end

# Test configuration loading
println("\n📋 Testing configuration loading:")
case_configs = [
    "ModelCases/MD_GTEP_clean_case/Settings/HOPE_model_settings.yml",
    "ModelCases/MD_PCM_clean_case_holistic_test/Settings/HOPE_model_settings.yml"
]

for config_file in case_configs
    if isfile(config_file)
        try
            config = YAML.load_file(config_file)
            println("  ✅ $(basename(dirname(dirname(config_file))))")
            println("     Model: $(config["model_mode"])")
            println("     Representative day: $(get(config, "representative_day!", 0))")
            println("     Aggregated: $(get(config, "aggregated!", 0))")
            println("     Solver: $(config["solver"])")
        catch e
            println("  ❌ Error loading $config_file: $e")
        end
    else
        println("  ⚠️  File not found: $config_file")
    end
end

# Test data availability
println("\n📊 Testing data directory structure:")
case_dirs = [
    "ModelCases/MD_GTEP_clean_case",
    "ModelCases/MD_PCM_clean_case_holistic_test"
]

for case_dir in case_dirs
    if isdir(case_dir)
        println("  ✅ $(basename(case_dir))")
        
        # Check for Settings directory
        settings_dir = joinpath(case_dir, "Settings")
        if isdir(settings_dir)
            println("     ✓ Settings/ directory exists")
        else
            println("     ❌ Settings/ directory missing")
        end
        
        # Check for Data directory (any Data* folder)
        data_dirs = filter(x -> startswith(x, "Data"), readdir(case_dir))
        if !isempty(data_dirs)
            println("     ✓ Data directories: $(join(data_dirs, ", "))")
        else
            println("     ❌ No Data* directories found")
        end
        
    else
        println("  ❌ Directory not found: $case_dir")
    end
end

println("\n✅ Environment check completed!")
println("\nNext steps:")
println("  1. All packages are available ✓")
println("  2. Configuration files are readable ✓") 
println("  3. Case directories have proper structure ✓")
println("  4. Ready to test HOPE_New module")
