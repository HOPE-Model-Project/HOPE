# Utility functions for HOPE model

# This module is designed to work as part of the HOPE module and uses its constants

# Guard against redefinition of functions
if !@isdefined(validate_case_directory)

"""
    validate_case_directory(case::AbstractString)

Validate that a case directory exists and contains required files.
"""
function validate_case_directory(case::AbstractString)
    if !isdir(case)
        throw(ArgumentError("Case directory does not exist: $case"))
    end
    
    settings_file = joinpath(case, "Settings", "HOPE_model_settings.yml")
    if !isfile(settings_file)
        throw(ArgumentError("Settings file not found: $settings_file"))
    end
    
    return true
end

"""
    validate_model_mode(mode::AbstractString)

Validate that the model mode is supported.
"""
function validate_model_mode(mode::AbstractString)
    if !(mode in VALID_MODEL_MODES)
        throw(ArgumentError("Invalid model mode: $mode. Must be one of: $(join(VALID_MODEL_MODES, ", "))"))
    end
    return true
end

"""
    safe_file_read(filepath::AbstractString, reader_func::Function)

Safely read a file with error handling.
"""
function safe_file_read(filepath::AbstractString, reader_func::Function)
    if !isfile(filepath)
        throw(ArgumentError("File not found: $filepath"))
    end
    
    try
        return reader_func(filepath)
    catch e
        @error "Error reading file: $filepath" exception=(e, catch_backtrace())
        rethrow()
    end
end

"""
    ensure_output_directory(outpath::AbstractString)

Ensure output directory exists, create if it doesn't.
"""
function ensure_output_directory(outpath::AbstractString)
    if !isdir(outpath)
        try
            mkpath(outpath)
            @info "Created output directory: $outpath"
        catch e
            @error "Failed to create output directory: $outpath" exception=(e, catch_backtrace())
            rethrow()
        end
    end
    return outpath
end

"""
    apply_technology_mapping(df::DataFrame, col_name::Symbol = :Technology)

Apply technology acronym mapping to a DataFrame column.
"""
function apply_technology_mapping(df::DataFrame, col_name::Symbol = :Technology)
    if col_name in names(df)
        df[!, col_name] = map(x -> get(TECH_ACRONYM_MAP, x, x), df[!, col_name])
    end
    return df
end

"""
    aggregate_capacity_data(df::DataFrame, group_cols::Vector{Symbol}, sum_cols::Vector{Symbol})

Generic function to aggregate capacity data by specified columns.
"""
function aggregate_capacity_data(df::DataFrame, group_cols::Vector{Symbol}, sum_cols::Vector{Symbol})
    agg_df = combine(groupby(df, group_cols), sum_cols .=> sum)
    
    # Rename columns to remove _sum suffix
    old_names = [Symbol("$(col)_sum") for col in sum_cols]
    rename!(agg_df, old_names .=> sum_cols)
    
    return agg_df
end

# Helper functions for path construction
"""
    get_project_root()

Get the root directory of the HOPE project.
"""
function get_project_root()
    return dirname(dirname(@__FILE__))
end

"""
    get_case_paths(case_name::String)

Get the case directory and input directory paths for a given case.
"""
function get_case_paths(case_name::String)
    project_root = get_project_root()
    case_dir = joinpath(project_root, "ModelCases", case_name)
    input_dir = joinpath(case_dir, "Output")
    return case_dir, input_dir
end

"""
    get_paths(case_name::String = "MD_clean_case0RPS")

Get input and output paths for a given case.
"""
function get_paths(case_name::String = "MD_clean_case0RPS")
    project_root = get_project_root()
    input_dir = joinpath(project_root, "ModelCases", case_name, "Output")
    outpath = joinpath(project_root, "ModelCases", case_name)
    return input_dir, outpath
end

"""
    safe_remove_directory(path::AbstractString; max_retries::Int = 3)

Safely remove a directory with retry logic for Windows file locking issues.
"""
function safe_remove_directory(path::AbstractString; max_retries::Int = 3)
    if !isdir(path)
        return true  # Already doesn't exist
    end
    
    for attempt in 1:max_retries
        try
            rm(path; force=true, recursive=true)
            return true  # Success
        catch e
            if isa(e, SystemError) && attempt < max_retries
                println("Warning: Failed to remove directory '$path' (attempt $attempt/$max_retries): $(e.msg)")
                println("Retrying in 1 second...")
                sleep(1)
                GC.gc()  # Force garbage collection to release file handles
            elseif attempt == max_retries
                println("Error: Could not remove directory '$path' after $max_retries attempts: $e")
                return false
            end
        end
    end
    return false
end

end # Guard against redefinition
