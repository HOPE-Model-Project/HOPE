"""
# HOPE_New.jl - Modern HOPE Power System Modeling Framework
# 
# New modular architecture with integrated preprocessing, unified time management,
# and flexible constraint system.
"""

module HOPE_New

# Core dependencies
using JuMP
using DataFrames
using Clustering
using Statistics

# Include submodules
include("io/SimpleDataReader.jl")
include("io/DataReader.jl")
include("preprocessing/DataPreprocessor.jl")
include("core/TimeManager.jl")
include("core/ConstraintPool.jl")
include("core/ModelBuilder.jl")
include("models/PCM.jl")
include("output/SolverInterface.jl")
include("output/OutputWriter.jl")
include("output/PlotGenerator.jl")
include("utils/Utils.jl")

# Import and re-export main functionality
using .SimpleDataReader
using .DataReader
using .DataPreprocessor
using .TimeManager
using .ConstraintPool
using .ModelBuilder
using .PCM
using .SolverInterface
using .OutputWriter
using .PlotGenerator
using .Utils

# Legacy function - replaced by flexible run_hope_model above
# """
# Main HOPE model workflow with integrated preprocessing
# """
# function run_hope_model_old(case_path::String; solver_name::String="cbc")
#     # This function has been replaced by the flexible run_hope_model function above
#     return run_hope_model_with_preprocessing(case_path; solver_name=solver_name)
# end

"""
Setup time structure from already preprocessed data
"""
function setup_time_structure_from_preprocessed!(time_manager::HOPETimeManager, processed_data::Dict)
    # Create a simple time structure from the preprocessed data
    if haskey(processed_data, "is_clustered") && processed_data["is_clustered"]
        # Clustered time structure
        time_structure = UnifiedTimeStructure(
            get(processed_data, "H", collect(1:8760)),
            get(processed_data, "T", [1]),
            get(processed_data, "H_T", Dict(1 => collect(1:8760))),
            get(processed_data, "period_weights", Dict(1 => 1.0)),
            get(processed_data, "days_per_period", Dict(1 => 365)),
            true,  # is_clustered
            Dict{Int, Int}(),  # cluster_mapping (simplified)
            get(processed_data, "representative_data", Dict()),
            Dict{Int, Int}(),  # hour_to_day (simplified)
            Dict{Int, Int}(),  # hour_to_month (simplified)
            get(processed_data, "model_mode", "PCM")
        )
    else
        # Full time structure
        hours = get(processed_data, "H", collect(1:8760))
        time_structure = UnifiedTimeStructure(
            hours,
            [1],
            Dict(1 => hours),
            Dict(1 => 1.0),
            Dict(1 => 365),
            false,  # not clustered
            Dict{Int, Int}(),
            Dict(),
            Dict{Int, Int}(),
            Dict{Int, Int}(),
            get(processed_data, "model_mode", "PCM")
        )
    end
    
    set_time_structure!(time_manager, time_structure)
    println("   ✓ Time structure configured from preprocessed data")
end

"""
Simplified workflow for testing and development
"""
function run_hope_preprocessing_only(case_path::String)
    println("🧪 Testing HOPE Preprocessing Only")
    println("=" ^ 40)
      try
        # Load data and configuration
        reader = HOPEDataReader(case_path)
        input_data, config = load_case_data(reader, case_path)
          # Create and run preprocessing
        preprocessing_config = create_preprocessing_config_from_hope_settings(config)
        preprocessor = HOPEDataPreprocessor(preprocessing_config)
        processed_data = preprocess_data!(preprocessor, input_data)
        
        println("✅ Preprocessing test completed!")
        return processed_data, preprocessor.preprocessing_report
        
    catch e
        println("❌ Error in preprocessing test:")
        println("   $(string(e))")
        rethrow(e)
    end
end

# Main workflow function with preprocessing
"""
Main HOPE model workflow with integrated preprocessing
Supports time clustering and generator aggregation for computational efficiency

# Arguments
- `case_path`: Path to the case directory
- `solver_name`: Solver to use (default: "cbc")

# Returns
- Results dictionary with preprocessing report and model outputs
"""
function run_hope_model_with_preprocessing(case_path::String; solver_name::String="cbc")
    println("🚀 Starting HOPE Model with Integrated Preprocessing")
    println("=" ^ 60)
    
    start_time = time()
    
    try
        # Step 1: Load configuration and data
        println("📂 Loading data and configuration...")
        reader = HOPEDataReader(case_path)
        input_data, config = load_case_data(reader, case_path)
        
        # Step 2: Create preprocessing configuration from HOPE settings        println("⚙️  Setting up preprocessing...")
        preprocessing_config = create_preprocessing_config_from_hope_settings(config)
        preprocessor = HOPEDataPreprocessor(preprocessing_config)
        
        # Step 3: Preprocess data (time clustering + generator aggregation)
        println("🔧 Preprocessing data (clustering and aggregation)...")
        processed_data = preprocess_data!(preprocessor, input_data)
          # Step 4: Setup time management with preprocessed data
        println("⏰ Setting up time management...")
        time_manager = HOPETimeManager()
        setup_time_structure_from_preprocessed!(time_manager, processed_data)
          # Step 5: Build model
        println("🏗️  Building optimization model...")
        builder = HOPEModelBuilder()
        solver_config = SolverInterface.SolverConfig(solver_name)
        optimizer = SolverInterface.create_optimizer(solver_config)
        ModelBuilder.initialize!(builder, config, processed_data, optimizer, time_manager)
        model = ModelBuilder.build_model!(builder)
        
        # Step 6: Solve model
        println("🔧 Solving model...")
        solve_results = SolverInterface.solve_hope_model!(model, solver_config, config)
        
        # Step 7: Generate outputs
        println("📊 Generating outputs...")
        output_writer = HOPEOutputWriter(case_path, config)
        output_files = OutputWriter.write_results!(output_writer, solve_results, processed_data)
        
        execution_time = time() - start_time
        println("✅ HOPE model with preprocessing completed successfully in $(round(execution_time, digits=2)) seconds!")
        
        return Dict(
            "status" => "success",
            "execution_time" => execution_time,
            "preprocessing_report" => preprocessor.preprocessing_report,
            "model" => model,
            "solve_results" => solve_results,
            "output_files" => output_files,
            "processed_data" => processed_data,
            "config" => config,
            "workflow" => "preprocessing"
        )
        
    catch e
        execution_time = time() - start_time
        println("❌ Error in HOPE model execution after $(round(execution_time, digits=2)) seconds:")
        println("   $(string(e))")
        rethrow(e)
    end
end

"""
Direct HOPE model workflow without preprocessing
Load Data → Build Model → Solve → Output
Suitable for small-scale studies or when using pre-processed data

# Arguments
- `case_path`: Path to the case directory
- `solver_name`: Solver to use (default: "cbc")

# Returns
- Results dictionary with model outputs
"""
function run_hope_model_direct(case_path::String; solver_name::String="cbc")
    println("🚀 Starting HOPE Model (Direct Mode - No Preprocessing)")
    println("=" ^ 60)
    
    start_time = time()
    
    try
        # Step 1: Load configuration and data
        println("📂 Loading data and configuration...")
        reader = HOPEDataReader(case_path)
        input_data, config = load_case_data(reader, case_path)
          # Step 2: Setup time management directly from configuration
        println("⏰ Setting up time management...")
        time_manager = HOPETimeManager()
        setup_time_structure!(time_manager, input_data, config)
          # Step 3: Build model
        println("🏗️  Building optimization model...")
        builder = HOPEModelBuilder()
        solver_config = SolverInterface.SolverConfig(solver_name)
        optimizer = SolverInterface.create_optimizer(solver_config)
        ModelBuilder.initialize!(builder, config, input_data, optimizer, time_manager)
        model = ModelBuilder.build_model!(builder)
        
        # Step 4: Solve model
        println("🔧 Solving model...")
        solve_results = SolverInterface.solve_hope_model!(model, solver_config, config)
        
        # Step 5: Generate outputs
        println("📊 Generating outputs...")
        output_writer = HOPEOutputWriter(case_path, config)
        output_files = OutputWriter.write_results!(output_writer, solve_results, input_data)
        
        execution_time = time() - start_time
        println("✅ HOPE model (direct) completed successfully in $(round(execution_time, digits=2)) seconds!")
        
        return Dict(
            "status" => "success",
            "execution_time" => execution_time,
            "model" => model,
            "solve_results" => solve_results,
            "output_files" => output_files,
            "input_data" => input_data,
            "config" => config,
            "workflow" => "direct"
        )
        
    catch e
        execution_time = time() - start_time
        println("❌ Error in HOPE model execution after $(round(execution_time, digits=2)) seconds:")
        println("   $(string(e))")
        rethrow(e)
    end
end

"""
Flexible HOPE model workflow that auto-detects preprocessing needs
Main entry point that chooses between preprocessed and direct workflows

# Arguments
- `case_path`: Path to the case directory containing Settings/ and Data/ folders
- `solver_name`: Solver to use (default: "cbc")
- `use_preprocessing`: Force preprocessing on/off, or auto-detect if nothing
- `config_override`: Optional dictionary to override configuration parameters

# Returns
- Results dictionary containing model outputs, timing information, and metadata
"""
function run_hope_model(case_path::String; 
                       solver_name::String="cbc", 
                       use_preprocessing::Union{Bool, Nothing}=nothing,
                       config_override::Dict=Dict())
    
    start_time = time()
    
    try
        # Load configuration to determine preprocessing needs
        reader = HOPEDataReader(case_path)
        _, config = load_case_data(reader, case_path)
        
        # Apply configuration overrides
        merge!(config, config_override)
        
        # Auto-detect preprocessing needs if not specified
        if use_preprocessing === nothing
            needs_preprocessing = detect_preprocessing_needs(config)
            println("🔍 Auto-detected preprocessing needs: $needs_preprocessing")
        else
            needs_preprocessing = use_preprocessing
            println("🎯 User-specified preprocessing: $needs_preprocessing")
        end
        
        # Choose workflow based on preprocessing needs
        if needs_preprocessing
            println("🔄 Running with preprocessing workflow")
            results = run_hope_model_with_preprocessing(case_path; solver_name=solver_name)
        else
            println("⚡ Running direct workflow (no preprocessing)")
            results = run_hope_model_direct(case_path; solver_name=solver_name)
        end
        
        # Add workflow metadata
        execution_time = time() - start_time
        results["total_execution_time"] = execution_time
        results["workflow_type"] = needs_preprocessing ? "preprocessing" : "direct"
        results["preprocessing_enabled"] = needs_preprocessing
        results["config"] = config
        
        println("✅ Total execution time: $(round(execution_time, digits=2)) seconds")
        return results
        
    catch e
        execution_time = time() - start_time
        println("❌ Model execution failed after $(round(execution_time, digits=2)) seconds")
        println("Error: $e")
        rethrow(e)
    end
end

"""
Detect if preprocessing is needed based on configuration and data characteristics

# Arguments
- `config`: Configuration dictionary from YAML file

# Returns
- `true` if preprocessing is needed, `false` otherwise

# Detection criteria:
- Time clustering: representative_day! = 1 and time_periods defined
- Generator aggregation: aggregated! = 1  
- Large dataset: Automatic detection based on data size (future)
"""
function detect_preprocessing_needs(config::Dict)::Bool
    # Check if time clustering is explicitly enabled
    if get(config, "representative_day!", 0) == 1
        # Verify time_periods are defined
        if haskey(config, "time_periods") && !isempty(config["time_periods"])
            println("   ✓ Time clustering enabled with time_periods defined")
            return true
        else
            @warn "representative_day! is enabled but time_periods is not defined or empty"
        end
    end
    
    # Check if generator aggregation is enabled
    if get(config, "aggregated!", 0) == 1
        println("   ✓ Generator aggregation enabled")
        return true
    end
    
    # Future: Could add automatic detection based on data size
    # if data size > threshold, suggest preprocessing
    
    println("   ✓ No preprocessing flags detected")
    return false
end

# Export main functions
export run_hope_model, run_hope_model_with_preprocessing, run_hope_model_direct
export run_hope_preprocessing_only, detect_preprocessing_needs
export setup_time_structure_from_preprocessed!

# Export key types and functions from submodules
export SimpleHOPEDataReader, load_simple_case_data
export HOPEDataReader, load_case_data
export PreprocessingConfig, HOPEDataPreprocessor, create_preprocessing_config_from_hope_settings
export preprocess_data!, process_time_clustering!, process_generator_aggregation!
export UnifiedTimeStructure, HOPETimeManager, create_unified_time_structure
export setup_time_structure!, set_time_structure!, get_time_indices, get_effective_hours
export HOPEModelBuilder, initialize!, build_model!
export SolverConfig, solve_hope_model!
export HOPEOutputWriter, write_results!

# Additional utility functions
"""
    validate_case_directory(case_path::String)

Validate that a case directory has the required structure and files.
"""
function validate_case_directory(case_path::String)
    if !isdir(case_path)
        throw(ArgumentError("Case directory does not exist: $case_path"))
    end
    
    settings_dir = joinpath(case_path, "Settings")
    if !isdir(settings_dir)
        throw(ArgumentError("Settings directory not found: $settings_dir"))
    end
    
    config_file = joinpath(settings_dir, "HOPE_model_settings.yml")
    if !isfile(config_file)
        throw(ArgumentError("Configuration file not found: $config_file"))
    end
    
    return true
end

"""
    get_available_solvers()

Get list of available solvers in the current environment.
"""
function get_available_solvers()
    available = String[]
    
    # Check commonly available solvers by checking if they're in the environment
    # Use haskey on the loaded packages
    try
        if haskey(Base.loaded_modules, Base.PkgId(Base.UUID("9961bab8-2fa3-5c5a-9d89-47fab24efd76"), "Cbc"))
            push!(available, "cbc")
        end
    catch
    end
    
    try
        if haskey(Base.loaded_modules, Base.PkgId(Base.UUID("e2554f3b-3117-50c0-817c-e040a3ddf72d"), "Clp"))
            push!(available, "clp")
        end
    catch
    end
    
    try
        if haskey(Base.loaded_modules, Base.PkgId(Base.UUID("60bf3e95-4087-53dc-ae20-288a0d20c6a6"), "GLPK"))
            push!(available, "glpk")
        end
    catch
    end
    
    try
        if haskey(Base.loaded_modules, Base.PkgId(Base.UUID("87dc4568-4c63-4d18-b0c0-bb2238e4078b"), "HiGHS"))
            push!(available, "highs")
        end
    catch
    end
    
    try
        if haskey(Base.loaded_modules, Base.PkgId(Base.UUID("2e9cd046-0924-5485-92f1-d5272153d98b"), "Gurobi"))
            push!(available, "gurobi")
        end
    catch
    end
    
    try
        if haskey(Base.loaded_modules, Base.PkgId(Base.UUID("a076750e-1247-5638-91d2-ce28b192dca0"), "CPLEX"))
            push!(available, "cplex")
        end
    catch
    end
    
    # If no solvers detected in loaded modules, add default ones that are likely available
    if isempty(available)
        push!(available, "cbc")  # CBC is usually available
        push!(available, "highs") # HiGHS is becoming standard
    end
    
    return available
end

"""
    print_hope_info()

Print information about HOPE system and available features.
"""
function print_hope_info()
    println("🏛️  HOPE: Holistic Optimization Power-system Economy Model")
    println("=" ^ 60)
    println("🔄 Flexible Workflow: Auto-detects preprocessing needs")
    println("⚡ Direct Mode: No preprocessing for small studies")
    println("🔧 Preprocessing Mode: Time clustering + generator aggregation")
    println("📊 Supported Models: GTEP (capacity expansion), PCM (dispatch)")
    println()
    println("Available Solvers: $(join(get_available_solvers(), ", "))")
    println()
    println("Usage Examples:")
    println("  # Auto-detect workflow")
    println("  results = run_hope_model(\"ModelCases/MyCase\")")
    println()
    println("  # Force preprocessing")
    println("  results = run_hope_model(\"ModelCases/MyCase\", use_preprocessing=true)")
    println()
    println("  # Use specific solver")
    println("  results = run_hope_model(\"ModelCases/MyCase\", solver_name=\"highs\")")
end

export validate_case_directory, get_available_solvers, print_hope_info

end # module HOPE_New
