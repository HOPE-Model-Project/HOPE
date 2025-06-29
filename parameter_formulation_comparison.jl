"""
Parameter and Formulation Comparison - Old vs New PCM
===================================================
Since both models have complete constraints, this script compares:
1. Parameter values (P_max, P_min, VCG, etc.)
2. Index sets (G_i vs G_exist, etc.)  
3. Mathematical formulation differences
4. Constraint coefficient consistency

Goal: Identify exact source of objective value differences
"""

using Pkg
Pkg.activate(".")

include("src_new/HOPE_New.jl")
using .HOPE_New

include("src/HOPE.jl")
using .HOPE

using JuMP, YAML

function compare_parameter_values()
    """Compare parameter values between old and new data loading systems"""
    
    println("🔍 PARAMETER VALUE COMPARISON")
    println("="^80)
    
    # Load data using NEW system
    case_path = "ModelCases/MD_PCM_Excel_case"
    config_file = joinpath(case_path, "Settings", "HOPE_model_settings.yml")
    config = YAML.load_file(config_file)
    config["unit_commitment"] = 0
    
    println("📊 Loading data with NEW system...")
    reader = HOPE_New.SimpleHOPEDataReader(case_path)
    new_input_data, new_config = HOPE_New.load_simple_case_data(reader, case_path)
    
    println("📊 Loading data with OLD system...")
    old_input_data = HOPE.load_data(config, case_path)
    
    # Compare key parameters
    println("\n🔍 PARAMETER COMPARISON:")
    compare_generator_parameters(old_input_data, new_input_data)
    compare_load_parameters(old_input_data, new_input_data)
    compare_transmission_parameters(old_input_data, new_input_data)
    compare_storage_parameters(old_input_data, new_input_data)
end

function compare_generator_parameters(old_data, new_data)
    """Compare generator-related parameters"""
    
    println("\n📊 GENERATOR PARAMETERS:")
    
    # Check if both have generator data
    if haskey(old_data, "P_max") && haskey(new_data, "P_max")
        old_pmax = old_data["P_max"]
        new_pmax = new_data["P_max"]
        
        println("   P_max:")
        println("     OLD length: $(length(old_pmax))")
        println("     NEW length: $(length(new_pmax))")
        
        if length(old_pmax) == length(new_pmax)
            differences = sum(abs.(old_pmax .- new_pmax))
            println("     Total difference: $differences")
            if differences < 1e-10
                println("     ✅ P_max values match")
            else
                println("     ❌ P_max values differ!")
                # Show first few differences
                for i in 1:min(5, length(old_pmax))
                    if abs(old_pmax[i] - new_pmax[i]) > 1e-10
                        println("       Generator $i: OLD=$(old_pmax[i]), NEW=$(new_pmax[i])")
                    end
                end
            end
        else
            println("     ❌ Different number of generators!")
        end
    else
        println("   ❌ P_max not found in one or both datasets")
    end
    
    # Check P_min
    if haskey(old_data, "P_min") && haskey(new_data, "P_min")
        old_pmin = old_data["P_min"]
        new_pmin = new_data["P_min"]
        differences = sum(abs.(old_pmin .- new_pmin))
        println("   P_min total difference: $differences")
        if differences < 1e-10
            println("     ✅ P_min values match")
        else
            println("     ❌ P_min values differ!")
        end
    end
    
    # Check VCG (variable cost)
    if haskey(old_data, "VCG") && haskey(new_data, "VCG")
        old_vcg = old_data["VCG"]
        new_vcg = new_data["VCG"]
        differences = sum(abs.(old_vcg .- new_vcg))
        println("   VCG total difference: $differences")
        if differences < 1e-10
            println("     ✅ VCG values match")
        else
            println("     ❌ VCG values differ!")
            # Show cost differences for first few generators
            for i in 1:min(5, length(old_vcg))
                if abs(old_vcg[i] - new_vcg[i]) > 1e-10
                    println("       Generator $i cost: OLD=$(old_vcg[i]), NEW=$(new_vcg[i])")
                end
            end
        end
    end
end

function compare_load_parameters(old_data, new_data)
    """Compare load/demand parameters"""
    
    println("\n📊 LOAD PARAMETERS:")
    
    # Check load data structure
    if haskey(old_data, "P_load") && haskey(new_data, "P_load")
        old_load = old_data["P_load"]
        new_load = new_data["P_load"]
        
        println("   Load data structure:")
        println("     OLD type: $(typeof(old_load))")
        println("     NEW type: $(typeof(new_load))")
        
        # If both are dictionaries, compare by zone
        if isa(old_load, Dict) && isa(new_load, Dict)
            old_zones = collect(keys(old_load))
            new_zones = collect(keys(new_load))
            
            println("     OLD zones: $(length(old_zones))")
            println("     NEW zones: $(length(new_zones))")
            
            common_zones = intersect(old_zones, new_zones)
            println("     Common zones: $(length(common_zones))")
            
            for zone in common_zones[1:min(3, length(common_zones))]
                old_zone_load = old_load[zone]
                new_zone_load = new_load[zone]
                
                if length(old_zone_load) == length(new_zone_load)
                    differences = sum(abs.(old_zone_load .- new_zone_load))
                    println("     Zone $zone load difference: $differences")
                    if differences < 1e-10
                        println("       ✅ Zone $zone loads match")
                    else
                        println("       ❌ Zone $zone loads differ!")
                    end
                else
                    println("     ❌ Zone $zone: different time series lengths")
                end
            end
        end
    else
        println("   ❌ P_load structure differs or missing")
    end
end

function compare_transmission_parameters(old_data, new_data)
    """Compare transmission parameters"""
    
    println("\n📊 TRANSMISSION PARAMETERS:")
    
    if haskey(old_data, "F_max") && haskey(new_data, "F_max")
        old_fmax = old_data["F_max"]
        new_fmax = new_data["F_max"]
        
        println("   F_max:")
        println("     OLD length: $(length(old_fmax))")
        println("     NEW length: $(length(new_fmax))")
        
        if length(old_fmax) == length(new_fmax)
            differences = sum(abs.(old_fmax .- new_fmax))
            println("     Total difference: $differences")
            if differences < 1e-10
                println("     ✅ F_max values match")
            else
                println("     ❌ F_max values differ!")
            end
        else
            println("     ❌ Different number of transmission lines!")
        end
    else
        println("   ❌ F_max not found in one or both datasets")
    end
end

function compare_storage_parameters(old_data, new_data)
    """Compare storage parameters"""
    
    println("\n📊 STORAGE PARAMETERS:")
    
    storage_params = ["SCAP", "SECAP", "VCS", "EFF"]
    
    for param in storage_params
        if haskey(old_data, param) && haskey(new_data, param)
            old_val = old_data[param]
            new_val = new_data[param]
            
            if isa(old_val, Vector) && isa(new_val, Vector) && length(old_val) == length(new_val)
                differences = sum(abs.(old_val .- new_val))
                println("   $param difference: $differences")
                if differences < 1e-10
                    println("     ✅ $param values match")
                else
                    println("     ❌ $param values differ!")
                end
            else
                println("   ❌ $param: structure mismatch")
            end
        else
            println("   ⚠️  $param: not found in one or both datasets")
        end
    end
end

function compare_index_sets()
    """Compare index sets between old and new PCM"""
    
    println("\n🔍 INDEX SET COMPARISON")
    println("="^80)
    
    # This would require building both models to compare sets
    # For now, let's focus on data-level comparison
    println("📊 Index set comparison requires model building...")
    println("   Key sets to verify:")
    println("   • G_exist (existing generators)")
    println("   • G_i (generators by zone)")
    println("   • I (zones)")
    println("   • H (time periods)")
    println("   • L_exist (transmission lines)")
    println("   • S_exist (storage units)")
end

function run_parameter_comparison()
    """Run the complete parameter comparison analysis"""
    
    println("🔍 PARAMETER & FORMULATION COMPARISON")
    println("="^80)
    println("Identifying exact source of objective value differences")
    println("between old and new PCM implementations")
    println("")
    
    try
        compare_parameter_values()
        compare_index_sets()
        
        println("\n" * "="^80)
        println("📊 COMPARISON SUMMARY")
        println("="^80)
        println("")
        println("🎯 Key areas to investigate further:")
        println("   1. Parameter value mismatches identified above")
        println("   2. Index set differences (requires model building)")
        println("   3. Constraint coefficient calculation differences")
        println("   4. Objective function formulation differences")
        
    catch e
        println("❌ Error during comparison: $e")
        println("Stacktrace:")
        for (exc, bt) in Base.catch_stack()
            showerror(stdout, exc, bt)
            println()
        end
    end
end

# Run the analysis
if abspath(PROGRAM_FILE) == @__FILE__
    run_parameter_comparison()
end
