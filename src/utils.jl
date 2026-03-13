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

"""
    normalize_timeseries_time_columns!(df::DataFrame; context::AbstractString = "timeseries")

Normalize timeseries metadata columns to HOPE's standard:
- required: `Time Period`, `Hours`
- accepted legacy aliases: `Period`, `Hour`

If `Time Period` is missing, it defaults to `1` for all rows.
If `Hours` is missing, it is derived from `Period`/`Hour`; otherwise defaults to row index.
"""
function normalize_timeseries_time_columns!(df::DataFrame; context::AbstractString = "timeseries")
    colnames = Set(string.(names(df)))
    n = nrow(df)

    if !("Time Period" in colnames)
        insertcols!(df, 1, "Time Period" => ones(Int, n))
    end

    colnames = Set(string.(names(df)))
    if !("Hours" in colnames)
        if "Period" in colnames
            rename!(df, "Period" => "Hours")
        elseif "Hour" in colnames
            rename!(df, "Hour" => "Hours")
        else
            insertcols!(df, "Hours" => collect(1:n))
        end
    end

    to_int(x, default::Int) = (ismissing(x) || string(x) == "") ? default : parse(Int, string(x))
    df[!, "Time Period"] = [to_int(df[r, "Time Period"], 1) for r in 1:n]
    df[!, "Hours"] = [to_int(df[r, "Hours"], r) for r in 1:n]
    return df
end

"""
    validate_aligned_time_columns!(reference_df::DataFrame, other_df::DataFrame, other_name::AbstractString)

Validate that two timeseries share identical `Time Period` and `Hours` vectors.
"""
function validate_aligned_time_columns!(reference_df::DataFrame, other_df::DataFrame, other_name::AbstractString)
    if nrow(reference_df) != nrow(other_df)
        throw(ArgumentError("Timeseries row mismatch: reference has $(nrow(reference_df)) rows but $(other_name) has $(nrow(other_df)) rows."))
    end
    if any(reference_df[!, "Time Period"] .!= other_df[!, "Time Period"]) || any(reference_df[!, "Hours"] .!= other_df[!, "Hours"])
        throw(ArgumentError("Timeseries time mapping mismatch between reference and $(other_name). Columns 'Time Period' and 'Hours' must align row-by-row."))
    end
    return true
end

"""
    build_time_period_hours(df::DataFrame)

Build HOPE sets from normalized timeseries columns:
- `T`: sorted time-period IDs
- `H_t`: row-index hours grouped by time period
- `H_T`: all modeled row-index hours
- `has_custom_time_periods`: whether input defines multiple time periods
"""
function build_time_period_hours(df::DataFrame)
    tp = Int.(df[!, "Time Period"])
    t_vals = sort(unique(tp))
    if isempty(t_vals)
        throw(ArgumentError("No valid Time Period values found in timeseries input."))
    end
    if t_vals != collect(1:length(t_vals))
        throw(ArgumentError("Time Period values must be contiguous 1..T. Found $(t_vals)."))
    end
    H_t = [findall(tp .== t) for t in t_vals]
    H_T = collect(1:nrow(df))
    has_custom_time_periods = length(t_vals) > 1
    return t_vals, H_t, H_T, has_custom_time_periods
end

"""
    resolve_rep_day_mode(config_set::AbstractDict; context::AbstractString = "model")

Resolve representative-day settings with support for both new and legacy keys.

New keys:
- `endogenous_rep_day`: 1 = HOPE clusters representative days from full chronology
- `external_rep_day`: 1 = user provides representative periods + weights

Legacy keys (deprecated aliases):
- `representative_day!` -> `endogenous_rep_day`
- `external_rep_weights` -> `external_rep_day`

Returns `(endogenous_rep_day, external_rep_day, representative_day_mode)`.
"""
function resolve_rep_day_mode(config_set::AbstractDict; context::AbstractString = "model")
    parse_binary_setting(x, keyname) = begin
        v = x isa Integer ? Int(x) : parse(Int, string(x))
        if !(v in (0, 1))
            throw(ArgumentError("Invalid $(keyname)=$(v). Expected 0 or 1."))
        end
        v
    end

    has_new_endogenous = haskey(config_set, "endogenous_rep_day")
    has_new_external = haskey(config_set, "external_rep_day")
    has_old_rep = haskey(config_set, "representative_day!")
    has_old_external = haskey(config_set, "external_rep_weights")

    endogenous_rep_day = 0
    external_rep_day = 0

    if has_new_endogenous
        endogenous_rep_day = parse_binary_setting(config_set["endogenous_rep_day"], "endogenous_rep_day")
        if has_old_rep
            old_rep = parse_binary_setting(config_set["representative_day!"], "representative_day!")
            if old_rep != endogenous_rep_day
                println("Warning ($(context)): representative_day! conflicts with endogenous_rep_day. Using endogenous_rep_day=$(endogenous_rep_day).")
            end
        end
    elseif has_old_rep
        endogenous_rep_day = parse_binary_setting(config_set["representative_day!"], "representative_day!")
        println("Warning ($(context)): representative_day! is deprecated; use endogenous_rep_day.")
    end

    if has_new_external
        external_rep_day = parse_binary_setting(config_set["external_rep_day"], "external_rep_day")
        if has_old_external
            old_external = parse_binary_setting(config_set["external_rep_weights"], "external_rep_weights")
            if old_external != external_rep_day
                println("Warning ($(context)): external_rep_weights conflicts with external_rep_day. Using external_rep_day=$(external_rep_day).")
            end
        end
    elseif has_old_external
        external_rep_day = parse_binary_setting(config_set["external_rep_weights"], "external_rep_weights")
        println("Warning ($(context)): external_rep_weights is deprecated; use external_rep_day.")
    end

    if endogenous_rep_day == 1 && external_rep_day == 1
        throw(ArgumentError("Invalid representative-day settings: endogenous_rep_day=1 and external_rep_day=1 are mutually exclusive."))
    end

    representative_day_mode = (endogenous_rep_day == 1 || external_rep_day == 1) ? 1 : 0
    return endogenous_rep_day, external_rep_day, representative_day_mode
end

end # Guard against redefinition
