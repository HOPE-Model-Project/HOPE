"""
    default_aggregation_settings(config_set::AbstractDict=Dict{String,Any}())

Return default advanced settings for resource aggregation. These settings are
loaded from `Settings/HOPE_aggregation_settings.yml` when
`resource_aggregation = 1`.
"""
function default_aggregation_settings(config_set::AbstractDict=Dict{String,Any}())
    return Dict{String,Any}(
        "write_aggregation_audit" => 1,
        "grouping_keys" => ["Zone", "Type"],
        "pcm_additional_grouping_keys" => ["Flag_UC"],
        "clustered_thermal_commitment" => 1,
        "aggregate_technologies" => Any[],
        "keep_separate_technologies" => Any[],
    )
end

"""
    load_aggregation_settings(case_path::AbstractString, config_set::AbstractDict)

Load optional advanced aggregation settings from
`Settings/HOPE_aggregation_settings.yml`. Missing files fall back to built-in
defaults.
"""
function load_aggregation_settings(case_path::AbstractString, config_set::AbstractDict)
    settings = default_aggregation_settings(config_set)
    settings_path = joinpath(case_path, "Settings", "HOPE_aggregation_settings.yml")
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

function parse_aggregation_binary(x, keyname::AbstractString)
    v = x isa Integer ? Int(x) : parse(Int, string(x))
    if !(v in (0, 1))
        throw(ArgumentError("Invalid $(keyname)=$(v). Expected 0 or 1."))
    end
    return v
end

function aggregation_settings_value(config_set::AbstractDict, key::AbstractString, default)
    settings = haskey(config_set, "aggregation_settings") ? config_set["aggregation_settings"] : default_aggregation_settings(config_set)
    return get(settings, key, default)
end

function write_aggregation_audit_enabled(config_set::AbstractDict)
    return parse_aggregation_binary(
        aggregation_settings_value(config_set, "write_aggregation_audit", 1),
        "aggregation_settings.write_aggregation_audit",
    ) == 1
end

function clustered_thermal_commitment_enabled(config_set::AbstractDict)
    return parse_aggregation_binary(
        aggregation_settings_value(config_set, "clustered_thermal_commitment", 1),
        "aggregation_settings.clustered_thermal_commitment",
    ) == 1
end

function aggregation_setting_string_list(config_set::AbstractDict, key::AbstractString, default::Vector{String}=String[])
    raw = aggregation_settings_value(config_set, key, default)
    if raw isa AbstractVector
        return [string(v) for v in raw]
    elseif raw === nothing
        return copy(default)
    else
        throw(ArgumentError("aggregation_settings.$(key) must be a YAML list."))
    end
end

function aggregation_grouping_keys(df::AbstractDataFrame, config_set::AbstractDict, model_mode::AbstractString)
    keys = aggregation_setting_string_list(config_set, "grouping_keys", ["Zone", "Type"])
    if model_mode == "PCM"
        append!(keys, aggregation_setting_string_list(config_set, "pcm_additional_grouping_keys", ["Flag_UC"]))
    end
    available = Set(string.(names(df)))
    missing = [k for k in keys if !(k in available)]
    if !isempty(missing)
        throw(ArgumentError("aggregation_settings.grouping_keys contains columns missing from input data: $(join(missing, ", "))."))
    end
    return unique(keys)
end

function aggregation_should_merge_type(type_name::AbstractString, config_set::AbstractDict)
    keep_separate = Set(aggregation_setting_string_list(config_set, "keep_separate_technologies", String[]))
    type_name in keep_separate && return false
    aggregate_only = Set(aggregation_setting_string_list(config_set, "aggregate_technologies", String[]))
    isempty(aggregate_only) && return true
    return type_name in aggregate_only
end
