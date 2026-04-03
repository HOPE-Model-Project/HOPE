using DataFrames
using CSV

@testset "Resource Aggregation Helpers" begin
    defaults = HOPE.default_aggregation_settings()
    @test defaults["write_aggregation_audit"] == 1

    mktempdir() do tmpdir
        case_dir = joinpath(tmpdir, "agg_case")
        settings_dir = joinpath(case_dir, "Settings")
        mkpath(settings_dir)
        open(joinpath(settings_dir, "HOPE_aggregation_settings.yml"), "w") do io
            write(io, "write_aggregation_audit: 0\n")
        end
        loaded = HOPE.load_aggregation_settings(case_dir, Dict{String,Any}())
        @test loaded["write_aggregation_audit"] == 0
    end

    raw = DataFrame(
        Zone = ["Z1", "Z1", "Z2"],
        Type = ["SolarPV", "SolarPV", "NGCT"],
        EF = [0.0, 0.0, 0.4],
        CC = [0.3, 0.3, 0.95],
        AF = [1.0, 1.0, 1.0],
        FOR = [0.0, 0.0, 0.08],
        Flag_thermal = [0, 0, 1],
        Flag_VRE = [1, 1, 0],
        Flag_RET = [0, 0, 0],
        Flag_mustrun = [0, 0, 0],
        Flag_RPS = [1, 1, 0],
    )
    raw[!, Symbol("Pmax (MW)")] = [100.0, 50.0, 80.0]
    raw[!, Symbol("Pmin (MW)")] = [0.0, 0.0, 20.0]
    raw[!, Symbol("Cost (\$/MWh)")] = [0.0, 0.0, 90.0]
    agg = HOPE.aggregate_gendata_gtep(raw)
    raw_af = DataFrame(
        "Time Period" => [1, 1],
        "Hours" => [1, 2],
        "G1" => [0.6, 0.8],
        "G2" => [0.2, 0.4],
        "G3" => [1.0, 1.0],
    )
    cand = DataFrame(
        Zone = String[],
        Type = String[],
    )
    agg_af = HOPE.aggregate_afdata_gtep(raw, agg, cand, raw_af)
    audit = HOPE.build_gtep_aggregation_audit(raw, agg; raw_afdata=raw_af, aggregated_afdata=agg_af)

    @test nrow(audit["mapping"]) == 3
    @test nrow(audit["summary"]) == 2
    @test nrow(audit["af_summary"]) == 2
    @test audit["summary"][1, :GroupSize] == 2

    mktempdir() do outdir
        config = Dict{String,Any}(
            "resource_aggregation" => 1,
            "aggregation_settings" => Dict("write_aggregation_audit" => 1),
        )
        input_data = Dict{String,Any}("AggregationAudit" => audit)
        HOPE.write_resource_aggregation_audit_outputs(outdir, config, input_data)
        @test isfile(joinpath(outdir, "resource_aggregation_mapping.csv"))
        @test isfile(joinpath(outdir, "resource_aggregation_summary.csv"))
        @test isfile(joinpath(outdir, "resource_aggregation_af_summary.csv"))
    end
end
