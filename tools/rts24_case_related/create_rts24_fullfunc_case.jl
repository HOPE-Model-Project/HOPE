using CSV
using DataFrames
using Dates

const SRC_CASE = joinpath("ModelCases", "RTS24_PCM_case")
const DST_CASE = joinpath("ModelCases", "RTS24_PCM_fullfunc_case")
const SRC_DATA = joinpath(SRC_CASE, "Data_RTS24_PCM")
const DST_DATA = joinpath(DST_CASE, "Data_RTS24_PCM_full")

function reset_dir(path::AbstractString)
    if isdir(path)
        rm(path; force = true, recursive = true)
    end
    mkpath(path)
end

function copy_tree(src::AbstractString, dst::AbstractString)
    if isdir(dst)
        rm(dst; force = true, recursive = true)
    end
    cp(src, dst; force = true)
end

function build_generator_mix!(gendata::DataFrame)
    wind_buses = Set([7, 8, 9, 10, 11, 12])
    solar_buses = Set([13, 14, 15, 16, 17, 18])
    coal_buses = Set([1, 2, 3, 4])
    ngct_buses = Set([5, 6])
    hydro_buses = Set([22, 23, 24])

    if !("RM_REG_UP" in names(gendata))
        gendata[!, "RM_REG_UP"] = gendata[:, "RM_SPIN"]
    end
    if !("RM_REG_DN" in names(gendata))
        gendata[!, "RM_REG_DN"] = gendata[:, "RM_SPIN"]
    end
    if !("RM_NSPIN" in names(gendata))
        gendata[!, "RM_NSPIN"] = gendata[:, "RM_SPIN"]
    end

    for r in 1:nrow(gendata)
        bus = Int(round(gendata[r, "Bus_id"]))
        pmax = Float64(gendata[r, "Pmax (MW)"])

        if bus in wind_buses
            gendata[r, "Type"] = "WindOn"
            gendata[r, "Flag_thermal"] = 0
            gendata[r, "Flag_VRE"] = 1
            gendata[r, "Flag_UC"] = 0
            gendata[r, "Pmin (MW)"] = 0.0
            gendata[r, "Cost (\$/MWh)"] = 5.0
            gendata[r, "EF"] = 0.0
            gendata[r, "FOR"] = 0.08
            gendata[r, "RM_SPIN"] = 0.0
            gendata[r, "RM_REG_UP"] = 0.0
            gendata[r, "RM_REG_DN"] = 0.0
            gendata[r, "RM_NSPIN"] = 0.0
        elseif bus in solar_buses
            gendata[r, "Type"] = "SolarPV"
            gendata[r, "Flag_thermal"] = 0
            gendata[r, "Flag_VRE"] = 1
            gendata[r, "Flag_UC"] = 0
            gendata[r, "Pmin (MW)"] = 0.0
            gendata[r, "Cost (\$/MWh)"] = 4.0
            gendata[r, "EF"] = 0.0
            gendata[r, "FOR"] = 0.05
            gendata[r, "RM_SPIN"] = 0.0
            gendata[r, "RM_REG_UP"] = 0.0
            gendata[r, "RM_REG_DN"] = 0.0
            gendata[r, "RM_NSPIN"] = 0.0
        elseif bus in coal_buses
            gendata[r, "Type"] = "Coal"
            gendata[r, "Flag_thermal"] = 1
            gendata[r, "Flag_VRE"] = 0
            gendata[r, "Flag_UC"] = 1
            gendata[r, "Pmin (MW)"] = max(Float64(gendata[r, "Pmin (MW)"]), 0.25 * pmax)
            gendata[r, "Cost (\$/MWh)"] = 35.0
            gendata[r, "EF"] = 0.95
            gendata[r, "FOR"] = 0.08
            gendata[r, "RU"] = 0.40
            gendata[r, "RD"] = 0.40
            gendata[r, "RM_SPIN"] = 0.10
            gendata[r, "RM_REG_UP"] = 0.08
            gendata[r, "RM_REG_DN"] = 0.08
            gendata[r, "RM_NSPIN"] = 0.10
            gendata[r, "Min_up_time"] = 6
            gendata[r, "Min_down_time"] = 6
            gendata[r, "Start_up_cost (\$/MW)"] = 12.0
        elseif bus in ngct_buses
            gendata[r, "Type"] = "NGCT"
            gendata[r, "Flag_thermal"] = 1
            gendata[r, "Flag_VRE"] = 0
            gendata[r, "Flag_UC"] = 1
            gendata[r, "Pmin (MW)"] = max(Float64(gendata[r, "Pmin (MW)"]), 0.10 * pmax)
            gendata[r, "Cost (\$/MWh)"] = 65.0
            gendata[r, "EF"] = 0.60
            gendata[r, "FOR"] = 0.06
            gendata[r, "RU"] = 1.20
            gendata[r, "RD"] = 1.20
            gendata[r, "RM_SPIN"] = 0.20
            gendata[r, "RM_REG_UP"] = 0.15
            gendata[r, "RM_REG_DN"] = 0.15
            gendata[r, "RM_NSPIN"] = 0.20
            gendata[r, "Min_up_time"] = 2
            gendata[r, "Min_down_time"] = 2
            gendata[r, "Start_up_cost (\$/MW)"] = 6.0
        elseif bus in hydro_buses
            gendata[r, "Type"] = "Hydro"
            gendata[r, "Flag_thermal"] = 0
            gendata[r, "Flag_VRE"] = 0
            gendata[r, "Flag_UC"] = 0
            gendata[r, "Pmin (MW)"] = 0.0
            gendata[r, "Cost (\$/MWh)"] = 12.0
            gendata[r, "EF"] = 0.0
            gendata[r, "FOR"] = 0.03
            gendata[r, "RM_SPIN"] = 0.0
            gendata[r, "RM_REG_UP"] = 0.0
            gendata[r, "RM_REG_DN"] = 0.0
            gendata[r, "RM_NSPIN"] = 0.0
        else
            gendata[r, "Type"] = "NGCC"
            gendata[r, "Flag_thermal"] = 1
            gendata[r, "Flag_VRE"] = 0
            gendata[r, "Flag_UC"] = 1
            gendata[r, "Pmin (MW)"] = max(Float64(gendata[r, "Pmin (MW)"]), 0.15 * pmax)
            gendata[r, "Cost (\$/MWh)"] = 25.0
            gendata[r, "EF"] = 0.40
            gendata[r, "FOR"] = 0.05
            gendata[r, "RU"] = 0.90
            gendata[r, "RD"] = 0.90
            gendata[r, "RM_SPIN"] = 0.15
            gendata[r, "RM_REG_UP"] = 0.12
            gendata[r, "RM_REG_DN"] = 0.12
            gendata[r, "RM_NSPIN"] = 0.15
            gendata[r, "Min_up_time"] = 3
            gendata[r, "Min_down_time"] = 3
            gendata[r, "Start_up_cost (\$/MW)"] = 8.0
        end
    end
end

function expand_storage(storagedata::DataFrame, zones::Vector{String})
    st = deepcopy(storagedata)
    zones_target = ["B1", "B6", "B12", "B18", "B24"]
    buses_target = [1, 6, 12, 18, 24]
    ecap = [160.0, 120.0, 140.0, 110.0, 100.0]
    pcap = [40.0, 30.0, 35.0, 27.5, 25.0]
    for (z, b, e, p) in zip(zones_target, buses_target, ecap, pcap)
        if !(z in zones)
            continue
        end
        push!(st, (
            z,
            b,
            "BES",
            e,
            p,
            0.90,
            0.90,
            1.0,
            0.0,
            0.95,
            1.0,
            1.0,
        ))
    end
    unique!(st, [:Zone, :Bus_id, :Type])
    return st
end

function build_dr_inputs(loaddata::DataFrame, zonedata::DataFrame)
    zones = Vector{String}(zonedata[:, "Zone_id"])
    n_hour = nrow(loaddata)
    month = loaddata[:, "Month"]
    day = loaddata[:, "Day"]
    time_period = if "Time Period" in names(loaddata)
        loaddata[:, "Time Period"]
    else
        ones(Int, n_hour)
    end
    hour = if "Hour" in names(loaddata)
        loaddata[:, "Hour"]
    elseif "Hours" in names(loaddata)
        loaddata[:, "Hours"]
    elseif "Period" in names(loaddata)
        loaddata[:, "Period"]
    else
        [(h - 1) % 24 + 1 for h in 1:n_hour]
    end

    dr_ts = DataFrame("Time Period" => Int.(time_period), "Month" => month, "Day" => day, "Hours" => Int.(hour))
    for z in zones
        base = Float64.(loaddata[:, z])
        den = max(maximum(base), 1.0e-6)
        shape = clamp.(0.30 .+ 0.55 .* (base ./ den), 0.20, 0.95)
        dr_ts[:, z] = shape
    end
    dr_ts[:, "NI"] = zeros(n_hour)

    dr_data = DataFrame(
        "Zone" => zones,
        "Type" => fill("DRShift", length(zones)),
        "Max Power (MW)" => [max(3.0, 0.12 * Float64(zonedata[i, "Demand (MW)"])) for i in 1:nrow(zonedata)],
        "Cost (\$/MW)" => fill(18.0, length(zones)),
    )

    return dr_data, dr_ts
end

function write_settings(path::AbstractString)
    txt = """
DataCase: Data_RTS24_PCM_full/
model_mode: PCM
resource_aggregation: 0
endogenous_rep_day: 0
external_rep_day: 0
flexible_demand: 1
clean_energy_policy: 1
carbon_policy: 0
operation_reserve_mode: 2
network_model: 3
reference_bus: 1
inv_dcs_bin: 0
time_periods:
    1 : (3, 20, 6, 20)
    2 : (6, 21, 9, 21)
    3 : (9, 22, 12, 20)
    4 : (12, 21, 3, 19)
unit_commitment: 2
solver: gurobi
debug: 0
"""
    open(path, "w") do io
        write(io, txt)
    end
end

function build_case()
    if !isdir(SRC_CASE)
        error("Source case not found: $(SRC_CASE)")
    end

    reset_dir(DST_CASE)
    copy_tree(joinpath(SRC_CASE, "raw"), joinpath(DST_CASE, "raw"))
    copy_tree(joinpath(SRC_CASE, "Settings"), joinpath(DST_CASE, "Settings"))
    copy_tree(SRC_DATA, DST_DATA)
    mkpath(joinpath(DST_CASE, "output"))

    gendata = CSV.read(joinpath(DST_DATA, "gendata.csv"), DataFrame)
    zonedata = CSV.read(joinpath(DST_DATA, "zonedata.csv"), DataFrame)
    storagedata = CSV.read(joinpath(DST_DATA, "storagedata.csv"), DataFrame)
    loaddata = CSV.read(joinpath(DST_DATA, "load_timeseries_regional.csv"), DataFrame)
    singlepar = CSV.read(joinpath(DST_DATA, "single_parameter.csv"), DataFrame)
    rps = CSV.read(joinpath(DST_DATA, "rpspolicies.csv"), DataFrame)

    build_generator_mix!(gendata)
    storagedata2 = expand_storage(storagedata, Vector{String}(zonedata[:, "Zone_id"]))
    dr_data, dr_ts = build_dr_inputs(loaddata, zonedata)

    singlepar[1, "reg_up_requirement"] = 0.01
    singlepar[1, "reg_dn_requirement"] = 0.01
    singlepar[1, "spin_requirement"] = 0.03
    singlepar[1, "nspin_requirement"] = 0.02
    singlepar[1, "delta_reg"] = 1.0 / 12.0
    singlepar[1, "delta_spin"] = 1.0 / 6.0
    singlepar[1, "delta_nspin"] = 0.5
    rps[:, "RPS"] .= 0.35

    CSV.write(joinpath(DST_DATA, "gendata.csv"), gendata)
    CSV.write(joinpath(DST_DATA, "storagedata.csv"), storagedata2)
    CSV.write(joinpath(DST_DATA, "single_parameter.csv"), singlepar)
    CSV.write(joinpath(DST_DATA, "rpspolicies.csv"), rps)
    CSV.write(joinpath(DST_DATA, "flexddata.csv"), dr_data)
    CSV.write(joinpath(DST_DATA, "dr_timeseries_regional.csv"), dr_ts)

    write_settings(joinpath(DST_CASE, "Settings", "HOPE_model_settings.yml"))

    stamp = Dates.format(now(), dateformat"yyyy-mm-dd HH:MM:SS")
    readme = """
# RTS24_PCM_fullfunc_case

Derived from `RTS24_PCM_case` and upgraded for full PCM nodal feature testing.

Created: $(stamp)

Key upgrades:
- Mixed generator fleet (Coal / NGCC / NGCT / Hydro / WindOn / SolarPV)
- Expanded storage fleet across multiple buses
- Added DR inputs (`flexddata.csv`, `dr_timeseries_regional.csv`)
- Enabled nodal PTDF network mode (`network_model: 3`)
- Enabled UC, operating reserves, DR, and RPS switch for workflow testing
"""
    open(joinpath(DST_CASE, "README.md"), "w") do io
        write(io, readme)
    end

    println("Created $(DST_CASE)")
    println("Data folder: $(DST_DATA)")
    println("Generator type counts:")
    println(combine(groupby(gendata, :Type), nrow => :N))
    println("Storage count: $(nrow(storagedata2))")
    println("DR rows: $(nrow(dr_data)), DR hours: $(nrow(dr_ts))")
end

if abspath(PROGRAM_FILE) == @__FILE__
    build_case()
end
