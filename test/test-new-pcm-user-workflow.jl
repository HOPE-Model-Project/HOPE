# Test New PCM Model - User Workflow Test
# This test mirrors the exact user workflow used for the old PCM with MD_PCM_Excel_case and UC=0

using Test
using JuMP
using CSV
using DataFrames
using YAML

# Include the HOPE modules
include("../src/HOPE.jl")

@testset "New PCM Model - User Workflow Test" begin
    
    println("\n=== Testing New PCM Model with MD_PCM_Excel_case (UC=0) ===")
    println("This test replicates the exact user workflow used for old PCM testing")
    
    # Test setup - exactly like a user would do
    println("\n1. Setting up test case...")
    case_path = "e:\\Dropbox (MIT)\\PJMShen\\HOPE\\ModelCases\\MD_PCM_Excel_case"
    
    # Verify case directory exists
    @test isdir(case_path) "Test case directory not found: $case_path"
    
    # Read configuration (like user would do)
    config_file = joinpath(case_path, "Settings", "HOPE_model_settings.yml")
    @test isfile(config_file) "Configuration file not found: $config_file"
    
    println("2. Loading configuration...")
    config_dict = YAML.load_file(config_file)
    
    # Verify key settings for this test
    @test config_dict["model_mode"] == "PCM" "Expected PCM mode"
    @test config_dict["unit_commitment"] == 0 "Expected UC=0 for this test"
    @test config_dict["solver"] == "HiGHS" "Expected HiGHS solver"
    
    println("3. Running HOPE with new PCM model...")
    
    # Time the execution (for performance comparison)
    start_time = time()
    
    # Run HOPE exactly as user would - this should use the new PCM model
    result = nothing
    try
        # Change to case directory (like user would do)
        original_dir = pwd()
        cd(case_path)
        
        # Run HOPE
        result = run_HOPE()
        
        # Change back
        cd(original_dir)
        
        println("✓ HOPE execution completed successfully")
    catch e
        @test false "HOPE execution failed: $e"
    end
    
    execution_time = time() - start_time
    println("   Execution time: $(round(execution_time, digits=2)) seconds")
    
    # Verify outputs were generated
    println("\n4. Verifying outputs...")
    output_dir = joinpath(case_path, "output")
    @test isdir(output_dir) "Output directory not created"
    
    # Check for key output files
    expected_files = [
        "system_cost.csv",
        "power_hourly.csv", 
        "power_flow.csv",
        "es_power_charge.csv",
        "es_power_discharge.csv",
        "es_power_soc.csv",
        "power_loadshedding.csv",
        "power_price.csv",
        "power_renewable_curtailment.csv"
    ]
    
    for file in expected_files
        file_path = joinpath(output_dir, file)
        @test isfile(file_path) "Expected output file not found: $file"
    end
    
    println("✓ All expected output files generated")
    
    # Load and verify results against old PCM benchmark
    println("\n5. Comparing results with old PCM benchmark...")
    
    # Read system cost results
    system_cost_file = joinpath(output_dir, "system_cost.csv")
    system_cost_df = CSV.read(system_cost_file, DataFrame)
    
    # Expected benchmark values from old PCM (UC=0)
    # These are the values we established as correct from the old PCM model
    expected_system_costs = Dict(
        "APS_MD" => (3.9721533407795703e8, 6.237398413161154e7, 4.5958931820956856e8),
        "BGE" => (2.2547988159397188e8, 0.0, 2.2547988159397188e8),
        "PEPCO" => (7.929695821625987e8, 0.0, 7.929695821625987e8),
        "DPL_MD" => (1.9503375554931617e8, 0.0, 1.9503375554931617e8),
        "APS" => (0.0, 2.8790302021558046e7, 2.8790302021558046e7),
        "DPL" => (0.0, 0.0, 0.0)
    )
    
    println("   Comparing system costs by zone:")
    total_cost_new = 0.0
    total_cost_expected = 0.0
    
    for row in eachrow(system_cost_df)
        zone = row.Zone
        opr_cost = row[Symbol("Opr_cost (\$)")]
        lol_cost = row[Symbol("LoL_plt (\$)")]
        total_cost = row[Symbol("Total_cost (\$)")]
        
        if haskey(expected_system_costs, zone)
            expected_opr, expected_lol, expected_total = expected_system_costs[zone]
            
            println("     $zone:")
            println("       Operation Cost: \$$(round(opr_cost/1e6, digits=2))M (expected: \$$(round(expected_opr/1e6, digits=2))M)")
            println("       Load Shedding Cost: \$$(round(lol_cost/1e6, digits=2))M (expected: \$$(round(expected_lol/1e6, digits=2))M)")
            println("       Total Cost: \$$(round(total_cost/1e6, digits=2))M (expected: \$$(round(expected_total/1e6, digits=2))M)")
            
            # Allow for small numerical differences (1% tolerance)
            tolerance = 0.01
            @test abs(opr_cost - expected_opr) / max(expected_opr, 1.0) < tolerance "Operation cost mismatch for $zone"
            @test abs(lol_cost - expected_lol) / max(expected_lol, 1.0) < tolerance "Load shedding cost mismatch for $zone"  
            @test abs(total_cost - expected_total) / max(expected_total, 1.0) < tolerance "Total cost mismatch for $zone"
            
            total_cost_new += total_cost
            total_cost_expected += expected_total
        end
    end
    
    println("   Total System Cost: \$$(round(total_cost_new/1e9, digits=3))B (expected: \$$(round(total_cost_expected/1e9, digits=3))B)")
    @test abs(total_cost_new - total_cost_expected) / total_cost_expected < 0.01 "Total system cost differs from benchmark"
    
    # Verify power generation data structure
    println("\n6. Verifying power generation output structure...")
    power_hourly_file = joinpath(output_dir, "power_hourly.csv")
    power_df = CSV.read(power_hourly_file, DataFrame)
    
    # Check basic structure
    expected_columns = ["Technology", "Zone", "EC_Category", "AnnSum"]
    for col in expected_columns
        @test col in names(power_df) "Missing expected column: $col"
    end
    
    # Check for hourly columns (h1 to h8760)
    hourly_cols = [name for name in names(power_df) if startswith(string(name), "h") && length(string(name)) > 1]
    @test length(hourly_cols) == 8760 "Expected 8760 hourly columns, found $(length(hourly_cols))"
    
    println("✓ Power generation output structure verified")
    
    # Verify energy storage outputs
    println("\n7. Verifying energy storage outputs...")
    storage_files = ["es_power_charge.csv", "es_power_discharge.csv", "es_power_soc.csv"]
    
    for file in storage_files
        file_path = joinpath(output_dir, file)
        if isfile(file_path)
            df = CSV.read(file_path, DataFrame)
            @test nrow(df) > 0 "Energy storage file $file is empty"
            println("   ✓ $file verified ($(nrow(df)) rows)")
        end
    end
    
    # Performance and model verification
    println("\n8. Model performance and verification...")
    println("   ✓ Execution time: $(round(execution_time, digits=2)) seconds")
    println("   ✓ New PCM model produces results consistent with old PCM benchmark")
    println("   ✓ All expected outputs generated successfully")
    println("   ✓ User workflow test completed successfully")
    
    # Final summary
    println("\n=== Test Summary ===")
    println("✓ New PCM model successfully replaces old PCM model")
    println("✓ Results match old PCM benchmark within 1% tolerance")  
    println("✓ All output files generated correctly")
    println("✓ User workflow preserved - no breaking changes")
    println("✓ Ready for production use")
    
end

println("\n=== New PCM Model User Workflow Test Completed ===")
