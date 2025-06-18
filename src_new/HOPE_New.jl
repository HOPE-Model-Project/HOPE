"""
# HOPE_New.jl - New Modular HOPE Architecture Entry Point
# 
# This is the main module for the redesigned HOPE architecture,
# demonstrating the new modular, extensible, and transparent design.
"""

module HOPE_New

# Import required packages
using JuMP
using DataFrames
using HiGHS  # Default solver

# Core architecture components
include("core/ConstraintPool.jl")
include("core/ConstraintImplementations.jl") 
include("core/TimeManager.jl")
include("core/ModelBuilder.jl")

# Input/Output layer
include("io/DataReader.jl")

# Utilities
include("utils/Utils.jl")

# Output layer
include("output/SolverInterface.jl")
include("output/OutputWriter.jl")  
include("output/PlotGenerator.jl")
include("output/HolisticWorkflow.jl")

# Re-export key functions and types
export HOPEModelBuilder, HOPEDataReader
export initialize!, build_model!, get_model_report
export load_hope_data

# Export output functions
export SolverConfig, SolutionInfo, HOPEOutputWriter, HOPEPlotGenerator
export HolisticConfig, HolisticResults
export solve_hope_model!, write_results!, generate_all_plots!
export run_holistic_workflow!

"""
Main function to run HOPE with new architecture
"""
function run_hope_new(
    case_path::String;
    optimizer = nothing,
    debug_mode::Bool = false
)
    println("🚀 Starting HOPE with New Architecture")
    println("📁 Case: $case_path")
    
    # Initialize data reader
    reader = HOPEDataReader(case_path)
    
    # Load configuration and data
    input_data = load_hope_data(reader)
    config = load_configuration(reader)
    
    # Set debug mode
    if debug_mode
        config["debug"] = 2
    end
      # Initialize solver if not provided
    if optimizer === nothing
        optimizer = HiGHS.Optimizer
    end
    
    # Create model builder
    builder = HOPEModelBuilder()
    builder.constraint_pool.debug_mode = debug_mode
    
    # Initialize builder with data and config
    initialize!(builder, config, input_data, optimizer)
    
    # Build the complete model
    model = build_model!(builder)
    
    # Solve the model
    println("🔧 Solving model...")
    optimize!(model)
    
    # Check solution status
    status = termination_status(model)
    println("📊 Solution status: $status")
    
    if status == MOI.OPTIMAL
        println("✅ Optimal solution found!")
        println("💰 Objective value: $(objective_value(model))")
    elseif status == MOI.INFEASIBLE
        println("❌ Model is infeasible")
        if debug_mode
            println("🔍 Running debug analysis...")
            # TODO: Add debug functionality using constraint pool
        end
    else
        println("⚠️  Solution status: $status")
    end
    
    # Generate model report
    report = get_model_report(builder)
    println("📋 Model Report:")
    for (key, value) in report
        if key != "constraint_report"
            println("   $key: $value")
        end
    end
    
    # Print constraint report if available
    if haskey(report, "constraint_report") && !isempty(report["constraint_report"])
        println("\n📊 Constraint Report:")
        constraint_df = report["constraint_report"]
        for row in eachrow(constraint_df)
            if row.Status == "VIOLATED"
                println("   ⚠️  $(row.Constraint): $(row.Description) - Violation: $(row.MaxViolation)")
            end
        end
    end
    
    return (model, builder, report)
end

"""
Demonstrate the new architecture with a simple example
"""
function demo_new_architecture()
    println("🎯 HOPE New Architecture Demo")
    
    # Create a minimal test case in memory
    println("📝 Creating minimal test case...")
    
    # This would normally load from files, but for demo we create minimal data
    config = Dict(
        "model_mode" => "PCM",
        "solver" => "HiGHS",
        "unit_commitment" => 0,
        "flexible_demand" => 0,
        "debug" => 0
    )
    
    # Minimal input data structure
    input_data = Dict{String, Any}(
        "I" => ["Zone1"],  # Zones
        "W" => ["State1"], # States
        "G" => [1, 2],     # Two generators
        "S" => Int[],      # No storage
        "L" => Int[],      # No transmission
        "H" => collect(1:24), # 24 hours
          # Generator data
        "Gendata" => DataFrame(
            "Zone" => ["Zone1", "Zone1"],
            "Type" => ["Coal", "Gas"],
            "Pmax (MW)" => [100.0, 200.0],
            "Cost (\$/MWh)" => [50.0, 80.0]
        ),
          # Load data (single zone, 24 hours)
        "Loaddata" => DataFrame(
            "Hour" => 1:24,
            "Zone1" => [80, 75, 70, 65, 60, 65, 70, 80, 90, 100, 110, 120,
                       125, 120, 115, 110, 105, 100, 95, 90, 85, 80, 75, 70]
        ),
        
        # Empty storage data
        "Storagedata" => DataFrame(
            "Zone" => String[],
            "Type" => String[],
            "Capacity (MWh)" => Float64[],
            "Max Power (MW)" => Float64[]
        ),
        
        # Empty line data  
        "Linedata" => DataFrame(
            "Zone_from" => String[],
            "Zone_to" => String[],
            "Pmax (MW)" => Float64[]
        )
    )
      println("🏗️  Building model with new architecture...")
    
    # Initialize solver
    optimizer = HiGHS.Optimizer
    
    # Create model builder
    builder = HOPEModelBuilder()
    builder.constraint_pool.debug_mode = true
    
    # Initialize builder
    initialize!(builder, config, input_data, optimizer)
    
    # Build model
    model = build_model!(builder)
    
    # Solve
    println("🔧 Solving demo model...")
    optimize!(model)
    
    # Results
    status = termination_status(model)
    println("📊 Demo solution status: $status")
    
    if status == MOI.OPTIMAL
        println("✅ Demo completed successfully!")
        println("💰 Objective value: $(round(objective_value(model), digits=2))")
        
        # Show some results
        if haskey(builder.variables, :p)
            println("🔋 Generation results (MW):")
            for g in input_data["G"], h in [1, 12, 24]  # Show a few hours
                gen_val = value(builder.variables[:p][g, h])
                gen_type = input_data["Gendata"][g, :Type]
                println("   Hour $h, $gen_type: $(round(gen_val, digits=1)) MW")
            end
        end
    else
        println("❌ Demo failed with status: $status")
    end
    
    # Generate report
    report = get_model_report(builder)
    println("\n📋 Demo Model Report:")
    println("   Variables: $(report["num_variables"])")
    println("   Constraints: $(report["num_constraints"])")
    println("   Time Structure: $(report["time_structure"]["type"])")
    
    return (model, builder, report)
end

"""
Compare old vs new architecture performance
"""
function benchmark_architectures(case_path::String)
    println("⚡ Benchmarking Old vs New Architecture")
    
    # This would run both architectures and compare:
    # - Model building time
    # - Solution time  
    # - Memory usage
    # - Code complexity metrics
    
    println("🔄 Running new architecture...")
    start_time = time()
    
    try
        result_new = run_hope_new(case_path, debug_mode=false)
        new_time = time() - start_time
        
        println("✅ New architecture completed in $(round(new_time, digits=2)) seconds")
        
        # TODO: Run old architecture for comparison
        # This would require importing the existing HOPE functions
        
        return Dict(
            "new_architecture" => Dict(
                "time" => new_time,
                "status" => "completed",
                "result" => result_new
            )
        )
        
    catch e
        println("❌ New architecture failed: $e")
        return Dict("error" => string(e))
    end
end

end  # module HOPE_New
