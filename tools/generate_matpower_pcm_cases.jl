using CSV
using DataFrames
using Dates
using Downloads
using Printf

struct CaseSpec
    case_name::String
    data_folder::String
    matpower_name::String
    source_url::String
end

function strip_comment(line::AbstractString)
    idx = findfirst('%', line)
    return idx === nothing ? line : line[1:prevind(line, idx)]
end

function extract_matrix(text::String, key::String)
    rx = Regex("mpc\\." * key * "\\s*=\\s*\\[(.*?)\\];", "s")
    m = match(rx, text)
    if m === nothing
        return nothing
    end
    body = m.captures[1]
    rows = Vector{Vector{Float64}}()
    for raw in split(body, '\n')
        line = strip(strip_comment(raw))
        if isempty(line)
            continue
        end
        line = replace(line, ';' => ' ')
        toks = split(line)
        vals = Float64[]
        for t in toks
            push!(vals, parse(Float64, t))
        end
        if !isempty(vals)
            push!(rows, vals)
        end
    end
    if isempty(rows)
        return nothing
    end
    ncol = maximum(length.(rows))
    mat = fill(NaN, length(rows), ncol)
    for i in eachindex(rows)
        for j in eachindex(rows[i])
            mat[i, j] = rows[i][j]
        end
    end
    return mat
end

function parse_matpower_case(path::AbstractString)
    txt = read(path, String)
    bus = extract_matrix(txt, "bus")
    gen = extract_matrix(txt, "gen")
    branch = extract_matrix(txt, "branch")
    gencost = extract_matrix(txt, "gencost")
    if bus === nothing || gen === nothing || branch === nothing
        error("Failed to parse MATPOWER file: missing bus/gen/branch matrix in $(path)")
    end
    return (bus = bus, gen = gen, branch = branch, gencost = gencost)
end

function infer_linear_costs(gen::Matrix{Float64}, gencost::Union{Nothing, Matrix{Float64}})
    ng = size(gen, 1)
    costs = fill(25.0, ng)
    if gencost === nothing
        return costs
    end
    nrow = size(gencost, 1)
    for g in 1:ng
        if g > nrow
            break
        end
        model = Int(round(gencost[g, 1]))
        ncost = Int(round(gencost[g, 4]))
        coeff_start = 5
        coeff_end = min(size(gencost, 2), coeff_start + ncost - 1)
        if coeff_end < coeff_start
            continue
        end
        coeffs = [gencost[g, j] for j in coeff_start:coeff_end if !isnan(gencost[g, j])]
        if isempty(coeffs)
            continue
        end
        if model == 2
            # Polynomial model: [c_n ... c1 c0], choose linear coefficient c1 when available.
            if length(coeffs) >= 2
                costs[g] = coeffs[end - 1]
            else
                costs[g] = coeffs[1]
            end
        elseif model == 1
            # Piecewise linear model: [x1 y1 x2 y2 ...], estimate first-segment slope.
            if length(coeffs) >= 4 && coeffs[3] != coeffs[1]
                costs[g] = (coeffs[4] - coeffs[2]) / (coeffs[3] - coeffs[1])
            end
        end
    end
    return clamp.(costs, 1.0, 200.0)
end

function make_time_series(zones::Vector{String})
    n_hour = 8760
    t0 = DateTime(2021, 1, 1, 0, 0, 0)
    month = Vector{Int}(undef, n_hour)
    day = Vector{Int}(undef, n_hour)
    period = Vector{Int}(undef, n_hour)
    load_shape = Vector{Float64}(undef, n_hour)
    wind_shape = Vector{Float64}(undef, n_hour)
    solar_shape = Vector{Float64}(undef, n_hour)

    for h in 1:n_hour
        dt = t0 + Hour(h - 1)
        month[h] = Dates.month(dt)
        day[h] = Dates.day(dt)
        hod = Dates.hour(dt) + 1
        period[h] = hod
        doy = dayofyear(dt)
        dow = dayofweek(dt)

        daily = 0.75 + 0.25 * sin(pi * (hod - 6) / 24)^2
        seasonal = 0.95 + 0.08 * cos(2pi * (doy - 15) / 365)
        weekend = dow >= 6 ? 0.96 : 1.0
        load_shape[h] = clamp(daily * seasonal * weekend, 0.55, 1.15)

        wind_daily = 0.08 * cos(2pi * hod / 24)
        wind_season = 0.05 * sin(2pi * (doy - 30) / 365)
        wind_shape[h] = clamp(0.35 + wind_daily + wind_season, 0.05, 0.80)

        if 7 <= hod <= 18
            sun = sin(pi * (hod - 6) / 12)
            sun_season = 0.65 + 0.35 * sin(2pi * (doy - 80) / 365)^2
            solar_shape[h] = clamp(sun * sun_season, 0.0, 1.0)
        else
            solar_shape[h] = 0.0
        end
    end

    load_df = DataFrame("Month" => month, "Day" => day, "Period" => period)
    wind_df = DataFrame("Month" => month, "Day" => day, "Period" => period)
    solar_df = DataFrame("Month" => month, "Day" => day, "Period" => period)

    for (k, z) in enumerate(zones)
        lmul = clamp(0.92 + 0.02 * ((k - 1) % 5), 0.90, 1.04)
        wmul = clamp(0.95 + 0.03 * ((k - 1) % 4), 0.90, 1.04)
        smul = clamp(0.95 + 0.02 * ((k - 1) % 3), 0.90, 1.02)
        load_df[!, z] = load_shape .* lmul
        wind_df[!, z] = wind_shape .* wmul
        solar_df[!, z] = solar_shape .* smul
    end

    load_df[!, "NI"] = zeros(n_hour)
    wind_df[!, "NI"] = zeros(n_hour)
    solar_df[!, "NI"] = zeros(n_hour)
    return (load_df, wind_df, solar_df)
end

function write_settings(case_dir::String, data_folder::String, reference_bus::Int)
    settings_dir = joinpath(case_dir, "Settings")
    mkpath(settings_dir)

    hope_settings = """
DataCase: $(data_folder)/
model_mode: PCM
aggregated!: 0
representative_day!: 0
flexible_demand: 0
clean_energy_policy: 0
carbon_policy: 0
operation_reserve_mode: 0
network_model: 2
reference_bus: $(reference_bus)
inv_dcs_bin: 0
time_periods:
    1 : (3, 20, 6, 20)
    2 : (6, 21, 9, 21)
    3 : (9, 22, 12, 20)
    4 : (12, 21, 3, 19)
unit_commitment: 0
solver: cbc
debug: 0
"""
    open(joinpath(settings_dir, "HOPE_model_settings.yml"), "w") do io
        write(io, hope_settings)
    end

    cbc_settings = """
# CBC Solver Parameters
TimeLimit: 300
logLevel: 1
maxSolutions: -1
maxNodes: -1
allowableGap: 0.001
ratioGap: 0.001
threads: 1
"""
    open(joinpath(settings_dir, "cbc_settings.yml"), "w") do io
        write(io, cbc_settings)
    end

    # Copy other solver templates from an existing PCM case when present.
    template_dir = joinpath(dirname(case_dir), "MD_PCM_Excel_case", "Settings")
    for f in ("clp_settings.yml", "cplex_settings.yml", "gurobi_settings.yml", "highs_settings.yml", "scip_settings.yml")
        src = joinpath(template_dir, f)
        dst = joinpath(settings_dir, f)
        if isfile(src)
            cp(src, dst; force = true)
        end
    end
end

function build_case(spec::CaseSpec, project_root::String)
    case_dir = joinpath(project_root, "ModelCases", spec.case_name)
    data_dir = joinpath(case_dir, spec.data_folder)
    raw_dir = joinpath(case_dir, "raw")
    mkpath(data_dir)
    mkpath(raw_dir)
    mkpath(joinpath(case_dir, "output"))

    mat_path = joinpath(raw_dir, spec.matpower_name * ".m")
    Downloads.download(spec.source_url, mat_path)
    parsed = parse_matpower_case(mat_path)

    bus = parsed.bus
    gen = parsed.gen
    branch = parsed.branch
    gencost = parsed.gencost

    bus_ids = Int.(round.(bus[:, 1]))
    pd = [max(0.0, isnan(bus[i, 3]) ? 0.0 : bus[i, 3]) for i in 1:size(bus, 1)]
    zones = ["B$(b)" for b in bus_ids]
    zone_of = Dict(bus_ids[i] => zones[i] for i in eachindex(bus_ids))

    zonedata = DataFrame(
        "Zone_id" => zones,
        "Demand (MW)" => pd,
        "State" => fill("TS", length(bus_ids)),
    )
    CSV.write(joinpath(data_dir, "zonedata.csv"), zonedata)

    busdata = DataFrame(
        "Bus_id" => bus_ids,
        "Zone_id" => zones,
        "Load_share" => ones(length(bus_ids)),
        "Demand (MW)" => pd,
    )
    CSV.write(joinpath(data_dir, "busdata.csv"), busdata)

    f_bus = Int.(round.(branch[:, 1]))
    t_bus = Int.(round.(branch[:, 2]))
    x = [abs(isnan(branch[i, 4]) ? 0.0 : branch[i, 4]) for i in 1:size(branch, 1)]
    x = [v < 1e-6 ? 0.01 : v for v in x]
    total_load = sum(pd)
    fallback_limit = max(total_load, 100.0)
    rate_a = [isnan(branch[i, 6]) ? 0.0 : branch[i, 6] for i in 1:size(branch, 1)]
    fmax = [v > 0 ? v : fallback_limit for v in rate_a]

    linedata = DataFrame(
        "From_zone" => [zone_of[b] for b in f_bus],
        "To_zone" => [zone_of[b] for b in t_bus],
        "from_bus" => f_bus,
        "to_bus" => t_bus,
        "X" => x,
        "Capacity (MW)" => fmax,
    )
    CSV.write(joinpath(data_dir, "linedata.csv"), linedata)
    CSV.write(joinpath(data_dir, "branchdata.csv"), linedata)

    gen_bus = Int.(round.(gen[:, 1]))
    pmax = [max(1.0, isnan(gen[i, 9]) ? 1.0 : gen[i, 9]) for i in 1:size(gen, 1)]
    pmin = [max(0.0, isnan(gen[i, 10]) ? 0.0 : gen[i, 10]) for i in 1:size(gen, 1)]
    costs = infer_linear_costs(gen, gencost)

    gendata = DataFrame(
        "Pmax (MW)" => pmax,
        "Pmin (MW)" => pmin,
        "Zone" => [zone_of[b] for b in gen_bus],
        "Bus_id" => gen_bus,
        "Type" => fill("NGCC", length(gen_bus)),
        "Flag_thermal" => ones(Int, length(gen_bus)),
        "Flag_RET" => zeros(Int, length(gen_bus)),
        "Flag_VRE" => zeros(Int, length(gen_bus)),
        "Flag_mustrun" => zeros(Int, length(gen_bus)),
        "Cost (\$/MWh)" => costs,
        "EF" => fill(0.40, length(gen_bus)),
        "CC" => fill(1.0, length(gen_bus)),
        "AF" => fill(1.0, length(gen_bus)),
        "FOR" => fill(0.05, length(gen_bus)),
        "RM_SPIN" => fill(0.10, length(gen_bus)),
        "RU" => fill(1.0, length(gen_bus)),
        "RD" => fill(1.0, length(gen_bus)),
        "Flag_UC" => zeros(Int, length(gen_bus)),
        "Min_down_time" => ones(Int, length(gen_bus)),
        "Min_up_time" => ones(Int, length(gen_bus)),
        "Start_up_cost (\$/MW)" => zeros(length(gen_bus)),
    )
    CSV.write(joinpath(data_dir, "gendata.csv"), gendata)

    # Add one storage asset at first load bus (or first bus if all-zero load).
    storage_bus = if any(pd .> 0)
        bus_ids[findfirst(>(0.0), pd)]
    else
        bus_ids[1]
    end
    storage_zone = zone_of[storage_bus]
    e_cap = max(20.0, 0.05 * max(total_load, 100.0))
    p_cap = max(5.0, e_cap / 4.0)
    storagedata = DataFrame(
        "Zone" => [storage_zone],
        "Bus_id" => [storage_bus],
        "Type" => ["BES"],
        "Capacity (MWh)" => [e_cap],
        "Max Power (MW)" => [p_cap],
        "Charging efficiency" => [0.90],
        "Discharging efficiency" => [0.90],
        "Cost (\$/MWh)" => [1.0],
        "EF" => [0.0],
        "CC" => [0.95],
        "Charging Rate" => [1.0],
        "Discharging Rate" => [1.0],
    )
    CSV.write(joinpath(data_dir, "storagedata.csv"), storagedata)

    rpspolicies = DataFrame("From_state" => ["TS"], "To_state" => ["TS"], "RPS" => [0.0])
    CSV.write(joinpath(data_dir, "rpspolicies.csv"), rpspolicies)

    carbonpolicies = DataFrame(
        "State" => fill("TS", 4),
        "Time Period" => collect(1:4),
        "Allowance (tons)" => fill(1.0e9, 4),
    )
    CSV.write(joinpath(data_dir, "carbonpolicies.csv"), carbonpolicies)

    single_parameter = DataFrame(
        "VOLL" => [100000.0],
        "planning_reserve_margin" => [0.02],
        "BigM" => [1.0e13],
        "PT_RPS" => [1.0e10],
        "PT_emis" => [1.0e10],
        "Inv_bugt_gen" => [1.0e16],
        "Inv_bugt_line" => [1.0e16],
        "Inv_bugt_storage" => [1.0e16],
        "alpha_storage_anchor" => [0.5],
        "reg_up_requirement" => [0.0],
        "reg_dn_requirement" => [0.0],
        "spin_requirement" => [0.03],
        "nspin_requirement" => [0.0],
        "delta_reg" => [1.0 / 12.0],
        "delta_spin" => [1.0 / 6.0],
        "delta_nspin" => [0.5],
        "theta_max" => [1000.0],
    )
    CSV.write(joinpath(data_dir, "single_parameter.csv"), single_parameter)

    load_df, wind_df, solar_df = make_time_series(zones)
    CSV.write(joinpath(data_dir, "load_timeseries_regional.csv"), load_df)
    CSV.write(joinpath(data_dir, "wind_timeseries_regional.csv"), wind_df)
    CSV.write(joinpath(data_dir, "solar_timeseries_regional.csv"), solar_df)

    write_settings(case_dir, spec.data_folder, bus_ids[1])

    stamp = Dates.format(now(), dateformat"yyyy-mm-dd HH:MM:SS")
    readme = """
# $(spec.case_name)

Generated from MATPOWER `$(spec.matpower_name).m`.

Source URL:
- $(spec.source_url)

Generation timestamp: $(stamp)

Notes:
- One HOPE zone per bus (`B<bus_id>`)
- Nodal network mode ready (`busdata.csv`, `branchdata.csv`)
- Synthetic 8760 load/wind/solar profiles for PCM smoke/performance testing
- Policies and operation reserve are off by default in settings
"""
    open(joinpath(case_dir, "README.md"), "w") do io
        write(io, readme)
    end

    @printf("Created %s (buses=%d, gens=%d, branches=%d)\n", spec.case_name, size(bus, 1), size(gen, 1), size(branch, 1))
end

function generate_all(project_root::String = joinpath(@__DIR__, ".."))
    specs = [
        CaseSpec(
            "IEEE14_PCM_case",
            "Data_IEEE14_PCM",
            "case14",
            "https://raw.githubusercontent.com/MATPOWER/matpower/master/data/case14.m",
        ),
        CaseSpec(
            "IEEE118_PCM_case",
            "Data_IEEE118_PCM",
            "case118",
            "https://raw.githubusercontent.com/MATPOWER/matpower/master/data/case118.m",
        ),
        CaseSpec(
            "RTS24_PCM_case",
            "Data_RTS24_PCM",
            "case24_ieee_rts",
            "https://raw.githubusercontent.com/MATPOWER/matpower/master/data/case24_ieee_rts.m",
        ),
    ]

    for spec in specs
        build_case(spec, project_root)
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    generate_all()
end
