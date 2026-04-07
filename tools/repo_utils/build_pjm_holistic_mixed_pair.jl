using CSV
using DataFrames
using Dates

include(normpath(joinpath(@__DIR__, "build_pjm_holistic_canonical_pair.jl")))

const GTEP_MIXED_CASE = "PJM_MD100_GTEP_holistic_mixed_baseline_case_v20260405d"
const PCM_MIXED_CASE = "PJM_MD100_PCM_holistic_mixed_baseline_case_v20260405d"
const MIXED_NOTES_DIR = joinpath(REPO_ROOT, "tools", "repo_utils", "pjm_holistic_mixed_pair")
const STATUS_FILE = joinpath(MIXED_NOTES_DIR, "build_mixed_pair_status.txt")
const RPS_ELIGIBLE_TYPES = Set(["Hydro", "MSW", "Bio", "Landfill_NG", "Nuc", "NuC", "WindOn", "WindOff", "SolarPV"])
const TIMESERIES_META_COLS = ["Time Period", "Month", "Day", "Hours"]

to_f64_mixed(x, default=0.0) = ismissing(x) || x === nothing ? default : (x isa Number ? Float64(x) : parse(Float64, string(x)))

function copy_case_clean(src_case::AbstractString, dst_case::AbstractString)
    dst_dir = joinpath(MODEL_CASES_DIR, dst_case)
    if isdir(dst_dir)
        rm(dst_dir; recursive=true, force=true)
    end
    case_dir = copy_case(src_case, dst_case)
    cleanup_case_outputs(case_dir)
    return case_dir
end

function append_status(line::AbstractString)
    mkpath(dirname(STATUS_FILE))
    open(STATUS_FILE, "a") do io
        println(io, line)
    end
end

function select_existing_gtep_columns(df::DataFrame)
    required = [
        "Pmax (MW)",
        "Pmin (MW)",
        "Zone",
        "Type",
        "Flag_thermal",
        "Flag_RET",
        "Flag_VRE",
        "Flag_mustrun",
        "Cost (\$/MWh)",
        "EF",
        "CC",
        "AF",
        "FOR",
    ]
    out = DataFrame()
    for col in required
        out[!, Symbol(col)] = copy(df[!, col])
    end
    return out
end

function add_flag_rps!(df::DataFrame)
    if "Flag_RPS" in names(df)
        return df
    end
    vre_vals = ("Flag_VRE" in names(df)) ? [Int(round(to_f64_mixed(v, 0.0))) for v in df[:, "Flag_VRE"]] : fill(0, nrow(df))
    type_vals = String.(df[:, "Type"])
    df[!, :Flag_RPS] = [((type_vals[i] in RPS_ELIGIBLE_TYPES) || (vre_vals[i] == 1)) ? 1 : 0 for i in 1:nrow(df)]
    return df
end

function ensure_time_columns(df::DataFrame)
    cols = [Symbol(col) for col in TIMESERIES_META_COLS if col in names(df)]
    return select(df, cols)
end

function safe_profile_value(df::DataFrame, zone::AbstractString, row_idx::Int, default::Float64)
    if zone in names(df)
        return clamp(to_f64_mixed(df[row_idx, zone], default), 0.0, 1.0)
    end
    return clamp(default, 0.0, 1.0)
end

is_vre_type(gen_type::String) = gen_type == "SolarPV" || gen_type == "WindOn" || gen_type == "WindOff"

function zonal_profile_means(df::DataFrame)
    means = Dict{String,Float64}()
    for col in names(df)
        col_name = String(col)
        if col_name in TIMESERIES_META_COLS || col_name == "NI"
            continue
        end
        vals = [clamp(to_f64_mixed(v, 0.0), 0.0, 1.0) for v in df[!, col]]
        means[col_name] = isempty(vals) ? 0.0 : sum(vals) / length(vals)
    end
    return means
end

function assign_static_vre_af!(df::DataFrame, wind_means::Dict{String,Float64}, solar_means::Dict{String,Float64})
    if !("AF" in names(df))
        df[!, :AF] = ones(Float64, nrow(df))
    end
    for row_idx in 1:nrow(df)
        zone = string(df[row_idx, "Zone"])
        gen_type = string(df[row_idx, "Type"])
        if gen_type == "SolarPV"
            df[row_idx, "AF"] = get(solar_means, zone, to_f64_mixed(df[row_idx, "AF"], 1.0))
        elseif gen_type in ("WindOn", "WindOff")
            df[row_idx, "AF"] = get(wind_means, zone, to_f64_mixed(df[row_idx, "AF"], 1.0))
        end
    end
    return df
end

function write_time_only_afdata_csv(path::AbstractString, winddata::DataFrame)
    write_csv(path, ensure_time_columns(winddata))
    return path
end

function copy_file(src::AbstractString, dst::AbstractString)
    cp(src, dst; force=true)
    return dst
end

function build_mixed_pair()
    open(STATUS_FILE, "w") do io
        println(io, "status=started")
    end
    gtep_case_dir = copy_case_clean(GTEP_CANONICAL_CASE, GTEP_MIXED_CASE)
    pcm_case_dir = copy_case_clean(PCM_CANONICAL_CASE, PCM_MIXED_CASE)
    append_status("stage=case_copies_ready")

    gtep_data_dir = joinpath(gtep_case_dir, "Data_PJM_GTEP_subzones")
    pcm_data_dir = joinpath(pcm_case_dir, "Data_PJM_PCM_subzones")
    canonical_gtep_data = joinpath(MODEL_CASES_DIR, GTEP_CANONICAL_CASE, "Data_PJM_GTEP_subzones")
    canonical_pcm_data = joinpath(MODEL_CASES_DIR, PCM_CANONICAL_CASE, "Data_PJM_PCM_subzones")

    notes = String[]
    push!(notes, "Built mixed holistic baseline pair from the existing canonical zonal pair.")
    push!(notes, "Selection logic: PCM existing fleet tables; GTEP zonedata/network/policies/chronology; GTEP candidate resource tables.")

    pcm_existing_gendata = read_csv(joinpath(canonical_pcm_data, "gendata.csv"))
    pcm_existing_storage = read_csv(joinpath(canonical_pcm_data, "storagedata.csv"))
    mixed_gtep_gendata = add_flag_rps!(select_existing_gtep_columns(pcm_existing_gendata))
    write_csv(joinpath(gtep_data_dir, "gendata.csv"), mixed_gtep_gendata)
    append_status("stage=gtep_existing_gendata_written")
    push!(notes, "GTEP existing gendata.csv replaced with PCM canonical fleet and derived Flag_RPS.")

    write_csv(joinpath(gtep_data_dir, "storagedata.csv"), pcm_existing_storage)
    append_status("stage=gtep_storage_written")
    push!(notes, "GTEP existing storagedata.csv replaced with PCM canonical storage fleet.")

    append_status("stage=gtep_reference_files_ready")
    push!(notes, "GTEP base case inherits zonedata/network/policy/chronology/candidate tables directly from the copied GTEP canonical case.")

    gtep_wind = read_csv(joinpath(gtep_data_dir, "wind_timeseries_regional.csv"))
    gtep_solar = read_csv(joinpath(gtep_data_dir, "solar_timeseries_regional.csv"))
    wind_means = zonal_profile_means(gtep_wind)
    solar_means = zonal_profile_means(gtep_solar)
    assign_static_vre_af!(mixed_gtep_gendata, wind_means, solar_means)
    write_csv(joinpath(gtep_data_dir, "gendata.csv"), mixed_gtep_gendata)
    gtep_candidate_gendata = read_csv(joinpath(gtep_data_dir, "gendata_candidate.csv"))
    assign_static_vre_af!(gtep_candidate_gendata, wind_means, solar_means)
    write_csv(joinpath(gtep_data_dir, "gendata_candidate.csv"), gtep_candidate_gendata)
    write_time_only_afdata_csv(joinpath(gtep_data_dir, "gen_availability_timeseries.csv"), gtep_wind)
    append_status("stage=gtep_af_written")
    push!(notes, "GTEP VRE AF values were reset to zonal mean wind/solar availability by zone, and gen_availability_timeseries.csv was reduced to time columns only so GTEP uses those static AF values without a large generator-level AF matrix.")

    write_csv(joinpath(pcm_data_dir, "gendata.csv"), pcm_existing_gendata)
    write_csv(joinpath(pcm_data_dir, "storagedata.csv"), pcm_existing_storage)
    append_status("stage=pcm_existing_fleet_written")
    push!(notes, "PCM existing gendata.csv and storagedata.csv kept from PCM canonical fleet tables.")

    for filename in [
        "zonedata.csv",
        "linedata.csv",
        "load_timeseries_regional.csv",
        "wind_timeseries_regional.csv",
        "solar_timeseries_regional.csv",
        "carbonpolicies.csv",
        "rpspolicies.csv",
        "single_parameter.csv",
    ]
        copy_file(joinpath(canonical_gtep_data, filename), joinpath(pcm_data_dir, filename))
    end
    append_status("stage=pcm_reference_files_copied")
    push!(notes, "PCM zonedata/network/policy/chronology refreshed from GTEP canonical case for baseline harmonization.")

    pcm_af_path = joinpath(pcm_data_dir, "gen_availability_timeseries.csv")
    if isfile(pcm_af_path)
        rm(pcm_af_path; force=true)
    end
    append_status("stage=pcm_af_removed")
    push!(notes, "PCM does not add a generator-level AF override in the mixed baseline case; it will use the shared zonal wind/solar profiles directly.")

    write_note(joinpath(MIXED_NOTES_DIR, "mixed_case_notes.md"), "PJM Holistic Mixed Pair", notes)
    append_status("status=completed")
    return gtep_case_dir, pcm_case_dir
end

function main()
    try
        gtep_case_dir, pcm_case_dir = build_mixed_pair()
        println("Created mixed holistic pair:")
        println("  GTEP: ", gtep_case_dir)
        println("  PCM : ", pcm_case_dir)
        println("  Notes: ", joinpath(MIXED_NOTES_DIR, "mixed_case_notes.md"))
    catch err
        append_status("error=$(sprint(showerror, err))")
        rethrow(err)
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end