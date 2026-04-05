"""
    default_erec_settings()

Return the default settings dictionary for the Equivalent Reliability Enhancement Capability
(EREC) postprocessing workflow.
"""
function default_erec_settings()
    return Dict{String,Any}(
        "enabled" => 1,
        "voll_override" => nothing,
        "delta_mw" => 1.0,
        "perturbation_mode" => "forward",
        "reference_resource_mode" => "same_zone",
        "resource_types" => ["generator", "storage"],
        "resource_scope" => "built_only",
        "custom_resources" => Dict{String,Any}(
            "generators" => Any[],
            "storages" => Any[],
        ),
        "write_outputs" => 1,
        "output_dir_name" => "output_erec",
        "erec_results_file" => "erec_results.csv",
        "erec_summary_file" => "erec_summary.csv",
        "write_cc_to_tables" => 0,
        "skip_if_eue_zero" => 1,
        "min_denominator_eue_drop" => 1.0e-6,
        "storage_duration_mode" => "preserve",
    )
end

"""
    load_erec_settings(case_path::AbstractString)

Load optional EREC settings from `Settings/HOPE_erec_settings.yml`.
Missing files fall back to built-in defaults.
"""
function load_erec_settings(case_path::AbstractString)
    settings = default_erec_settings()
    settings_path = joinpath(case_path, "Settings", "HOPE_erec_settings.yml")
    if isfile(settings_path)
        user_settings = open(settings_path) do io
            YAML.load(io)
        end
        for (k, v) in user_settings
            settings[string(k)] = v
        end
    end
    return settings
end

const POSTPROCESS_SNAPSHOT_DIRNAME = "postprocess_snapshot"
snapshot_yaml_value(x) = x === missing ? nothing : x

function parse_postprocess_snapshot_mode(x)
    v = x isa Integer ? Int(x) : parse(Int, string(x))
    if !(v in (0, 1, 2))
        throw(ArgumentError("Invalid save_postprocess_snapshot=$(v). Expected 0, 1, or 2."))
    end
    return v
end

snapshot_dir_from_output(output_path::AbstractString) = joinpath(output_path, POSTPROCESS_SNAPSHOT_DIRNAME)
snapshot_settings_dir(snapshot_dir::AbstractString) = joinpath(snapshot_dir, "Settings")
snapshot_base_input_dir(snapshot_dir::AbstractString) = joinpath(snapshot_dir, "base_input")
snapshot_fixed_input_dir(snapshot_dir::AbstractString) = joinpath(snapshot_dir, "fixed_fleet_input")

function write_yaml_file(path::AbstractString, data)
    open(path, "w") do io
        YAML.write(io, data)
    end
    return path
end

function snapshot_input_file_map()
    return [
        ("Gendata", "gendata.csv"),
        ("Gendata_candidate", "gendata_candidate.csv"),
        ("Storagedata", "storagedata.csv"),
        ("Estoragedata_candidate", "storagedata_candidate.csv"),
        ("Linedata", "linedata.csv"),
        ("Linedata_candidate", "linedata_candidate.csv"),
        ("Zonedata", "zonedata.csv"),
        ("CBPdata", "carbonpolicies.csv"),
        ("RPSdata", "rpspolicies.csv"),
        ("Singlepar", "single_parameter.csv"),
        ("Loaddata", "load_timeseries_regional.csv"),
        ("AFdata", "gen_availability_timeseries.csv"),
        ("DRdata", "flexddata.csv"),
        ("DRtsdata", "dr_timeseries_regional.csv"),
        ("RepWeightData", "rep_period_weights.csv"),
    ]
end

function save_snapshot_input_tables(input_data::Dict, target_dir::AbstractString)
    mkpath(target_dir)
    for (key, filename) in snapshot_input_file_map()
        if haskey(input_data, key)
            CSV.write(joinpath(target_dir, filename), input_data[key])
        end
    end
    return target_dir
end

function load_snapshot_input_tables(source_dir::AbstractString)
    input_data = Dict{String,Any}()
    for (key, filename) in snapshot_input_file_map()
        filepath = joinpath(source_dir, filename)
        if isfile(filepath)
            input_data[key] = CSV.read(filepath, DataFrame)
        end
    end
    if haskey(input_data, "Loaddata")
        normalize_timeseries_time_columns!(input_data["Loaddata"]; context="snapshot/load_timeseries_regional")
        input_data["NIdata"] = ("NI" in names(input_data["Loaddata"])) ? input_data["Loaddata"][:, "NI"] : zeros(nrow(input_data["Loaddata"]))
    end
    if haskey(input_data, "AFdata")
        normalize_timeseries_time_columns!(input_data["AFdata"]; context="snapshot/gen_availability_timeseries")
        if haskey(input_data, "Loaddata")
            validate_aligned_time_columns!(input_data["Loaddata"], input_data["AFdata"], "snapshot/gen_availability_timeseries")
        end
    end
    if haskey(input_data, "DRtsdata")
        normalize_timeseries_time_columns!(input_data["DRtsdata"]; context="snapshot/dr_timeseries_regional")
        if haskey(input_data, "Loaddata")
            validate_aligned_time_columns!(input_data["Loaddata"], input_data["DRtsdata"], "snapshot/dr_timeseries_regional")
        end
    end
    return input_data
end

function maybe_copy_settings_file(src_dir::AbstractString, dest_dir::AbstractString, filename::AbstractString)
    src = joinpath(src_dir, filename)
    if isfile(src)
        cp(src, joinpath(dest_dir, filename); force=true)
    end
    return nothing
end

function model_component_or_nothing(model::Model, sym::Symbol)
    try
        return model[sym]
    catch
        return nothing
    end
end

function save_postprocess_snapshot_bundle(
    output_path::AbstractString,
    case_path::AbstractString,
    config_set::Dict,
    base_input::Dict,
    fixed_input::Dict;
    mode::Int,
    solved_model::Union{Nothing,Model}=nothing,
)
    snapshot_dir = snapshot_dir_from_output(output_path)
    if isdir(snapshot_dir)
        rm(snapshot_dir; recursive=true, force=true)
    end
    mkpath(snapshot_dir)
    mkpath(snapshot_settings_dir(snapshot_dir))

    save_snapshot_input_tables(base_input, snapshot_base_input_dir(snapshot_dir))
    save_snapshot_input_tables(fixed_input, snapshot_fixed_input_dir(snapshot_dir))

    write_yaml_file(joinpath(snapshot_dir, "resolved_model_settings.yml"), config_set)
    settings_src_dir = joinpath(case_path, "Settings")
    maybe_copy_settings_file(settings_src_dir, snapshot_settings_dir(snapshot_dir), "HOPE_model_settings.yml")
    maybe_copy_settings_file(settings_src_dir, snapshot_settings_dir(snapshot_dir), "HOPE_rep_day_settings.yml")
    maybe_copy_settings_file(settings_src_dir, snapshot_settings_dir(snapshot_dir), "HOPE_aggregation_settings.yml")
    maybe_copy_settings_file(settings_src_dir, snapshot_settings_dir(snapshot_dir), "HOPE_erec_settings.yml")
    maybe_copy_settings_file(settings_src_dir, snapshot_settings_dir(snapshot_dir), string(config_set["solver"]) * "_settings.yml")

    metadata = Dict{String,Any}(
        "snapshot_version" => 1,
        "source_case_path" => case_path,
        "source_output_path" => output_path,
        "model_mode" => snapshot_yaml_value(get(config_set, "model_mode", nothing)),
        "created_at" => Dates.format(now(), dateformat"yyyy-mm-ddTHH:MM:SS"),
        "save_postprocess_snapshot" => mode,
        "solver" => snapshot_yaml_value(get(config_set, "solver", nothing)),
        "planning_reserve_mode" => snapshot_yaml_value(get(config_set, "planning_reserve_mode", nothing)),
        "resource_aggregation" => snapshot_yaml_value(get(config_set, "resource_aggregation", get(config_set, "aggregated!", nothing))),
        "endogenous_rep_day" => snapshot_yaml_value(get(config_set, "endogenous_rep_day", nothing)),
        "external_rep_day" => snapshot_yaml_value(get(config_set, "external_rep_day", nothing)),
        "representative_day!" => snapshot_yaml_value(get(config_set, "representative_day!", nothing)),
        "flexible_demand" => snapshot_yaml_value(get(config_set, "flexible_demand", nothing)),
        "unit_commitment" => snapshot_yaml_value(get(config_set, "unit_commitment", nothing)),
    )
    if solved_model !== nothing
        metadata["termination_status"] = string(termination_status(solved_model))
        metadata["primal_status"] = string(primal_status(solved_model))
        if primal_status(solved_model) in (MOI.FEASIBLE_POINT, MOI.NEARLY_FEASIBLE_POINT)
            metadata["objective_value"] = objective_value(solved_model)
        end
    end
    write_yaml_file(joinpath(snapshot_dir, "metadata.yml"), metadata)

    if mode == 2 && solved_model !== nothing
        solved_decisions_dir = joinpath(snapshot_dir, "solved_decisions")
        mkpath(solved_decisions_dir)

        x_var = model_component_or_nothing(solved_model, :x)
        y_var = model_component_or_nothing(solved_model, :y)
        z_var = model_component_or_nothing(solved_model, :z)
        x_ret_var = model_component_or_nothing(solved_model, :x_RET)

        if x_var !== nothing && nrow(base_input["Gendata_candidate"]) > 0
            CSV.write(joinpath(solved_decisions_dir, "build_generator.csv"), DataFrame(
                CandidateIndex = collect(1:nrow(base_input["Gendata_candidate"])),
                BuildDecision = [Float64(value(x_var[nrow(base_input["Gendata"]) + i])) for i in 1:nrow(base_input["Gendata_candidate"])],
            ))
        end
        if z_var !== nothing && nrow(base_input["Estoragedata_candidate"]) > 0
            CSV.write(joinpath(solved_decisions_dir, "build_storage.csv"), DataFrame(
                CandidateIndex = collect(1:nrow(base_input["Estoragedata_candidate"])),
                BuildDecision = [Float64(value(z_var[nrow(base_input["Storagedata"]) + i])) for i in 1:nrow(base_input["Estoragedata_candidate"])],
            ))
        end
        if y_var !== nothing && nrow(base_input["Linedata_candidate"]) > 0
            CSV.write(joinpath(solved_decisions_dir, "build_line.csv"), DataFrame(
                CandidateIndex = collect(1:nrow(base_input["Linedata_candidate"])),
                BuildDecision = [Float64(value(y_var[nrow(base_input["Linedata"]) + i])) for i in 1:nrow(base_input["Linedata_candidate"])],
            ))
        end
        if x_ret_var !== nothing
            CSV.write(joinpath(solved_decisions_dir, "retire_generator.csv"), DataFrame(
                ExistingIndex = collect(1:nrow(base_input["Gendata"])),
                RetirementDecision = [Float64(value(x_ret_var[i])) for i in 1:nrow(base_input["Gendata"])],
            ))
        end

        baseline_summary_dir = joinpath(snapshot_dir, "baseline_summary")
        mkpath(baseline_summary_dir)
        summary_df = DataFrame(
            Metric = ["termination_status", "primal_status", "objective_value"],
            Value = [
                get(metadata, "termination_status", missing),
                get(metadata, "primal_status", missing),
                get(metadata, "objective_value", missing),
            ],
        )
        CSV.write(joinpath(baseline_summary_dir, "baseline_metrics.csv"), summary_df)
    end

    return Dict(
        "snapshot_dir" => snapshot_dir,
        "snapshot_mode" => mode,
        "metadata_path" => joinpath(snapshot_dir, "metadata.yml"),
    )
end

function save_postprocess_snapshot(
    output_path::AbstractString,
    case_path::AbstractString,
    config_set::Dict,
    base_input::Dict,
    solved_model::Model;
    mode::Int,
)
    if get(config_set, "model_mode", "") != "GTEP"
        throw(ArgumentError("save_postprocess_snapshot is currently implemented only for GTEP solved cases."))
    end
    fixed_input = build_fixed_fleet_input(base_input, solved_model)
    return save_postprocess_snapshot_bundle(
        output_path,
        case_path,
        config_set,
        base_input,
        fixed_input;
        mode=mode,
        solved_model=solved_model,
    )
end

function resolve_snapshot_dir(snapshot_or_output_path::AbstractString)
    candidate = rstrip(snapshot_or_output_path, ['/', '\\'])
    if basename(candidate) == POSTPROCESS_SNAPSHOT_DIRNAME
        return candidate
    end
    return snapshot_dir_from_output(candidate)
end

function load_postprocess_snapshot(snapshot_or_output_path::AbstractString)
    snapshot_dir = resolve_snapshot_dir(snapshot_or_output_path)
    if !isdir(snapshot_dir)
        throw(ArgumentError("Postprocess snapshot directory not found: $snapshot_dir"))
    end

    metadata_path = joinpath(snapshot_dir, "metadata.yml")
    config_path = joinpath(snapshot_dir, "resolved_model_settings.yml")
    if !isfile(metadata_path) || !isfile(config_path)
        throw(ArgumentError("Incomplete postprocess snapshot in $snapshot_dir. Expected metadata.yml and resolved_model_settings.yml."))
    end

    metadata = open(metadata_path) do io
        YAML.load(io)
    end
    config_set = open(config_path) do io
        YAML.load(io)
    end

    base_input = load_snapshot_input_tables(snapshot_base_input_dir(snapshot_dir))
    fixed_input = load_snapshot_input_tables(snapshot_fixed_input_dir(snapshot_dir))

    return Dict(
        "snapshot_dir" => snapshot_dir,
        "output_path" => dirname(snapshot_dir),
        "metadata" => metadata,
        "config" => config_set,
        "base_input" => base_input,
        "fixed_input" => fixed_input,
    )
end

parse_erec_binary(x, keyname::AbstractString) = begin
    v = x isa Integer ? Int(x) : parse(Int, string(x))
    if !(v in (0, 1))
        throw(ArgumentError("Invalid EREC setting $(keyname)=$(v). Expected 0 or 1."))
    end
    v
end

to_float_erec(x, default::Float64=0.0) = ismissing(x) || x === nothing || string(x) == "" ? default : (x isa Number ? Float64(x) : parse(Float64, string(x)))

function normalize_erec_resource_types(raw_types)
    if raw_types isa AbstractVector
        vals = lowercase.(strip.(string.(collect(raw_types))))
    else
        vals = [lowercase(strip(string(raw_types)))]
    end
    allowed = Set(["generator", "storage"])
    bad = [v for v in vals if !(v in allowed)]
    if !isempty(bad)
        throw(ArgumentError("Invalid EREC resource_types=$(bad). Allowed values: generator, storage."))
    end
    return unique(vals)
end

function normalize_custom_erec_resources(raw_selection)
    normalized = Dict(
        "generator" => Set{Tuple{String,Int}}(),
        "storage" => Set{Tuple{String,Int}}(),
    )
    raw_selection === nothing && return normalized
    raw_selection isa AbstractDict || throw(ArgumentError("Invalid custom_resources=$(raw_selection). Expected a dictionary with generator/storage selections."))

    key_map = Dict(
        "generator" => "generator",
        "generators" => "generator",
        "storage" => "storage",
        "storages" => "storage",
    )

    for (raw_key, raw_vals) in raw_selection
        key = lowercase(strip(string(raw_key)))
        haskey(key_map, key) || throw(ArgumentError("Invalid custom_resources key=$(raw_key). Allowed keys: generators, storages."))
        target_type = key_map[key]
        vals = raw_vals isa AbstractVector ? raw_vals : [raw_vals]
        for raw_val in vals
            source = ""
            idx = 0
            if raw_val isa Integer
                source = "existing"
                idx = Int(raw_val)
            else
                label = lowercase(strip(string(raw_val)))
                m = match(r"^(existing|candidate)_(\d+)$", label)
                if m === nothing
                    idx = try
                        parse(Int, label)
                    catch
                        throw(ArgumentError("Invalid custom_resources entry=$(raw_val). Use integers for existing rows or labels like existing_12 / candidate_3."))
                    end
                    source = "existing"
                else
                    source = m.captures[1]
                    idx = parse(Int, m.captures[2])
                end
            end
            idx >= 1 || throw(ArgumentError("Invalid custom_resources entry=$(raw_val). Resource index must be positive."))
            push!(normalized[target_type], (source, idx))
        end
    end
    return normalized
end

function custom_erec_selected(custom_selection::Dict, resource_type::AbstractString, source::AbstractString, idx::Int)
    key = lowercase(strip(String(resource_type)))
    return (String(source), Int(idx)) in get(custom_selection, key, Set{Tuple{String,Int}}())
end

function resolve_case_path_for_erec(case::AbstractString)
    case_path = rstrip(case, ['/', '\\'])
    if startswith(case_path, "HOPE/") || startswith(case_path, "HOPE\\")
        case_path = case_path[6:end]
    end
    tried_paths = String[]
    for candidate in (case_path, joinpath("ModelCases", case_path), joinpath("ModelCases", basename(case_path)))
        push!(tried_paths, candidate)
        if isdir(candidate)
            return candidate
        end
    end
    throw(ArgumentError("EREC case directory does not exist: $case. Tried paths: $(tried_paths)"))
end

function build_erec_config(base_config::Dict, erec_settings::Dict)
    config = deepcopy(base_config)
    if get(config, "model_mode", "") != "GTEP"
        throw(ArgumentError("EREC is currently implemented only for GTEP cases. Found model_mode=$(get(config, "model_mode", missing))."))
    end
    config["planning_reserve_mode"] = 0
    config["summary_table"] = 0
    return config
end

function baseline_voll_for_erec(input_data::Dict)
    singlepar = input_data["Singlepar"]
    if "VOLL" in names(singlepar)
        return to_float_erec(singlepar[1, "VOLL"], 100000.0)
    end
    return 100000.0
end

function resolve_erec_voll(singlepar::DataFrame, erec_settings::Dict)
    baseline_voll = ("VOLL" in names(singlepar)) ? to_float_erec(singlepar[1, "VOLL"], 100000.0) : 100000.0
    raw_override = get(erec_settings, "voll_override", nothing)
    override_active = !(raw_override === nothing || ismissing(raw_override) || strip(string(raw_override)) == "" || lowercase(strip(string(raw_override))) == "baseline")
    voll = override_active ? to_float_erec(raw_override, baseline_voll) : baseline_voll
    return voll, baseline_voll, override_active
end

function maybe_warn_erec_voll_mismatch(context::Symbol, baseline_voll::Float64, erec_voll::Float64, override_active::Bool)
    if !override_active || isapprox(erec_voll, baseline_voll; atol=1.0e-9, rtol=0.0)
        return nothing
    end
    if context == :solved_baseline
        @warn "EREC voll_override=$(erec_voll) differs from the baseline solved-case VOLL=$(baseline_voll). This changes the EREC redispatch objective relative to the solved baseline fleet. To preserve consistency, omit voll_override or set it equal to the original baseline VOLL."
    elseif context == :case_input
        @warn "EREC voll_override=$(erec_voll) differs from the case-input VOLL=$(baseline_voll). HOPE will solve the EREC baseline with the override value instead of the VOLL stored in single_parameter.csv."
    end
    return nothing
end

function apply_erec_overrides!(input_data::Dict, erec_settings::Dict; voll_warning_context::Symbol=:none)
    singlepar = input_data["Singlepar"]
    voll, baseline_voll, override_active = resolve_erec_voll(singlepar, erec_settings)
    maybe_warn_erec_voll_mismatch(voll_warning_context, baseline_voll, voll, override_active)
    if "VOLL" in names(singlepar)
        singlepar[1, "VOLL"] = voll
    else
        singlepar[!, "VOLL"] = fill(voll, nrow(singlepar))
    end
    return input_data
end

function rep_period_weights_for_erec(config_set::Dict, input_data::Dict)
    loaddata = input_data["Loaddata"]
    endogenous_rep_day, external_rep_day, representative_day_mode = resolve_rep_day_mode(config_set; context="EREC")
    input_T, input_H_t, input_H_T, has_custom_time_periods = build_time_period_hours(loaddata)
    T = input_T
    H_t = input_H_t
    H_T = input_H_T
    N = Dict{Int,Float64}()
    if representative_day_mode == 1
        if external_rep_day == 1
            rep_weight_df = input_data["RepWeightData"]
            T = sort(unique(Int.(rep_weight_df[!, "Time Period"])))
            H_t = [collect(1 + 24 * (t - 1):24 + 24 * (t - 1)) for t in T]
            H_T = collect(unique(reduce(vcat, H_t)))
            for row in eachrow(rep_weight_df)
                N[Int(row["Time Period"])] = Float64(row["Weight"])
            end
        else
            zonedata = input_data["Zonedata"]
            ordered_zone = [string(zonedata[i, "Zone_id"]) for i in 1:nrow(zonedata)]
            ordered_gen = ["G$(i)" for i in 1:(nrow(input_data["Gendata"]) + nrow(input_data["Gendata_candidate"]))]
            rep_period_data = build_endogenous_rep_periods(
                loaddata,
                input_data["AFdata"],
                ordered_zone,
                ordered_gen,
                config_set;
                drtsdata=(haskey(input_data, "DRtsdata") ? input_data["DRtsdata"] : nothing),
                generator_data=input_data["Gendata"],
                candidate_generator_data=input_data["Gendata_candidate"],
            )
            T = rep_period_data["T"]
            H_t = [collect(1 + 24 * (t - 1):24 + 24 * (t - 1)) for t in T]
            H_T = collect(unique(reduce(vcat, H_t)))
            N = rep_period_data["N"]
        end
    else
        N = Dict(t => 1.0 for t in T)
    end
    return T, H_t, H_T, N, has_custom_time_periods
end

function compute_gtep_eue(config_set::Dict, input_data::Dict, model::Model)
    pr_status = primal_status(model)
    if !(pr_status in (MOI.FEASIBLE_POINT, MOI.NEARLY_FEASIBLE_POINT))
        throw(ArgumentError("Cannot compute EUE because solved model does not have a feasible primal solution (primal_status=$(pr_status))."))
    end
    T, H_t, _, N, _ = rep_period_weights_for_erec(config_set, input_data)
    num_zone = nrow(input_data["Zonedata"])
    p_ls = value.(model[:p_LS])
    return sum(N[t] * sum(p_ls[i, h] for i in 1:num_zone for h in H_t[t]) for t in T)
end

function solve_gtep_for_erec(case_path::AbstractString, config_set::Dict, input_data::Dict)
    optimizer = initiate_solver(case_path, String(config_set["solver"]))
    model = create_GTEP_model(config_set, input_data, optimizer)
    solved_model = solve_model(config_set, input_data, model)
    term_status = termination_status(solved_model)
    pr_status = primal_status(solved_model)
    if !(pr_status in (MOI.FEASIBLE_POINT, MOI.NEARLY_FEASIBLE_POINT))
        throw(ArgumentError("EREC solve did not find a feasible primal solution. termination_status=$(term_status), primal_status=$(pr_status)"))
    end
    return solved_model
end

function add_erec_metadata!(df::DataFrame, source::AbstractString)
    df[!, "EREC_Source"] = fill(String(source), nrow(df))
    df[!, "EREC_OrigIndex"] = collect(1:nrow(df))
    df[!, "EREC_Label"] = ["$(source)_$(i)" for i in 1:nrow(df)]
    return df
end

function empty_df_like(df::DataFrame)
    return copy(df[1:0, :])
end

function append_row_with_schema!(target_df::DataFrame, values::Dict{String,Any})
    row_df = DataFrame()
    for col in names(target_df)
        row_df[!, col] = [get(values, col, missing)]
    end
    append!(target_df, row_df; cols=:setequal, promote=true)
    return target_df
end

function rebuild_fixed_fleet_afdata(base_input::Dict, fixed_gendata::DataFrame)
    base_af = base_input["AFdata"]
    time_cols = [col for col in ["Time Period", "Month", "Day", "Hours"] if col in names(base_af)]
    fixed_af = copy(base_af[:, time_cols])
    num_gen_exist = nrow(base_input["Gendata"])

    for (new_idx, row) in enumerate(eachrow(fixed_gendata))
        new_col = "G$(new_idx)"
        source = string(row["EREC_Source"])
        orig_idx = Int(row["EREC_OrigIndex"])
        source_col = if source == "existing"
            "G$(orig_idx)"
        elseif source == "candidate"
            "G$(num_gen_exist + orig_idx)"
        else
            nothing
        end

        if source_col !== nothing && source_col in names(base_af)
            fixed_af[!, new_col] = copy(base_af[!, source_col])
        else
            fixed_af[!, new_col] = fill(to_float_erec(row["AF"], 1.0), nrow(base_af))
        end
    end

    return fixed_af
end

function append_generator_af_column!(input_data::Dict, base_input::Dict, source::AbstractString, orig_idx::Int, fallback_af::Float64)
    afdata = input_data["AFdata"]
    base_af = base_input["AFdata"]
    num_gen_exist = nrow(base_input["Gendata"])
    new_col = "G$(nrow(input_data["Gendata"]))"
    source_col = if source == "existing"
        "G$(orig_idx)"
    elseif source == "candidate"
        "G$(num_gen_exist + orig_idx)"
    else
        nothing
    end

    if source_col !== nothing && source_col in names(base_af)
        afdata[!, new_col] = copy(base_af[!, source_col])
    else
        afdata[!, new_col] = fill(fallback_af, nrow(afdata))
    end
    return input_data
end

function build_fixed_fleet_input(base_input::Dict, solved_model::Model)
    fixed_input = deepcopy(base_input)

    gendata_exist = copy(base_input["Gendata"])
    gendata_cand = base_input["Gendata_candidate"]
    add_erec_metadata!(gendata_exist, "existing")
    num_gen_exist = nrow(gendata_exist)
    g_mr_exist = findall(x -> to_float_erec(x) > 0.0, gendata_exist[:, "Flag_mustrun"])
    g_ret_raw = findall(x -> to_float_erec(x) > 0.0, gendata_exist[:, "Flag_RET"])
    g_ret = Set(setdiff(g_ret_raw, g_mr_exist))
    for i in 1:nrow(gendata_exist)
        scale = 1.0
        if i in g_ret
            scale = max(1.0 - Float64(value(solved_model[:x_RET][i])), 0.0)
        end
        gendata_exist[i, "Pmax (MW)"] = to_float_erec(gendata_exist[i, "Pmax (MW)"]) * scale
        gendata_exist[i, "Pmin (MW)"] = to_float_erec(gendata_exist[i, "Pmin (MW)"]) * scale
        if "Flag_RET" in names(gendata_exist)
            gendata_exist[i, "Flag_RET"] = 0
        end
    end
    gendata_exist = filter(row -> to_float_erec(row["Pmax (MW)"]) > 1.0e-9, gendata_exist)
    for j in 1:nrow(gendata_cand)
        build_val = Float64(value(solved_model[:x][num_gen_exist + j]))
        if build_val <= 1.0e-9
            continue
        end
        values = Dict{String,Any}()
        for col in names(gendata_exist)
            if col == "EREC_Source"
                values[col] = "candidate"
            elseif col == "EREC_OrigIndex"
                values[col] = j
            elseif col == "EREC_Label"
                values[col] = "candidate_$(j)"
            elseif col == "Flag_RET"
                values[col] = 0
            elseif col in names(gendata_cand)
                values[col] = gendata_cand[j, col]
            end
        end
        values["Pmax (MW)"] = to_float_erec(gendata_cand[j, "Pmax (MW)"]) * build_val
        values["Pmin (MW)"] = to_float_erec(gendata_cand[j, "Pmin (MW)"]) * build_val
        append_row_with_schema!(gendata_exist, values)
    end
    fixed_input["Gendata"] = gendata_exist
    fixed_input["Gendata_candidate"] = empty_df_like(base_input["Gendata_candidate"])
    fixed_input["AFdata"] = rebuild_fixed_fleet_afdata(base_input, gendata_exist)

    storagedata_exist = copy(base_input["Storagedata"])
    storagedata_cand = base_input["Estoragedata_candidate"]
    add_erec_metadata!(storagedata_exist, "existing")
    num_sto_exist = nrow(storagedata_exist)
    for i in 1:nrow(storagedata_exist)
        storagedata_exist[i, "Capacity (MWh)"] = to_float_erec(storagedata_exist[i, "Capacity (MWh)"])
        storagedata_exist[i, "Max Power (MW)"] = to_float_erec(storagedata_exist[i, "Max Power (MW)"])
    end
    storagedata_exist = filter(row -> to_float_erec(row["Max Power (MW)"]) > 1.0e-9, storagedata_exist)
    for j in 1:nrow(storagedata_cand)
        build_val = Float64(value(solved_model[:z][num_sto_exist + j]))
        if build_val <= 1.0e-9
            continue
        end
        values = Dict{String,Any}()
        for col in names(storagedata_exist)
            if col == "EREC_Source"
                values[col] = "candidate"
            elseif col == "EREC_OrigIndex"
                values[col] = j
            elseif col == "EREC_Label"
                values[col] = "candidate_$(j)"
            elseif col in names(storagedata_cand)
                values[col] = storagedata_cand[j, col]
            end
        end
        values["Capacity (MWh)"] = to_float_erec(storagedata_cand[j, "Capacity (MWh)"]) * build_val
        values["Max Power (MW)"] = to_float_erec(storagedata_cand[j, "Max Power (MW)"]) * build_val
        append_row_with_schema!(storagedata_exist, values)
    end
    fixed_input["Storagedata"] = storagedata_exist
    fixed_input["Estoragedata_candidate"] = empty_df_like(base_input["Estoragedata_candidate"])

    linedata_exist = copy(base_input["Linedata"])
    linedata_cand = base_input["Linedata_candidate"]
    num_line_exist = nrow(linedata_exist)
    for j in 1:nrow(linedata_cand)
        build_val = Float64(value(solved_model[:y][num_line_exist + j]))
        if build_val <= 1.0e-9
            continue
        end
        values = Dict{String,Any}()
        for col in names(linedata_exist)
            if col in names(linedata_cand)
                values[col] = linedata_cand[j, col]
            end
        end
        values["Capacity (MW)"] = to_float_erec(linedata_cand[j, "Capacity (MW)"]) * build_val
        append_row_with_schema!(linedata_exist, values)
    end
    fixed_input["Linedata"] = filter(row -> to_float_erec(row["Capacity (MW)"]) > 1.0e-9, linedata_exist)
    fixed_input["Linedata_candidate"] = empty_df_like(base_input["Linedata_candidate"])

    return fixed_input
end

function perturb_generator_capacity!(input_data::Dict, row_idx::Int, delta_mw::Float64)
    gendata = input_data["Gendata"]
    pmax = to_float_erec(gendata[row_idx, "Pmax (MW)"])
    pmin = to_float_erec(gendata[row_idx, "Pmin (MW)"])
    ratio = pmax > 1.0e-9 ? pmin / pmax : 0.0
    new_pmax = pmax + delta_mw
    if new_pmax <= 0
        throw(ArgumentError("Generator perturbation would create non-positive Pmax at row $(row_idx)."))
    end
    gendata[row_idx, "Pmax (MW)"] = new_pmax
    gendata[row_idx, "Pmin (MW)"] = max(pmin + ratio * delta_mw, 0.0)
    return input_data
end

function append_virtual_generator_capacity!(input_data::Dict, base_input::Dict, source::AbstractString, source_idx::Int, delta_mw::Float64)
    source_df = source == "existing" ? base_input["Gendata"] : base_input["Gendata_candidate"]
    template = source_df[source_idx, :]
    gendata = input_data["Gendata"]
    template_pmax = to_float_erec(template["Pmax (MW)"])
    template_pmin = to_float_erec(template["Pmin (MW)"])
    pmin_ratio = template_pmax > 1.0e-9 ? template_pmin / template_pmax : 0.0

    values = Dict{String,Any}()
    for col in names(gendata)
        if col == "EREC_Source"
            values[col] = source
        elseif col == "EREC_OrigIndex"
            values[col] = source_idx
        elseif col == "EREC_Label"
            values[col] = "$(source)_$(source_idx)"
        elseif col == "Pmax (MW)"
            values[col] = delta_mw
        elseif col == "Pmin (MW)"
            values[col] = max(pmin_ratio * delta_mw, 0.0)
        elseif col == "Flag_RET"
            values[col] = 0
        elseif col in names(source_df)
            values[col] = template[col]
        end
    end
    append_row_with_schema!(gendata, values)
    append_generator_af_column!(input_data, base_input, source, source_idx, to_float_erec(template["AF"], 1.0))
    return input_data
end

function perturb_storage_capacity!(input_data::Dict, row_idx::Int, delta_mw::Float64, storage_duration_mode::AbstractString)
    storagedata = input_data["Storagedata"]
    pmax = to_float_erec(storagedata[row_idx, "Max Power (MW)"])
    ecap = to_float_erec(storagedata[row_idx, "Capacity (MWh)"])
    new_pmax = pmax + delta_mw
    if new_pmax <= 0
        throw(ArgumentError("Storage perturbation would create non-positive Max Power at row $(row_idx)."))
    end
    storagedata[row_idx, "Max Power (MW)"] = new_pmax
    if storage_duration_mode == "preserve"
        duration = pmax > 1.0e-9 ? ecap / pmax : 0.0
        storagedata[row_idx, "Capacity (MWh)"] = ecap + duration * delta_mw
    elseif storage_duration_mode == "power_only"
        storagedata[row_idx, "Capacity (MWh)"] = ecap
    else
        throw(ArgumentError("Unsupported storage_duration_mode=$(storage_duration_mode). Expected preserve or power_only."))
    end
    return input_data
end

function append_virtual_storage_capacity!(input_data::Dict, base_input::Dict, source::AbstractString, source_idx::Int, delta_mw::Float64, storage_duration_mode::AbstractString)
    source_df = source == "existing" ? base_input["Storagedata"] : base_input["Estoragedata_candidate"]
    template = source_df[source_idx, :]
    storagedata = input_data["Storagedata"]
    template_pmax = to_float_erec(template["Max Power (MW)"])
    template_ecap = to_float_erec(template["Capacity (MWh)"])
    duration = template_pmax > 1.0e-9 ? template_ecap / template_pmax : 0.0

    values = Dict{String,Any}()
    for col in names(storagedata)
        if col == "EREC_Source"
            values[col] = source
        elseif col == "EREC_OrigIndex"
            values[col] = source_idx
        elseif col == "EREC_Label"
            values[col] = "$(source)_$(source_idx)"
        elseif col == "Max Power (MW)"
            values[col] = delta_mw
        elseif col == "Capacity (MWh)"
            values[col] = storage_duration_mode == "preserve" ? duration * delta_mw : template_ecap
        elseif col in names(source_df)
            values[col] = template[col]
        end
    end
    append_row_with_schema!(storagedata, values)
    return input_data
end

function append_perfect_reference_generator!(input_data::Dict, zone_label, delta_mw::Float64)
    gendata = input_data["Gendata"]
    values = Dict{String,Any}()
    for col in names(gendata)
        if col == "Zone"
            values[col] = zone_label
        elseif col == "Type"
            values[col] = "ERECPerfect"
        elseif col == "Pmax (MW)"
            values[col] = delta_mw
        elseif col == "Pmin (MW)"
            values[col] = 0.0
        elseif col == "Cost (\$/MWh)"
            values[col] = 0.0
        elseif col == "EF"
            values[col] = 0.0
        elseif col == "FOR"
            values[col] = 0.0
        elseif col == "CC"
            values[col] = 0.0
        elseif col == "AF"
            values[col] = 1.0
        elseif col == "Flag_RET"
            values[col] = 0
        elseif col == "Flag_thermal"
            values[col] = 1
        elseif col == "Flag_VRE"
            values[col] = 0
        elseif col == "Flag_mustrun"
            values[col] = 0
        elseif col == "Flag_RPS"
            values[col] = 0
        elseif col == "EREC_Source"
            values[col] = "reference"
        elseif col == "EREC_OrigIndex"
            values[col] = 0
        elseif col == "EREC_Label"
            values[col] = "reference_same_zone"
        end
    end
    append_row_with_schema!(gendata, values)
    return input_data
end

function solve_perturbed_eue(case_path::AbstractString, config_set::Dict, input_data::Dict)
    solved_model = solve_gtep_for_erec(case_path, config_set, input_data)
    return compute_gtep_eue(config_set, input_data, solved_model)
end

function build_eval_targets(base_input::Dict, fixed_input::Dict, resource_types::Vector{String}, resource_scope::AbstractString; custom_resources::Dict=normalize_custom_erec_resources(nothing))
    targets = DataFrame(
        ResourceType = String[],
        EvalMode = String[],
        FixedRowIndex = Int[],
        Label = String[],
        Source = String[],
        SourceIndex = Int[],
        Technology = String[],
        Zone = String[],
        BaselinePowerMW = Float64[],
        BaselineEnergyMWh = Float64[],
    )

    function append_target!(resource_type::AbstractString, eval_mode::AbstractString, fixed_row_idx::Int, label::AbstractString, source::AbstractString, source_idx::Int, technology::AbstractString, zone::AbstractString, baseline_power_mw::Float64, baseline_energy_mwh::Float64)
        push!(targets, (String(resource_type), String(eval_mode), fixed_row_idx, String(label), String(source), source_idx, String(technology), String(zone), baseline_power_mw, baseline_energy_mwh))
    end

    if "generator" in resource_types
        fixed_gendata = fixed_input["Gendata"]
        fixed_lookup = Dict{Tuple{String,Int},Int}()
        for (i, row) in enumerate(eachrow(fixed_gendata))
            fixed_lookup[(string(row["EREC_Source"]), Int(row["EREC_OrigIndex"]))] = i
        end
        for (source, source_df) in (("existing", base_input["Gendata"]), ("candidate", base_input["Gendata_candidate"]))
            for i in 1:nrow(source_df)
                if resource_scope == "custom" && !custom_erec_selected(custom_resources, "generator", source, i)
                    continue
                end
                key = (source, i)
                if haskey(fixed_lookup, key)
                    row_idx = fixed_lookup[key]
                    row = fixed_gendata[row_idx, :]
                    append_target!("generator", "fixed", row_idx, string(row["EREC_Label"]), source, i, string(row["Type"]), string(row["Zone"]), to_float_erec(row["Pmax (MW)"]), 0.0)
                elseif resource_scope in ("all", "custom") && to_float_erec(source_df[i, "Pmax (MW)"]) > 1.0e-9
                    append_target!("generator", "virtual", 0, "$(source)_$(i)", source, i, string(source_df[i, "Type"]), string(source_df[i, "Zone"]), 0.0, 0.0)
                end
            end
        end
    end

    if "storage" in resource_types
        fixed_storagedata = fixed_input["Storagedata"]
        fixed_lookup = Dict{Tuple{String,Int},Int}()
        for (i, row) in enumerate(eachrow(fixed_storagedata))
            fixed_lookup[(string(row["EREC_Source"]), Int(row["EREC_OrigIndex"]))] = i
        end
        for (source, source_df) in (("existing", base_input["Storagedata"]), ("candidate", base_input["Estoragedata_candidate"]))
            for i in 1:nrow(source_df)
                if resource_scope == "custom" && !custom_erec_selected(custom_resources, "storage", source, i)
                    continue
                end
                key = (source, i)
                if haskey(fixed_lookup, key)
                    row_idx = fixed_lookup[key]
                    row = fixed_storagedata[row_idx, :]
                    append_target!("storage", "fixed", row_idx, string(row["EREC_Label"]), source, i, string(row["Type"]), string(row["Zone"]), to_float_erec(row["Max Power (MW)"]), to_float_erec(row["Capacity (MWh)"]))
                elseif resource_scope in ("all", "custom") && to_float_erec(source_df[i, "Max Power (MW)"]) > 1.0e-9
                    append_target!("storage", "virtual", 0, "$(source)_$(i)", source, i, string(source_df[i, "Type"]), string(source_df[i, "Zone"]), 0.0, 0.0)
                end
            end
        end
    end

    if !(resource_scope in ("built_only", "all", "custom"))
        throw(ArgumentError("Unsupported resource_scope=$(resource_scope). Expected built_only, all, or custom."))
    end
    return targets
end

function build_erec_results(base_input::Dict, fixed_input::Dict, case_path::AbstractString, config_set::Dict, erec_settings::Dict, baseline_eue::Float64)
    delta_mw = to_float_erec(get(erec_settings, "delta_mw", 1.0))
    storage_duration_mode = lowercase(strip(string(get(erec_settings, "storage_duration_mode", "preserve"))))
    min_denom = to_float_erec(get(erec_settings, "min_denominator_eue_drop", 1.0e-6))
    resource_types = normalize_erec_resource_types(get(erec_settings, "resource_types", ["generator", "storage"]))
    resource_scope = lowercase(strip(string(get(erec_settings, "resource_scope", "built_only"))))
    custom_resources = normalize_custom_erec_resources(get(erec_settings, "custom_resources", nothing))
    perfect_eue_by_zone = Dict{String,Float64}()
    eval_targets = build_eval_targets(base_input, fixed_input, resource_types, resource_scope; custom_resources=custom_resources)

    results = DataFrame(
        ResourceType = String[],
        ResourceIndex = Int[],
        Label = String[],
        Source = String[],
        SourceIndex = Int[],
        Technology = String[],
        Zone = String[],
        BaselinePowerMW = Float64[],
        BaselineEnergyMWh = Float64[],
        DeltaMW = Float64[],
        EUEBase = Float64[],
        EUEResource = Float64[],
        EUEPerfect = Float64[],
        EREC = Float64[],
    )

    gen_targets = eval_targets[eval_targets.ResourceType .== "generator", :]
    for target in eachrow(gen_targets)
        zone = target.Zone
        if !haskey(perfect_eue_by_zone, zone)
            ref_input = deepcopy(fixed_input)
            append_perfect_reference_generator!(ref_input, zone, delta_mw)
            perfect_eue_by_zone[zone] = solve_perturbed_eue(case_path, config_set, ref_input)
        end
        perturbed_input = deepcopy(fixed_input)
        if target.EvalMode == "fixed"
            perturb_generator_capacity!(perturbed_input, Int(target.FixedRowIndex), delta_mw)
        else
            append_virtual_generator_capacity!(perturbed_input, base_input, target.Source, Int(target.SourceIndex), delta_mw)
        end
        eue_resource = solve_perturbed_eue(case_path, config_set, perturbed_input)
        denom = baseline_eue - perfect_eue_by_zone[zone]
        erec = abs(denom) <= min_denom ? NaN : (baseline_eue - eue_resource) / denom
        push!(results, (
            "generator",
            Int(target.FixedRowIndex),
            target.Label,
            target.Source,
            Int(target.SourceIndex),
            target.Technology,
            zone,
            Float64(target.BaselinePowerMW),
            0.0,
            delta_mw,
            baseline_eue,
            eue_resource,
            perfect_eue_by_zone[zone],
            erec,
        ))
    end

    sto_targets = eval_targets[eval_targets.ResourceType .== "storage", :]
    for target in eachrow(sto_targets)
        zone = target.Zone
        if !haskey(perfect_eue_by_zone, zone)
            ref_input = deepcopy(fixed_input)
            append_perfect_reference_generator!(ref_input, zone, delta_mw)
            perfect_eue_by_zone[zone] = solve_perturbed_eue(case_path, config_set, ref_input)
        end
        perturbed_input = deepcopy(fixed_input)
        if target.EvalMode == "fixed"
            perturb_storage_capacity!(perturbed_input, Int(target.FixedRowIndex), delta_mw, storage_duration_mode)
        else
            append_virtual_storage_capacity!(perturbed_input, base_input, target.Source, Int(target.SourceIndex), delta_mw, storage_duration_mode)
        end
        eue_resource = solve_perturbed_eue(case_path, config_set, perturbed_input)
        denom = baseline_eue - perfect_eue_by_zone[zone]
        erec = abs(denom) <= min_denom ? NaN : (baseline_eue - eue_resource) / denom
        push!(results, (
            "storage",
            Int(target.FixedRowIndex),
            target.Label,
            target.Source,
            Int(target.SourceIndex),
            target.Technology,
            zone,
            Float64(target.BaselinePowerMW),
            Float64(target.BaselineEnergyMWh),
            delta_mw,
            baseline_eue,
            eue_resource,
            perfect_eue_by_zone[zone],
            erec,
        ))
    end

    return results
end

function build_cc_export_tables(base_input::Dict, fixed_input::Dict, erec_results::DataFrame; resource_scope::AbstractString="built_only")
    gendata = if resource_scope == "all"
        g_existing = copy(base_input["Gendata"])
        g_candidate = copy(base_input["Gendata_candidate"])
        add_erec_metadata!(g_existing, "existing")
        add_erec_metadata!(g_candidate, "candidate")
        vcat(g_existing, g_candidate; cols=:union)
    else
        copy(fixed_input["Gendata"])
    end
    storagedata = if resource_scope == "all"
        s_existing = copy(base_input["Storagedata"])
        s_candidate = copy(base_input["Estoragedata_candidate"])
        add_erec_metadata!(s_existing, "existing")
        add_erec_metadata!(s_candidate, "candidate")
        vcat(s_existing, s_candidate; cols=:union)
    else
        copy(fixed_input["Storagedata"])
    end
    gendata[!, "CC"] = Float64.(to_float_erec.(gendata[:, "CC"]))
    storagedata[!, "CC"] = Float64.(to_float_erec.(storagedata[:, "CC"]))
    gen_rows = erec_results[erec_results.ResourceType .== "generator", :]
    sto_rows = erec_results[erec_results.ResourceType .== "storage", :]

    if resource_scope == "all" && all(("Source" in names(gen_rows), "SourceIndex" in names(gen_rows)))
        gen_lookup = Dict{Tuple{String,Int},Int}()
        for (i, row) in enumerate(eachrow(gendata))
            gen_lookup[(string(row["EREC_Source"]), Int(row["EREC_OrigIndex"]))] = i
        end
        for row in eachrow(gen_rows)
            key = (string(row.Source), Int(row.SourceIndex))
            if haskey(gen_lookup, key) && !isnan(row.EREC)
                gendata[gen_lookup[key], "CC"] = row.EREC
            end
        end
    else
        for row in eachrow(gen_rows)
            if row.ResourceIndex <= nrow(gendata) && !isnan(row.EREC)
                gendata[row.ResourceIndex, "CC"] = row.EREC
            end
        end
    end

    if resource_scope == "all" && all(("Source" in names(sto_rows), "SourceIndex" in names(sto_rows)))
        sto_lookup = Dict{Tuple{String,Int},Int}()
        for (i, row) in enumerate(eachrow(storagedata))
            sto_lookup[(string(row["EREC_Source"]), Int(row["EREC_OrigIndex"]))] = i
        end
        for row in eachrow(sto_rows)
            key = (string(row.Source), Int(row.SourceIndex))
            if haskey(sto_lookup, key) && !isnan(row.EREC)
                storagedata[sto_lookup[key], "CC"] = row.EREC
            end
        end
    else
        for row in eachrow(sto_rows)
            if row.ResourceIndex <= nrow(storagedata) && !isnan(row.EREC)
                storagedata[row.ResourceIndex, "CC"] = row.EREC
            end
        end
    end
    return gendata, storagedata
end

function empty_erec_results_table()
    return DataFrame(
        ResourceType = String[],
        ResourceIndex = Int[],
        Label = String[],
        Source = String[],
        SourceIndex = Int[],
        Technology = String[],
        Zone = String[],
        BaselinePowerMW = Float64[],
        BaselineEnergyMWh = Float64[],
        DeltaMW = Float64[],
        EUEBase = Float64[],
        EUEResource = Float64[],
        EUEPerfect = Float64[],
        EREC = Float64[],
    )
end

function run_erec_from_prepared_inputs(
    case_path::AbstractString,
    solver_context_path::AbstractString,
    output_root::AbstractString,
    base_config::Dict,
    erec_settings::Dict,
    base_input::Dict,
    fixed_input::Dict;
    baseline_model::Union{Nothing,Model}=nothing,
)
    baseline_config = build_erec_config(base_config, erec_settings)
    fixed_config = deepcopy(baseline_config)
    fixed_config["planning_reserve_mode"] = 0
    fixed_config["inv_dcs_bin"] = 0
    fixed_model = solve_gtep_for_erec(solver_context_path, fixed_config, fixed_input)
    baseline_eue = compute_gtep_eue(fixed_config, fixed_input, fixed_model)

    skip_if_zero = parse_erec_binary(get(erec_settings, "skip_if_eue_zero", 1), "skip_if_eue_zero")
    if baseline_eue <= to_float_erec(get(erec_settings, "min_denominator_eue_drop", 1.0e-6), 1.0e-6) && skip_if_zero == 1
        erec_results = empty_erec_results_table()
    else
        erec_results = build_erec_results(base_input, fixed_input, solver_context_path, fixed_config, erec_settings, baseline_eue)
    end

    resource_scope = lowercase(strip(string(get(erec_settings, "resource_scope", "built_only"))))
    output_dir = joinpath(output_root, string(get(erec_settings, "output_dir_name", "output_erec")))
    output_paths = Dict{String,String}()
    if parse_erec_binary(get(erec_settings, "write_outputs", 1), "write_outputs") == 1
        mkpath(output_dir)
        results_path = joinpath(output_dir, string(get(erec_settings, "erec_results_file", "erec_results.csv")))
        summary_path = joinpath(output_dir, string(get(erec_settings, "erec_summary_file", "erec_summary.csv")))
        CSV.write(results_path, erec_results)
        summary_df = DataFrame(
            Metric = ["baseline_eue_mwh", "num_generator_results", "num_storage_results"],
            Value = [
                baseline_eue,
                sum(erec_results.ResourceType .== "generator"),
                sum(erec_results.ResourceType .== "storage"),
            ],
        )
        CSV.write(summary_path, summary_df)
        output_paths["erec_results"] = results_path
        output_paths["erec_summary"] = summary_path

        if parse_erec_binary(get(erec_settings, "write_cc_to_tables", 0), "write_cc_to_tables") == 1
            cc_gendata, cc_storagedata = build_cc_export_tables(base_input, fixed_input, erec_results; resource_scope=resource_scope)
            gendata_path = joinpath(output_dir, "gendata_with_erec_cc.csv")
            storagedata_path = joinpath(output_dir, "storagedata_with_erec_cc.csv")
            CSV.write(gendata_path, cc_gendata)
            CSV.write(storagedata_path, cc_storagedata)
            output_paths["gendata_with_erec_cc"] = gendata_path
            output_paths["storagedata_with_erec_cc"] = storagedata_path
        end
    end

    return Dict(
        "case_path" => case_path,
        "erec_settings" => erec_settings,
        "baseline_config" => baseline_config,
        "baseline_eue" => baseline_eue,
        "baseline_model" => baseline_model,
        "fixed_fleet_input" => fixed_input,
        "fixed_fleet_model" => fixed_model,
        "erec_results" => erec_results,
        "output_paths" => output_paths,
    )
end

"""
    calculate_erec(case::AbstractString; kwargs...)

Run the V1 EREC workflow for a GTEP case:
1. solve the baseline expansion case with planning reserve disabled,
2. reconstruct the solved fleet as a fixed redispatch case,
3. compute weighted EUE-based EREC values for generators and/or storage,
4. optionally write result CSVs and CC-updated tables.
"""
function calculate_erec(case::AbstractString; kwargs...)
    case_path = resolve_case_path_for_erec(case)
    base_settings_path = joinpath(case_path, "Settings", "HOPE_model_settings.yml")
    if !isfile(base_settings_path)
        throw(ArgumentError("Settings file not found: $base_settings_path"))
    end

    base_config = open(base_settings_path) do io
        YAML.load(io)
    end
    endogenous_rep_day, _, _ = resolve_rep_day_mode(base_config; context="calculate_erec")
    if endogenous_rep_day == 1
        base_config["rep_day_settings"] = load_rep_day_settings(case_path, base_config)
    end
    erec_settings = load_erec_settings(case_path)
    for (k, v) in kwargs
        erec_settings[string(k)] = v
    end
    if parse_erec_binary(get(erec_settings, "enabled", 1), "enabled") == 0
        return Dict(
            "case_path" => case_path,
            "erec_settings" => erec_settings,
            "message" => "EREC workflow disabled by settings.",
        )
    end

    resource_scope = lowercase(strip(string(get(erec_settings, "resource_scope", "built_only"))))
    if !(resource_scope in ("built_only", "all", "custom"))
        throw(ArgumentError("EREC currently supports resource_scope = built_only, all, or custom."))
    end
    if resource_scope == "custom"
        normalize_custom_erec_resources(get(erec_settings, "custom_resources", nothing))
    end
    perturbation_mode = lowercase(strip(string(get(erec_settings, "perturbation_mode", "forward"))))
    if perturbation_mode != "forward"
        throw(ArgumentError("V1 EREC implementation currently supports only perturbation_mode = forward."))
    end
    reference_mode = lowercase(strip(string(get(erec_settings, "reference_resource_mode", "same_zone"))))
    if reference_mode != "same_zone"
        throw(ArgumentError("V1 EREC implementation currently supports only reference_resource_mode = same_zone."))
    end

    baseline_config = build_erec_config(base_config, erec_settings)
    base_input = load_data(baseline_config, case_path)
    apply_erec_overrides!(base_input, erec_settings; voll_warning_context=:case_input)

    expansion_input = deepcopy(base_input)
    baseline_solved_model = solve_gtep_for_erec(case_path, baseline_config, expansion_input)
    fixed_input = build_fixed_fleet_input(base_input, baseline_solved_model)

    return run_erec_from_prepared_inputs(
        case_path,
        case_path,
        case_path,
        base_config,
        erec_settings,
        base_input,
        fixed_input;
        baseline_model=baseline_solved_model,
    )
end

function calculate_erec(results::Dict; kwargs...)
    haskey(results, "config") || throw(ArgumentError("calculate_erec(results::Dict) requires a results dictionary that includes key \"config\" from HOPE.run_hope()."))
    haskey(results, "input") || throw(ArgumentError("calculate_erec(results::Dict) requires a results dictionary that includes key \"input\" from HOPE.run_hope()."))
    haskey(results, "solved_model") || throw(ArgumentError("calculate_erec(results::Dict) requires a results dictionary that includes key \"solved_model\" from HOPE.run_hope()."))
    haskey(results, "case_path") || throw(ArgumentError("calculate_erec(results::Dict) requires a results dictionary that includes key \"case_path\" from HOPE.run_hope()."))

    case_path = results["case_path"]
    base_config = deepcopy(results["config"])
    erec_settings = load_erec_settings(case_path)
    for (k, v) in kwargs
        erec_settings[string(k)] = v
    end
    if parse_erec_binary(get(erec_settings, "enabled", 1), "enabled") == 0
        return Dict(
            "case_path" => case_path,
            "erec_settings" => erec_settings,
            "message" => "EREC workflow disabled by settings.",
        )
    end

    resource_scope = lowercase(strip(string(get(erec_settings, "resource_scope", "built_only"))))
    if !(resource_scope in ("built_only", "all", "custom"))
        throw(ArgumentError("EREC currently supports resource_scope = built_only, all, or custom."))
    end
    if resource_scope == "custom"
        normalize_custom_erec_resources(get(erec_settings, "custom_resources", nothing))
    end
    perturbation_mode = lowercase(strip(string(get(erec_settings, "perturbation_mode", "forward"))))
    if perturbation_mode != "forward"
        throw(ArgumentError("V1 EREC implementation currently supports only perturbation_mode = forward."))
    end
    reference_mode = lowercase(strip(string(get(erec_settings, "reference_resource_mode", "same_zone"))))
    if reference_mode != "same_zone"
        throw(ArgumentError("V1 EREC implementation currently supports only reference_resource_mode = same_zone."))
    end

    base_input = deepcopy(results["input"])
    apply_erec_overrides!(base_input, erec_settings; voll_warning_context=:solved_baseline)
    fixed_input = build_fixed_fleet_input(base_input, results["solved_model"])
    output_root = get(results, "output_path", case_path)

    return run_erec_from_prepared_inputs(
        case_path,
        case_path,
        output_root,
        base_config,
        erec_settings,
        base_input,
        fixed_input;
        baseline_model=results["solved_model"],
    )
end

function calculate_erec_from_output(output_path::AbstractString; kwargs...)
    snapshot = load_postprocess_snapshot(output_path)
    snapshot_dir = snapshot["snapshot_dir"]
    base_config = snapshot["config"]
    case_path = get(snapshot["metadata"], "source_case_path", dirname(snapshot["output_path"]))
    erec_settings = load_erec_settings(snapshot_dir)
    for (k, v) in kwargs
        erec_settings[string(k)] = v
    end
    if parse_erec_binary(get(erec_settings, "enabled", 1), "enabled") == 0
        return Dict(
            "case_path" => case_path,
            "erec_settings" => erec_settings,
            "message" => "EREC workflow disabled by settings.",
        )
    end

    resource_scope = lowercase(strip(string(get(erec_settings, "resource_scope", "built_only"))))
    if !(resource_scope in ("built_only", "all", "custom"))
        throw(ArgumentError("EREC currently supports resource_scope = built_only, all, or custom."))
    end
    if resource_scope == "custom"
        normalize_custom_erec_resources(get(erec_settings, "custom_resources", nothing))
    end
    perturbation_mode = lowercase(strip(string(get(erec_settings, "perturbation_mode", "forward"))))
    if perturbation_mode != "forward"
        throw(ArgumentError("V1 EREC implementation currently supports only perturbation_mode = forward."))
    end
    reference_mode = lowercase(strip(string(get(erec_settings, "reference_resource_mode", "same_zone"))))
    if reference_mode != "same_zone"
        throw(ArgumentError("V1 EREC implementation currently supports only reference_resource_mode = same_zone."))
    end

    base_input = snapshot["base_input"]
    apply_erec_overrides!(base_input, erec_settings; voll_warning_context=:solved_baseline)

    return run_erec_from_prepared_inputs(
        case_path,
        snapshot_dir,
        snapshot["output_path"],
        base_config,
        erec_settings,
        base_input,
        snapshot["fixed_input"];
        baseline_model=nothing,
    )
end
