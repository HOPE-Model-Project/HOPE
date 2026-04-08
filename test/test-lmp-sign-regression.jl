using JuMP
using DataFrames

const PROJECT_ROOT = normpath(joinpath(@__DIR__, ".."))

to_float_test(x) = x isa Number ? Float64(x) : parse(Float64, string(x))

function test_case_config(case_path::AbstractString)
    config =
        HOPE.YAML.load(open(joinpath(case_path, "Settings", "HOPE_model_settings.yml")))
    config["solver"] = "clp"
    config["summary_table"] = 0
    config["debug"] = 0
    config["flexible_demand"] = 0
    config["clean_energy_policy"] = 0
    config["carbon_policy"] = 0
    config["operation_reserve_mode"] = 0
    config["unit_commitment"] = 0
    config["write_shadow_prices"] = 0
    return config
end

function trim_pcm_timeseries!(input_data::Dict)
    for key in (
        "Loaddata",
        "Winddata",
        "Solardata",
        "DRtsdata",
        "NodalLoaddata",
        "NodalNIdata",
        "AFdata",
    )
        if haskey(input_data, key)
            input_data[key] = copy(input_data[key][1:1, :])
        end
    end
    input_data["NIdata"] =
        ("NI" in names(input_data["Loaddata"])) ? copy(input_data["Loaddata"][:, "NI"]) :
        zeros(1)
    return input_data
end

function ensure_nodal_load!(input_data::Dict)
    haskey(input_data, "NodalLoaddata") && return input_data
    busdata = input_data["Busdata"]
    loaddata = input_data["Loaddata"]
    nodal = DataFrame()
    for col in ("Time Period", "Month", "Day", "Hours")
        if col in names(loaddata)
            nodal[!, Symbol(col)] = copy(loaddata[:, col])
        end
    end
    for row = 1:nrow(busdata)
        bus_id = string(busdata[row, "Bus_id"])
        zone_id = string(busdata[row, "Zone_id"])
        nodal[!, Symbol(bus_id)] = to_float_test.(loaddata[:, zone_id])
    end
    input_data["NodalLoaddata"] = nodal
    return input_data
end

function bus_peak_mw_by_row(input_data::Dict)
    busdata = input_data["Busdata"]
    zonedata = input_data["Zonedata"]
    zone_peak = Dict(
        string(zonedata[i, "Zone_id"]) => to_float_test(zonedata[i, "Demand (MW)"]) for
        i = 1:nrow(zonedata)
    )
    bus_peak = zeros(Float64, nrow(busdata))
    for zone in unique(string.(busdata[:, "Zone_id"]))
        rows = findall(string.(busdata[:, "Zone_id"]) .== zone)
        raw = if "Load_share" in names(busdata)
            to_float_test.(busdata[rows, "Load_share"])
        else
            to_float_test.(busdata[rows, "Demand (MW)"])
        end
        den = sum(raw)
        @test den > 0.0
        for (idx, row_idx) in enumerate(rows)
            bus_peak[row_idx] = zone_peak[zone] * raw[idx] / den
        end
    end
    return bus_peak
end

function bus_column_name(df::DataFrame, bus_label::AbstractString)
    match_idx = findfirst(name -> string(name) == bus_label, names(df))
    match_idx === nothing &&
        error("Bus column $(bus_label) not found in nodal load dataframe.")
    return names(df)[match_idx]
end

function choose_test_bus(input_data::Dict)
    bus_peak = bus_peak_mw_by_row(input_data)
    idx = findfirst(>(1.0e-6), bus_peak)
    idx === nothing && error("No positive-load bus available for perturbation test.")
    return idx, string(input_data["Busdata"][idx, "Bus_id"]), bus_peak[idx]
end

function solve_one_hour_pcm(case_rel::AbstractString)
    case_path = joinpath(PROJECT_ROOT, case_rel)
    config = test_case_config(case_path)
    input_data = HOPE.load_data(config, case_path)
    trim_pcm_timeseries!(input_data)
    ensure_nodal_load!(input_data)
    optimizer = HOPE.initiate_solver(case_path, config["solver"])
    model = HOPE.create_PCM_model(config, input_data, optimizer)
    solved = HOPE.solve_model(config, input_data, model)
    @test string(termination_status(solved)) == "OPTIMAL"
    return case_path, config, input_data, solved
end

function run_price_sign_check(case_rel::AbstractString, semantics::Symbol, con_name::Symbol)
    case_path, config, input_data, solved = solve_one_hour_pcm(case_rel)
    bus_idx, bus_label, bus_peak = choose_test_bus(input_data)
    con_ref = solved[con_name][bus_idx, 1]
    exported_lmp = HOPE.marginal_load_price_from_dual(con_ref, semantics)
    raw_dual = dual(con_ref)
    raw_shadow = shadow_price(con_ref)
    outputs = mktempdir() do tmpdir
        HOPE.write_output(tmpdir, config, input_data, solved)
    end
    price_df = outputs["power_price_nodal"]
    row_idx = findfirst(string.(price_df[!, :Bus]) .== bus_label)
    row_idx === nothing && error("Bus $(bus_label) not found in exported nodal prices.")
    file_lmp = to_float_test(price_df[row_idx, Symbol("h1")])

    perturbed_input = deepcopy(input_data)
    nodal_load = perturbed_input["NodalLoaddata"]
    bus_col = bus_column_name(nodal_load, bus_label)
    nodal_load[1, bus_col] = to_float_test(nodal_load[1, bus_col]) + 1.0 / bus_peak
    pert_optimizer = HOPE.initiate_solver(case_path, config["solver"])
    perturbed_model = HOPE.create_PCM_model(config, perturbed_input, pert_optimizer)
    perturbed_model = HOPE.solve_model(config, perturbed_input, perturbed_model)
    @test string(termination_status(perturbed_model)) == "OPTIMAL"
    delta_obj = objective_value(perturbed_model) - objective_value(solved)

    return (
        bus_label = bus_label,
        exported_lmp = exported_lmp,
        file_lmp = file_lmp,
        raw_dual = raw_dual,
        raw_shadow = raw_shadow,
        delta_obj = delta_obj,
    )
end

@testset "PCM LMP Sign Regression" begin
    if get(ENV, "HOPE_MODELCASES_PATH", "") == ""
        @info "Skipping LMP sign regression test. Set HOPE_MODELCASES_PATH to the ModelCases directory to enable."
    else
        angle_report = run_price_sign_check(
            joinpath(ENV["HOPE_MODELCASES_PATH"], "ISONE_PCM_250bus_case"),
            :balance_rhs_load,
            :PBNode_con,
        )
        @test isapprox(angle_report.exported_lmp, angle_report.file_lmp; atol = 1.0e-6)
        @test isapprox(
            angle_report.exported_lmp,
            angle_report.delta_obj;
            atol = 1.0e-4,
            rtol = 1.0e-6,
        )
        @test isapprox(angle_report.exported_lmp, angle_report.raw_dual; atol = 1.0e-6)
        @test isapprox(angle_report.exported_lmp, -angle_report.raw_shadow; atol = 1.0e-6)

        ptdf_report = run_price_sign_check(
            joinpath(ENV["HOPE_MODELCASES_PATH"], "RTS24_PCM_fullfunc_case"),
            :ptdf_injection_definition,
            :PTDFInjDef_con,
        )
        @test isapprox(ptdf_report.exported_lmp, ptdf_report.file_lmp; atol = 1.0e-6)
        @test isapprox(
            ptdf_report.exported_lmp,
            ptdf_report.delta_obj;
            atol = 1.0e-4,
            rtol = 1.0e-6,
        )
        @test isapprox(ptdf_report.exported_lmp, -ptdf_report.raw_dual; atol = 1.0e-6)
        @test isapprox(ptdf_report.exported_lmp, -ptdf_report.raw_shadow; atol = 1.0e-6)
    end
end
