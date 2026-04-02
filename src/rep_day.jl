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
        "feature_mode" => "joint_daily",
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

"""
    build_endogenous_rep_periods(loaddata, afdata, ordered_zone, ordered_gen, config_set; drtsdata=nothing)

Construct endogenous representative-day inputs using the advanced settings in
`HOPE_rep_day_settings.yml`. Phase 1 selects one actual representative day per
time period from a joint daily feature matrix.
"""
function build_endogenous_rep_periods(
    loaddata::DataFrame,
    afdata::DataFrame,
    ordered_zone,
    ordered_gen,
    config_set::AbstractDict;
    drtsdata::Union{Nothing,DataFrame}=nothing,
)
    rep_time_periods = resolve_rep_day_time_periods(config_set)
    feature_mode = lowercase(String(rep_day_settings_value(config_set, "feature_mode", "joint_daily")))
    clustering_method = lowercase(String(rep_day_settings_value(config_set, "clustering_method", "kmedoids")))

    load_rep = Dict{Int,DataFrame}()
    af_rep = Dict{Int,DataFrame}()
    dr_rep = drtsdata === nothing ? nothing : Dict{Int,DataFrame}()
    ndays = Dict{Int,Float64}()
    metadata = DataFrame(
        TimePeriod = Int[],
        SelectedMonth = Int[],
        SelectedDay = Int[],
        WeightDays = Float64[],
        Method = String[],
    )

    for (tp, dates) in rep_time_periods
        blocks = collect_day_blocks(loaddata, dates)
        selected_block = nothing
        selected_method = clustering_method

        if feature_mode == "legacy_column_centroid"
            legacy_load, legacy_n = legacy_column_centroid_ts(loaddata, [tp => dates], ordered_zone)
            legacy_af, _ = legacy_column_centroid_ts(afdata, [tp => dates], ordered_gen)
            load_rep[tp] = legacy_load[tp]
            af_rep[tp] = legacy_af[tp]
            if drtsdata !== nothing
                legacy_dr, _ = legacy_column_centroid_ts(drtsdata, [tp => dates], ordered_zone)
                dr_rep[tp] = legacy_dr[tp]
            end
            ndays[tp] = Float64(legacy_n[tp])
            push!(metadata, (tp, dates[1], dates[2], ndays[tp], "legacy_column_centroid"))
            continue
        end

        if feature_mode != "joint_daily"
            throw(ArgumentError("Unsupported rep_day_settings.feature_mode=$(feature_mode). Supported values: joint_daily, legacy_column_centroid."))
        end
        if clustering_method != "kmedoids"
            throw(ArgumentError("Unsupported rep_day_settings.clustering_method=$(clustering_method) for Phase 1. Supported value: kmedoids."))
        end

        feature_matrix = build_joint_daily_feature_matrix(loaddata, afdata, drtsdata, blocks, ordered_zone, ordered_gen, config_set)
        selected_idx = select_medoid_index(feature_matrix)
        selected_block = blocks[selected_idx]

        load_rep[tp] = extract_rep_block(loaddata, selected_block.rows, ordered_zone; include_ni=true, add_hour=true)
        af_rep[tp] = extract_rep_block(afdata, selected_block.rows, ordered_gen; include_ni=false, add_hour=false)
        if drtsdata !== nothing
            dr_rep[tp] = extract_rep_block(drtsdata, selected_block.rows, ordered_zone; include_ni=false, add_hour=false)
        end
        ndays[tp] = Float64(length(blocks))
        push!(metadata, (tp, selected_block.key[1], selected_block.key[2], ndays[tp], "joint_daily_kmedoids"))
    end

    return Dict(
        "Load_rep" => load_rep,
        "AF_rep" => af_rep,
        "DR_rep" => dr_rep,
        "N" => ndays,
        "metadata" => metadata,
        "time_periods" => rep_time_periods,
    )
end

function endogenous_rep_day_weights(loaddata::DataFrame, config_set::AbstractDict)
    rep_time_periods = resolve_rep_day_time_periods(config_set)
    return Dict(tp => Float64(length(collect_day_blocks(loaddata, dates))) for (tp, dates) in rep_time_periods)
end
