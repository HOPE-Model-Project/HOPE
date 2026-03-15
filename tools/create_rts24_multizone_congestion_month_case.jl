using CSV
using DataFrames
using Dates
using YAML

const FULLFUNC_CASE = joinpath("ModelCases", "RTS24_PCM_fullfunc_case")
const TEMPLATE_CASE = joinpath("ModelCases", "RTS24_PCM_multizone4_congested_1month_case")
const DATA_DIR = "Data_RTS24_PCM_full"

const NEW_ZONES = ["Z1", "Z2", "Z3", "Z4"]
const MONTH_NAMES = Dict(
    1 => "jan",
    2 => "feb",
    3 => "mar",
    4 => "apr",
    5 => "may",
    6 => "jun",
    7 => "jul",
    8 => "aug",
    9 => "sep",
    10 => "oct",
    11 => "nov",
    12 => "dec",
)

bus_to_zone(bus::Int) = bus <= 6 ? "Z1" : bus <= 12 ? "Z2" : bus <= 18 ? "Z3" : "Z4"

function aggregate_timeseries(
    df::DataFrame,
    old_zones::Vector{String},
    old_to_new::Dict{String,String},
    weights_old::Dict{String,Float64},
    load_scale::Float64 = 1.0,
)
    out = select(df, 1:4)
    for z in NEW_ZONES
        oz = [o for o in old_zones if old_to_new[o] == z]
        w = [get(weights_old, o, 1.0) for o in oz]
        if sum(w) <= 0
            w .= 1.0
        end
        den = sum(w)
        vals = zeros(Float64, nrow(df))
        for (k, o) in enumerate(oz)
            vals .+= Float64.(df[!, Symbol(o)]) .* w[k]
        end
        out[!, Symbol(z)] = (vals ./ den) .* load_scale
    end
    if "NI" in names(df)
        out[!, :NI] = Float64.(df[!, :NI])
    end
    return out
end

function reset_dir(path::AbstractString)
    if isdir(path)
        rm(path; recursive=true, force=true)
    end
    mkpath(path)
end

function month_case_name(month::Int)
    token = MONTH_NAMES[month]
    return "RTS24_PCM_multizone4_congested_$(token)_1month_case"
end

function write_case_readme(path::AbstractString, month::Int)
    month_name = Dates.monthname(month)
    open(path, "w") do io
        write(io, """
# $(basename(dirname(path)))

Derived from `RTS24_PCM_multizone4_congested_1month_case` with the same 4-zone tightened network, but using $(month_name) hourly profiles sliced from `RTS24_PCM_fullfunc_case`.

Created: $(Dates.format(now(), "yyyy-mm-dd HH:MM:SS"))

Key characteristics:
- 24-bus nodal PTDF PCM with buses mapped into 4 reporting zones
- Tightened inter-zone transfer limits to preserve congestion visibility
- $(month_name)-only hourly load, wind, solar, and DR profiles
- Same solver/settings workflow as the original dashboard case
""")
    end
end

function main()
    month = length(ARGS) >= 1 ? parse(Int, ARGS[1]) : 2
    if !(1 <= month <= 12)
        error("Month must be between 1 and 12. Got: $(month)")
    end

    case_name = length(ARGS) >= 2 ? ARGS[2] : month_case_name(month)
    dst_case = joinpath("ModelCases", case_name)
    dst_data = joinpath(dst_case, DATA_DIR)

    if !isdir(FULLFUNC_CASE)
        error("Full-function source case not found: $(FULLFUNC_CASE)")
    end
    if !isdir(TEMPLATE_CASE)
        error("Template case not found: $(TEMPLATE_CASE)")
    end

    reset_dir(dst_case)
    cp(joinpath(TEMPLATE_CASE, "raw"), joinpath(dst_case, "raw"); force=true)
    cp(joinpath(TEMPLATE_CASE, "Settings"), joinpath(dst_case, "Settings"); force=true)
    cp(joinpath(TEMPLATE_CASE, DATA_DIR), dst_data; force=true)
    mkpath(joinpath(dst_case, "output"))

    full_data = joinpath(FULLFUNC_CASE, DATA_DIR)
    bus = CSV.read(joinpath(full_data, "busdata.csv"), DataFrame)
    gen = CSV.read(joinpath(full_data, "gendata.csv"), DataFrame)
    flexd = CSV.read(joinpath(full_data, "flexddata.csv"), DataFrame)

    load_ts_full = CSV.read(joinpath(full_data, "load_timeseries_regional.csv"), DataFrame)
    solar_ts_full = CSV.read(joinpath(full_data, "solar_timeseries_regional.csv"), DataFrame)
    wind_ts_full = CSV.read(joinpath(full_data, "wind_timeseries_regional.csv"), DataFrame)
    dr_ts_full = CSV.read(joinpath(full_data, "dr_timeseries_regional.csv"), DataFrame)

    month_mask(df::DataFrame) = Int.(df[!, :Month]) .== month
    load_ts_month = load_ts_full[month_mask(load_ts_full), :]
    solar_ts_month = solar_ts_full[month_mask(solar_ts_full), :]
    wind_ts_month = wind_ts_full[month_mask(wind_ts_full), :]
    dr_ts_month = dr_ts_full[month_mask(dr_ts_full), :]

    old_zone_vec = ["B$(i)" for i in 1:24]
    old_to_new = Dict(z => bus_to_zone(parse(Int, replace(z, "B" => ""))) for z in old_zone_vec)
    old_peak = Dict("B$(Int(bus[r, :Bus_id]))" => Float64(bus[r, Symbol("Demand (MW)")]) for r in 1:nrow(bus))
    load_weights = Dict(z => get(old_peak, z, 1.0) for z in old_zone_vec)

    vre_cap_by_zone = Dict(z => 0.0 for z in old_zone_vec)
    for r in 1:nrow(gen)
        if Int(gen[r, :Flag_VRE]) == 1
            z = "B$(Int(gen[r, :Bus_id]))"
            vre_cap_by_zone[z] += Float64(gen[r, Symbol("Pmax (MW)")])
        end
    end

    dr_cap_by_zone = Dict(z => 0.0 for z in old_zone_vec)
    for r in 1:nrow(flexd)
        z = String(flexd[r, :Zone])
        dr_cap_by_zone[z] += Float64(flexd[r, Symbol("Max Power (MW)")])
    end

    load_scale = 0.55
    load_ts_new = aggregate_timeseries(load_ts_month, old_zone_vec, old_to_new, load_weights, load_scale)
    solar_ts_new = aggregate_timeseries(solar_ts_month, old_zone_vec, old_to_new, vre_cap_by_zone, 1.0)
    wind_ts_new = aggregate_timeseries(wind_ts_month, old_zone_vec, old_to_new, vre_cap_by_zone, 1.0)
    dr_ts_new = aggregate_timeseries(dr_ts_month, old_zone_vec, old_to_new, dr_cap_by_zone, 1.0)

    CSV.write(joinpath(dst_data, "load_timeseries_regional.csv"), load_ts_new)
    CSV.write(joinpath(dst_data, "solar_timeseries_regional.csv"), solar_ts_new)
    CSV.write(joinpath(dst_data, "wind_timeseries_regional.csv"), wind_ts_new)
    CSV.write(joinpath(dst_data, "dr_timeseries_regional.csv"), dr_ts_new)

    settings_path = joinpath(dst_case, "Settings", "HOPE_model_settings.yml")
    cfg = YAML.load_file(settings_path)
    cfg["DataCase"] = "Data_RTS24_PCM_full/"
    open(settings_path, "w") do io
        YAML.write(io, cfg)
    end

    write_case_readme(joinpath(dst_case, "README.md"), month)

    println("Created case: $(dst_case)")
    println("Month: $(month) ($(Dates.monthname(month)))")
    println("Hours: $(nrow(load_ts_new))")
end

main()
