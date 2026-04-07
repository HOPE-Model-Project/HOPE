using CSV
using DataFrames
using Dates

const REPO_ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const MODEL_CASES_DIR = joinpath(REPO_ROOT, "ModelCases")
const CANONICAL_NOTES_DIR = joinpath(REPO_ROOT, "tools", "repo_utils", "pjm_holistic_canonical_pair")

const GTEP_SOURCE_CASE = "PJM_MD100_GTEP_case"
const PCM_SOURCE_CASE = "PJM_MD100_PCM_case"
const GTEP_CANONICAL_CASE = "PJM_MD100_GTEP_holistic_canonical_case"
const PCM_CANONICAL_CASE = "PJM_MD100_PCM_holistic_canonical_case"

const STALE_PJM_CASES = [
    "PJM_MD100_GTEP_holistic_run_case",
    "PJM_MD100_GTEP_holistic_run_case_v2",
    "PJM_MD100_GTEP_holistic_run_case_v3",
    "PJM_MD100_GTEP_holistic_run_case_v4",
    "PJM_MD100_GTEP_holistic_run_case_v5",
    "PJM_MD100_GTEP_holistic_run_case_v6",
    "PJM_MD100_GTEP_holistic_test_case",
    "PJM_MD100_PCM_holistic_run_case",
    "PJM_MD100_PCM_holistic_run_case_v2",
    "PJM_MD100_PCM_holistic_run_case_v3",
    "PJM_MD100_PCM_holistic_run_case_v4",
    "PJM_MD100_PCM_holistic_run_case_v5",
    "PJM_MD100_PCM_holistic_run_case_v6",
    "PJM_MD100_PCM_holistic_test_case",
]

function read_csv(path::AbstractString)
    CSV.read(path, DataFrame)
end

function write_csv(path::AbstractString, df::DataFrame)
    CSV.write(path, df)
    return path
end

function metadata_columns(df::DataFrame)
    Set([name for name in names(df) if String(name) in ["Time Period", "Month", "Day", "Hours", "NI"]])
end

function zone_columns(df::DataFrame)
    metadata = metadata_columns(df)
    Set(String(name) for name in names(df) if !(name in metadata))
end

function sync_directory(src::AbstractString, dst::AbstractString)
    mkpath(dst)
    for entry in readdir(src)
        src_entry = joinpath(src, entry)
        dst_entry = joinpath(dst, entry)
        if isdir(src_entry)
            sync_directory(src_entry, dst_entry)
        else
            cp(src_entry, dst_entry; force=true)
        end
    end
end

function copy_case(src_case::AbstractString, dest_case::AbstractString)
    src = joinpath(MODEL_CASES_DIR, src_case)
    dst = joinpath(MODEL_CASES_DIR, dest_case)
    sync_directory(src, dst)
    return dst
end

function cleanup_case_outputs(case_dir::AbstractString)
    for entry in readdir(case_dir)
        entry_path = joinpath(case_dir, entry)
        if !isdir(entry_path)
            continue
        end
        if entry in ("output", "plot_output", "backup", "debug_report") || startswith(entry, "output_backup")
            rm(entry_path; recursive=true, force=true)
        end
    end
end

function keep_zone_rows(df::DataFrame, zone_col::AbstractString, keep_zones::Set{String})
    col = Symbol(zone_col)
    if !(col in Symbol.(names(df)))
        return copy(df), 0, String[]
    end
    kept = filter(row -> String(row[col]) in keep_zones, df)
    removed = nrow(df) - nrow(kept)
    removed_zones = sort!(collect(Set(String(row[col]) for row in eachrow(df) if !(String(row[col]) in keep_zones))))
    return kept, removed, removed_zones
end

function keep_line_rows(df::DataFrame, from_col::AbstractString, to_col::AbstractString, keep_zones::Set{String})
    from_sym = Symbol(from_col)
    to_sym = Symbol(to_col)
    available_cols = Set(Symbol.(names(df)))
    if !(from_sym in available_cols && to_sym in available_cols)
        return copy(df), 0, String[]
    end
    kept = filter(row -> String(row[from_sym]) in keep_zones && String(row[to_sym]) in keep_zones, df)
    removed = nrow(df) - nrow(kept)
    removed_corridors = sort!(collect(Set(string(String(row[from_sym]), "-", String(row[to_sym])) for row in eachrow(df) if !(String(row[from_sym]) in keep_zones && String(row[to_sym]) in keep_zones))))
    return kept, removed, removed_corridors
end

function keep_timeseries_columns(df::DataFrame, keep_zones::Set{String})
    metadata = metadata_columns(df)
    original_zone_cols = zone_columns(df)
    keep_cols = [name for name in names(df) if name in metadata || String(name) in keep_zones]
    kept = select(df, keep_cols)
    removed_zone_cols = sort!(collect(setdiff(original_zone_cols, keep_zones)))
    return kept, length(removed_zone_cols), removed_zone_cols
end

function write_note(path::AbstractString, title::AbstractString, lines::Vector{String})
    mkpath(dirname(path))
    open(path, "w") do io
        println(io, "# ", title)
        println(io)
        println(io, "Generated on ", Dates.format(now(), dateformat"yyyy-mm-dd HH:MM:SS"), ".")
        println(io)
        for line in lines
            println(io, "- ", line)
        end
    end
end

function invalid_zone_counts(df::DataFrame, zone_col::AbstractString, keep_zones::Set{String})
    col = Symbol(zone_col)
    if !(col in Symbol.(names(df)))
        return String[]
    end
    invalid = filter(row -> !(String(row[col]) in keep_zones), df)
    if nrow(invalid) == 0
        return String[]
    end
    grouped = combine(groupby(invalid, col), nrow => :count)
    sort!(grouped, col)
    return ["$(row[col]): $(row[:count]) row(s)" for row in eachrow(grouped)]
end

function build_gtep_case(keep_zones::Set{String})
    case_dir = copy_case(GTEP_SOURCE_CASE, GTEP_CANONICAL_CASE)
    cleanup_case_outputs(case_dir)
    data_dir = joinpath(case_dir, "Data_PJM_GTEP_subzones")

    notes = String[]

    zonedata = read_csv(joinpath(data_dir, "zonedata.csv"))
    zonedata, removed_zones, removed_zone_names = keep_zone_rows(zonedata, "Zone_id", keep_zones)
    write_csv(joinpath(data_dir, "zonedata.csv"), zonedata)
    push!(notes, "Trimmed zonedata to the shared 33-zone PCM basis.")
    push!(notes, "Removed zonedata rows: $(removed_zones) ($(join(removed_zone_names, ", ")))")

    for filename in ["gendata.csv", "gendata_candidate.csv", "storagedata.csv", "storagedata_candidate.csv"]
        path = joinpath(data_dir, filename)
        if !isfile(path)
            continue
        end
        df = read_csv(path)
        filtered, removed, removed_zone_list = keep_zone_rows(df, "Zone", keep_zones)
        write_csv(path, filtered)
        push!(notes, "$(filename): removed $(removed) row(s) outside the 33-zone basis$(isempty(removed_zone_list) ? "" : " [$(join(removed_zone_list, ", "))]").")
    end

    for filename in ["linedata.csv", "linedata_candidate.csv"]
        path = joinpath(data_dir, filename)
        if !isfile(path)
            continue
        end
        df = read_csv(path)
        filtered, removed, removed_corridors = keep_line_rows(df, "From_zone", "To_zone", keep_zones)
        write_csv(path, filtered)
        if removed == 0
            push!(notes, "$(filename): no corridors removed.")
        else
            push!(notes, "$(filename): removed $(removed) corridor row(s) outside the 33-zone basis [$(join(removed_corridors, ", "))].")
        end
    end

    for filename in [
        "load_timeseries_regional.csv",
        "wind_timeseries_regional.csv",
        "solar_timeseries_regional.csv",
        "gen_availability_timeseries.csv",
    ]
        path = joinpath(data_dir, filename)
        if !isfile(path)
            continue
        end
        df = read_csv(path)
        filtered, removed, removed_cols = keep_timeseries_columns(df, keep_zones)
        write_csv(path, filtered)
        push!(notes, "$(filename): removed $(removed) zone column(s)$(isempty(removed_cols) ? "" : " [$(join(removed_cols, ", "))]").")
    end

    write_note(joinpath(CANONICAL_NOTES_DIR, "gtep_case_notes.md"), "PJM GTEP Holistic Canonical Case", notes)
    return case_dir
end

function build_pcm_case(keep_zones::Set{String})
    case_dir = copy_case(PCM_SOURCE_CASE, PCM_CANONICAL_CASE)
    cleanup_case_outputs(case_dir)
    data_dir = joinpath(case_dir, "Data_PJM_PCM_subzones")

    notes = String[]
    push!(notes, "This case keeps the existing 33-zone PCM zonedata and chronology as the topology basis for the paired holistic benchmark.")

    gendata = read_csv(joinpath(data_dir, "gendata.csv"))
    invalid_gen = invalid_zone_counts(gendata, "Zone", keep_zones)
    filtered_gendata, removed_gen, _ = keep_zone_rows(gendata, "Zone", keep_zones)
    write_csv(joinpath(data_dir, "gendata.csv"), filtered_gendata)
    push!(notes, "gendata.csv: removed $(removed_gen) row(s) with zone labels outside zonedata.")
    append!(notes, ["Dropped generator zone " * line for line in invalid_gen])

    storagedata = read_csv(joinpath(data_dir, "storagedata.csv"))
    invalid_storage = invalid_zone_counts(storagedata, "Zone", keep_zones)
    filtered_storage, removed_storage, _ = keep_zone_rows(storagedata, "Zone", keep_zones)
    write_csv(joinpath(data_dir, "storagedata.csv"), filtered_storage)
    push!(notes, "storagedata.csv: removed $(removed_storage) row(s) with zone labels outside zonedata.")
    append!(notes, ["Dropped storage zone " * line for line in invalid_storage])

    linedata = read_csv(joinpath(data_dir, "linedata.csv"))
    filtered_linedata, removed_lines, removed_corridors = keep_line_rows(linedata, "From_zone", "To_zone", keep_zones)
    write_csv(joinpath(data_dir, "linedata.csv"), filtered_linedata)
    if removed_lines == 0
        push!(notes, "linedata.csv: all corridors already matched the 33-zone basis.")
    else
        push!(notes, "linedata.csv: removed $(removed_lines) corridor row(s) [$(join(removed_corridors, ", "))].")
    end

    write_note(joinpath(CANONICAL_NOTES_DIR, "pcm_case_notes.md"), "PJM PCM Holistic Canonical Case", notes)
    return case_dir
end

function cleanup_stale_cases()
    removed = String[]
    for case_name in STALE_PJM_CASES
        case_dir = joinpath(MODEL_CASES_DIR, case_name)
        if isdir(case_dir)
            rm(case_dir; recursive=true, force=true)
            push!(removed, case_name)
        end
    end
    return removed
end

function main(args)
    cleanup_stale = "--cleanup-stale" in args

    pcm_zones = Set(String.(read_csv(joinpath(MODEL_CASES_DIR, PCM_SOURCE_CASE, "Data_PJM_PCM_subzones", "zonedata.csv"))[!, "Zone_id"]))

    gtep_case_dir = build_gtep_case(pcm_zones)
    pcm_case_dir = build_pcm_case(pcm_zones)

    println("Created canonical holistic pair:")
    println("  GTEP: ", gtep_case_dir)
    println("  PCM : ", pcm_case_dir)

    if cleanup_stale
        removed = cleanup_stale_cases()
        println("Removed stale PJM holistic case directories: ", isempty(removed) ? "none" : join(removed, ", "))
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
