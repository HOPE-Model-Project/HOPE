using CSV
using DataFrames
using Dates
using XLSX

include(normpath(joinpath(@__DIR__, "build_pjm_holistic_canonical_pair.jl")))

const MD_GTEP_SOURCE_CASE = "MD_GTEP_clean_case"
const MD_PCM_SOURCE_CASE = "MD_PCM_clean_case_holistic_test"
const MD_GTEP_FULL_CASE = "MD_GTEP_holistic_full8760_case_v20260406g"
const MD_PCM_FULL_CASE = "MD_PCM_holistic_full8760_case_v20260406g"
const MD_NOTES_DIR = joinpath(REPO_ROOT, "tools", "repo_utils", "md_holistic_full_pair")
const STATUS_FILE = joinpath(MD_NOTES_DIR, "build_md_holistic_full_pair_status.txt")
const RPS_ELIGIBLE_TYPES = Set(["Hydro", "MSW", "Bio", "Landfill_NG", "Nuc", "NuC", "WindOn", "WindOff", "SolarPV"])
const TIMESERIES_META_COLS = ["Time Period", "Month", "Day", "Hours", "Period", "Hour"]
const OUTPUT_DIR_NAMES = Set(["output", "plot_output", "backup", "debug_report"])
const MD_REALISTIC_RPS = 0.60
const MD_REALISTIC_PRM = 0.15
const MD_SOLAR_CAP_FACTOR = 0.60
const MD_WINDON_CAP_FACTOR = 0.50
const MD_WINDOFF_CAP_FACTOR = 0.75
const MD_NGCT_CCS_CAP_FACTOR = 0.50
const MD_NGCC_CCS_CAP_FACTOR = 0.75
const MD_STORAGE_POWER_CAP_FACTOR = 1.0
const MD_STORAGE_DURATION_HOURS = 4.0
const MD_STORAGE_ROUNDTRIP_COMPONENT_EFF = 0.90

to_f64_md(x, default=0.0) = ismissing(x) || x === nothing ? default : (x isa Number ? Float64(x) : parse(Float64, string(x)))

function append_status(line::AbstractString)
    mkpath(dirname(STATUS_FILE))
    open(STATUS_FILE, "a") do io
        println(io, line)
    end
end

function is_output_dir_name(name::AbstractString)
    return (name in OUTPUT_DIR_NAMES) || startswith(name, "output_backup")
end

function sync_case_tree_without_outputs(src::AbstractString, dst::AbstractString)
    mkpath(dst)
    for entry in readdir(src)
        src_entry = joinpath(src, entry)
        dst_entry = joinpath(dst, entry)
        if isdir(src_entry)
            if is_output_dir_name(entry)
                continue
            end
            sync_case_tree_without_outputs(src_entry, dst_entry)
        else
            cp(src_entry, dst_entry; force=true)
        end
    end
end

function copy_case_clean(src_case::AbstractString, dst_case::AbstractString)
    src_dir = joinpath(MODEL_CASES_DIR, src_case)
    dst_dir = joinpath(MODEL_CASES_DIR, dst_case)
    sync_case_tree_without_outputs(src_dir, dst_dir)
    return dst_dir
end

function copy_file(src::AbstractString, dst::AbstractString)
    cp(src, dst; force=true)
    return dst
end

function read_csv(path::AbstractString)
    CSV.read(path, DataFrame)
end

function write_csv(path::AbstractString, df::DataFrame)
    CSV.write(path, df)
    return path
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

function add_flag_rps!(df::DataFrame)
    if "Flag_RPS" in names(df)
        return df
    end
    vre_vals = ("Flag_VRE" in names(df)) ? [Int(round(to_f64_md(v, 0.0))) for v in df[:, "Flag_VRE"]] : fill(0, nrow(df))
    type_vals = String.(df[:, "Type"])
    df[!, :Flag_RPS] = [((type_vals[i] in RPS_ELIGIBLE_TYPES) || (vre_vals[i] == 1)) ? 1 : 0 for i in 1:nrow(df)]
    return df
end

function ensure_zero_flag_column!(df::DataFrame, col_name::AbstractString)
    if !(col_name in names(df))
        df[!, Symbol(col_name)] = fill(0, nrow(df))
    end
    return df
end

function normalize_single_parameter_columns!(df::DataFrame)
    rename_map = Dict(
        "planning _reserve_margin" => "planning_reserve_margin",
    )
    for (old_name, new_name) in rename_map
        if (old_name in names(df)) && !(new_name in names(df))
            rename!(df, old_name => new_name)
        end
    end
    return df
end

function ensure_time_columns(df::DataFrame)
    cols = [Symbol(col) for col in TIMESERIES_META_COLS if col in names(df)]
    return select(df, cols)
end

function filter_md_zones(zonedata::DataFrame)
    if "Flag_MD" in names(zonedata)
        return filter(row -> Int(round(to_f64_md(row["Flag_MD"], 0.0))) == 1, zonedata)
    end
    if "State" in names(zonedata)
        return filter(row -> string(row["State"]) == "MD", zonedata)
    end
    return zonedata
end

function zone_ids(zonedata::DataFrame)
    return String.(zonedata[:, "Zone_id"])
end

function filter_by_zone(df::DataFrame, zone_col::AbstractString, kept_zones::Set{String})
    if !(zone_col in names(df))
        return df
    end
    return filter(row -> string(row[zone_col]) in kept_zones, df)
end

function filter_lines_by_zones(df::DataFrame, kept_zones::Set{String})
    if !(("From_zone" in names(df)) && ("To_zone" in names(df)))
        return df
    end
    return filter(row -> (string(row["From_zone"]) in kept_zones) && (string(row["To_zone"]) in kept_zones), df)
end

function filter_timeseries_zone_columns(df::DataFrame, kept_zone_list::Vector{String})
    keep_cols = String[]
    for col in names(df)
        if (col in TIMESERIES_META_COLS) || (col in kept_zone_list)
            push!(keep_cols, col)
        end
    end
    return select(df, keep_cols)
end

function filter_load_timeseries_columns(df::DataFrame, kept_zone_list::Vector{String})
    keep_cols = String[]
    for col in names(df)
        if (col in TIMESERIES_META_COLS) || (col in kept_zone_list) || (col == "NI")
            push!(keep_cols, col)
        end
    end
    return select(df, keep_cols)
end

function update_zonedata_demand!(zonedata::DataFrame, zone_peaks::Dict{String,Float64})
    if !("Demand (MW)" in names(zonedata))
        return zonedata
    end
    for row_idx in 1:nrow(zonedata)
        zone = string(zonedata[row_idx, "Zone_id"])
        if haskey(zone_peaks, zone)
            zonedata[row_idx, "Demand (MW)"] = zone_peaks[zone]
        end
    end
    return zonedata
end

function demand_by_zone(zonedata::DataFrame)
    demand_map = Dict{String,Float64}()
    if !(("Zone_id" in names(zonedata)) && ("Demand (MW)" in names(zonedata)))
        return demand_map
    end
    for row in eachrow(zonedata)
        demand_map[string(row["Zone_id"])] = to_f64_md(row["Demand (MW)"], 0.0)
    end
    return demand_map
end

function tuned_candidate_cap(gen_type::AbstractString, zone_demand::Float64, original_cap::Float64)
    factor = if gen_type == "SolarPV"
        MD_SOLAR_CAP_FACTOR
    elseif gen_type == "WindOn"
        MD_WINDON_CAP_FACTOR
    elseif gen_type == "WindOff"
        MD_WINDOFF_CAP_FACTOR
    elseif gen_type == "NGCT_CCS"
        MD_NGCT_CCS_CAP_FACTOR
    elseif gen_type == "NGCC_CCS"
        MD_NGCC_CCS_CAP_FACTOR
    else
        return original_cap
    end
    return min(original_cap, factor * zone_demand)
end

function tune_candidate_generation!(gendata_candidate::DataFrame, zonedata::DataFrame)
    if !(("Zone" in names(gendata_candidate)) && ("Type" in names(gendata_candidate)) && ("Pmax (MW)" in names(gendata_candidate)))
        return gendata_candidate
    end
    zone_demand = demand_by_zone(zonedata)
    for row_idx in 1:nrow(gendata_candidate)
        zone = string(gendata_candidate[row_idx, "Zone"])
        gen_type = string(gendata_candidate[row_idx, "Type"])
        zone_peak = get(zone_demand, zone, to_f64_md(gendata_candidate[row_idx, "Pmax (MW)"], 0.0))
        old_pmax = to_f64_md(gendata_candidate[row_idx, "Pmax (MW)"], 0.0)
        gendata_candidate[row_idx, "Pmax (MW)"] = round(tuned_candidate_cap(gen_type, zone_peak, old_pmax); digits=3)
    end
    return gendata_candidate
end

function tune_candidate_storage!(storagedata_candidate::DataFrame, zonedata::DataFrame)
    if !("Zone" in names(storagedata_candidate))
        return storagedata_candidate
    end
    if "Charging efficiency" in names(storagedata_candidate)
        storagedata_candidate[!, Symbol("Charging efficiency")] = Float64.(to_f64_md.(storagedata_candidate[:, "Charging efficiency"], 1.0))
    end
    if "Discharging efficiency" in names(storagedata_candidate)
        storagedata_candidate[!, Symbol("Discharging efficiency")] = Float64.(to_f64_md.(storagedata_candidate[:, "Discharging efficiency"], 1.0))
    end
    zone_demand = demand_by_zone(zonedata)
    for row_idx in 1:nrow(storagedata_candidate)
        zone = string(storagedata_candidate[row_idx, "Zone"])
        zone_peak = get(zone_demand, zone, 0.0)
        old_power = to_f64_md(storagedata_candidate[row_idx, "Max Power (MW)"], 0.0)
        tuned_power = min(old_power, MD_STORAGE_POWER_CAP_FACTOR * zone_peak)
        storagedata_candidate[row_idx, "Max Power (MW)"] = round(tuned_power; digits=3)
        if "Capacity (MWh)" in names(storagedata_candidate)
            old_energy = to_f64_md(storagedata_candidate[row_idx, "Capacity (MWh)"], 0.0)
            storagedata_candidate[row_idx, "Capacity (MWh)"] = round(min(old_energy, tuned_power * MD_STORAGE_DURATION_HOURS); digits=3)
        end
        if "Charging efficiency" in names(storagedata_candidate)
            storagedata_candidate[row_idx, "Charging efficiency"] = min(to_f64_md(storagedata_candidate[row_idx, "Charging efficiency"], 1.0), MD_STORAGE_ROUNDTRIP_COMPONENT_EFF)
        end
        if "Discharging efficiency" in names(storagedata_candidate)
            storagedata_candidate[row_idx, "Discharging efficiency"] = min(to_f64_md(storagedata_candidate[row_idx, "Discharging efficiency"], 1.0), MD_STORAGE_ROUNDTRIP_COMPONENT_EFF)
        end
    end
    return storagedata_candidate
end

function tune_policy_inputs!(rpspolicies::DataFrame, single_parameter::DataFrame)
    if ("From_state" in names(rpspolicies)) && ("RPS" in names(rpspolicies))
        for row_idx in 1:nrow(rpspolicies)
            if string(rpspolicies[row_idx, "From_state"]) == "MD"
                rpspolicies[row_idx, "RPS"] = MD_REALISTIC_RPS
            end
        end
    end
    normalize_single_parameter_columns!(single_parameter)
    if !("planning_reserve_margin" in names(single_parameter))
        single_parameter[!, :planning_reserve_margin] = fill(MD_REALISTIC_PRM, nrow(single_parameter))
    else
        single_parameter[1, "planning_reserve_margin"] = MD_REALISTIC_PRM
    end
    return rpspolicies, single_parameter
end

function zonal_profile_means(df::DataFrame)
    means = Dict{String,Float64}()
    for col in names(df)
        col_name = String(col)
        if col_name in TIMESERIES_META_COLS || col_name == "NI"
            continue
        end
        vals = [clamp(to_f64_md(v, 0.0), 0.0, 1.0) for v in df[!, col]]
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
            df[row_idx, "AF"] = get(solar_means, zone, to_f64_md(df[row_idx, "AF"], 1.0))
        elseif gen_type in ("WindOn", "WindOff")
            df[row_idx, "AF"] = get(wind_means, zone, to_f64_md(df[row_idx, "AF"], 1.0))
        end
    end
    return df
end

function write_time_only_afdata_csv(path::AbstractString, winddata::DataFrame)
    write_csv(path, ensure_time_columns(winddata))
    return path
end

function load_pcm_workbook_sheet_csv(path::AbstractString, sheet_name::AbstractString)
    return DataFrame(XLSX.readtable(path, sheet_name))
end

function update_gtep_settings!(settings_path::AbstractString)
    lines = readlines(settings_path)
    replacements = Dict(
        "resource_aggregation:" => "resource_aggregation: 1           # 1 aggregate resources before model build; 0 use full input resources",
        "endogenous_rep_day:" => "endogenous_rep_day: 0            #Binary,1 use endogenous representative-day selection; 0 Does Not",
        "external_rep_day:" => "external_rep_day: 0              #Binary,1 use user-provided representative periods and weights; 0 Does Not",
        "flexible_demand:" => "flexible_demand: 0               #Binary, 1 enable DR backlog formulation; 0 disable DR",
        "carbon_policy:" => "carbon_policy: 0                 #Int, 0 no carbon policy; 1 Option A state emissions cap; 2 Option B cap-and-trade",
        "clean_energy_policy:" => "clean_energy_policy: 1           #Int, 0 turn off RPS constraints; 1 turn on RPS constraints",
        "planning_reserve_mode:" => "planning_reserve_mode: 1         #Int, 0 disable RA; 1 system-level RA; 2 zonal-level RA",
        "solver:" => "solver: gurobi                    #String, solver: cbc, clp, scip, highs, cplex, gurobi",
        "save_postprocess_snapshot:" => "save_postprocess_snapshot: 1      #Int, 0 do not save; 1 save minimal snapshot for later postprocessing such as EREC; 2 save full snapshot with additional solved-run details",
    )
    for i in eachindex(lines)
        stripped = strip(lines[i])
        for (prefix, replacement) in replacements
            if startswith(stripped, prefix)
                lines[i] = replacement
                break
            end
        end
    end
    open(settings_path, "w") do io
        for line in lines
            println(io, line)
        end
    end
    return settings_path
end

function update_pcm_settings!(settings_path::AbstractString)
    lines = readlines(settings_path)
    replacements = Dict(
        "resource_aggregation:" => "resource_aggregation: 1           # 1 aggregate resources before model build; 0 use full input resources",
        "representative_day!:" => "endogenous_rep_day: 0            # 1 representative-day formulation; 0 full chronological hours",
        "endogenous_rep_day:" => "endogenous_rep_day: 0            # 1 representative-day formulation; 0 full chronological hours",
        "external_rep_day:" => "external_rep_day: 0              # 1 use user-provided representative periods and weights; 0 otherwise",
        "flexible_demand:" => "flexible_demand: 0                # 1 enable demand response formulation; 0 disable",
        "clean_energy_policy:" => "clean_energy_policy: 1            # 1 enforce RPS/clean-energy constraints; 0 disable",
        "carbon_policy:" => "carbon_policy: 0                  # 0 none; 1 state cap; 2 cap-and-trade",
        "operation_reserve_mode:" => "operation_reserve_mode: 1         # PCM: 0 none; 1 REG+SPIN; 2 REG+SPIN+NSPIN",
        "unit_commitment:" => "unit_commitment: 1                # PCM UC mode: 0 no UC; 1 integer UC; 2 convexified UC",
        "solver:" => "solver: gurobi                     # Solver name: cbc, clp, highs, scip, cplex, gurobi",
    )
    for i in eachindex(lines)
        stripped = strip(lines[i])
        for (prefix, replacement) in replacements
            if startswith(stripped, prefix)
                lines[i] = replacement
                break
            end
        end
    end
    open(settings_path, "w") do io
        for line in lines
            println(io, line)
        end
    end
    return settings_path
end

function remove_if_exists(path::AbstractString)
    isfile(path) && rm(path; force=true)
    return nothing
end

function build_md_holistic_full_pair()
    open(STATUS_FILE, "w") do io
        println(io, "status=started")
    end

    gtep_case_dir = copy_case_clean(MD_GTEP_SOURCE_CASE, MD_GTEP_FULL_CASE)
    pcm_case_dir = copy_case_clean(MD_PCM_SOURCE_CASE, MD_PCM_FULL_CASE)
    append_status("stage=case_copies_ready")

    gtep_data_dir = joinpath(gtep_case_dir, "Data_100RPS")
    pcm_data_dir = joinpath(pcm_case_dir, "Data_PCM2035")
    pcm_workbook_path = joinpath(MODEL_CASES_DIR, MD_PCM_SOURCE_CASE, "Data_PCM2035", "PCM_input_total.xlsx")

    notes = String[]
    push!(notes, "Built a full-8760 MD holistic pair from the standalone MD GTEP and MD PCM source cases.")
    push!(notes, "Baseline philosophy: both cases share the same zonedata, linedata, existing generation/storage fleets, chronology, and policy inputs; PCM keeps only operational fields such as UC and reserve parameters.")

    pcm_zonedata = filter_md_zones(load_pcm_workbook_sheet_csv(pcm_workbook_path, "zonedata"))
    kept_zone_list = zone_ids(pcm_zonedata)
    kept_zones = Set(kept_zone_list)
    pcm_linedata = filter_lines_by_zones(load_pcm_workbook_sheet_csv(pcm_workbook_path, "linedata"), kept_zones)
    pcm_gendata = filter_by_zone(load_pcm_workbook_sheet_csv(pcm_workbook_path, "gendata"), "Zone", kept_zones)
    ensure_zero_flag_column!(pcm_gendata, "Flag_RET")
    pcm_storagedata = filter_by_zone(load_pcm_workbook_sheet_csv(pcm_workbook_path, "storagedata"), "Zone", kept_zones)
    pcm_load = filter_load_timeseries_columns(load_pcm_workbook_sheet_csv(pcm_workbook_path, "load_timeseries_regional"), kept_zone_list)
    pcm_wind = filter_timeseries_zone_columns(load_pcm_workbook_sheet_csv(pcm_workbook_path, "wind_timeseries_regional"), kept_zone_list)
    pcm_solar = filter_timeseries_zone_columns(load_pcm_workbook_sheet_csv(pcm_workbook_path, "solar_timeseries_regional"), kept_zone_list)
    pcm_cbp = load_pcm_workbook_sheet_csv(pcm_workbook_path, "carbonpolicies")
    pcm_rps = load_pcm_workbook_sheet_csv(pcm_workbook_path, "rpspolicies")
    pcm_singlepar = load_pcm_workbook_sheet_csv(pcm_workbook_path, "single_parameter")
    pcm_rps, pcm_singlepar = tune_policy_inputs!(pcm_rps, pcm_singlepar)
    append_status("stage=pcm_workbook_loaded")

    write_csv(joinpath(gtep_data_dir, "zonedata.csv"), pcm_zonedata)
    write_csv(joinpath(gtep_data_dir, "linedata.csv"), pcm_linedata)
    write_csv(joinpath(gtep_data_dir, "gendata.csv"), add_flag_rps!(select(pcm_gendata, [
        "Pmax (MW)",
        "Pmin (MW)",
        "Zone",
        "Type",
        "Flag_RET",
        "Flag_thermal",
        "Flag_VRE",
        "Flag_mustrun",
        "Cost (\$/MWh)",
        "EF",
        "CC",
        "FOR",
    ])))
    write_csv(joinpath(gtep_data_dir, "storagedata.csv"), pcm_storagedata)
    write_csv(joinpath(gtep_data_dir, "load_timeseries_regional.csv"), pcm_load)
    write_csv(joinpath(gtep_data_dir, "wind_timeseries_regional.csv"), pcm_wind)
    write_csv(joinpath(gtep_data_dir, "solar_timeseries_regional.csv"), pcm_solar)
    write_csv(joinpath(gtep_data_dir, "carbonpolicies.csv"), pcm_cbp)
    write_csv(joinpath(gtep_data_dir, "rpspolicies.csv"), pcm_rps)
    write_csv(joinpath(gtep_data_dir, "single_parameter.csv"), pcm_singlepar)
    append_status("stage=gtep_shared_baseline_written")

    wind_means = zonal_profile_means(pcm_wind)
    solar_means = zonal_profile_means(pcm_solar)
    gtep_existing = read_csv(joinpath(gtep_data_dir, "gendata.csv"))
    assign_static_vre_af!(gtep_existing, wind_means, solar_means)
    write_csv(joinpath(gtep_data_dir, "gendata.csv"), gtep_existing)

    gtep_candidates = filter_by_zone(read_csv(joinpath(gtep_data_dir, "gendata_candidate.csv")), "Zone", kept_zones)
    add_flag_rps!(gtep_candidates)
    assign_static_vre_af!(gtep_candidates, wind_means, solar_means)
    tune_candidate_generation!(gtep_candidates, pcm_zonedata)
    write_csv(joinpath(gtep_data_dir, "gendata_candidate.csv"), gtep_candidates)
    write_csv(joinpath(gtep_data_dir, "linedata_candidate.csv"), filter_lines_by_zones(read_csv(joinpath(gtep_data_dir, "linedata_candidate.csv")), kept_zones))
    gtep_storage_candidates = filter_by_zone(read_csv(joinpath(gtep_data_dir, "storagedata_candidate.csv")), "Zone", kept_zones)
    tune_candidate_storage!(gtep_storage_candidates, pcm_zonedata)
    write_csv(joinpath(gtep_data_dir, "storagedata_candidate.csv"), gtep_storage_candidates)
    write_time_only_afdata_csv(joinpath(gtep_data_dir, "gen_availability_timeseries.csv"), pcm_wind)
    append_status("stage=gtep_af_ready")

    for filename in [
        "zonedata.csv",
        "linedata.csv",
        "gendata.csv",
        "storagedata.csv",
        "load_timeseries_regional.csv",
        "wind_timeseries_regional.csv",
        "solar_timeseries_regional.csv",
        "carbonpolicies.csv",
        "rpspolicies.csv",
        "single_parameter.csv",
    ]
        copy_file(joinpath(gtep_data_dir, filename), joinpath(pcm_data_dir, filename))
    end
    append_status("stage=pcm_shared_baseline_written")

    write_csv(joinpath(pcm_data_dir, "gendata.csv"), pcm_gendata)
    write_csv(joinpath(pcm_data_dir, "storagedata.csv"), pcm_storagedata)
    remove_if_exists(joinpath(pcm_data_dir, "PCM_input_total.xlsx"))
    remove_if_exists(joinpath(pcm_data_dir, "~\$PCM_input_total.xlsx"))
    append_status("stage=pcm_operational_fields_restored")

    update_gtep_settings!(joinpath(gtep_case_dir, "Settings", "HOPE_model_settings.yml"))
    update_pcm_settings!(joinpath(pcm_case_dir, "Settings", "HOPE_model_settings.yml"))
    append_status("stage=settings_updated")

    push!(notes, "Shared baseline files now come from the MD PCM holistic workbook: zonedata, linedata, existing fleets, load, wind, solar, carbon, RPS, and single-parameter tables.")
    push!(notes, "The rebuilt pair keeps only MD zones (Flag_MD = 1), removes external APS and DPL corridors, and filters existing and candidate assets to the retained MD topology.")
    push!(notes, "The load chronology now preserves the original MD zonal profile columns and the original NI time series from the PCM workbook while dropping non-MD zones, instead of reconstructing load from NI-derived shares.")
    push!(notes, "The new realistic benchmark tuning reduces the Maryland RPS target to $(MD_REALISTIC_RPS), raises the planning reserve margin to $(MD_REALISTIC_PRM), and turns off the otherwise non-binding carbon policy flag.")
    push!(notes, "Candidate build envelopes are now scaled to zonal peak demand: SolarPV $(MD_SOLAR_CAP_FACTOR)x, WindOn $(MD_WINDON_CAP_FACTOR)x, WindOff $(MD_WINDOFF_CAP_FACTOR)x, NGCT_CCS $(MD_NGCT_CCS_CAP_FACTOR)x, NGCC_CCS $(MD_NGCC_CCS_CAP_FACTOR)x, and battery power $(MD_STORAGE_POWER_CAP_FACTOR)x with $(MD_STORAGE_DURATION_HOURS)-hour energy duration.")
    push!(notes, "GTEP representative-day mode was disabled for this pair so the new small case exercises the full 8760 chronology.")
    push!(notes, "PCM was converted to CSV inputs so the new case has an explicit, inspectable shared baseline rather than a hidden workbook-only baseline.")
    push!(notes, "PCM gendata.csv intentionally keeps UC and reserve fields that do not exist in the GTEP baseline; those are the allowed operational-only differences.")

    write_note(joinpath(MD_NOTES_DIR, "md_holistic_full_pair_notes.md"), "MD Holistic Full Pair", notes)
    append_status("status=completed")
    return gtep_case_dir, pcm_case_dir
end

function main()
    try
        gtep_case_dir, pcm_case_dir = build_md_holistic_full_pair()
        println("Created MD holistic full pair:")
        println("  GTEP: ", gtep_case_dir)
        println("  PCM : ", pcm_case_dir)
        println("  Notes: ", joinpath(MD_NOTES_DIR, "md_holistic_full_pair_notes.md"))
    catch err
        append_status("error=$(sprint(showerror, err))")
        rethrow(err)
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end