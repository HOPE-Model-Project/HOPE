fill_missing_with_group_mean(df::DataFrame, group_cols::Vector{Symbol}, cols_to_fill::Vector{Symbol}) = begin
    work = copy(df)
    for col in cols_to_fill
        col in names(work) || continue
        group_means = combine(groupby(work, group_cols), col => (x -> mean(skipmissing(x))) => Symbol(col, "_mean"))
        rename!(group_means, Symbol(col, "_mean") => Symbol("mean_", col))
        work = leftjoin(work, group_means, on=group_cols, makeunique=true, matchmissing=:notequal)
        work[!, col] = coalesce.(work[!, col], work[!, Symbol("mean_", col)])
        select!(work, Not(Symbol("mean_", col)))
    end
    work
end

function convert_columns_to_float64!(df::DataFrame, cols::Vector{Symbol})
    for col in cols
        col in names(df) || continue
        df[!, col] = allowmissing(df[!, col])
        df[!, col] = map(x ->
            x isa Missing ? missing :
            x isa Float64 ? x :
            x isa Int ? Float64(x) :
            x === "NaN" ? NaN :
            x isa AbstractString ? parse(Float64, x) :
            throw(ArgumentError("Cannot convert value $x in column $col to Float64")), df[!, col])
    end
    return df
end

function append_rows_preserve_columns(base_df::DataFrame, rows_to_add::DataFrame)
    if nrow(rows_to_add) == 0
        return copy(base_df)
    end
    work = copy(base_df)
    add_df = copy(rows_to_add)
    for col in names(work)
        if !(col in names(add_df))
            add_df[!, col] = missing
        end
    end
    for col in names(add_df)
        if !(col in names(work))
            work[!, col] = missings(nrow(work))
        end
    end
    return vcat(work, select(add_df, names(work)); cols=:union)
end

function holistic_fill_columns(df::DataFrame, by_cols::Vector{Vector{Symbol}}, fill_cols::Vector{Symbol})
    work = copy(df)
    valid_fill_cols = [col for col in fill_cols if col in names(work)]
    for group_cols in by_cols
        valid_group_cols = [col for col in group_cols if col in names(work)]
        isempty(valid_group_cols) && continue
        work = fill_missing_with_group_mean(work, valid_group_cols, valid_fill_cols)
    end
    return work
end

function extract_new_generation_rows(capacity_df::DataFrame)
    build_df = filter(row -> to_float_output(row["New_Build"], 0.0) > 0 && to_float_output(row[Symbol("Capacity_FIN (MW)")], 0.0) > 0, capacity_df)
    if nrow(build_df) == 0
        return DataFrame(Zone=String[], Type=String[], Symbol("Pmax (MW)") => Float64[])
    end
    rows = DataFrame(
        Zone = String[string(row[:Zone]) for row in eachrow(build_df)],
        Type = String[string(row[:Technology]) for row in eachrow(build_df)],
        Symbol("Pmax (MW)") => Float64[to_float_output(row[Symbol("Capacity_FIN (MW)")], 0.0) for row in eachrow(build_df)],
    )
    return combine(groupby(rows, [:Zone, :Type]), Symbol("Pmax (MW)") => sum => Symbol("Pmax (MW)"))
end

function extract_new_storage_rows(es_capacity_df::DataFrame)
    build_df = filter(row -> to_float_output(row["New_Build"], 0.0) > 0 && to_float_output(row[Symbol("Capacity (MW)")], 0.0) > 0, es_capacity_df)
    if nrow(build_df) == 0
        return DataFrame(Zone=String[], Type=String[], Symbol("Capacity (MWh)") => Float64[], Symbol("Max Power (MW)") => Float64[])
    end
    rows = DataFrame(
        Zone = String[string(row[:Zone]) for row in eachrow(build_df)],
        Type = String[string(row[:Technology]) for row in eachrow(build_df)],
        Symbol("Capacity (MWh)") => Float64[to_float_output(row[:EnergyCapacity], 0.0) for row in eachrow(build_df)],
        Symbol("Max Power (MW)") => Float64[to_float_output(row[:Capacity], 0.0) for row in eachrow(build_df)],
    )
    return combine(groupby(rows, [:Zone, :Type]), Symbol("Capacity (MWh)") => sum => Symbol("Capacity (MWh)"), Symbol("Max Power (MW)") => sum => Symbol("Max Power (MW)"))
end

function apply_line_builds!(linedata::DataFrame, line_builds::DataFrame)
    nrow(line_builds) == 0 && return linedata
    for row in eachrow(line_builds)
        from_zone = string(row[:From_zone])
        to_zone = string(row[:To_zone])
        build_cap = to_float_output(row[:Capacity], 0.0)
        matches = findall(i ->
            string(linedata[i, "From_zone"]) == from_zone && string(linedata[i, "To_zone"]) == to_zone,
            1:nrow(linedata),
        )
        if isempty(matches)
            reverse_matches = findall(i ->
                string(linedata[i, "From_zone"]) == to_zone && string(linedata[i, "To_zone"]) == from_zone,
                1:nrow(linedata),
            )
            matches = reverse_matches
        end
        if isempty(matches)
            continue
        end
        target = first(matches)
        linedata[target, Symbol("Capacity (MW)")] = to_float_output(linedata[target, Symbol("Capacity (MW)")], 0.0) + build_cap
    end
    return linedata
end

function prepare_pcm_inputs_from_gtep(gtep_output::Dict, pcm_input::Dict, pcm_config::Dict)
    updated_input = deepcopy(pcm_input)

    new_gen_rows = extract_new_generation_rows(gtep_output["capacity"])
    if nrow(new_gen_rows) > 0
        updated_gendata = append_rows_preserve_columns(updated_input["Gendata"], new_gen_rows)
        fill_cols = pcm_config["unit_commitment"] != 0 ?
            [Symbol("Pmin (MW)"), Symbol("Cost (\$/MWh)"), :EF, :CC, :FOR, :RM_SPIN, :RU, :RD, :Flag_thermal, :Flag_VRE, :Flag_mustrun, :Flag_UC, :Min_down_time, :Min_up_time, Symbol("Start_up_cost (\$/MW)")] :
            [Symbol("Pmin (MW)"), Symbol("Cost (\$/MWh)"), :EF, :CC, :FOR, :RM_SPIN, :RU, :RD, :Flag_thermal, :Flag_VRE, :Flag_mustrun]
        updated_input["Gendata"] = holistic_fill_columns(updated_gendata, [[:Zone, :Type], [:Type]], fill_cols)
    end

    new_storage_rows = extract_new_storage_rows(gtep_output["es_capacity"])
    if nrow(new_storage_rows) > 0
        updated_storage = append_rows_preserve_columns(updated_input["Storagedata"], new_storage_rows)
        convert_columns_to_float64!(updated_storage, [Symbol("Capacity (MWh)"), Symbol("Max Power (MW)"), Symbol("Charging efficiency"), Symbol("Discharging efficiency"), Symbol("Cost (\$/MWh)"), :EF, :CC, Symbol("Charging Rate"), Symbol("Discharging Rate")])
        updated_input["Storagedata"] = holistic_fill_columns(updated_storage, [[:Zone, :Type], [:Type]], [Symbol("Capacity (MWh)"), Symbol("Max Power (MW)"), Symbol("Charging efficiency"), Symbol("Discharging efficiency"), Symbol("Cost (\$/MWh)"), :EF, :CC, Symbol("Charging Rate"), Symbol("Discharging Rate")])
    end

    line_builds = filter(row -> to_float_output(row["New_Build"], 0.0) > 0 && to_float_output(row[:Capacity], 0.0) > 0, gtep_output["line"])
    if nrow(line_builds) > 0
        updated_input["Linedata"] = apply_line_builds!(copy(updated_input["Linedata"]), line_builds)
    end

    return updated_input
end

function run_hope_holistic(GTEP_case::AbstractString, PCM_case::AbstractString)
    println("Run Holistic Assessment: 'GTEP-PCM' mode!")
    println("First stage: solving 'GTEP' mode!")
    gtep_results = run_hope(GTEP_case)

    println("Second stage: preparing 'PCM' inputs from solved GTEP builds")
    pcm_settings_path = joinpath(PCM_case, "Settings", "HOPE_model_settings.yml")
    pcm_config = open(pcm_settings_path) do io
        YAML.load(io)
    end
    if resource_aggregation_enabled(pcm_config)
        pcm_config["aggregation_settings"] = load_aggregation_settings(PCM_case, pcm_config)
    end
    endogenous_rep_day, _, _ = resolve_rep_day_mode(pcm_config; context="run_hope_holistic")
    if endogenous_rep_day == 1
        pcm_config["rep_day_settings"] = load_rep_day_settings(PCM_case, pcm_config)
    end

    pcm_input = load_data(pcm_config, PCM_case)
    updated_pcm_input = prepare_pcm_inputs_from_gtep(gtep_results["output"], pcm_input, pcm_config)

    println("Second stage: solving 'PCM' mode with GTEP-informed capacities")
    optimizer = initiate_solver(PCM_case, String(pcm_config["solver"]))
    pcm_model = create_PCM_model(pcm_config, updated_pcm_input, optimizer)
    solved_pcm_model = solve_model(pcm_config, updated_pcm_input, pcm_model)

    pcm_outpath = joinpath(PCM_case, "output_holistic")
    pcm_output = write_output(pcm_outpath, pcm_config, updated_pcm_input, solved_pcm_model)

    transfer_summary = Dict(
        "new_generation_rows" => nrow(extract_new_generation_rows(gtep_results["output"]["capacity"])),
        "new_storage_rows" => nrow(extract_new_storage_rows(gtep_results["output"]["es_capacity"])),
        "new_line_rows" => nrow(filter(row -> to_float_output(row["New_Build"], 0.0) > 0 && to_float_output(row[:Capacity], 0.0) > 0, gtep_results["output"]["line"])),
    )

    println("Holistic two-stage 'GTEP-PCM' mode solved successfully.")
    return Dict(
        "gtep" => gtep_results,
        "pcm_case_path" => PCM_case,
        "pcm_output_path" => pcm_outpath,
        "pcm_config" => pcm_config,
        "pcm_input" => updated_pcm_input,
        "pcm_solved_model" => solved_pcm_model,
        "pcm_output" => pcm_output,
        "transfer_summary" => transfer_summary,
    )
end
