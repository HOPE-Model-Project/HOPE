using DataFrames
using CSV

function build_snapshot_test_inputs()
    gendata = DataFrame(; Zone=["Z1"], Type=["NGCC_CCS"], EF=[0.4], CC=[0.9], AF=[1.0], FOR=[0.05], Flag_thermal=[1], Flag_VRE=[0], Flag_RET=[0], Flag_mustrun=[0], Flag_RPS=[0])
    gendata[!, Symbol("Pmax (MW)")] = [100.0]
    gendata[!, Symbol("Pmin (MW)")] = [25.0]
    gendata[!, Symbol("Cost (\$/MWh)")] = [30.0]

    gendata_candidate = DataFrame(; Zone=["Z1"], Type=["SolarPV"], EF=[0.0], CC=[0.0], AF=[0.4], FOR=[0.0], Flag_thermal=[0], Flag_VRE=[1], Flag_RET=[0], Flag_mustrun=[0], Flag_RPS=[1])
    gendata_candidate[!, Symbol("Pmax (MW)")] = [50.0]
    gendata_candidate[!, Symbol("Pmin (MW)")] = [0.0]
    gendata_candidate[!, Symbol("Cost (\$/MWh)")] = [0.0]

    storagedata = DataFrame(; Zone=["Z1"], Type=["Battery"], CC=[0.0])
    storagedata[!, Symbol("Capacity (MWh)")] = [40.0]
    storagedata[!, Symbol("Max Power (MW)")] = [10.0]
    storagedata[!, Symbol("Cost (\$/MWh)")] = [1.0]

    storagedata_candidate = DataFrame(; Zone=["Z1"], Type=["Battery"], CC=[0.0])
    storagedata_candidate[!, Symbol("Capacity (MWh)")] = [20.0]
    storagedata_candidate[!, Symbol("Max Power (MW)")] = [5.0]
    storagedata_candidate[!, Symbol("Cost (\$/MWh)")] = [1.0]
    linedata = DataFrame(; From_zone=["Z1"], To_zone=["Z1"])
    linedata[!, Symbol("Capacity (MW)")] = [1000.0]
    linedata[!, Symbol("Cost (M\$)")] = [0.0]
    linedata_candidate = DataFrame(; From_zone=String[], To_zone=String[])
    linedata_candidate[!, Symbol("Capacity (MW)")] = Float64[]
    linedata_candidate[!, Symbol("Cost (M\$)")] = Float64[]
    zonedata = DataFrame(; Zone_id=["Z1"], State=["S1"])
    zonedata[!, Symbol("Demand (MW)")] = [100.0]
    cbpdata = DataFrame(From_state = ["S1"], Carbon_cap = [1.0e6])
    rpsdata = DataFrame(From_state = ["S1"], RPS = [0.0])
    singlepar = DataFrame(VOLL = [15000.0], Inv_bugt_gen = [0.0], Inv_bugt_storage = [0.0], Inv_bugt_line = [0.0], Reserve_margin = [0.15])
    loaddata = DataFrame(; Month=[1, 1], Day=[1, 1], Hours=[1, 2], Z1=[0.9, 1.0], NI=[0.0, 0.0])
    loaddata[!, Symbol("Time Period")] = [1, 1]
    select!(loaddata, Symbol("Time Period"), :Month, :Day, :Hours, :Z1, :NI)
    afdata = DataFrame(; Month=[1, 1], Day=[1, 1], Hours=[1, 2], G1=[1.0, 1.0], G2=[0.2, 0.5])
    afdata[!, Symbol("Time Period")] = [1, 1]
    select!(afdata, Symbol("Time Period"), :Month, :Day, :Hours, :G1, :G2)
    repweights = DataFrame(; Weight=[365.0])
    repweights[!, Symbol("Time Period")] = [1]
    select!(repweights, Symbol("Time Period"), :Weight)

    base_input = Dict(
        "Gendata" => gendata,
        "Gendata_candidate" => gendata_candidate,
        "Storagedata" => storagedata,
        "Estoragedata_candidate" => storagedata_candidate,
        "Linedata" => linedata,
        "Linedata_candidate" => linedata_candidate,
        "Zonedata" => zonedata,
        "CBPdata" => cbpdata,
        "RPSdata" => rpsdata,
        "Singlepar" => singlepar,
        "Loaddata" => loaddata,
        "AFdata" => afdata,
        "RepWeightData" => repweights,
    )

    fixed_input = deepcopy(base_input)
    fixed_input["Gendata_candidate"] = gendata_candidate[1:0, :]
    fixed_input["Estoragedata_candidate"] = storagedata_candidate[1:0, :]
    fixed_input["Linedata_candidate"] = linedata_candidate[1:0, :]

    return base_input, fixed_input
end

@testset "EREC Snapshot" begin
    @test isdefined(HOPE, :calculate_erec_from_output)
    @test isdefined(HOPE, :load_postprocess_snapshot)

    mktempdir() do tmpdir
        case_dir = joinpath(tmpdir, "case")
        output_dir = joinpath(case_dir, "output")
        settings_dir = joinpath(case_dir, "Settings")
        mkpath(output_dir)
        mkpath(settings_dir)

        open(joinpath(settings_dir, "HOPE_model_settings.yml"), "w") do io
            write(io, """
DataCase: Data/
model_mode: GTEP
resource_aggregation: 0
endogenous_rep_day: 0
external_rep_day: 1
flexible_demand: 0
planning_reserve_mode: 0
solver: cbc
save_postprocess_snapshot: 1
""")
        end
        open(joinpath(settings_dir, "HOPE_erec_settings.yml"), "w") do io
            write(io, """
enabled: 1
resource_types:
  - generator
""")
        end
        open(joinpath(settings_dir, "HOPE_rep_day_settings.yml"), "w") do io
            write(io, "time_periods:\n  1: [1, 1, 1, 1]\n")
        end
        open(joinpath(settings_dir, "cbc_settings.yml"), "w") do io
            write(io, "TimeLimit: 60\n")
        end

        config = Dict{String,Any}(
            "DataCase" => "Data/",
            "model_mode" => "GTEP",
            "resource_aggregation" => 0,
            "endogenous_rep_day" => 0,
            "external_rep_day" => 1,
            "flexible_demand" => 0,
            "planning_reserve_mode" => 0,
            "solver" => "cbc",
            "save_postprocess_snapshot" => 1,
        )
        base_input, fixed_input = build_snapshot_test_inputs()

        snapshot_info = HOPE.save_postprocess_snapshot_bundle(
            output_dir,
            case_dir,
            config,
            base_input,
            fixed_input;
            mode=1,
        )

        snapshot_dir = snapshot_info["snapshot_dir"]
        @test isdir(snapshot_dir)
        @test isfile(joinpath(snapshot_dir, "metadata.yml"))
        @test isfile(joinpath(snapshot_dir, "resolved_model_settings.yml"))
        @test isfile(joinpath(snapshot_dir, "Settings", "HOPE_model_settings.yml"))
        @test isfile(joinpath(snapshot_dir, "Settings", "HOPE_rep_day_settings.yml"))
        @test isfile(joinpath(snapshot_dir, "Settings", "HOPE_erec_settings.yml"))
        @test isfile(joinpath(snapshot_dir, "Settings", "cbc_settings.yml"))
        @test isfile(joinpath(snapshot_dir, "base_input", "gendata.csv"))
        @test isfile(joinpath(snapshot_dir, "fixed_fleet_input", "gendata.csv"))

        loaded = HOPE.load_postprocess_snapshot(output_dir)
        @test loaded["output_path"] == output_dir
        @test loaded["config"]["solver"] == "cbc"
        @test loaded["metadata"]["save_postprocess_snapshot"] == 1
        @test nrow(loaded["base_input"]["Gendata"]) == 1
        @test nrow(loaded["base_input"]["Gendata_candidate"]) == 1
        @test nrow(loaded["fixed_input"]["Gendata_candidate"]) == 0
        @test "NI" in names(loaded["base_input"]["Loaddata"])
        @test length(loaded["base_input"]["NIdata"]) == nrow(loaded["base_input"]["Loaddata"])

        snapshot_settings = HOPE.load_erec_settings(snapshot_dir)
        @test snapshot_settings["resource_types"] == ["generator"]
    end
end
