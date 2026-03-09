using CSV
using DataFrames
using YAML
using Statistics

const SRC_CASE = joinpath("ModelCases", "RTS24_PCM_fullfunc_1month_case")
const DST_CASE = joinpath("ModelCases", "RTS24_PCM_multizone4_congested_1month_case")
const DATA_DIR = "Data_RTS24_PCM_full"
const INTERZONE_CAP_FACTOR = 0.30
const INTERZONE_CAP_MIN = 40.0
const LOAD_SCALE = 0.55

bus_to_zone(bus::Int) = bus <= 6 ? "Z1" : bus <= 12 ? "Z2" : bus <= 18 ? "Z3" : "Z4"
const NEW_ZONES = ["Z1", "Z2", "Z3", "Z4"]

function aggregate_timeseries(
    df::DataFrame,
    old_zones::Vector{String},
    old_to_new::Dict{String,String},
    weights_old::Dict{String,Float64},
    load_scale::Float64 = 1.0,
)
    out = select(df, 1:3)
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

function main()
    if !isdir(SRC_CASE)
        error("Source case not found: $(SRC_CASE)")
    end
    if isdir(DST_CASE)
        try
            rm(DST_CASE; force=true, recursive=true)
        catch
            backup = DST_CASE * "_backup_" * string(round(Int, time()))
            mv(DST_CASE, backup)
            println("Warning: target case folder locked; moved existing folder to $(backup)")
        end
    end
    cp(SRC_CASE, DST_CASE; force=true)

    data_path = joinpath(DST_CASE, DATA_DIR)
    bus_path = joinpath(data_path, "busdata.csv")
    zone_path = joinpath(data_path, "zonedata.csv")
    gen_path = joinpath(data_path, "gendata.csv")
    sto_path = joinpath(data_path, "storagedata.csv")
    line_path = joinpath(data_path, "linedata.csv")
    branch_path = joinpath(data_path, "branchdata.csv")
    load_path = joinpath(data_path, "load_timeseries_regional.csv")
    solar_path = joinpath(data_path, "solar_timeseries_regional.csv")
    wind_path = joinpath(data_path, "wind_timeseries_regional.csv")
    flexd_path = joinpath(data_path, "flexddata.csv")
    dr_ts_path = joinpath(data_path, "dr_timeseries_regional.csv")

    bus = CSV.read(bus_path, DataFrame)
    zone = CSV.read(zone_path, DataFrame)
    gen = CSV.read(gen_path, DataFrame)
    sto = CSV.read(sto_path, DataFrame)
    line = CSV.read(line_path, DataFrame)
    branch = CSV.read(branch_path, DataFrame)
    load_ts = CSV.read(load_path, DataFrame)
    solar_ts = CSV.read(solar_path, DataFrame)
    wind_ts = CSV.read(wind_path, DataFrame)
    flexd = CSV.read(flexd_path, DataFrame)
    flexd_old = deepcopy(flexd)
    dr_ts = CSV.read(dr_ts_path, DataFrame)

    old_zone_vec = String.(zone[!, :Zone_id])
    old_bus_zone = Dict(Int(bus[r, :Bus_id]) => String(bus[r, :Zone_id]) for r in 1:nrow(bus))
    old_to_new = Dict(z => bus_to_zone(parse(Int, replace(z, "B" => ""))) for z in old_zone_vec)
    bus_id_to_new = Dict(Int(bus[r, :Bus_id]) => bus_to_zone(Int(bus[r, :Bus_id])) for r in 1:nrow(bus))

    # 1) busdata: keep all buses, map each bus into one of 4 zones.
    bus[!, :Zone_id] = [bus_id_to_new[Int(b)] for b in bus[!, :Bus_id]]
    # Use demand as load-share basis; model/output normalize shares within each zone.
    bus[!, Symbol("Load_share")] = Float64.(bus[!, Symbol("Demand (MW)")])
    CSV.write(bus_path, bus)

    # 2) zonedata: aggregate demand from original buses/zones into Z1..Z4.
    new_zone = DataFrame(Zone_id=String[], State=String[])
    new_zone[!, Symbol("Demand (MW)")] = Float64[]
    old_peak = Dict(String(zone[r, :Zone_id]) => Float64(zone[r, Symbol("Demand (MW)")]) for r in 1:nrow(zone))
    for z in NEW_ZONES
        members = [b for b in keys(old_bus_zone) if bus_id_to_new[b] == z]
        demand_sum = sum(Float64(bus[findfirst(==(b), bus[!, :Bus_id]), Symbol("Demand (MW)")]) for b in members)
        push!(new_zone, (z, "TS", demand_sum))
    end
    select!(new_zone, :Zone_id, Symbol("Demand (MW)"), :State)
    CSV.write(zone_path, new_zone)

    # 3) gendata/storagedata/flexddata: remap zone by bus mapping.
    gen[!, :Zone] = [bus_id_to_new[Int(b)] for b in gen[!, :Bus_id]]
    CSV.write(gen_path, gen)

    sto[!, :Zone] = [bus_id_to_new[Int(b)] for b in sto[!, :Bus_id]]
    CSV.write(sto_path, sto)

    flexd[!, :Zone] = [old_to_new[String(z)] for z in flexd[!, :Zone]]
    flexd_agg = combine(groupby(flexd, [:Zone, :Type]),
        Symbol("Max Power (MW)") => sum => Symbol("Max Power (MW)"),
        Symbol("Cost (\$/MW)") => (x -> mean(Float64.(x))) => Symbol("Cost (\$/MW)"),
    )
    CSV.write(flexd_path, flexd_agg)

    # 4) Linedata/branchdata: keep nodal topology, but map endpoint zones and tighten inter-zone transfer limits.
    for df in (line, branch)
        df[!, :From_zone] = [bus_id_to_new[Int(b)] for b in df[!, :from_bus]]
        df[!, :To_zone] = [bus_id_to_new[Int(b)] for b in df[!, :to_bus]]
        for r in 1:nrow(df)
            if df[r, :From_zone] != df[r, :To_zone]
                base_cap = Float64(df[r, Symbol("Capacity (MW)")])
                df[r, Symbol("Capacity (MW)")] = max(INTERZONE_CAP_MIN, INTERZONE_CAP_FACTOR * base_cap)
            end
        end
    end
    CSV.write(line_path, line)
    CSV.write(branch_path, branch)

    # 5) Aggregate timeseries from 24 zone columns to 4 zone columns.
    # Load profile: peak-demand-weighted average by original zone.
    load_weights = Dict(z => get(old_peak, z, 1.0) for z in old_zone_vec)
    load_ts_new = aggregate_timeseries(load_ts, old_zone_vec, old_to_new, load_weights, LOAD_SCALE)
    CSV.write(load_path, load_ts_new)

    # VRE availability profile: VRE-capacity-weighted average by original zone.
    vre_cap_by_zone = Dict(z => 0.0 for z in old_zone_vec)
    for r in 1:nrow(gen)
        if Int(gen[r, :Flag_VRE]) == 1
            # Map back to original zone via bus-id to avoid using remapped zone.
            old_z = old_bus_zone[Int(gen[r, :Bus_id])]
            vre_cap_by_zone[old_z] += Float64(gen[r, Symbol("Pmax (MW)")])
        end
    end
    solar_ts_new = aggregate_timeseries(solar_ts, old_zone_vec, old_to_new, vre_cap_by_zone, 1.0)
    wind_ts_new = aggregate_timeseries(wind_ts, old_zone_vec, old_to_new, vre_cap_by_zone, 1.0)
    CSV.write(solar_path, solar_ts_new)
    CSV.write(wind_path, wind_ts_new)

    # DR profile: DR-capacity-weighted average by original zone.
    dr_cap_by_zone = Dict(z => 0.0 for z in old_zone_vec)
    for r in 1:nrow(flexd_old)
        z = String(flexd_old[r, :Zone])
        if haskey(dr_cap_by_zone, z)
            dr_cap_by_zone[z] += Float64(flexd_old[r, Symbol("Max Power (MW)")])
        end
    end
    dr_ts_new = aggregate_timeseries(dr_ts, old_zone_vec, old_to_new, dr_cap_by_zone, 1.0)
    CSV.write(dr_ts_path, dr_ts_new)

    # 6) Case settings tuned for congestion diagnostics.
    settings_path = joinpath(DST_CASE, "Settings", "HOPE_model_settings.yml")
    cfg = YAML.load(open(settings_path))
    cfg["model_mode"] = "PCM"
    cfg["network_model"] = 3
    cfg["unit_commitment"] = 0
    cfg["write_shadow_prices"] = 0
    cfg["operation_reserve_mode"] = 0
    cfg["clean_energy_policy"] = 0
    cfg["carbon_policy"] = 0
    cfg["solver"] = "gurobi"
    open(settings_path, "w") do io
        YAML.write(io, cfg)
    end

    println("Created: $(DST_CASE)")
    println("Buses: $(nrow(bus)); Zones: $(length(NEW_ZONES)); Network model: 3 (PTDF)")
    println("Use this case for nodal-vs-zonal LMP and congestion diagnostics.")
end

main()
