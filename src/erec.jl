"""
    default_erec_settings()

Return the default settings dictionary for the EREC postprocessing workflow.
"""
function default_erec_settings()
    return Dict{String,Any}(
        "enabled" => 1,
        "voll_override" => 100000.0,
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

function apply_erec_overrides!(input_data::Dict, erec_settings::Dict)
    singlepar = input_data["Singlepar"]
    voll = to_float_erec(get(erec_settings, "voll_override", singlepar[1, "VOLL"]))
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
    T, H_t, H_T, has_custom_time_periods = build_time_period_hours(loaddata)
    N = Dict{Int,Float64}()
    if representative_day_mode == 1
        if external_rep_day == 1
            rep_weight_df = input_data["RepWeightData"]
            for row in eachrow(rep_weight_df)
                N[Int(row["Time Period"])] = Float64(row["Weight"])
            end
        else
            zonedata = input_data["Zonedata"]
            ordered_zone = [zonedata[i, "Zone_id"] for i in 1:nrow(zonedata)]
            N = Dict(k => Float64(v) for (k, v) in get_representative_ts(loaddata, config_set["time_periods"], ordered_zone)[2])
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
    apply_erec_overrides!(base_input, erec_settings)

    expansion_input = deepcopy(base_input)
    baseline_solved_model = solve_gtep_for_erec(case_path, baseline_config, expansion_input)
    fixed_input = build_fixed_fleet_input(base_input, baseline_solved_model)

    fixed_config = deepcopy(baseline_config)
    fixed_config["planning_reserve_mode"] = 0
    fixed_config["inv_dcs_bin"] = 0
    fixed_model = solve_gtep_for_erec(case_path, fixed_config, fixed_input)
    baseline_eue = compute_gtep_eue(fixed_config, fixed_input, fixed_model)

    skip_if_zero = parse_erec_binary(get(erec_settings, "skip_if_eue_zero", 1), "skip_if_eue_zero")
    if baseline_eue <= to_float_erec(get(erec_settings, "min_denominator_eue_drop", 1.0e-6), 1.0e-6) && skip_if_zero == 1
        erec_results = DataFrame(
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
    else
        erec_results = build_erec_results(base_input, fixed_input, case_path, fixed_config, erec_settings, baseline_eue)
    end

    output_dir = joinpath(case_path, string(get(erec_settings, "output_dir_name", "output_erec")))
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
        "baseline_model" => baseline_solved_model,
        "fixed_fleet_input" => fixed_input,
        "fixed_fleet_model" => fixed_model,
        "erec_results" => erec_results,
        "output_paths" => output_paths,
    )
end
