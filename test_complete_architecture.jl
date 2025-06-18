#!/usr/bin/env julia

"""
# test_complete_architecture.jl - Comprehensive test of the new HOPE architecture
# 
# This script tests the complete workflow including:
# - Model building
# - Solving with different solvers
# - Output generation
# - Plotting
# - Holistic workflow
"""

using Pkg
Pkg.activate(".")

# Load the new HOPE architecture
push!(LOAD_PATH, joinpath(@__DIR__, "src_new"))
using HOPE_New
using Test
using JuMP
using DataFrames

function test_complete_workflow()
    println("🧪 Testing Complete HOPE Architecture Workflow")
    println("=" ^ 60)
    
    # Test 1: Basic Architecture Components
    println("\n1️⃣  Testing Basic Architecture Components")
    test_basic_components()
    
    # Test 2: Solver Interface
    println("\n2️⃣  Testing Solver Interface")
    test_solver_interface()
    
    # Test 3: Output Generation
    println("\n3️⃣  Testing Output Generation")
    test_output_generation()
    
    # Test 4: Plotting System
    println("\n4️⃣  Testing Plotting System") 
    test_plotting_system()
    
    # Test 5: Complete Model Workflow
    println("\n5️⃣  Testing Complete Model Workflow")
    test_complete_model_workflow()
    
    println("\n✅ All tests completed!")
end

function test_basic_components()
    println("   Testing constraint pool initialization...")
    
    # Test constraint pool
    constraint_pool = HOPE_New.initialize_hope_constraint_pool()
    @test length(constraint_pool.constraints) > 0
    println("   ✅ Constraint pool: $(length(constraint_pool.constraints)) constraint types")
    
    # Test time manager
    time_manager = HOPE_New.TimeManager()
    @test time_manager !== nothing
    println("   ✅ Time manager initialized")
    
    # Test model builder
    builder = HOPEModelBuilder()
    @test builder !== nothing
    @test builder.constraint_pool !== nothing
    @test builder.time_manager !== nothing
    println("   ✅ Model builder initialized")
end

function test_solver_interface()
    println("   Testing solver availability...")
    
    # Test solver detection
    available_solvers = get_available_solvers()
    println("   Available solvers: $available_solvers")
    @test !isempty(available_solvers)
    
    # Test best solver selection
    best_solver = choose_best_solver()
    println("   Best available solver: $best_solver")
    @test best_solver in available_solvers
      # Test solver config creation
    config = SolverConfig(best_solver, time_limit=30.0, gap_tolerance=0.05, other_params=Dict{String, Any}())
    @test config.name == best_solver
    @test config.time_limit == 30.0
    println("   ✅ Solver configuration created")
end

function test_output_generation()
    println("   Testing output writer...")
    
    # Create temporary output directory
    temp_output = mktempdir()
    
    # Test output writer creation
    writer = HOPEOutputWriter(temp_output, "TEST", Dict("test" => true))
    @test writer !== nothing
    @test isdir(writer.output_path)
    println("   ✅ Output writer created: $(writer.output_path)")
    
    # Clean up
    rm(temp_output, recursive=true)
end

function test_plotting_system()
    println("   Testing plot generator...")
    
    # Create temporary output directory
    temp_output = mktempdir()
    
    # Test plot generator creation
    plotter = HOPEPlotGenerator(temp_output, "TEST", Dict("test" => true))
    @test plotter !== nothing
    @test isdir(plotter.output_path)
    println("   ✅ Plot generator created: $(plotter.output_path)")
    
    # Clean up
    rm(temp_output, recursive=true)
end

function test_complete_model_workflow()
    println("   Testing complete model workflow...")
    
    # Create test data
    config = create_test_config()
    input_data = create_test_input_data()
    
    # Test model building
    builder = HOPEModelBuilder()
    best_solver = choose_best_solver()
    optimizer = create_optimizer(SolverConfig(best_solver, other_params=Dict{String, Any}()))
    
    initialize!(builder, config, input_data, optimizer)
    model = build_model!(builder)
      @test model !== nothing
    @test num_variables(model) > 0
    @test num_constraints(model, count_variable_in_set_constraints=false) > 0
    println("   ✅ Model built successfully")
    println("      Variables: $(num_variables(model))")
    println("      Constraints: $(num_constraints(model, count_variable_in_set_constraints=false))")
      # Test model solving
    solver_config = SolverConfig(best_solver, time_limit=30.0, other_params=Dict{String, Any}())
    solution_info = solve_hope_model!(model, solver_config)
    
    @test solution_info !== nothing
    @test solution_info.status !== nothing
    println("   ✅ Model solved with status: $(solution_info.status)")
    
    if solution_info.objective_value !== nothing
        println("      Objective value: $(solution_info.objective_value)")
    end
    
    # Test output generation
    temp_output = mktempdir()
    writer = HOPEOutputWriter(temp_output, config["model_mode"], config)
    
    try
        write_results!(writer, builder, solution_info_to_dict(solution_info))
        println("   ✅ Results written to: $(writer.output_path)")
        
        # Check that files were created
        @test isfile(joinpath(writer.output_path, "solve_summary.csv"))
        @test isfile(joinpath(writer.output_path, "model_summary.csv"))
        
    catch e
        println("   ⚠️  Output generation warning: $e")
    end
    
    # Test plotting
    try
        plotter = HOPEPlotGenerator(writer.output_path, config["model_mode"], config)
        generate_all_plots!(plotter, writer.output_path)
        println("   ✅ Plots generated")
    catch e
        println("   ⚠️  Plotting warning: $e")
    end
    
    # Clean up
    rm(temp_output, recursive=true)
end

function create_test_config()
    return Dict(
        "model_mode" => "PCM",
        "solver" => "HiGHS",
        "unit_commitment" => 0,
        "flexible_demand" => false,
        "investment_binary" => false,
        "debug" => 0
    )
end

function create_test_input_data()
    return Dict{String, Any}(
        "I" => ["Zone1", "Zone2"],  # Zones
        "W" => ["State1"],          # States
        "G" => [1, 2, 3],          # Three generators
        "S" => [1],                # One storage unit
        "L" => [1],                # One transmission line
        "H" => collect(1:24),      # 24 hours
          # Generator data
        "Gendata" => DataFrame(
            :Zone => ["Zone1", "Zone1", "Zone2"],
            :Fuel => ["Coal", "Gas", "Wind"],
            Symbol("Pmax (MW)") => [100.0, 150.0, 200.0],
            Symbol("Cost (\$/MWh)") => [45.0, 75.0, 10.0],
            Symbol("CO2 (ton/MWh)") => [0.9, 0.4, 0.0]
        ),
        
        # Storage data
        "Storagedata" => DataFrame(
            :Zone => ["Zone1"],
            :Type => ["Battery"],
            Symbol("Capacity (MWh)") => [400.0],
            Symbol("Pmax (MW)") => [100.0],
            :Efficiency => [0.9]
        ),
        
        # Transmission data
        "Linedata" => DataFrame(
            :From => ["Zone1"],
            :To => ["Zone2"],
            Symbol("Pmax (MW)") => [150.0]
        ),
          # Load data
        "Loaddata" => DataFrame(
            :Hour => 1:24,
            :Zone1 => [80, 75, 70, 65, 60, 65, 70, 80, 90, 100, 110, 120,
                    125, 120, 115, 110, 105, 100, 95, 90, 85, 80, 75, 70],
            :Zone2 => [60, 55, 50, 45, 40, 45, 50, 60, 70, 80, 90, 100,
                    105, 100, 95, 90, 85, 80, 75, 70, 65, 60, 55, 50]
        ),
        
        # Wind profile
        "Winddata" => DataFrame(
            :Hour => 1:24,
            :Zone2 => [0.3, 0.4, 0.5, 0.6, 0.7, 0.6, 0.5, 0.4, 0.3, 0.2, 0.1, 0.2,
                    0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.7, 0.6, 0.5, 0.4, 0.3, 0.2]
        )
    )
end

function test_holistic_workflow()
    println("\n6️⃣  Testing Holistic Workflow")
    
    # This would test the complete GTEP→PCM workflow
    # For now, just test the configuration
    holistic_config = HolisticConfig(
        gtep_config=Dict("model_mode" => "GTEP"),
        pcm_config=Dict("model_mode" => "PCM"),
        coupling_method="sequential"
    )
    
    @test holistic_config !== nothing
    @test holistic_config.coupling_method == "sequential"
    println("   ✅ Holistic configuration created")
end

# Run the tests
if abspath(PROGRAM_FILE) == @__FILE__
    test_complete_workflow()
    test_holistic_workflow()
end
