using CSV
using DataFrames
using YAML
using Statistics

const SRC_ROOT = joinpath("ModelCases", "USA_64zone", "Parameter_527")
const DST_CASE = joinpath("ModelCases", "USA_64zone_GTEP_case")
const DST_DATA = joinpath(DST_CASE, "Data_USA64_GTEP")
const DST_SETTINGS = joinpath(DST_CASE, "Settings")

tofloat(x, d=0.0) = ismissing(x) || x === nothing || string(x) == "" ? d : parse(Float64, string(x))
toint(x, d=0) = ismissing(x) || x === nothing || string(x) == "" ? d : parse(Int, string(x))

function normalize_zone_id(z)
    if z isa Number
        return "z$(Int(z))"
    end
    zs = strip(string(z))
    if startswith(lowercase(zs), "z")
        return "z$(parse(Int, replace(lowercase(zs), "z" => "")))"
    end
    return "z$(parse(Int, zs))"
end

function filldown!(df::DataFrame, col::Symbol)
    lastv = missing
    for r in 1:nrow(df)
        v = df[r, col]
        if ismissing(v) || string(v) == ""
            df[r, col] = lastv
        else
            lastv = v
        end
    end
    return df
end

function map_gen_type(resource::AbstractString, resource_type::AbstractString, therm::Int, vre::Int, stor::Int)
    r = lowercase(resource)
    rt = lowercase(resource_type)
    if stor == 1
        if occursin("pump", r) || occursin("pump", rt)
            return "PHS"
        end
        return "Battery"
    end
    if vre == 1
        if occursin("offshore", r)
            return "WindOff"
        elseif occursin("wind", r)
            return "WindOn"
        else
            return "SolarPV"
        end
    end
    if occursin("nuclear", r) || occursin("nuclear", rt)
        return "NuC"
    elseif occursin("coal", r) || occursin("coal", rt)
        return "Coal"
    elseif occursin("combined_cycle", r) || occursin("combined cycle", rt)
        return "NGCC"
    elseif occursin("combustion_turbine", r) || occursin("combustion turbine", rt)
        return "NGCT"
    elseif occursin("hydro", r) || occursin("hydro", rt)
        return "Hydro"
    elseif therm == 1
        return "Thermal"
    else
        return "Other"
    end
end

function fuel_ef(fuel::AbstractString)
    f = lowercase(fuel)
    if occursin("coal", f)
        return 0.95
    elseif occursin("naturalgas", f)
        return 0.40
    else
        return 0.0
    end
end

function parse_line_endpoints(row, zcols::Vector{Symbol})
    from_zone = nothing
    to_zone = nothing
    for zc in zcols
        v = tofloat(row[zc], 0.0)
        if v < -1e-9
            from_zone = string(zc)
        elseif v > 1e-9
            to_zone = string(zc)
        end
    end
    if isnothing(from_zone) || isnothing(to_zone)
        error("Cannot parse line endpoints for line row $(row[:Network_Lines]).")
    end
    return (from_zone, to_zone)
end

function map_rps_flag(resource::AbstractString, resource_type::AbstractString, vre::Int)
    if vre == 1
        return 1
    end
    s = lowercase(resource * " " * resource_type)
    return occursin("hydro", s) ? 1 : 0
end

function is_ngcc_like(resource::AbstractString, resource_type::AbstractString)
    s = lowercase(resource * " " * resource_type)
    return occursin("combined_cycle", s) || occursin("ccavgcf", s)
end

function row_cap_credit(row, zone_idx::Int)
    col = Symbol("CapRes_$(zone_idx)")
    if col in propertynames(row)
        return max(tofloat(row[col], 0.0), 0.0)
    end
    return 0.0
end

function build_zone_state_map(gen::DataFrame)
    out = Dict{Int,String}()
    for z in sort(unique(Int.(gen[!, :Zone])))
        rows = gen[Int.(gen[!, :Zone]) .== z, :]
        s = ""
        if "Transmission Region" in names(rows)
            vals = unique(string.(rows[!, Symbol("Transmission Region")]))
            vals = filter(x -> x != "" && lowercase(x) != "missing", vals)
            if !isempty(vals)
                s = vals[1]
            end
        end
        if isempty(s) && "region" in names(rows)
            vals = unique(string.(rows[!, :region]))
            vals = filter(x -> x != "" && lowercase(x) != "missing", vals)
            if !isempty(vals)
                s = vals[1]
            end
        end
        out[z] = isempty(s) ? "Region$(z)" : s
    end
    return out
end

function main()
    if !isdir(SRC_ROOT)
        error("Source folder not found: $(SRC_ROOT)")
    end

    if !isdir(DST_CASE)
        mkpath(DST_CASE)
    end
    mkpath(DST_DATA)
    mkpath(DST_SETTINGS)

    gen = CSV.read(joinpath(SRC_ROOT, "Generators_data.csv"), DataFrame)
    net = CSV.read(joinpath(SRC_ROOT, "Network.csv"), DataFrame)
    load_tdr = CSV.read(joinpath(SRC_ROOT, "TDR_Results", "Load_data.csv"), DataFrame)
    gen_var = CSV.read(joinpath(SRC_ROOT, "TDR_Results", "Generators_variability.csv"), DataFrame)
    fuels = CSV.read(joinpath(SRC_ROOT, "TDR_Results", "Fuels_data.csv"), DataFrame)
    capres = CSV.read(joinpath(SRC_ROOT, "Capacity_reserve_margin.csv"), DataFrame)

    filldown!(load_tdr, :Rep_Periods)
    filldown!(load_tdr, Symbol("Timesteps_per_Rep_Period"))

    # GenX TDR load format in this dataset stores Sub_Weights in the first T rows.
    rep_weight_hours_vec = Float64[]
    for r in 1:nrow(load_tdr)
        v = load_tdr[r, :Sub_Weights]
        if !(ismissing(v) || string(v) == "")
            push!(rep_weight_hours_vec, tofloat(v, 0.0))
        end
    end
    n_rep = length(rep_weight_hours_vec)
    rep_periods = collect(1:n_rep)
    expected_rows = 24 * n_rep
    if nrow(load_tdr) != expected_rows
        error("Expected 24*T rows in TDR load data. Got $(nrow(load_tdr)) vs expected $expected_rows.")
    end
    if nrow(gen_var) != expected_rows
        error("Generator variability rows $(nrow(gen_var)) do not match load rows $expected_rows.")
    end

    rep_weight_hours = Dict{Int,Float64}(t => rep_weight_hours_vec[t] for t in rep_periods)
    rep_weights = DataFrame("Time Period" => rep_periods, "Weight" => [rep_weight_hours[t] / 24.0 for t in rep_periods])
    CSV.write(joinpath(DST_DATA, "rep_period_weights.csv"), rep_weights)

    zone_ids = ["z$(i)" for i in 1:64]
    zone_state = build_zone_state_map(gen)

    peak_by_zone = Dict{Int,Float64}()
    for z in 1:64
        col = Symbol("Load_MW_z$(z)")
        peak_by_zone[z] = maximum(Float64.(load_tdr[!, col]))
        if peak_by_zone[z] <= 0
            peak_by_zone[z] = 1.0
        end
    end

    zonal_prm = Dict{Int,Float64}()
    for z in 1:64
        rows = capres[Int.(capres[!, :Network_zones]) .== z, :]
        if nrow(rows) == 0
            zonal_prm[z] = 0.15
        else
            zonal_prm[z] = max(tofloat(rows[1, Symbol("CapRes_$(z)")], 0.15), 0.0)
        end
    end

    # Use zone-level policy surface by default: each zone is its own "State" in HOPE inputs.
    zonedata = DataFrame(
        "Zone_id" => zone_ids,
        "Demand (MW)" => [peak_by_zone[z] for z in 1:64],
        "State" => copy(zone_ids),
        "Zonal PRM" => [zonal_prm[z] for z in 1:64],
    )
    CSV.write(joinpath(DST_DATA, "zonedata.csv"), zonedata)

    tp_col = Vector{Int}(undef, expected_rows)
    month_col = Vector{Int}(undef, expected_rows)
    day_col = Vector{Int}(undef, expected_rows)
    hour_col = Vector{Int}(undef, expected_rows)
    for r in 1:expected_rows
        t = Int(ceil(r / 24))
        h = ((r - 1) % 24) + 1
        tp_col[r] = t
        month_col[r] = 1
        day_col[r] = t
        hour_col[r] = h
    end

    load_out = DataFrame("Time Period" => tp_col, "Month" => month_col, "Day" => day_col, "Hours" => hour_col)
    for z in 1:64
        mw_col = Symbol("Load_MW_z$(z)")
        load_out[!, Symbol("z$(z)")] = Float64.(load_tdr[!, mw_col]) ./ peak_by_zone[z]
    end
    load_out[!, :NI] = zeros(Float64, expected_rows)
    CSV.write(joinpath(DST_DATA, "load_timeseries_regional.csv"), load_out)

    fuels_use = fuels[toint.(fuels[!, :Time_Index], 0) .> 0, :]
    if nrow(fuels_use) != expected_rows
        error("Fuels_data rows with Time_Index>0 ($(nrow(fuels_use))) must match expected rows ($expected_rows).")
    end
    hour_weights = Vector{Float64}(undef, expected_rows)
    for r in 1:expected_rows
        t = Int(ceil(r / 24))
        hour_weights[r] = rep_weight_hours[t] / 24.0
    end
    fuel_avg = Dict{String,Float64}()
    for nm in names(fuels_use)
        snm = string(nm)
        if snm == "Time_Index" || snm == "None"
            continue
        end
        vals = Float64.(fuels_use[!, nm])
        fuel_avg[snm] = sum(vals .* hour_weights) / sum(hour_weights)
    end

    function gen_var_cost(row)
        v_om = tofloat(row[:Var_OM_Cost_per_MWh], 0.0)
        hr = tofloat(row[:Heat_Rate_MMBTU_per_MWh], 0.0)
        fuel = string(row[:Fuel])
        if fuel == "None" || !haskey(fuel_avg, fuel)
            return v_om
        end
        return v_om + hr * fuel_avg[fuel]
    end

    existing_gen = DataFrame(
        "Pmax (MW)" => Float64[],
        "Pmin (MW)" => Float64[],
        "Type" => String[],
        "Zone" => String[],
        "Flag_thermal" => Int[],
        "Flag_RET" => Int[],
        "Flag_VRE" => Int[],
        "Flag_mustrun" => Int[],
        "Cost (\$/MWh)" => Float64[],
        "EF" => Float64[],
        "CC" => Float64[],
        "AF" => Float64[],
        "Flag_RPS" => Int[],
    )
    candidate_gen = DataFrame(
        "Zone" => String[],
        "Pmax (MW)" => Float64[],
        "Pmin (MW)" => Float64[],
        "Cost (\$/MW/yr)" => Float64[],
        "Cost (\$/MWh)" => Float64[],
        "Type" => String[],
        "Flag_thermal" => Int[],
        "Flag_VRE" => Int[],
        "Flag_mustrun" => Int[],
        "EF" => Float64[],
        "CC" => Float64[],
        "AF" => Float64[],
        "Flag_RPS" => Int[],
    )
    gen_names_existing = String[]
    gen_names_candidate = String[]
    ngcc_existing_template = NamedTuple[]
    ngcc_inv_by_zone = Dict{Int,Float64}()
    ngcc_cap_by_zone = Dict{Int,Float64}()
    ngcc_inv_values = Float64[]

    for r in eachrow(gen)
        zone_int = toint(r[:Zone], 0)
        if zone_int < 1 || zone_int > 64
            continue
        end
        zone = "z$(zone_int)"
        therm = toint(r[:THERM], 0)
        vre = toint(r[:VRE], 0)
        stor = toint(r[:STOR], 0)
        mustrun = toint(r[:MUST_RUN], 0)
        new_build = toint(r[:New_Build], 0)
        resource = string(r[:Resource])
        rtype = string(r[:Resource_Type])
        gtype = map_gen_type(resource, rtype, therm, vre, stor)
        ngcc_like = is_ngcc_like(resource, rtype)
        cc = row_cap_credit(r, zone_int)
        ef = fuel_ef(string(r[:Fuel]))
        pmin_frac = clamp(tofloat(r[:Min_Power], 0.0), 0.0, 1.0)
        rps_flag = map_rps_flag(resource, rtype, vre)

        if stor == 0
            pmax_exist = max(tofloat(r[:Existing_Cap_MW], 0.0), 0.0)
            if pmax_exist > 0 && new_build != 1
                push!(existing_gen, (
                    pmax_exist,
                    pmin_frac * pmax_exist,
                    gtype,
                    zone,
                    therm,
                    0,
                    vre,
                    mustrun,
                    gen_var_cost(r),
                    ef,
                    cc,
                    1.0,
                    rps_flag,
                ))
                push!(gen_names_existing, resource)
                if ngcc_like
                    push!(ngcc_existing_template, (
                        heat_rate = tofloat(r[:Heat_Rate_MMBTU_per_MWh], 1.0e9),
                        var_cost = gen_var_cost(r),
                        pmin_frac = pmin_frac,
                        cc = cc,
                    ))
                end
            end

            pmax_new = max(tofloat(r[:Max_Cap_MW], 0.0), 0.0)
            if new_build == 1 && pmax_new > 0
                push!(candidate_gen, (
                    zone,
                    pmax_new,
                    pmin_frac * pmax_new,
                    tofloat(r[:Inv_Cost_per_MWyr], 0.0),
                    gen_var_cost(r),
                    gtype,
                    therm,
                    vre,
                    mustrun,
                    ef,
                    cc,
                    1.0,
                    rps_flag,
                ))
                push!(gen_names_candidate, resource)
            end
            if new_build == 1 && ngcc_like
                pmax_ngcc = tofloat(r[:Max_Cap_MW], 0.0)
                if pmax_ngcc < 0
                    pmax_ngcc = peak_by_zone[zone_int]
                else
                    pmax_ngcc = max(pmax_ngcc, 0.0)
                end
                ngcc_cap_by_zone[zone_int] = max(get(ngcc_cap_by_zone, zone_int, 0.0), pmax_ngcc)
                inv_ngcc = tofloat(r[:Inv_Cost_per_MWyr], 0.0)
                if inv_ngcc > 0
                    ngcc_inv_by_zone[zone_int] = inv_ngcc
                    push!(ngcc_inv_values, inv_ngcc)
                end
            end
        end
    end

    if !isempty(ngcc_existing_template)
        template_sorted = sort(ngcc_existing_template, by = x -> (x.heat_rate, x.var_cost))
        best_ngcc = first(template_sorted)
        ngcc_inv_default = isempty(ngcc_inv_values) ? 85000.0 : median(ngcc_inv_values)
        for z in 1:64
            zone = "z$(z)"
            pmax_new = get(ngcc_cap_by_zone, z, max(300.0, 0.5 * peak_by_zone[z]))
            if pmax_new <= 0
                continue
            end
            inv_new = get(ngcc_inv_by_zone, z, ngcc_inv_default)
            push!(candidate_gen, (
                zone,
                pmax_new,
                best_ngcc.pmin_frac * pmax_new,
                inv_new,
                best_ngcc.var_cost,
                "NGCC",
                1,
                0,
                0,
                0.40,
                best_ngcc.cc,
                1.0,
                0,
            ))
            push!(gen_names_candidate, "ADV_NGCC_z$(z)")
        end
    end

    CSV.write(joinpath(DST_DATA, "gendata.csv"), existing_gen)
    CSV.write(joinpath(DST_DATA, "gendata_candidate.csv"), candidate_gen)

    existing_sto = DataFrame(
        "Zone" => String[],
        "Type" => String[],
        "Capacity (MWh)" => Float64[],
        "Max Power (MW)" => Float64[],
        "Charging efficiency" => Float64[],
        "Discharging efficiency" => Float64[],
        "Cost (\$/MWh)" => Float64[],
        "EF" => Float64[],
        "CC" => Float64[],
        "Charging Rate" => Float64[],
        "Discharging Rate" => Float64[],
    )
    candidate_sto = DataFrame(
        "Zone" => String[],
        "Type" => String[],
        "Capacity (MWh)" => Float64[],
        "Max Power (MW)" => Float64[],
        "Charging efficiency" => Float64[],
        "Discharging efficiency" => Float64[],
        "Cost (\$/MW/yr)" => Float64[],
        "Cost (\$/MWh)" => Float64[],
        "EF" => Float64[],
        "CC" => Float64[],
        "Charging Rate" => Float64[],
        "Discharging Rate" => Float64[],
    )

    for r in eachrow(gen)
        if toint(r[:STOR], 0) != 1
            continue
        end
        zone_int = toint(r[:Zone], 0)
        if zone_int < 1 || zone_int > 64
            continue
        end
        zone = "z$(zone_int)"
        resource = string(r[:Resource])
        rtype = string(r[:Resource_Type])
        stype = map_gen_type(resource, rtype, 0, 0, 1)
        cc = row_cap_credit(r, zone_int)
        eta_ch = clamp(tofloat(r[:Eff_Up], 0.9), 0.01, 1.0)
        eta_dis = clamp(tofloat(r[:Eff_Down], 0.9), 0.01, 1.0)
        vcost = tofloat(r[:Var_OM_Cost_per_MWh], tofloat(r[:Var_OM_Cost_per_MWh_In], 0.0))

        p_dis_exist = max(tofloat(r[:Existing_Cap_MW], 0.0), 0.0)
        p_ch_exist = max(tofloat(r[:Existing_Charge_Cap_MW], 0.0), 0.0)
        p_exist = max(p_dis_exist, p_ch_exist)
        e_exist = max(tofloat(r[:Existing_Cap_MWh], 0.0), 0.0)
        if p_exist > 0 || e_exist > 0
            if p_exist <= 0 && e_exist > 0
                p_exist = e_exist / 4.0
            end
            if e_exist <= 0 && p_exist > 0
                e_exist = 4.0 * p_exist
            end
            # Keep existing storage operating limits neutral in HOPE conversion.
            # Requested by user: avoid tiny 0.001 rates from missing charge caps.
            ch_rate = 1.0
            dis_rate = 1.0
            push!(existing_sto, (
                zone, stype, e_exist, p_exist, eta_ch, eta_dis, vcost, 0.0, cc, ch_rate, dis_rate
            ))
        end

        new_build = toint(r[:New_Build], 0)
        p_dis_new_raw = tofloat(r[:Max_Cap_MW], 0.0)
        p_ch_new_raw = tofloat(r[:Max_Charge_Cap_MW], 0.0)
        # GenX uses -1 as an unconstrained sentinel for some storage candidates.
        # HOPE requires finite candidate blocks, so map to a zone-scaled proxy bound.
        p_dis_new = p_dis_new_raw < 0 ? peak_by_zone[zone_int] : max(p_dis_new_raw, 0.0)
        p_ch_new = p_ch_new_raw < 0 ? p_dis_new : max(p_ch_new_raw, 0.0)
        p_new = max(p_dis_new, p_ch_new)
        e_new_raw = tofloat(r[:Max_Cap_MWh], 0.0)
        e_new = e_new_raw < 0 ? 4.0 * p_new : max(e_new_raw, 0.0)
        p_new_add = max(p_new - p_exist, 0.0)
        e_new_add = max(e_new - e_exist, 0.0)
        has_candidate_addition = (p_new_add > 1e-6) || (e_new_add > 1e-6)
        if (new_build == 1 || has_candidate_addition) && (p_new > 0 || e_new > 0)
            p_cand = has_candidate_addition ? p_new_add : p_new
            e_cand = has_candidate_addition ? e_new_add : e_new
            if p_cand <= 0 && e_cand > 0
                p_cand = e_cand / 4.0
            end
            if e_cand <= 0 && p_cand > 0
                e_cand = 4.0 * p_cand
            end
            ch_rate = p_cand > 0 ? max((p_ch_new > p_ch_exist ? p_ch_new - p_ch_exist : p_ch_new) / p_cand, 1e-3) : 1.0
            dis_rate = p_cand > 0 ? max((p_dis_new > p_dis_exist ? p_dis_new - p_dis_exist : p_dis_new) / p_cand, 1e-3) : 1.0
            inv_mw = tofloat(r[:Inv_Cost_per_MWyr], 0.0)
            inv_mwh = tofloat(r[:Inv_Cost_per_MWhyr], 0.0)
            inv_total_mw = inv_mw + (p_cand > 0 ? inv_mwh * (e_cand / p_cand) : 0.0)
            push!(candidate_sto, (
                zone, stype, e_cand, p_cand, eta_ch, eta_dis, inv_total_mw, vcost, 0.0, cc, ch_rate, dis_rate
            ))
        end
    end

    CSV.write(joinpath(DST_DATA, "storagedata.csv"), existing_sto)
    CSV.write(joinpath(DST_DATA, "storagedata_candidate.csv"), candidate_sto)

    zcols = [Symbol("z$(i)") for i in 1:64]
    line_exist = DataFrame("From_zone" => String[], "To_zone" => String[], "Capacity (MW)" => Float64[])
    line_cand = DataFrame("From_zone" => String[], "To_zone" => String[], "X" => Float64[], "Capacity (MW)" => Float64[], "Cost (M\$)" => Float64[])
    for r in eachrow(net)
        from_zone, to_zone = parse_line_endpoints(r, zcols)
        cap_exist = max(tofloat(r[:Line_Max_Flow_MW], 0.0), 0.0)
        cap_new = max(tofloat(r[:Line_Max_Reinforcement_MW], 0.0), 0.0)
        if cap_exist > 0
            push!(line_exist, (from_zone, to_zone, cap_exist))
        end
        if cap_new > 0
            inv = tofloat(r[:Line_Reinforcement_Cost_per_MWyr], 0.0) * cap_new / 1e6
            dist = tofloat(r[:distance_mile], 0.0)
            x = dist > 0 ? max(dist / 10000.0, 1e-4) : 0.01
            push!(line_cand, (from_zone, to_zone, x, cap_new, inv))
        end
    end
    CSV.write(joinpath(DST_DATA, "linedata.csv"), line_exist)
    CSV.write(joinpath(DST_DATA, "linedata_candidate.csv"), line_cand)

    gen_var = sort(gen_var, :Time_Index)
    gen_var_cols = Set(string.(names(gen_var)))
    af_out = DataFrame("Time Period" => tp_col, "Month" => month_col, "Day" => day_col, "Hours" => hour_col)
    gen_resource_order = vcat(gen_names_existing, gen_names_candidate)
    for (idx, gname) in enumerate(gen_resource_order)
        if gname in gen_var_cols
            af_out[!, Symbol("G$(idx)")] = Float64.(gen_var[!, gname])
        else
            af_out[!, Symbol("G$(idx)")] = ones(Float64, expected_rows)
        end
    end
    CSV.write(joinpath(DST_DATA, "gen_availability_timeseries.csv"), af_out)

    states = copy(zone_ids)
    carbon = DataFrame("State" => states, "Time Period" => fill(1, length(states)), "Allowance (tons)" => fill(1.0e15, length(states)))
    CSV.write(joinpath(DST_DATA, "carbonpolicies.csv"), carbon)
    rps = DataFrame("From_state" => states, "To_state" => states, "RPS" => zeros(Float64, length(states)))
    CSV.write(joinpath(DST_DATA, "rpspolicies.csv"), rps)

    single = DataFrame(
        "VOLL" => [100000.0],
        "planning _reserve_margin" => [0.15],
        "BigM" => [1.0e13],
        "PT_RPS" => [1.0e10],
        "PT_emis" => [1.0e10],
        "Inv_bugt_gen" => [1.0e16],
        "Inv_bugt_line" => [1.0e16],
        "Inv_bugt_storage" => [1.0e16],
        "alpha_storage_anchor" => [0.5],
        "spin_requirement" => [0.03],
        "delta_spin" => [1.0 / 6.0],
    )
    CSV.write(joinpath(DST_DATA, "single_parameter.csv"), single)

    settings = Dict(
        "DataCase" => "Data_USA64_GTEP/",
        "model_mode" => "GTEP",
        "aggregated!" => 1,
        "endogenous_rep_day" => 0,
        "external_rep_day" => 1,
        "flexible_demand" => 0,
        "inv_dcs_bin" => 0,
        "transmission_expansion" => 1,
        "carbon_policy" => 0,
        "clean_energy_policy" => 0,
        "planning_reserve_mode" => 0,
        "operation_reserve_mode" => 0,
        "storage_ld_duration_hours" => 12.0,
        "write_shadow_prices" => 0,
        "summary_table" => 0,
        "solver" => "gurobi",
        "debug" => 0,
    )
    open(joinpath(DST_SETTINGS, "HOPE_model_settings.yml"), "w") do io
        YAML.write(io, settings)
    end
    cbc_settings = Dict(
        "TimeLimit" => 7200.0,
        "logLevel" => 1,
        "maxSolutions" => -1,
        "maxNodes" => -1,
        "allowableGap" => -1.0,
        "ratioGap" => 0.01,
        "threads" => 8,
    )
    open(joinpath(DST_SETTINGS, "cbc_settings.yml"), "w") do io
        YAML.write(io, cbc_settings)
    end

    println("Created case: $(DST_CASE)")
    println("Zones: 64")
    println("Existing generators: $(nrow(existing_gen)), candidate generators: $(nrow(candidate_gen))")
    println("Existing lines: $(nrow(line_exist)), candidate lines: $(nrow(line_cand))")
    println("Representative periods: $(n_rep), hours modeled: $(expected_rows)")
end

main()
