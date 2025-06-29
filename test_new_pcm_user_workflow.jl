# Test New PCM Model (ConstraintPool) - User Workflow Test
# This test mimics the user workflow: activate HOPE, run MD_PCM_Excel_case with UC=0,
# and compare results with the old PCM benchmark results.

using Pkg
Pkg.activate(".")

# Load HOPE package and dependencies
using HOPE
using DataFrames
using CSV
using JuMP
using Printf

println("="^60)
println("NEW PCM MODEL (ConstraintPool) - USER WORKFLOW TEST")
println("="^60)
println("Testing case: MD_PCM_Excel_case with UC=0")
println("Comparing against old PCM benchmark results")
println()

# Test configuration
case_path = "ModelCases/MD_PCM_Excel_case"
settings_file = joinpath(case_path, "Settings", "HOPE_model_settings.yml")

println("Step 1: Loading case configuration...")
try
    # Load configuration
    config_set = HOPE.read_config(settings_file)
    
    # Ensure UC=0 (no unit commitment) to match benchmark
    config_set["unit_commitment"] = 0
    config_set["model_mode"] = "PCM"
    
    println("✓ Configuration loaded successfully")
    println("  - Model mode: $(config_set["model_mode"])")
    println("  - Unit commitment: $(config_set["unit_commitment"])")
    println()
catch e
    println("✗ Error loading configuration: $e")
    exit(1)
end

println("Step 2: Loading input data...")
try
    # Load input data
    input_data = HOPE.read_input_data(case_path, config_set)
    println("✓ Input data loaded successfully")
    println("  - Zones: $(size(input_data["Zonedata"], 1))")
    println("  - Generators: $(size(input_data["Gendata"], 1))")
    println("  - Storage units: $(size(input_data["Storagedata"], 1))")
    println("  - Transmission lines: $(size(input_data["Linedata"], 1))")
    println()
catch e
    println("✗ Error loading input data: $e")
    exit(1)
end

println("Step 3: Creating and solving new PCM model...")
start_time = time()
try
    # Create model using new PCM with ConstraintPool
    model = HOPE.create_PCM_model(config_set, input_data, HOPE.get_optimizer(config_set))
    
    # Solve the model
    optimize!(model)
    
    solve_time = time() - start_time
    
    # Check solution status
    status = termination_status(model)
    println("✓ Model solved successfully")
    println("  - Termination status: $status")
    println("  - Solve time: $(round(solve_time, digits=2)) seconds")
    println("  - Objective value: \$$(round(objective_value(model), digits=2))")
    println()
    
    if status != MOI.OPTIMAL
        println("⚠ Warning: Model did not reach optimality")
    end
    
catch e
    println("✗ Error creating/solving model: $e")
    exit(1)
end

println("Step 4: Extracting key results...")
try
    # Extract key results for comparison
    obj_value = objective_value(model)
    
    # Generation results
    p_values = value.(model[:p])
    total_generation = sum(p_values)
    
    # Generator-specific results
    gendata = input_data["Gendata"]
    gen_results = Dict()
    
    for g in 1:size(gendata, 1)
        gen_type = gendata[g, "Type"]
        gen_zone = gendata[g, "Zone"]
        total_gen_g = sum(p_values[g, h] for h in 1:8760)
        gen_results["$(gen_type)_$(gen_zone)_G$g"] = total_gen_g
    end
    
    # Storage results
    if haskey(model, :c) && haskey(model, :dc)
        c_values = value.(model[:c])
        dc_values = value.(model[:dc])
        total_charging = sum(c_values)
        total_discharging = sum(dc_values)
    else
        total_charging = 0.0
        total_discharging = 0.0
    end
    
    # Load shedding
    if haskey(model, :p_LS)
        ls_values = value.(model[:p_LS])
        total_load_shedding = sum(ls_values)
    else
        total_load_shedding = 0.0
    end
    
    # Transmission flow
    if haskey(model, :f)
        f_values = value.(model[:f])
        total_transmission = sum(abs.(f_values))
    else
        total_transmission = 0.0
    end
    
    println("✓ Key results extracted")
    println()
    
catch e
    println("✗ Error extracting results: $e")
    exit(1)
end

println("Step 5: Comparison with old PCM benchmark results...")
println()

# Old PCM benchmark results (from BENCHMARK_RESULTS.md)
benchmark_results = Dict(
    "objective_value" => 183636307.92,
    "total_generation" => 44839728.35,
    "total_charging" => 168896.89,
    "total_discharging" => 144159.03,
    "total_load_shedding" => 0.0,
    "key_generators" => Dict(
        "NGCC_MD_G1" => 11270089.08,
        "NGCC_MD_G2" => 11270089.08,
        "NGCC_MD_G3" => 9694968.06,
        "Coal_MD_G4" => 2508877.97,
        "NuC_MD_G5" => 7884131.96,
        "Hydro_MD_G6" => 439636.29,
        "WindOn_MD_G7" => 1771935.91
    )
)

# Compare results
println("COMPARISON RESULTS:")
println("-" * 50)

# Objective value comparison
obj_diff = abs(obj_value - benchmark_results["objective_value"])
obj_rel_diff = obj_diff / benchmark_results["objective_value"] * 100

println(@sprintf("Objective Value:"))
println(@sprintf("  Benchmark: \$%.2f", benchmark_results["objective_value"]))
println(@sprintf("  New PCM:   \$%.2f", obj_value))
println(@sprintf("  Difference: \$%.2f (%.4f%%)", obj_diff, obj_rel_diff))

if obj_rel_diff < 0.01  # Less than 0.01% difference
    println("  ✓ PASS: Objective values match within tolerance")
else
    println("  ✗ FAIL: Objective values differ significantly")
end
println()

# Total generation comparison
gen_diff = abs(total_generation - benchmark_results["total_generation"])
gen_rel_diff = gen_diff / benchmark_results["total_generation"] * 100

println(@sprintf("Total Generation:"))
println(@sprintf("  Benchmark: %.2f MWh", benchmark_results["total_generation"]))
println(@sprintf("  New PCM:   %.2f MWh", total_generation))
println(@sprintf("  Difference: %.2f MWh (%.4f%%)", gen_diff, gen_rel_diff))

if gen_rel_diff < 0.01
    println("  ✓ PASS: Total generation matches within tolerance")
else
    println("  ✗ FAIL: Total generation differs significantly")
end
println()

# Storage comparison
if total_charging > 0 || total_discharging > 0
    charge_diff = abs(total_charging - benchmark_results["total_charging"])
    discharge_diff = abs(total_discharging - benchmark_results["total_discharging"])
    
    println(@sprintf("Storage Operations:"))
    println(@sprintf("  Charging - Benchmark: %.2f MWh, New PCM: %.2f MWh", 
            benchmark_results["total_charging"], total_charging))
    println(@sprintf("  Discharging - Benchmark: %.2f MWh, New PCM: %.2f MWh", 
            benchmark_results["total_discharging"], total_discharging))
    
    if charge_diff < 100 && discharge_diff < 100  # Within 100 MWh
        println("  ✓ PASS: Storage operations match within tolerance")
    else
        println("  ✗ FAIL: Storage operations differ significantly")
    end
else
    println("Storage Operations: No storage activity detected")
end
println()

# Key generator comparison
println("Key Generator Comparison:")
all_generators_match = true
for (gen_name, benchmark_value) in benchmark_results["key_generators"]
    if haskey(gen_results, gen_name)
        new_value = gen_results[gen_name]
        diff = abs(new_value - benchmark_value)
        rel_diff = diff / benchmark_value * 100
        
        println(@sprintf("  %s:", gen_name))
        println(@sprintf("    Benchmark: %.2f MWh", benchmark_value))
        println(@sprintf("    New PCM:   %.2f MWh", new_value))
        println(@sprintf("    Diff: %.2f MWh (%.4f%%)", diff, rel_diff))
        
        if rel_diff < 0.01
            println("    ✓ PASS")
        else
            println("    ✗ FAIL")
            all_generators_match = false
        end
    else
        println(@sprintf("  %s: NOT FOUND in new results", gen_name))
        all_generators_match = false
    end
    println()
end

# Load shedding comparison
println(@sprintf("Load Shedding:"))
println(@sprintf("  Benchmark: %.2f MWh", benchmark_results["total_load_shedding"]))
println(@sprintf("  New PCM:   %.2f MWh", total_load_shedding))

if total_load_shedding == benchmark_results["total_load_shedding"]
    println("  ✓ PASS: Load shedding matches")
else
    println("  ✗ FAIL: Load shedding differs")
end
println()

# Overall test result
println("="^60)
println("OVERALL TEST RESULT:")
println("="^60)

if obj_rel_diff < 0.01 && gen_rel_diff < 0.01 && all_generators_match && total_load_shedding == benchmark_results["total_load_shedding"]
    println("✓ PASS: New PCM model successfully reproduces old PCM benchmark results!")
    println("The ConstraintPool-based PCM implementation is validated.")
else
    println("✗ FAIL: New PCM model results differ from old PCM benchmark!")
    println("Further investigation needed to identify discrepancies.")
    
    # Provide debugging information
    println()
    println("DEBUGGING INFORMATION:")
    println("-" * 30)
    println("Model variables available:")
    for var_name in keys(object_dictionary(model))
        println("  - $var_name")
    end
    
    println()
    println("Top 10 generators by output:")
    sorted_gens = sort(collect(gen_results), by=x->x[2], rev=true)
    for (i, (gen_name, output)) in enumerate(sorted_gens[1:min(10, length(sorted_gens))])
        println(@sprintf("  %d. %s: %.2f MWh", i, gen_name, output))
    end
end

println("="^60)
println("Test completed at $(Dates.now())")
println("="^60)
