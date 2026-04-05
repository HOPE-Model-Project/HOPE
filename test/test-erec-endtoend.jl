using DataFrames
using CSV
using YAML

function build_tiny_erec_case_tables()
    gendata = DataFrame(
        :Zone => ["Z1"],
        :Type => ["NGCC_CCS"],
        Symbol("Pmax (MW)") => [100.0],
        Symbol("Pmin (MW)") => [25.0],
        Symbol("Cost (\$/MWh)") => [30.0],
        :EF => [0.4],
        :CC => [0.0],
        :AF => [1.0],
        :FOR => [0.05],
        :Flag_thermal => [1],
        :Flag_VRE => [0],
        :Flag_RET => [0],
        :Flag_mustrun => [0],
        :Flag_RPS => [0],
    )

    gendata_candidate = gendata[1:0, :]
    insertcols!(gendata_candidate, 4, Symbol("Cost (\$/MW/yr)") => Float64[])

    storagedata = DataFrame(
        :Zone => ["Z1"],
        :Type => ["Battery"],
        Symbol("Capacity (MWh)") => [20.0],
        Symbol("Max Power (MW)") => [10.0],
        Symbol("Charging efficiency") => [1.0],
        Symbol("Discharging efficiency") => [1.0],
        Symbol("Cost (\$/MWh)") => [1.0],
        :EF => [0.0],
        :CC => [0.0],
        Symbol("Charging Rate") => [1.0],
        Symbol("Discharging Rate") => [1.0],
    )

    storagedata_candidate = storagedata[1:0, :]
    insertcols!(storagedata_candidate, 7, Symbol("Cost (\$/MW/yr)") => Float64[])

    linedata = DataFrame(
        :From_zone => String[],
        :To_zone => String[],
        Symbol("Capacity (MW)") => Float64[],
    )
    linedata_candidate = DataFrame(
        :From_zone => ["Z1"],
        :To_zone => ["Z1"],
        Symbol("Capacity (MW)") => [1.0],
        Symbol("Cost (M\$)") => [1.0e6],
    )

    zonedata = DataFrame(
        :Zone_id => ["Z1"],
        Symbol("Demand (MW)") => [120.0],
        :State => ["S1"],
    )

    carbonpolicies = DataFrame(
        Symbol("Time Period") => [1],
        :State => ["S1"],
        Symbol("Allowance (tons)") => [1.0e9],
    )

    rpspolicies = DataFrame(
        :From_state => ["S1"],
        :To_state => ["S1"],
        :RPS => [0.0],
    )

    singlepar = DataFrame(
        :VOLL => [15000.0],
        :Inv_bugt_gen => [0.0],
        :Inv_bugt_line => [0.0],
        :Inv_bugt_storage => [0.0],
        :planning_reserve_margin => [0.15],
        :spin_requirement => [0.0],
        :delta_spin => [1.0 / 6.0],
        :BigM => [1.0e10],
        :PT_RPS => [1.0e13],
        :PT_emis => [1.0e13],
    )

    rep_hours = collect(1:24)
    load_profile = vcat(fill(0.5, 23), [1.0])

    loaddata = DataFrame(
        Symbol("Time Period") => fill(1, 24),
        :Month => fill(1, 24),
        :Day => fill(1, 24),
        :Hours => rep_hours,
        :Z1 => load_profile,
        :NI => fill(0.0, 24),
    )

    afdata = DataFrame(
        Symbol("Time Period") => fill(1, 24),
        :Month => fill(1, 24),
        :Day => fill(1, 24),
        :Hours => rep_hours,
        :G1 => fill(1.0, 24),
    )

    repweights = DataFrame(
        Symbol("Time Period") => [1],
        :Weight => [365.0],
    )

    return Dict(
        "gendata.csv" => gendata,
        "gendata_candidate.csv" => gendata_candidate,
        "storagedata.csv" => storagedata,
        "storagedata_candidate.csv" => storagedata_candidate,
        "linedata.csv" => linedata,
        "linedata_candidate.csv" => linedata_candidate,
        "zonedata.csv" => zonedata,
        "carbonpolicies.csv" => carbonpolicies,
        "rpspolicies.csv" => rpspolicies,
        "single_parameter.csv" => singlepar,
        "load_timeseries_regional.csv" => loaddata,
        "gen_availability_timeseries.csv" => afdata,
        "rep_period_weights.csv" => repweights,
    )
end

function write_tiny_erec_case(case_dir::AbstractString)
    settings_dir = joinpath(case_dir, "Settings")
    data_dir = joinpath(case_dir, "Data")
    mkpath(settings_dir)
    mkpath(data_dir)

    open(joinpath(settings_dir, "HOPE_model_settings.yml"), "w") do io
        write(io, """
DataCase: Data/
model_mode: GTEP
resource_aggregation: 0
representative_day!: 0
flexible_demand: 0
inv_dcs_bin: 0
carbon_policy: 0
clean_energy_policy: 0
planning_reserve_mode: 0
operation_reserve_mode: 0
transmission_loss: 0
write_shadow_prices: 0
summary_table: 0
solver: cbc
debug: 0
endogenous_rep_day: 0
external_rep_day: 1
save_postprocess_snapshot: 1
""")
    end

    open(joinpath(settings_dir, "HOPE_erec_settings.yml"), "w") do io
        write(io, """
enabled: 1
voll_override: 15000
resource_types:
  - generator
  - storage
resource_scope: built_only
write_outputs: 1
write_cc_to_tables: 0
output_dir_name: output_erec
""")
    end

    open(joinpath(settings_dir, "cbc_settings.yml"), "w") do io
        write(io, """
TimeLimit: 60
logLevel: 0
threads: 1
""")
    end

    for (filename, table) in build_tiny_erec_case_tables()
        CSV.write(joinpath(data_dir, filename), table)
    end

    return case_dir
end

function sorted_erec_view(df::DataFrame)
    cols = [:ResourceType, :Label, :Technology, :Zone, :BaselinePowerMW, :BaselineEnergyMWh, :EUEBase, :EUEResource, :EUEPerfect, :EREC]
    return sort(df[:, cols], [:ResourceType, :Label])
end

function assert_same_erec_results(df_a::DataFrame, df_b::DataFrame; atol::Float64=1.0e-6)
    a = sorted_erec_view(df_a)
    b = sorted_erec_view(df_b)
    @test nrow(a) == nrow(b)
    @test names(a) == names(b)
    for row_idx in 1:nrow(a), col in names(a)
        aval = a[row_idx, col]
        bval = b[row_idx, col]
        if aval isa Number && bval isa Number
            @test isapprox(Float64(aval), Float64(bval); atol=atol, rtol=0.0)
        else
            @test aval == bval
        end
    end
end

@testset "EREC End-to-End Saved Baseline Workflows" begin
    mktempdir() do tmpdir
        case_dir = write_tiny_erec_case(joinpath(tmpdir, "tiny_erec_case"))

        run_res = HOPE.run_hope(case_dir)
        @test haskey(run_res, "case_path")
        @test haskey(run_res, "output_path")
        @test haskey(run_res, "config")
        @test haskey(run_res, "solved_model")
        @test haskey(run_res, "snapshot")
        @test run_res["snapshot"] !== nothing
        @test isdir(run_res["snapshot"]["snapshot_dir"])
        @test isfile(joinpath(run_res["output_path"], "postprocess_snapshot", "metadata.yml"))

        erec_from_results = HOPE.calculate_erec(
            run_res;
            resource_types=["generator", "storage"],
            output_dir_name="output_erec_from_results",
            write_cc_to_tables=0,
        )

        erec_from_output = HOPE.calculate_erec_from_output(
            run_res["output_path"];
            resource_types=["generator", "storage"],
            output_dir_name="output_erec_from_snapshot",
            write_cc_to_tables=0,
        )

        @test erec_from_results["baseline_eue"] > 0.0
        @test isapprox(erec_from_results["baseline_eue"], erec_from_output["baseline_eue"]; atol=1.0e-6, rtol=0.0)
        @test nrow(erec_from_results["erec_results"]) == 2
        @test nrow(erec_from_output["erec_results"]) == 2
        @test Set(erec_from_results["erec_results"].ResourceType) == Set(["generator", "storage"])
        @test Set(erec_from_output["erec_results"].ResourceType) == Set(["generator", "storage"])
        @test all((isnan(x) || (x >= -1.0e-8 && x <= 1.0 + 1.0e-8)) for x in erec_from_results["erec_results"].EREC)
        @test all((isnan(x) || (x >= -1.0e-8 && x <= 1.0 + 1.0e-8)) for x in erec_from_output["erec_results"].EREC)
        @test erec_from_results["baseline_model"] === run_res["solved_model"]
        @test erec_from_output["baseline_model"] === nothing

        assert_same_erec_results(erec_from_results["erec_results"], erec_from_output["erec_results"])

        @test isfile(erec_from_results["output_paths"]["erec_results"])
        @test isfile(erec_from_output["output_paths"]["erec_results"])

        snapshot_settings = joinpath(run_res["output_path"], "postprocess_snapshot", "Settings", "HOPE_erec_settings.yml")
        open(snapshot_settings, "w") do io
            YAML.write(io, Dict(
                "enabled" => 1,
                "resource_types" => ["generator", "storage"],
                "resource_scope" => "built_only",
                "write_outputs" => 0,
            ))
        end
        erec_preserve_voll = HOPE.calculate_erec_from_output(
            run_res["output_path"];
            resource_types=["generator", "storage"],
            output_dir_name="output_erec_preserve_voll",
            write_cc_to_tables=0,
            write_outputs=0,
        )
        @test isapprox(erec_preserve_voll["baseline_eue"], erec_from_output["baseline_eue"]; atol=1.0e-6, rtol=0.0)
    end
end
