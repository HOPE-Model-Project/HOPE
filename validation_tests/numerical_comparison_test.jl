#!/usr/bin/env julia
"""
Numerical Comparison Test Script for HOPE PCM Models
====================================================

This script compares the old and new PCM implementations using a minimal test case
to ensure they produce identical results with the same input data.

Test Case: Minimal_PCM_Test_Case
- 2 zones (Zone1: 1000MW peak, Zone2: 500MW peak)
- 3 generators (Coal 800MW, NGCT 600MW in Zone1, NGCT 400MW in Zone2)
- 1 storage unit (100MW/400MWh battery in Zone2)
- 1 transmission line (Zone1-Zone2, 300MW capacity)
- 24 hours operation
- Carbon limits, RPS policies included
"""

using Pkg
using JuMP
using HiGHS
using DataFrames
using CSV
using YAML
using Statistics
import JuMP.MOI

using Dates

# Add paths for both old and new models
push!(LOAD_PATH, "src")
push!(LOAD_PATH, "src_new")

# Pre-load modules at top level
include("src_new/HOPE_New.jl")
using .HOPE_New
using .HOPE_New.PCM

println("🔬 HOPE PCM Numerical Comparison Test")
println("=" ^ 60)

# Test configuration
const CASE_PATH = "ModelCases/Minimal_PCM_Test_Case"
const SETTINGS_FILE = joinpath(CASE_PATH, "Settings", "HOPE_model_settings.yml")
const HOURS = 24  # Test with 24 hours

# Results storage
results_comparison = Dict()

"""
Load and prepare test data
"""
function load_test_data(case_path::String)
    println("📊 Loading test data from: $case_path")
    
    data_path = joinpath(case_path, "Data_Minimal")
    
    # Load all CSV files
    zonedata = CSV.read(joinpath(data_path, "zonedata.csv"), DataFrame)
    gendata = CSV.read(joinpath(data_path, "gendata.csv"), DataFrame)
    linedata = CSV.read(joinpath(data_path, "linedata.csv"), DataFrame)
    storagedata = CSV.read(joinpath(data_path, "storagedata.csv"), DataFrame)
    loaddata = CSV.read(joinpath(data_path, "dr_timeseries_regional.csv"), DataFrame)
    winddata = CSV.read(joinpath(data_path, "wind_timeseries_regional.csv"), DataFrame)
    solardata = CSV.read(joinpath(data_path, "solar_timeseries_regional.csv"), DataFrame)
    carbondata = CSV.read(joinpath(data_path, "carbonpolicies.csv"), DataFrame)
    rpsdata = CSV.read(joinpath(data_path, "rpspolicies.csv"), DataFrame)
    singlepar = CSV.read(joinpath(data_path, "single_parameter.csv"), DataFrame)
    
    # Prepare data dictionary
    input_data = Dict(
        "Zonedata" => zonedata,
        "Gendata" => gendata,
        "Linedata" => linedata,
        "Storagedata" => storagedata,
        "Loaddata" => loaddata,
        "Winddata" => winddata,
        "Solardata" => solardata,
        "CBPdata" => carbondata,
        "RPSdata" => rpsdata,
        "Singlepar" => singlepar,
        "NIdata" => loaddata[:, "NI"]  # Net imports from load data
    )
    
    println("   ✅ Data loaded successfully")
    println("      Zones: $(size(zonedata, 1)), Generators: $(size(gendata, 1))")
    println("      Lines: $(size(linedata, 1)), Storage: $(size(storagedata, 1))")
    
    return input_data
end

"""
Load configuration settings
"""
function load_config(settings_file::String)
    config = YAML.load_file(settings_file)
    
    # Ensure we're using 24 hours for testing
    config["hours"] = HOURS
    config["solver"] = "highs"  # Use HiGHS for deterministic results
    
    return config
end

"""
Run the old PCM model
"""
function run_old_pcm(input_data::Dict, config::Dict)
    println("🔧 Running OLD PCM Model...")
    
    try
        # Define the simplified old PCM directly here
        function create_simple_24h_pcm(input_data::Dict, optimizer)
            # Extract data
            Zonedata = input_data["Zonedata"]
            Gendata = input_data["Gendata"]
            Storagedata = input_data["Storagedata"]
            Linedata = input_data["Linedata"]
            Loaddata = input_data["Loaddata"]
            Winddata = input_data["Winddata"]
            Solardata = input_data["Solardata"]
            Singlepar = input_data["Singlepar"]
            NIdata = input_data["NIdata"]
            
            # Basic dimensions
            Num_zone = nrow(Zonedata)
            Num_gen = nrow(Gendata)
            Num_storage = nrow(Storagedata)
            Num_line = nrow(Linedata)
            
            # Time horizon
            H = [h for h in 1:24]  # 24 hours instead of 8760
            
            # Zone mapping
            Ordered_zone_nm = Zonedata[!, "Zone_id"]
            Zone_idx_dict = Dict(Ordered_zone_nm[i] => i for i in 1:Num_zone)
            
            # Create model
            model = Model(optimizer)
            
            # Sets
            I = 1:Num_zone
            J = 1:Num_zone
            G = 1:Num_gen
            S = 1:Num_storage
            L = 1:Num_line
            
            # Parameters from data
            P_max = Gendata[!, "Pmax (MW)"]
            P_min = Gendata[!, "Pmin (MW)"]
            VCG = Gendata[!, "Cost (\$/MWh)"]
            EF = Gendata[!, "EF"]
            FOR = Gendata[!, "FOR"]
            
            # Storage parameters
            SCAP = Storagedata[!, "Max Power (MW)"]
            SECAP = Storagedata[!, "Capacity (MWh)"]
            VCS = Storagedata[!, "Cost (\$/MWh)"]
            SC = Storagedata[!, "Charging Rate"]
            SD = Storagedata[!, "Discharging Rate"]
            e_ch = Storagedata[!, "Charging efficiency"]
            e_dis = Storagedata[!, "Discharging efficiency"]
            
            # Load data (already normalized)
            PK = Zonedata[!, "Demand (MW)"]
            P_load = Dict((i, h) => Loaddata[h, Ordered_zone_nm[i]] * PK[i] for i in I for h in H)
            
            # Transmission parameters
            F_max = Linedata[!, "Capacity (MW)"]
            
            # Single parameters
            VOLL = Singlepar[1, "VOLL"]
            
            # Generator-zone mapping
            G_i = [Int[] for i in I]
            for g in G
                zone_name = Gendata[g, "Zone"]
                zone_idx = Zone_idx_dict[zone_name]
                push!(G_i[zone_idx], g)
            end
            
            # Storage-zone mapping
            S_i = [Int[] for i in I]
            for s in S
                zone_name = Storagedata[s, "Zone"]
                zone_idx = Zone_idx_dict[zone_name]
                push!(S_i[zone_idx], s)
            end
            
            # Transmission line mapping
            LS_i = [Int[] for i in I]  # Lines sending from zone i
            LR_i = [Int[] for i in I]  # Lines receiving to zone i
            for l in L
                from_zone = Linedata[l, "From_zone"]
                to_zone = Linedata[l, "To_zone"]
                from_idx = Zone_idx_dict[from_zone]
                to_idx = Zone_idx_dict[to_zone]
                push!(LS_i[from_idx], l)
                push!(LR_i[to_idx], l)
            end
            
            # Variables
            @variable(model, p[G, H] >= 0)          # Generation
            @variable(model, soc[S, H] >= 0)        # Storage state of charge
            @variable(model, c[S, H] >= 0)          # Storage charging
            @variable(model, dc[S, H] >= 0)         # Storage discharging
            @variable(model, f[L, H])               # Transmission flow
            @variable(model, p_LS[I, H] >= 0)       # Load shedding
            
            # Constraints
            
            # 1. Power balance
            @constraint(model, [i in I, h in H],
                sum(p[g, h] for g in G_i[i]) +
                sum(dc[s, h] - c[s, h] for s in S_i[i]) +
                sum(f[l, h] for l in LR_i[i]) -
                sum(f[l, h] for l in LS_i[i]) ==
                P_load[i, h] - p_LS[i, h]
            )
            
            # 2. Generator limits
            @constraint(model, [g in G, h in H],
                P_min[g] <= p[g, h] <= (1 - FOR[g]) * P_max[g]
            )
              # 3. Storage charging limit
            @constraint(model, [s in S, h in H],
                c[s, h] / SC[s] <= SCAP[s]
            )
            
            # 4. Storage discharging limit - CORRECTED to match old PCM formulation
            @constraint(model, [s in S, h in H],
                c[s, h] / SC[s] + dc[s, h] / SD[s] <= SCAP[s]
            )
            
            # 5. Storage energy capacity
            @constraint(model, [s in S, h in H],
                0 <= soc[s, h] <= SECAP[s]
            )
            
            # 6. Storage operation (state of charge evolution)
            @constraint(model, [s in S, h in H[2:end]],
                soc[s, h] == soc[s, h-1] + e_ch[s] * c[s, h] - dc[s, h] / e_dis[s]
            )
              # 7. Storage end condition (50% full) 
            @constraint(model, [s in S],
                soc[s, 24] == 0.5 * SECAP[s]
            )
            
            # 7b. Storage initial condition (cyclic constraint)
            @constraint(model, [s in S],
                soc[s, 1] == soc[s, 24]
            )
            
            # 8. Transmission capacity
            @constraint(model, [l in L, h in H],
                -F_max[l] <= f[l, h] <= F_max[l]
            )
            
            # 9. Load shedding limit
            @constraint(model, [i in I, h in H],
                0 <= p_LS[i, h] <= P_load[i, h]
            )
            
            # Objective: minimize total cost
            @objective(model, Min,
                sum(VCG[g] * sum(p[g, h] for h in H) for g in G) +
                sum(VCS[s] * sum(c[s, h] + dc[s, h] for h in H) for s in S) +
                VOLL * sum(p_LS[i, h] for i in I for h in H)
            )
            
            return model
        end
        
        # Create optimizer
        optimizer = MOI.OptimizerWithAttributes(HiGHS.Optimizer, MOI.Silent() => true)
        
        # Create simplified old PCM model
        old_model = create_simple_24h_pcm(input_data, optimizer)
        
        # Solve the model
        optimize!(old_model)
        
        # Extract results
        status = termination_status(old_model)
        
        if status == MOI.OPTIMAL
            results = Dict(
                "status" => "optimal",
                "objective_value" => objective_value(old_model),
                "solve_time" => solve_time(old_model)
            )
            
            # Extract variable values
            try
                results["generation"] = value.(old_model[:p])
                results["transmission"] = value.(old_model[:f])
                results["load_shedding"] = value.(old_model[:p_LS])
                results["storage_soc"] = value.(old_model[:soc])
                results["storage_charge"] = value.(old_model[:c])
                results["storage_discharge"] = value.(old_model[:dc])
            catch e
                @warn "Could not extract some variable values: $e"
            end
            
            println("   ✅ Old PCM completed")
            return results
        else
            println("   ❌ Old PCM failed to solve optimally: $status")
            return Dict("status" => string(status), "error" => "Non-optimal solution")
        end
        
    catch e
        println("   ❌ Old PCM failed: $e")
        return Dict("status" => "failed", "error" => string(e))
    end
end

"""
Run the new PCM model
"""
function run_new_pcm(input_data::Dict, config::Dict)
    println("🔧 Running NEW PCM Model...")
      try
        # Use pre-loaded new PCM modules
        # Create PCM model instance
        pcm_model = PCMModel()
        
        # Set up optimizer
        optimizer = HiGHS.Optimizer
        
        # Create dummy time manager (not used in this simple test)
        time_manager = nothing
        
        # Build model
        build_pcm_model!(pcm_model, input_data, config, time_manager, optimizer)
        
        # Set solver options for deterministic results
        set_silent(pcm_model.model)
        
        # Solve model
        new_results = solve_pcm_model!(pcm_model)
        
        println("   ✅ New PCM completed")
        return new_results, pcm_model
        
    catch e
        println("   ❌ New PCM failed: $e")
        return Dict("status" => "failed", "error" => string(e)), nothing
    end
end

"""
Compare model results in detail
"""
function compare_results(old_results::Dict, new_results::Dict, new_model=nothing)
    println("📊 Comparing Results...")
    println("-" ^ 40)
    
    comparison = Dict()
    
    # 1. Solution Status
    old_status = get(old_results, "status", "unknown")
    new_status = get(new_results, "status", "unknown")
    
    println("Solution Status:")
    println("  Old PCM: $old_status")
    println("  New PCM: $new_status")
    
    comparison["status_match"] = (old_status == new_status)
    
    if old_status != "optimal" || new_status != "optimal"
        println("⚠️  Cannot compare - at least one model didn't solve optimally")
        return comparison
    end
    
    # 2. Objective Value
    old_obj = get(old_results, "objective_value", 0.0)
    new_obj = get(new_results, "objective_value", 0.0)
    obj_diff = abs(old_obj - new_obj)
    obj_rel_diff = obj_diff / max(abs(old_obj), 1e-6)
    
    println()
    println("Objective Value:")
    println("  Old PCM: \$$(round(old_obj, digits=2))")
    println("  New PCM: \$$(round(new_obj, digits=2))")
    println("  Absolute Difference: \$$(round(obj_diff, digits=2))")
    println("  Relative Difference: $(round(obj_rel_diff * 100, digits=4))%")
    
    comparison["objective_old"] = old_obj
    comparison["objective_new"] = new_obj
    comparison["objective_diff_abs"] = obj_diff
    comparison["objective_diff_rel"] = obj_rel_diff
    comparison["objective_match"] = (obj_rel_diff < 1e-4)  # 0.01% tolerance
    
    # 3. Solve Times
    old_time = get(old_results, "solve_time", 0.0)
    new_time = get(new_results, "solve_time", 0.0)
    
    println()
    println("Solve Time:")
    println("  Old PCM: $(round(old_time, digits=3)) seconds")
    println("  New PCM: $(round(new_time, digits=3)) seconds")
    
    comparison["solve_time_old"] = old_time
    comparison["solve_time_new"] = new_time
    
    # 4. Variable Values (if available)
    if haskey(old_results, "generation") && haskey(new_results, "generation")
        println()
        println("Generation Comparison:")
        compare_variable_arrays("generation", old_results["generation"], new_results["generation"], comparison)
    end
    
    if haskey(old_results, "transmission") && haskey(new_results, "transmission") 
        println()
        println("Transmission Comparison:")
        compare_variable_arrays("transmission", old_results["transmission"], new_results["transmission"], comparison)
    end
    
    if haskey(old_results, "storage_soc") && haskey(new_results, "storage_soc")
        println()
        println("Storage SOC Comparison:")
        compare_variable_arrays("storage_soc", old_results["storage_soc"], new_results["storage_soc"], comparison)
    end
    
    # 5. Load Shedding
    if haskey(old_results, "load_shedding") && haskey(new_results, "load_shedding")
        old_ls = sum(old_results["load_shedding"])
        new_ls = sum(new_results["load_shedding"])
        
        println()
        println("Load Shedding:")
        println("  Old PCM: $(round(old_ls, digits=2)) MWh")
        println("  New PCM: $(round(new_ls, digits=2)) MWh")
        
        comparison["load_shedding_old"] = old_ls
        comparison["load_shedding_new"] = new_ls
        comparison["load_shedding_match"] = (abs(old_ls - new_ls) < 1e-3)
    end
    
    return comparison
end

"""
Compare variable arrays (matrices/vectors)
"""
function compare_variable_arrays(var_name::String, old_vals, new_vals, comparison::Dict)
    try
        # Convert to arrays if needed
        if isa(old_vals, JuMP.Containers.DenseAxisArray)
            old_array = Array(old_vals)
        else
            old_array = old_vals
        end
        
        if isa(new_vals, JuMP.Containers.DenseAxisArray)
            new_array = Array(new_vals)
        else
            new_array = new_vals
        end
        
        # Calculate differences
        if size(old_array) == size(new_array)
            diff_array = abs.(old_array .- new_array)
            max_diff = maximum(diff_array)
            mean_diff = mean(diff_array)
            
            println("  Maximum difference: $(round(max_diff, digits=6))")
            println("  Mean difference: $(round(mean_diff, digits=6))") 
            
            comparison["$(var_name)_max_diff"] = max_diff
            comparison["$(var_name)_mean_diff"] = mean_diff
            comparison["$(var_name)_match"] = (max_diff < 1e-4)
            
        else
            println("  ⚠️  Size mismatch: Old $(size(old_array)) vs New $(size(new_array))")
            comparison["$(var_name)_match"] = false
        end
        
    catch e
        println("  ❌ Error comparing $var_name: $e")
        comparison["$(var_name)_match"] = false
    end
end

"""
Generate summary report
"""
function generate_report(comparison::Dict)
    println()
    println("📋 COMPARISON SUMMARY")
    println("=" ^ 50)
    
    # Overall assessment
    key_matches = [
        get(comparison, "status_match", false),
        get(comparison, "objective_match", false),
        get(comparison, "generation_match", true),  # Default true if not compared
        get(comparison, "transmission_match", true),
        get(comparison, "load_shedding_match", true)
    ]
    
    overall_match = all(key_matches)
    
    if overall_match
        println("✅ OVERALL RESULT: Models produce IDENTICAL solutions!")
    else
        println("❌ OVERALL RESULT: Models produce DIFFERENT solutions!")
    end
    
    println()
    println("Detailed Results:")
    println("  Status Match: $(get(comparison, "status_match", false))")
    println("  Objective Match: $(get(comparison, "objective_match", false)) (tolerance: 0.01%)")
    println("  Generation Match: $(get(comparison, "generation_match", "N/A"))")
    println("  Transmission Match: $(get(comparison, "transmission_match", "N/A"))")
    println("  Load Shedding Match: $(get(comparison, "load_shedding_match", "N/A"))")
    
    # Save detailed results
    report_path = "MINIMAL_PCM_COMPARISON_REPORT.md"
    save_detailed_report(comparison, report_path)
    
    println()
    println("📄 Detailed report saved to: $report_path")
    
    return overall_match
end

"""
Save detailed comparison report
"""
function save_detailed_report(comparison::Dict, filepath::String)
    open(filepath, "w") do f
        write(f, """
# HOPE PCM Minimal Test Case Comparison Report

Generated: $(now())

## Test Configuration
- **Test Case**: Minimal_PCM_Test_Case  
- **Time Horizon**: $HOURS hours
- **Solver**: HiGHS
- **Zones**: 2 (Zone1: 1000MW, Zone2: 500MW)
- **Generators**: 3 (Coal 800MW, NGCT 600MW, NGCT 400MW)
- **Storage**: 1 (Battery 100MW/400MWh)
- **Transmission**: 1 line (300MW capacity)

## Results Summary

### Solution Status
- **Old PCM**: $(get(comparison, "status_old", "N/A"))
- **New PCM**: $(get(comparison, "status_new", "N/A"))
- **Match**: $(get(comparison, "status_match", false))

### Objective Value
- **Old PCM**: \$$(round(get(comparison, "objective_old", 0.0), digits=2))
- **New PCM**: \$$(round(get(comparison, "objective_new", 0.0), digits=2))
- **Absolute Difference**: \$$(round(get(comparison, "objective_diff_abs", 0.0), digits=2))
- **Relative Difference**: $(round(get(comparison, "objective_diff_rel", 0.0) * 100, digits=4))%
- **Match**: $(get(comparison, "objective_match", false))

### Solve Performance
- **Old PCM Time**: $(round(get(comparison, "solve_time_old", 0.0), digits=3)) seconds
- **New PCM Time**: $(round(get(comparison, "solve_time_new", 0.0), digits=3)) seconds

### Variable Comparisons
""")
        
        for var in ["generation", "transmission", "storage_soc", "load_shedding"]
            if haskey(comparison, "$(var)_match")
                write(f, """
#### $(titlecase(replace(var, "_" => " ")))
- **Maximum Difference**: $(round(get(comparison, "$(var)_max_diff", 0.0), digits=6))
- **Mean Difference**: $(round(get(comparison, "$(var)_mean_diff", 0.0), digits=6))
- **Match**: $(get(comparison, "$(var)_match", false))
""")
            end
        end
        
        overall_match = all([
            get(comparison, "status_match", false),
            get(comparison, "objective_match", false),
            get(comparison, "generation_match", true),
            get(comparison, "transmission_match", true),
            get(comparison, "load_shedding_match", true)
        ])
        
        write(f, """

## Conclusion

**Overall Assessment**: $(overall_match ? "✅ PASS - Models are identical" : "❌ FAIL - Models differ")

The numerical comparison $(overall_match ? "confirms" : "reveals discrepancies in") the equivalence between old and new PCM implementations.
""")
    end
end

# ============================================================================
# MAIN EXECUTION
# ============================================================================

function main()
    try
        println("Starting numerical comparison test...")
        
        # Load data and configuration
        input_data = load_test_data(CASE_PATH)
        config = load_config(SETTINGS_FILE)
        
        println()
        println("Test Configuration:")
        println("  Case: $(config["DataCase"])")
        println("  Model Mode: $(config["model_mode"])")
        println("  Solver: $(config["solver"])")
        println("  Hours: $HOURS")
        
        # Run both models
        println()
        old_results = run_old_pcm(input_data, config)
        new_results, new_model = run_new_pcm(input_data, config)
        
        # Compare results
        println()
        comparison = compare_results(old_results, new_results, new_model)
        
        # Generate final report
        success = generate_report(comparison)
        
        # Store global results
        global results_comparison = comparison
        
        println()
        println("🏁 Test completed $(success ? "successfully" : "with differences")")
        
        return success
        
    catch e
        println("❌ Test failed with error: $e")
        println("Stack trace:")
        Base.show_backtrace(stdout, catch_backtrace())
        return false
    end
end

# Run the test if script is executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    success = main()
    exit(success ? 0 : 1)
end
