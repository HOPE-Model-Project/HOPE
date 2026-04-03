"""
    default_aggregation_settings(config_set::AbstractDict=Dict{String,Any}())

Return default advanced settings for resource aggregation. These settings are
loaded from `Settings/HOPE_aggregation_settings.yml` when
`resource_aggregation = 1`.
"""
function default_aggregation_settings(config_set::AbstractDict=Dict{String,Any}())
    return Dict{String,Any}(
        "write_aggregation_audit" => 1,
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
