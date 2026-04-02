"""
    default_rep_day_settings(config_set::AbstractDict=Dict{String,Any}())

Return default advanced settings for endogenous representative-day construction.
These settings are loaded from `Settings/HOPE_rep_day_settings.yml` when
`endogenous_rep_day = 1`.
"""
function default_rep_day_settings(config_set::AbstractDict=Dict{String,Any}())
    default_time_periods = haskey(config_set, "time_periods") ? deepcopy(config_set["time_periods"]) : Dict{Any,Any}()
    return Dict{String,Any}(
        "time_periods" => default_time_periods,
        "clustering_method" => "kmedoids",
        "feature_mode" => "planning_features",
        "planning_feature_set" => ["zonal_load", "zonal_net_load", "zonal_wind_cf", "zonal_solar_cf", "system_net_load", "system_ramp"],
        "representative_days_per_period" => 2,
        "add_extreme_days" => 1,
        "extreme_day_metrics" => ["peak_load", "peak_net_load", "max_ramp"],
        "iterative_refinement" => 1,
        "iterative_refinement_days_per_period" => 1,
        "link_storage_rep_days" => 1,
        "include_load" => 1,
        "include_af" => 1,
        "include_dr" => 1,
        "normalize_features" => 1,
    )
end

"""
    load_rep_day_settings(case_path::AbstractString, config_set::AbstractDict)

Load optional endogenous representative-day settings from
`Settings/HOPE_rep_day_settings.yml`. Missing files fall back to built-in defaults
and legacy `time_periods` from `HOPE_model_settings.yml`.
"""
function load_rep_day_settings(case_path::AbstractString, config_set::AbstractDict)
    settings = default_rep_day_settings(config_set)
    settings_path = joinpath(case_path, "Settings", "HOPE_rep_day_settings.yml")
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

to_int_rep_day(x) = x isa Integer ? Int(x) : parse(Int, string(x))

function parse_rep_day_binary(x, keyname::AbstractString)
    v = to_int_rep_day(x)
    if !(v in (0, 1))
        throw(ArgumentError("Invalid $(keyname)=$(v). Expected 0 or 1."))
    end
    return v
end

function parse_rep_day_positive_int(x, keyname::AbstractString)
    v = to_int_rep_day(x)
    if v < 1
        throw(ArgumentError("Invalid $(keyname)=$(v). Expected an integer >= 1."))
    end
    return v
end

function parse_rep_day_nonnegative_int(x, keyname::AbstractString)
    v = to_int_rep_day(x)
    if v < 0
        throw(ArgumentError("Invalid $(keyname)=$(v). Expected an integer >= 0."))
    end
    return v
end

function parse_time_period_tuple(dates)
    if isa(dates, String)
        dates = eval(Meta.parse(dates))
    end
    vals = collect(dates)
    if length(vals) != 4
        throw(ArgumentError("Invalid time_period entry $(dates). Expected 4 values: (start_month, start_day, end_month, end_day)."))
    end
    return (to_int_rep_day(vals[1]), to_int_rep_day(vals[2]), to_int_rep_day(vals[3]), to_int_rep_day(vals[4]))
end

"""
    resolve_rep_day_time_periods(config_set::AbstractDict)

Return endogenous representative-day time periods as an ordered vector of
`Pair{Int,NTuple{4,Int}}`. Advanced settings are read from
`config_set["rep_day_settings"]` when available, otherwise legacy
`config_set["time_periods"]` is used.
"""
function resolve_rep_day_time_periods(config_set::AbstractDict)
    settings = haskey(config_set, "rep_day_settings") ? config_set["rep_day_settings"] : default_rep_day_settings(config_set)
    raw_time_periods = get(settings, "time_periods", get(config_set, "time_periods", nothing))
    if raw_time_periods === nothing || isempty(raw_time_periods)
        throw(ArgumentError("endogenous_rep_day=1 requires representative-day time_periods. Provide them in HOPE_rep_day_settings.yml under `time_periods:`."))
    end
    pairs_vec = Pair{Int,NTuple{4,Int}}[]
    for (key, value) in pairs(raw_time_periods)
        push!(pairs_vec, to_int_rep_day(key) => parse_time_period_tuple(value))
    end
    sort!(pairs_vec; by=first)
    expected = collect(1:length(pairs_vec))
    found = [first(p) for p in pairs_vec]
    if found != expected
        throw(ArgumentError("Representative-day time_period keys must be contiguous 1..T. Found $(found)."))
    end
    return pairs_vec
end

function rep_day_settings_value(config_set::AbstractDict, key::AbstractString, default)
    settings = haskey(config_set, "rep_day_settings") ? config_set["rep_day_settings"] : default_rep_day_settings(config_set)
    return get(settings, key, default)
end

function parse_rep_day_metric_list(raw_metrics, keyname::AbstractString)
    metrics = raw_metrics isa AbstractVector ? lowercase.(strip.(string.(collect(raw_metrics)))) : [lowercase(strip(string(raw_metrics)))]
    allowed = Set(["peak_load", "peak_net_load", "min_wind", "min_solar", "max_ramp"])
    bad = [m for m in metrics if !(m in allowed)]
    if !isempty(bad)
        throw(ArgumentError("Invalid $(keyname)=$(bad). Allowed values: peak_load, peak_net_load, min_wind, min_solar, max_ramp."))
    end
    return unique(metrics)
end

function parse_rep_day_feature_list(raw_features, keyname::AbstractString)
    features = raw_features isa AbstractVector ? lowercase.(strip.(string.(collect(raw_features)))) : [lowercase(strip(string(raw_features)))]
    allowed = Set(["zonal_load", "zonal_net_load", "zonal_wind_cf", "zonal_solar_cf", "system_load", "system_net_load", "zonal_ramp", "system_ramp", "ni"])
    bad = [f for f in features if !(f in allowed)]
    if !isempty(bad)
        throw(ArgumentError("Invalid $(keyname)=$(bad). Allowed values: zonal_load, zonal_net_load, zonal_wind_cf, zonal_solar_cf, system_load, system_net_load, zonal_ramp, system_ramp, ni."))
    end
    return unique(features)
end

function day_of_year_no_leap(month::Integer, day::Integer)
    return dayofyear(Date(2021, Int(month), Int(day)))
end

function row_in_time_period(dates::NTuple{4,Int}, row)
    start_doy = day_of_year_no_leap(dates[1], dates[2])
    end_doy = day_of_year_no_leap(dates[3], dates[4])
    row_doy = day_of_year_no_leap(row.Month, row.Day)
    if start_doy <= end_doy
        return start_doy <= row_doy <= end_doy
    end
    return row_doy >= start_doy || row_doy <= end_doy
end

function validate_endogenous_rep_day_partition(loaddata::DataFrame, rep_time_periods)
    if !all(col -> col in names(loaddata), ["Month", "Day"])
        throw(ArgumentError("endogenous_rep_day requires Month and Day columns in load_timeseries_regional for time-period validation."))
    end

    day_keys = sort!(unique([(Int(loaddata[row_idx, "Month"]), Int(loaddata[row_idx, "Day"])) for row_idx in 1:nrow(loaddata)]); by = x -> day_of_year_no_leap(x[1], x[2]))
    missing_days = Tuple{Int,Int}[]
    overlap_days = Vector{Tuple{Tuple{Int,Int},Vector{Int}}}()

    for day_key in day_keys
        day_row = (Month = day_key[1], Day = day_key[2])
        matched_periods = Int[first(tp) for tp in rep_time_periods if row_in_time_period(last(tp), day_row)]
        if isempty(matched_periods)
            push!(missing_days, day_key)
        elseif length(matched_periods) > 1
            push!(overlap_days, (day_key, matched_periods))
        end
    end

    if !isempty(missing_days) || !isempty(overlap_days)
        format_day(day_key) = string(day_key[1], "/", day_key[2])
        messages = String[]
        if !isempty(missing_days)
            examples = join(format_day.(missing_days[1:min(end, 5)]), ", ")
            push!(messages, "gap days not covered by any time_period (examples: $(examples))")
        end
        if !isempty(overlap_days)
            examples = join(["$(format_day(day_key)) -> periods $(periods)" for (day_key, periods) in overlap_days[1:min(end, 5)]], "; ")
            push!(messages, "overlap days covered by multiple time_period entries (examples: $(examples))")
        end
        details = join(messages, " ; ")
        throw(ArgumentError("Invalid representative-day time_periods: they must cover each real chronology day exactly once. Found $(details)."))
    end
end

function validate_external_rep_day_inputs(
    loaddata::DataFrame,
    afdata::DataFrame,
    rep_weight_df::DataFrame;
    drtsdata::Union{Nothing,DataFrame}=nothing,
)
    if !("Time Period" in names(rep_weight_df)) || !("Weight" in names(rep_weight_df))
        throw(ArgumentError("rep_period_weights must include columns: 'Time Period' and 'Weight'."))
    end

    t_raw = Int.(rep_weight_df[!, "Time Period"])
    duplicate_t = unique(t_raw[findall(>(1), [count(==(t), t_raw) for t in t_raw])])
    if !isempty(duplicate_t)
        throw(ArgumentError("rep_period_weights contains duplicate Time Period rows: $(sort(unique(duplicate_t))). Provide exactly one weight per representative period."))
    end

    weights = Float64.(rep_weight_df[!, "Weight"])
    bad_rows = findall(w -> !isfinite(w) || w <= 0.0, weights)
    if !isempty(bad_rows)
        throw(ArgumentError("rep_period_weights must contain strictly positive finite weights. Invalid rows: $(bad_rows)."))
    end
    total_weight = sum(weights)
    if !(isfinite(total_weight) && total_weight > 0.0)
        throw(ArgumentError("rep_period_weights must sum to a positive finite value. Found $(total_weight)."))
    end
    if abs(total_weight - round(total_weight)) > 1.0e-6
        @warn "rep_period_weights sums to $(total_weight), which is not an integer number of original periods/days. This is allowed, but unusual for a standard annual representative-day mapping."
    end

    t_vals = sort(unique(t_raw))
    if isempty(t_vals)
        throw(ArgumentError("rep_period_weights is empty."))
    end
    if t_vals != collect(1:length(t_vals))
        throw(ArgumentError("rep_period_weights Time Period must be contiguous 1..T. Found: $(t_vals)."))
    end

    function validate_external_timeseries_periods(df::DataFrame, label::AbstractString, expected_t::Vector{Int})
        required_cols = ["Time Period", "Hours"]
        missing_cols = [c for c in required_cols if !(c in names(df))]
        if !isempty(missing_cols)
            throw(ArgumentError("$(label) is missing required columns $(missing_cols) for external representative-day mode."))
        end
        data_t_vals = sort(unique(Int.(df[!, "Time Period"])))
        if data_t_vals != expected_t
            throw(ArgumentError("Time Period IDs in $(label) ($(data_t_vals)) must match rep_period_weights ($(expected_t)) for external representative mode."))
        end
        for t in expected_t
            idx_t = findall(Int.(df[!, "Time Period"]) .== t)
            if length(idx_t) != 24
                throw(ArgumentError("Each external representative Time Period must contain exactly 24 rows in $(label). Found $(length(idx_t)) rows for Time Period=$(t)."))
            end
            hours_t = Int.(df[idx_t, "Hours"])
            if sort(hours_t) != collect(1:24)
                throw(ArgumentError("Hours for external representative Time Period=$(t) in $(label) must be 1..24 exactly once. Found $(sort(hours_t))."))
            end
        end
    end

    validate_external_timeseries_periods(loaddata, "load_timeseries_regional", t_vals)
    validate_external_timeseries_periods(afdata, "gen_availability_timeseries", t_vals)
    if drtsdata !== nothing
        validate_external_timeseries_periods(drtsdata, "dr_timeseries_regional", t_vals)
    end

    if total_weight < length(t_vals)
        @warn "rep_period_weights sums to $(total_weight), which is smaller than the number of representative periods ($(length(t_vals))). This implies an average weight below 1.0 per representative period."
    end

    return Dict(Int(row["Time Period"]) => Float64(row["Weight"]) for row in eachrow(rep_weight_df))
end

function select_rep_columns(df::DataFrame, requested_cols; include_ni::Bool=false)
    cols = [col for col in string.(collect(requested_cols)) if col in names(df)]
    if include_ni && ("NI" in names(df))
        push!(cols, "NI")
    end
    return cols
end

function collect_day_blocks(df::DataFrame, dates::NTuple{4,Int})
    if !all(col -> col in names(df), ["Month", "Day", "Hours"])
        throw(ArgumentError("endogenous_rep_day requires Month, Day, and Hours columns in full chronology inputs."))
    end
    day_rows = Dict{Tuple{Int,Int},Vector{Int}}()
    for row_idx in 1:nrow(df)
        row = df[row_idx, :]
        if row_in_time_period(dates, row)
            key = (Int(row.Month), Int(row.Day))
            push!(get!(day_rows, key, Int[]), row_idx)
        end
    end
    ordered_keys = sort!(collect(keys(day_rows)); by = x -> day_of_year_no_leap(x[1], x[2]))
    blocks = NamedTuple{(:key, :rows)}[]
    for key in ordered_keys
        rows = day_rows[key]
        hours = Int.(df[rows, "Hours"])
        if length(rows) != 24 || sort(hours) != collect(1:24)
            throw(ArgumentError("Each endogenous representative-day candidate must contain exactly 24 hourly rows with Hours=1:24. Problem found for Month=$(key[1]) Day=$(key[2])."))
        end
        push!(blocks, (key = key, rows = rows[sortperm(hours)]))
    end
    if isempty(blocks)
        throw(ArgumentError("No chronology rows matched the requested representative-day time period $(dates)."))
    end
    return blocks
end

function append_day_block_features!(
    pieces::Vector{Vector{Float64}},
    df::Union{Nothing,DataFrame},
    rows::Vector{Int},
    cols,
)
    if df === nothing || isempty(cols)
        return pieces
    end
    for col in cols
        push!(pieces, parse.(Float64, string.(df[rows, col])))
    end
    return pieces
end

function build_joint_daily_feature_matrix(
    loaddata::DataFrame,
    afdata::DataFrame,
    drtsdata::Union{Nothing,DataFrame},
    day_blocks,
    ordered_zone,
    ordered_gen,
    config_set::AbstractDict,
)
    include_load = parse_rep_day_binary(rep_day_settings_value(config_set, "include_load", 1), "rep_day_settings.include_load")
    include_af = parse_rep_day_binary(rep_day_settings_value(config_set, "include_af", 1), "rep_day_settings.include_af")
    include_dr = parse_rep_day_binary(rep_day_settings_value(config_set, "include_dr", 1), "rep_day_settings.include_dr")
    normalize_features = parse_rep_day_binary(rep_day_settings_value(config_set, "normalize_features", 1), "rep_day_settings.normalize_features")

    load_cols = include_load == 1 ? select_rep_columns(loaddata, ordered_zone; include_ni=true) : String[]
    af_cols = include_af == 1 ? select_rep_columns(afdata, ordered_gen) : String[]
    dr_cols = (include_dr == 1 && drtsdata !== nothing) ? select_rep_columns(drtsdata, ordered_zone) : String[]
    if isempty(load_cols) && isempty(af_cols) && isempty(dr_cols)
        throw(ArgumentError("Representative-day feature matrix is empty. Enable at least one of include_load/include_af/include_dr in HOPE_rep_day_settings.yml."))
    end

    feature_matrix = Matrix{Float64}(undef, length(day_blocks), 0)
    for (day_idx, block) in enumerate(day_blocks)
        pieces = Vector{Float64}[]
        append_day_block_features!(pieces, loaddata, block.rows, load_cols)
        append_day_block_features!(pieces, afdata, block.rows, af_cols)
        append_day_block_features!(pieces, drtsdata, block.rows, dr_cols)
        day_vector = vcat(pieces...)
        if day_idx == 1
            feature_matrix = Matrix{Float64}(undef, length(day_blocks), length(day_vector))
        end
        feature_matrix[day_idx, :] = day_vector
    end

    if normalize_features == 1
        for j in axes(feature_matrix, 2)
            col = feature_matrix[:, j]
            mu = mean(col)
            sigma = std(col)
            if sigma > 0
                feature_matrix[:, j] = (col .- mu) ./ sigma
            else
                feature_matrix[:, j] .= 0.0
            end
        end
    end

    return feature_matrix
end

function zone_string(value)
    return string(value)
end

function generator_zone_type_maps(generator_df::Union{Nothing,DataFrame}, ordered_zone, ordered_gen, afdata::DataFrame)
    zone_labels = string.(ordered_zone)
    wind_maps = Dict(zone => (String[], Float64[]) for zone in zone_labels)
    solar_maps = Dict(zone => (String[], Float64[]) for zone in zone_labels)
    generator_df === nothing && return wind_maps, solar_maps

    for (idx, gen_col) in enumerate(string.(ordered_gen))
        idx > nrow(generator_df) && break
        if !(gen_col in names(afdata))
            continue
        end
        type_val = lowercase(strip(string(generator_df[idx, "Type"])))
        zone_val = if "Zone" in names(generator_df)
            zone_string(generator_df[idx, "Zone"])
        elseif length(zone_labels) == 1
            zone_labels[1]
        else
            continue
        end
        if !(zone_val in zone_labels)
            continue
        end
        weight = Float64(generator_df[idx, "Pmax (MW)"])
        if type_val in ("windon", "windoff")
            push!(wind_maps[zone_val][1], gen_col)
            push!(wind_maps[zone_val][2], weight)
        elseif type_val == "solarpv"
            push!(solar_maps[zone_val][1], gen_col)
            push!(solar_maps[zone_val][2], weight)
        end
    end
    return wind_maps, solar_maps
end

function weighted_profile_from_cols(df::DataFrame, rows::Vector{Int}, cols::Vector{String}, weights::Vector{Float64})
    if isempty(cols)
        return zeros(Float64, length(rows))
    end
    mat = Matrix{Float64}(df[rows, cols])
    if isempty(weights) || sum(weights) <= 0
        return vec(mean(mat, dims=2))
    end
    return vec(mat * (weights ./ sum(weights)))
end

function build_planning_daily_feature_matrix(
    loaddata::DataFrame,
    afdata::DataFrame,
    day_blocks,
    ordered_zone,
    ordered_gen,
    config_set::AbstractDict,
    generator_df::Union{Nothing,DataFrame},
)
    normalize_features = parse_rep_day_binary(rep_day_settings_value(config_set, "normalize_features", 1), "rep_day_settings.normalize_features")
    feature_set = parse_rep_day_feature_list(
        rep_day_settings_value(config_set, "planning_feature_set", default_rep_day_settings(config_set)["planning_feature_set"]),
        "rep_day_settings.planning_feature_set",
    )
    isempty(feature_set) && throw(ArgumentError("rep_day_settings.planning_feature_set cannot be empty when feature_mode = planning_features."))

    zone_labels = string.(ordered_zone)
    load_cols = select_rep_columns(loaddata, ordered_zone; include_ni=false)
    wind_maps, solar_maps = generator_zone_type_maps(generator_df, ordered_zone, ordered_gen, afdata)

    feature_matrix = Matrix{Float64}(undef, length(day_blocks), 0)
    for (day_idx, block) in enumerate(day_blocks)
        load_block = Matrix{Float64}(loaddata[block.rows, load_cols])
        system_load = vec(sum(load_block, dims=2))
        ni = "NI" in names(loaddata) ? Float64.(loaddata[block.rows, "NI"]) : zeros(24)
        zonal_features = Dict{String,Any}()
        system_wind = zeros(24)
        system_solar = zeros(24)
        zonal_net_cols = Vector{Vector{Float64}}()

        for (z_idx, zone) in enumerate(zone_labels)
            zonal_load = load_block[:, z_idx]
            wind_cols, wind_weights = wind_maps[zone]
            solar_cols, solar_weights = solar_maps[zone]
            zonal_wind_cf = weighted_profile_from_cols(afdata, block.rows, wind_cols, wind_weights)
            zonal_solar_cf = weighted_profile_from_cols(afdata, block.rows, solar_cols, solar_weights)
            zonal_wind_potential = sum(wind_weights) .* zonal_wind_cf
            zonal_solar_potential = sum(solar_weights) .* zonal_solar_cf
            system_wind .+= zonal_wind_potential
            system_solar .+= zonal_solar_potential
            zonal_ni = similar(system_load)
            for h in eachindex(system_load)
                zonal_ni[h] = system_load[h] > 0 ? ni[h] * zonal_load[h] / system_load[h] : 0.0
            end
            zonal_net_load = zonal_load .- zonal_ni .- zonal_wind_potential .- zonal_solar_potential
            push!(zonal_net_cols, zonal_net_load)
            zonal_features["load_$zone"] = zonal_load
            zonal_features["net_$zone"] = zonal_net_load
            zonal_features["wind_$zone"] = zonal_wind_cf
            zonal_features["solar_$zone"] = zonal_solar_cf
            zonal_features["ramp_$zone"] = vcat(0.0, diff(zonal_net_load))
        end

        system_net_load = system_load .- ni .- system_wind .- system_solar
        system_ramp = vcat(0.0, diff(system_net_load))
        pieces = Vector{Float64}[]
        for feature in feature_set
            if feature == "zonal_load"
                append!(pieces, [zonal_features["load_$zone"] for zone in zone_labels])
            elseif feature == "zonal_net_load"
                append!(pieces, [zonal_features["net_$zone"] for zone in zone_labels])
            elseif feature == "zonal_wind_cf"
                append!(pieces, [zonal_features["wind_$zone"] for zone in zone_labels])
            elseif feature == "zonal_solar_cf"
                append!(pieces, [zonal_features["solar_$zone"] for zone in zone_labels])
            elseif feature == "system_load"
                push!(pieces, system_load)
            elseif feature == "system_net_load"
                push!(pieces, system_net_load)
            elseif feature == "zonal_ramp"
                append!(pieces, [zonal_features["ramp_$zone"] for zone in zone_labels])
            elseif feature == "system_ramp"
                push!(pieces, system_ramp)
            elseif feature == "ni"
                push!(pieces, ni)
            end
        end
        day_vector = vcat(pieces...)
        if day_idx == 1
            feature_matrix = Matrix{Float64}(undef, length(day_blocks), length(day_vector))
        end
        feature_matrix[day_idx, :] = day_vector
    end

    if normalize_features == 1
        for j in axes(feature_matrix, 2)
            col = feature_matrix[:, j]
            mu = mean(col)
            sigma = std(col)
            if sigma > 0
                feature_matrix[:, j] = (col .- mu) ./ sigma
            else
                feature_matrix[:, j] .= 0.0
            end
        end
    end
    return feature_matrix
end

function legacy_column_centroid_ts(df::DataFrame, time_periods, ordered_cols)
    rep_dat_dict = Dict{Int,DataFrame}()
    ndays_dict = Dict{Int,Int}()
    for (tp, dates) in time_periods
        blocks = collect_day_blocks(df, dates)
        n_days = length(blocks)
        representative_day_df = DataFrame()
        for nm in select_rep_columns(df, ordered_cols; include_ni=("NI" in names(df)))
            col_mtx = hcat([parse.(Float64, string.(df[block.rows, nm])) for block in blocks]...)
            clustering_result = kmeans(col_mtx, 1)
            representative_day_df[!, nm] = clustering_result.centers'[1, :]
        end
        if !("Hour" in names(representative_day_df))
            representative_day_df[!, "Hour"] = collect(1:24)
        end
        rep_dat_dict[tp] = representative_day_df
        ndays_dict[tp] = n_days
    end
    return rep_dat_dict, ndays_dict
end

function normalize_time_period_iterable(time_periods)
    if time_periods isa AbstractVector{<:Pair}
        return [(to_int_rep_day(tp) => parse_time_period_tuple(dates)) for (tp, dates) in time_periods]
    end
    return [(to_int_rep_day(tp) => parse_time_period_tuple(dates)) for (tp, dates) in pairs(time_periods)]
end

"""
    get_representative_ts(df, time_periods, ordered_cols, k=1)

Legacy helper retained for backward compatibility. It builds one synthetic
centroid day per time period, independently by column.
"""
function get_representative_ts(df, time_periods, ordered_cols, k=1)
    return legacy_column_centroid_ts(df, normalize_time_period_iterable(time_periods), string.(ordered_cols))
end

function extract_rep_block(df::DataFrame, rows::Vector{Int}, ordered_cols; include_ni::Bool=false, add_hour::Bool=false)
    selected_cols = select_rep_columns(df, ordered_cols; include_ni=include_ni)
    rep_df = select(df[rows, :], selected_cols)
    if add_hour
        rep_df[!, "Hour"] = collect(1:24)
    end
    return rep_df
end

function select_medoid_index(feature_matrix::Matrix{Float64})
    n_days = size(feature_matrix, 1)
    if n_days == 1
        return 1
    end
    scores = fill(0.0, n_days)
    for i in 1:n_days
        xi = view(feature_matrix, i, :)
        for j in 1:n_days
            xj = view(feature_matrix, j, :)
            scores[i] += sum((xi[k] - xj[k])^2 for k in eachindex(xi))
        end
    end
    return argmin(scores)
end

function select_medoid_indices(feature_matrix::Matrix{Float64}, k::Int)
    n_days = size(feature_matrix, 1)
    if k >= n_days
        medoids = collect(1:n_days)
        assignments = collect(1:n_days)
        counts = ones(Int, n_days)
        return medoids, assignments, counts
    elseif k == 1
        medoid = select_medoid_index(feature_matrix)
        assignments = ones(Int, n_days)
        counts = [n_days]
        return [medoid], assignments, counts
    end

    distance_matrix = pairwise(SqEuclidean(), transpose(feature_matrix), dims=2)
    result = kmedoids(distance_matrix, k)
    medoids = collect(result.medoids)
    sort_order = sortperm(medoids)
    sorted_medoids = medoids[sort_order]
    cluster_map = Dict(old_idx => new_idx for (new_idx, old_idx) in enumerate(sort_order))
    sorted_assignments = [cluster_map[a] for a in result.assignments]
    sorted_counts = [count(==(cluster_idx), sorted_assignments) for cluster_idx in 1:k]
    return sorted_medoids, sorted_assignments, sorted_counts
end

function combine_rep_day_generator_data(generator_data::Union{Nothing,DataFrame}, candidate_generator_data::Union{Nothing,DataFrame})
    generator_data === nothing && candidate_generator_data === nothing && return nothing
    existing = generator_data === nothing ? DataFrame() : copy(generator_data)
    candidate = candidate_generator_data === nothing ? DataFrame() : copy(candidate_generator_data)
    return isempty(existing) ? candidate : (isempty(candidate) ? existing : vcat(existing, candidate; cols=:union))
end

function generator_metric_weights(generator_df::Union{Nothing,DataFrame}, ordered_gen, type_labels::Vector{String})
    generator_df === nothing && return Tuple{Vector{String},Vector{Float64}}(String[], Float64[])
    isempty(type_labels) && return Tuple{Vector{String},Vector{Float64}}(String[], Float64[])
    cols = String[]
    weights = Float64[]
    for (idx, col) in enumerate(string.(ordered_gen))
        idx > nrow(generator_df) && break
        type_val = lowercase(strip(string(generator_df[idx, "Type"])))
        if type_val in lowercase.(type_labels)
            push!(cols, col)
            push!(weights, Float64(generator_df[idx, "Pmax (MW)"]))
        end
    end
    return cols, weights
end

function filter_existing_af_columns(cols::Vector{String}, weights::Vector{Float64}, afdata::DataFrame)
    keep = findall(col -> col in names(afdata), cols)
    return cols[keep], weights[keep]
end

function safe_weighted_average(values::Vector{Float64}, weights::Vector{Float64})
    isempty(values) && return nothing
    if isempty(weights) || sum(weights) <= 0
        return mean(values)
    end
    return sum(values[i] * weights[i] for i in eachindex(values)) / sum(weights)
end

function row_numeric_values(df::DataFrame, row_idx::Int, cols::Vector{String})
    isempty(cols) && return Float64[]
    return vec(Float64.(Matrix(df[row_idx:row_idx, cols])))
end

function compute_extreme_metric_values(
    loaddata::DataFrame,
    afdata::DataFrame,
    day_blocks,
    ordered_zone,
    ordered_gen,
    generator_df::Union{Nothing,DataFrame},
)
    load_cols = select_rep_columns(loaddata, ordered_zone; include_ni=false)
    wind_cols, wind_weights = generator_metric_weights(generator_df, ordered_gen, ["WindOn", "WindOff"])
    solar_cols, solar_weights = generator_metric_weights(generator_df, ordered_gen, ["SolarPV"])
    wind_cols, wind_weights = filter_existing_af_columns(wind_cols, wind_weights, afdata)
    solar_cols, solar_weights = filter_existing_af_columns(solar_cols, solar_weights, afdata)
    values = Dict(
        "peak_load" => fill(-Inf, length(day_blocks)),
        "peak_net_load" => fill(-Inf, length(day_blocks)),
        "min_wind" => fill(Inf, length(day_blocks)),
        "min_solar" => fill(Inf, length(day_blocks)),
        "max_ramp" => fill(-Inf, length(day_blocks)),
    )

    for (block_idx, block) in enumerate(day_blocks)
        system_load = isempty(load_cols) ? zeros(24) : vec(sum(Matrix{Float64}(loaddata[block.rows, load_cols]), dims=2))
        ni = "NI" in names(loaddata) ? Float64.(loaddata[block.rows, "NI"]) : zeros(24)

        wind_cf = if isempty(wind_cols)
            nothing
        else
            [safe_weighted_average(row_numeric_values(afdata, block.rows[h], wind_cols), wind_weights) for h in 1:24]
        end
        solar_cf = if isempty(solar_cols)
            nothing
        else
            [safe_weighted_average(row_numeric_values(afdata, block.rows[h], solar_cols), solar_weights) for h in 1:24]
        end

        wind_potential = wind_cf === nothing ? zeros(24) : collect(sum(wind_weights) .* wind_cf)
        solar_potential = solar_cf === nothing ? zeros(24) : collect(sum(solar_weights) .* solar_cf)
        net_load = system_load .- ni .- wind_potential .- solar_potential

        values["peak_load"][block_idx] = maximum(system_load)
        values["peak_net_load"][block_idx] = maximum(net_load)
        values["max_ramp"][block_idx] = isempty(net_load) ? -Inf : maximum(vcat(0.0, diff(net_load)))
        values["min_wind"][block_idx] = wind_cf === nothing ? Inf : mean(wind_cf)
        values["min_solar"][block_idx] = solar_cf === nothing ? Inf : mean(solar_cf)
    end

    return values
end

function select_extreme_day_indices(
    loaddata::DataFrame,
    afdata::DataFrame,
    day_blocks,
    ordered_zone,
    ordered_gen,
    config_set::AbstractDict;
    generator_data::Union{Nothing,DataFrame}=nothing,
)
    add_extreme_days = parse_rep_day_binary(rep_day_settings_value(config_set, "add_extreme_days", 0), "rep_day_settings.add_extreme_days")
    add_extreme_days == 0 && return Int[], String[]

    metrics = parse_rep_day_metric_list(
        rep_day_settings_value(config_set, "extreme_day_metrics", ["peak_load", "peak_net_load", "min_wind", "min_solar", "max_ramp"]),
        "rep_day_settings.extreme_day_metrics",
    )
    metric_values = compute_extreme_metric_values(loaddata, afdata, day_blocks, ordered_zone, ordered_gen, generator_data)
    selected_indices = Int[]
    selected_metrics = String[]
    seen = Set{Int}()
    for metric in metrics
        vals = metric_values[metric]
        if all(v -> !isfinite(v), vals)
            continue
        end
        idx = metric in ("min_wind", "min_solar") ? argmin(vals) : argmax(vals)
        if !(idx in seen)
            push!(selected_indices, idx)
            push!(selected_metrics, metric)
            push!(seen, idx)
        end
    end
    return selected_indices, selected_metrics
end

function squared_distance(feature_matrix::Matrix{Float64}, i::Int, j::Int)
    xi = view(feature_matrix, i, :)
    xj = view(feature_matrix, j, :)
    return sum((xi[k] - xj[k])^2 for k in eachindex(xi))
end

function select_iterative_refinement_days(
    feature_matrix::Matrix{Float64},
    assignments::Vector{Int},
    cluster_counts::Vector{Float64},
    selected_indices::Vector{Int},
    n_refinement::Int,
)
    n_refinement <= 0 && return Tuple{Int,Float64}[]

    refinement = Tuple{Int,Float64}[]
    active_selected = copy(selected_indices)
    selected_set = Set(active_selected)

    for _ in 1:n_refinement
        best_idx = 0
        best_score = -Inf
        for day_idx in axes(feature_matrix, 1)
            if day_idx in selected_set
                continue
            end
            cluster_idx = assignments[day_idx]
            if cluster_counts[cluster_idx] <= 1.0
                continue
            end
            score = minimum(squared_distance(feature_matrix, day_idx, sel_idx) for sel_idx in active_selected)
            if score > best_score
                best_idx = day_idx
                best_score = score
            end
        end
        best_idx == 0 && break
        cluster_counts[assignments[best_idx]] -= 1.0
        push!(refinement, (best_idx, best_score))
        push!(active_selected, best_idx)
        push!(selected_set, best_idx)
    end

    return refinement
end

function build_storage_rep_linkage(day_assignments::DataFrame)
    if nrow(day_assignments) == 0
        return Dict(
            "day_assignments" => DataFrame(),
            "transition_table" => DataFrame(PredecessorRepresentativePeriod=Int[], RepresentativePeriod=Int[], Count=Int[], Weight=Float64[]),
            "predecessors" => Dict{Int,Vector{Int}}(),
            "predecessor_weight" => Dict{Tuple{Int,Int},Float64}(),
            "run_stats" => DataFrame(RepresentativePeriod=Int[], NumRuns=Int[], AverageRunLength=Float64[], MaxRunLength=Int[]),
        )
    end

    sorted_assignments = sort(copy(day_assignments), [:DayOfYear, :TimePeriod, :Month, :Day])
    reps = Int.(sorted_assignments[:, "RepresentativePeriod"])
    unique_reps = sort(unique(reps))

    transition_counts = Dict{Tuple{Int,Int},Int}()
    for idx in eachindex(reps)
        prev_rep = reps[idx == 1 ? end : idx - 1]
        curr_rep = reps[idx]
        transition_counts[(prev_rep, curr_rep)] = get(transition_counts, (prev_rep, curr_rep), 0) + 1
    end

    transition_rows = NamedTuple{(:PredecessorRepresentativePeriod, :RepresentativePeriod, :Count, :Weight),Tuple{Int,Int,Int,Float64}}[]
    predecessors = Dict{Int,Vector{Int}}()
    predecessor_weight = Dict{Tuple{Int,Int},Float64}()
    for rep in unique_reps
        incoming = [(prev, cnt) for ((prev, curr), cnt) in transition_counts if curr == rep]
        sort!(incoming; by=first)
        total_incoming = sum(cnt for (_, cnt) in incoming)
        predecessors[rep] = Int[prev for (prev, _) in incoming]
        for (prev, cnt) in incoming
            weight = total_incoming > 0 ? cnt / total_incoming : 0.0
            predecessor_weight[(prev, rep)] = weight
            push!(transition_rows, (prev, rep, cnt, weight))
        end
    end

    run_rows = NamedTuple{(:RepresentativePeriod, :NumRuns, :AverageRunLength, :MaxRunLength),Tuple{Int,Int,Float64,Int}}[]
    run_lengths = Dict{Int,Vector{Int}}()
    current_rep = reps[1]
    current_len = 1
    for idx in 2:length(reps)
        if reps[idx] == current_rep
            current_len += 1
        else
            push!(get!(run_lengths, current_rep, Int[]), current_len)
            current_rep = reps[idx]
            current_len = 1
        end
    end
    push!(get!(run_lengths, current_rep, Int[]), current_len)
    for rep in unique_reps
        lengths = get(run_lengths, rep, Int[])
        avg_len = isempty(lengths) ? 0.0 : mean(lengths)
        max_len = isempty(lengths) ? 0 : maximum(lengths)
        push!(run_rows, (rep, length(lengths), avg_len, max_len))
    end

    return Dict(
        "day_assignments" => sorted_assignments,
        "transition_table" => DataFrame(transition_rows),
        "predecessors" => predecessors,
        "predecessor_weight" => predecessor_weight,
        "run_stats" => DataFrame(run_rows),
    )
end

"""
    build_endogenous_rep_periods(loaddata, afdata, ordered_zone, ordered_gen, config_set; drtsdata=nothing)

Construct endogenous representative-day inputs using the advanced settings in
`HOPE_rep_day_settings.yml`. Features 1-5 select one or more actual
representative days per time period from a joint daily feature matrix and may
optionally augment them with extreme and iterative refinement days.
"""
function build_endogenous_rep_periods(
    loaddata::DataFrame,
    afdata::DataFrame,
    ordered_zone,
    ordered_gen,
    config_set::AbstractDict;
    drtsdata::Union{Nothing,DataFrame}=nothing,
    generator_data::Union{Nothing,DataFrame}=nothing,
    candidate_generator_data::Union{Nothing,DataFrame}=nothing,
)
    rep_time_periods = resolve_rep_day_time_periods(config_set)
    validate_endogenous_rep_day_partition(loaddata, rep_time_periods)
    feature_mode = lowercase(String(rep_day_settings_value(config_set, "feature_mode", "joint_daily")))
    clustering_method = lowercase(String(rep_day_settings_value(config_set, "clustering_method", "kmedoids")))
    rep_days_per_period = parse_rep_day_positive_int(
        rep_day_settings_value(config_set, "representative_days_per_period", 1),
        "rep_day_settings.representative_days_per_period",
    )

    load_rep = Dict{Int,DataFrame}()
    af_rep = Dict{Int,DataFrame}()
    dr_rep = drtsdata === nothing ? nothing : Dict{Int,DataFrame}()
    ndays = Dict{Int,Float64}()
    day_assignments = DataFrame(
        TimePeriod = Int[],
        Month = Int[],
        Day = Int[],
        DayOfYear = Int[],
        RepresentativePeriod = Int[],
        AssignmentType = String[],
    )
    metadata = DataFrame(
        RepresentativePeriod = Int[],
        TimePeriod = Int[],
        RepresentativeIndex = Int[],
        SelectedMonth = Int[],
        SelectedDay = Int[],
        WeightDays = Float64[],
        Method = String[],
        SelectionType = String[],
        ExtremeMetric = String[],
        RefinementScore = Float64[],
    )
    rep_period_ids_by_time_period = Dict{Int,Vector{Int}}()
    rep_period_id = 1
    method_label = feature_mode == "planning_features" ? "planning_features_kmedoids" : "joint_daily_kmedoids"
    extreme_method_label = feature_mode == "planning_features" ? "planning_features_kmedoids_extreme" : "joint_daily_kmedoids_extreme"
    refinement_method_label = feature_mode == "planning_features" ? "planning_features_kmedoids_iterative" : "joint_daily_kmedoids_iterative"
    iterative_refinement = parse_rep_day_binary(rep_day_settings_value(config_set, "iterative_refinement", 0), "rep_day_settings.iterative_refinement")
    iterative_refinement_days = parse_rep_day_nonnegative_int(
        rep_day_settings_value(config_set, "iterative_refinement_days_per_period", 1),
        "rep_day_settings.iterative_refinement_days_per_period",
    )
    link_storage_rep_days = parse_rep_day_binary(rep_day_settings_value(config_set, "link_storage_rep_days", 0), "rep_day_settings.link_storage_rep_days")

    for (tp, dates) in rep_time_periods
        blocks = collect_day_blocks(loaddata, dates)
        k_eff = min(rep_days_per_period, length(blocks))
        if rep_days_per_period > length(blocks)
            @warn "rep_day_settings.representative_days_per_period=$(rep_days_per_period) exceeds the number of available days ($(length(blocks))) in time_period=$(tp). Using $(k_eff) representative days for this period."
        end

        if feature_mode == "legacy_column_centroid"
            if k_eff != 1
                throw(ArgumentError("feature_mode=legacy_column_centroid currently supports only representative_days_per_period = 1."))
            end
            if parse_rep_day_binary(rep_day_settings_value(config_set, "add_extreme_days", 0), "rep_day_settings.add_extreme_days") == 1
                throw(ArgumentError("Feature 3 extreme-day augmentation is currently supported only with feature_mode = joint_daily."))
            end
            legacy_load, legacy_n = legacy_column_centroid_ts(loaddata, [tp => dates], ordered_zone)
            legacy_af, _ = legacy_column_centroid_ts(afdata, [tp => dates], ordered_gen)
            load_rep[rep_period_id] = legacy_load[tp]
            af_rep[rep_period_id] = legacy_af[tp]
            if drtsdata !== nothing
                legacy_dr, _ = legacy_column_centroid_ts(drtsdata, [tp => dates], ordered_zone)
                dr_rep[rep_period_id] = legacy_dr[tp]
            end
            ndays[rep_period_id] = Float64(legacy_n[tp])
            rep_period_ids_by_time_period[tp] = [rep_period_id]
            push!(metadata, (rep_period_id, tp, 1, dates[1], dates[2], ndays[rep_period_id], "legacy_column_centroid", "cluster_medoid", "", 0.0))
            rep_period_id += 1
            continue
        end

        if !(feature_mode in ("joint_daily", "planning_features"))
            throw(ArgumentError("Unsupported rep_day_settings.feature_mode=$(feature_mode). Supported values: joint_daily, planning_features, legacy_column_centroid."))
        end
        if clustering_method != "kmedoids"
            throw(ArgumentError("Unsupported rep_day_settings.clustering_method=$(clustering_method) for Features 1-4. Supported value: kmedoids."))
        end

        all_generator_data = combine_rep_day_generator_data(generator_data, candidate_generator_data)
        feature_matrix = if feature_mode == "joint_daily"
            build_joint_daily_feature_matrix(loaddata, afdata, drtsdata, blocks, ordered_zone, ordered_gen, config_set)
        else
            build_planning_daily_feature_matrix(
                loaddata,
                afdata,
                blocks,
                ordered_zone,
                ordered_gen,
                config_set,
                all_generator_data,
            )
        end
        medoid_indices, assignments, counts = select_medoid_indices(feature_matrix, k_eff)
        cluster_counts = Float64.(counts)
        extreme_indices, extreme_metrics = select_extreme_day_indices(
            loaddata,
            afdata,
            blocks,
            ordered_zone,
            ordered_gen,
            config_set;
            generator_data=all_generator_data,
        )
        selected_medoid_set = Set(medoid_indices)
        augmented_extremes = Tuple{Int,String}[]
        for (extreme_idx, metric) in zip(extreme_indices, extreme_metrics)
            if extreme_idx in selected_medoid_set
                continue
            end
            cluster_idx = assignments[extreme_idx]
            if cluster_counts[cluster_idx] <= 1.0
                continue
            end
            cluster_counts[cluster_idx] -= 1.0
            push!(augmented_extremes, (extreme_idx, metric))
        end
        selected_indices = vcat(medoid_indices, first.(augmented_extremes))
        refinement_days = iterative_refinement == 1 ? select_iterative_refinement_days(feature_matrix, assignments, cluster_counts, selected_indices, iterative_refinement_days) : Tuple{Int,Float64}[]
        rep_ids = Int[]
        medoid_rep_id_map = Dict{Int,Int}()
        extreme_rep_id_map = Dict{Int,Int}()
        refinement_rep_id_map = Dict{Int,Int}()
        for (local_idx, block_idx) in enumerate(medoid_indices)
            selected_block = blocks[block_idx]
            load_rep[rep_period_id] = extract_rep_block(loaddata, selected_block.rows, ordered_zone; include_ni=true, add_hour=true)
            af_rep[rep_period_id] = extract_rep_block(afdata, selected_block.rows, ordered_gen; include_ni=false, add_hour=false)
            if drtsdata !== nothing
                dr_rep[rep_period_id] = extract_rep_block(drtsdata, selected_block.rows, ordered_zone; include_ni=false, add_hour=false)
            end
            ndays[rep_period_id] = cluster_counts[local_idx]
            push!(metadata, (rep_period_id, tp, local_idx, selected_block.key[1], selected_block.key[2], ndays[rep_period_id], method_label, "cluster_medoid", "", 0.0))
            medoid_rep_id_map[block_idx] = rep_period_id
            push!(rep_ids, rep_period_id)
            rep_period_id += 1
        end
        for (offset_idx, (block_idx, metric)) in enumerate(augmented_extremes)
            selected_block = blocks[block_idx]
            load_rep[rep_period_id] = extract_rep_block(loaddata, selected_block.rows, ordered_zone; include_ni=true, add_hour=true)
            af_rep[rep_period_id] = extract_rep_block(afdata, selected_block.rows, ordered_gen; include_ni=false, add_hour=false)
            if drtsdata !== nothing
                dr_rep[rep_period_id] = extract_rep_block(drtsdata, selected_block.rows, ordered_zone; include_ni=false, add_hour=false)
            end
            ndays[rep_period_id] = 1.0
            push!(metadata, (rep_period_id, tp, k_eff + offset_idx, selected_block.key[1], selected_block.key[2], ndays[rep_period_id], extreme_method_label, "extreme_day", metric, 0.0))
            extreme_rep_id_map[block_idx] = rep_period_id
            push!(rep_ids, rep_period_id)
            rep_period_id += 1
        end
        for (offset_idx, (block_idx, score)) in enumerate(refinement_days)
            selected_block = blocks[block_idx]
            load_rep[rep_period_id] = extract_rep_block(loaddata, selected_block.rows, ordered_zone; include_ni=true, add_hour=true)
            af_rep[rep_period_id] = extract_rep_block(afdata, selected_block.rows, ordered_gen; include_ni=false, add_hour=false)
            if drtsdata !== nothing
                dr_rep[rep_period_id] = extract_rep_block(drtsdata, selected_block.rows, ordered_zone; include_ni=false, add_hour=false)
            end
            ndays[rep_period_id] = 1.0
            push!(metadata, (rep_period_id, tp, k_eff + length(augmented_extremes) + offset_idx, selected_block.key[1], selected_block.key[2], ndays[rep_period_id], refinement_method_label, "refinement_day", "", score))
            refinement_rep_id_map[block_idx] = rep_period_id
            push!(rep_ids, rep_period_id)
            rep_period_id += 1
        end
        for (block_idx, block) in enumerate(blocks)
            assigned_rep = 0
            assignment_type = "cluster_member"
            if haskey(extreme_rep_id_map, block_idx)
                assigned_rep = extreme_rep_id_map[block_idx]
                assignment_type = "extreme_day"
            elseif haskey(refinement_rep_id_map, block_idx)
                assigned_rep = refinement_rep_id_map[block_idx]
                assignment_type = "refinement_day"
            else
                assigned_rep = medoid_rep_id_map[medoid_indices[assignments[block_idx]]]
                if haskey(medoid_rep_id_map, block_idx)
                    assignment_type = "cluster_medoid"
                end
            end
            push!(day_assignments, (
                tp,
                block.key[1],
                block.key[2],
                day_of_year_no_leap(block.key[1], block.key[2]),
                assigned_rep,
                assignment_type,
            ))
        end
        rep_period_ids_by_time_period[tp] = rep_ids
    end

    storage_linkage = link_storage_rep_days == 1 ? build_storage_rep_linkage(day_assignments) : nothing

    return Dict(
        "Load_rep" => load_rep,
        "AF_rep" => af_rep,
        "DR_rep" => dr_rep,
        "N" => ndays,
        "day_assignments" => day_assignments,
        "metadata" => metadata,
        "storage_linkage" => storage_linkage,
        "time_periods" => rep_time_periods,
        "T" => sort(collect(keys(ndays))),
        "representative_days_per_period" => rep_days_per_period,
        "rep_period_ids_by_time_period" => rep_period_ids_by_time_period,
    )
end

function endogenous_rep_day_weights(
    loaddata::DataFrame,
    afdata::DataFrame,
    ordered_zone,
    ordered_gen,
    config_set::AbstractDict;
    drtsdata::Union{Nothing,DataFrame}=nothing,
)
    rep = build_endogenous_rep_periods(loaddata, afdata, ordered_zone, ordered_gen, config_set; drtsdata=drtsdata)
    return rep["N"]
end
