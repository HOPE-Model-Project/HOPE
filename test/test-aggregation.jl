using DataFrames
using CSV
using JuMP

@testset "Resource Aggregation Helpers" begin
    defaults = HOPE.default_aggregation_settings()
    @test defaults["write_aggregation_audit"] == 1
    @test defaults["clustered_thermal_commitment"] == 1

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

    flagged = deepcopy(raw)
    flagged[2, :Flag_RET] = 1
    split_cfg = Dict{String,Any}(
        "resource_aggregation" => 1,
        "aggregation_settings" => Dict(
            "grouping_keys" => ["Zone", "Type", "Flag_RET"],
            "pcm_additional_grouping_keys" => Any[],
            "aggregate_technologies" => Any[],
            "keep_separate_technologies" => Any[],
        ),
    )
    split_agg = HOPE.aggregate_gendata_gtep(flagged, split_cfg)
    @test nrow(split_agg) == 3

    sep_cfg = Dict{String,Any}(
        "resource_aggregation" => 1,
        "aggregation_settings" => Dict(
            "grouping_keys" => ["Zone", "Type", "Flag_RET", "Flag_mustrun", "Flag_VRE", "Flag_thermal"],
            "pcm_additional_grouping_keys" => Any[],
            "aggregate_technologies" => Any[],
            "keep_separate_technologies" => ["SolarPV"],
        ),
    )
    sep_agg = HOPE.aggregate_gendata_gtep(raw, sep_cfg)
    @test nrow(sep_agg) == 3

    pcm_raw = DataFrame(
        Zone = ["Z1", "Z1"],
        Type = ["NGCT", "NGCT"],
        EF = [0.4, 0.4],
        CC = [0.95, 0.95],
        FOR = [0.08, 0.08],
        RM_SPIN = [0.02, 0.02],
        RU = [1.0, 1.0],
        RD = [1.0, 1.0],
        Flag_thermal = [1, 1],
        Flag_VRE = [0, 0],
        Flag_mustrun = [0, 0],
        Flag_UC = [1, 1],
        Min_down_time = [2.0, 2.0],
        Min_up_time = [2.0, 2.0],
    )
    pcm_raw[!, Symbol("Pmax (MW)")] = [100.0, 200.0]
    pcm_raw[!, Symbol("Pmin (MW)")] = [20.0, 40.0]
    pcm_raw[!, Symbol("Cost (\$/MWh)")] = [40.0, 40.0]
    pcm_raw[!, Symbol("Start_up_cost (\$/MW)")] = [10.0, 10.0]
    pcm_cfg = Dict{String,Any}(
        "unit_commitment" => 1,
        "resource_aggregation" => 1,
        "aggregation_settings" => Dict(
            "grouping_keys" => ["Zone", "Type", "Flag_thermal", "Flag_VRE", "Flag_mustrun"],
            "pcm_additional_grouping_keys" => ["Flag_UC"],
            "clustered_thermal_commitment" => 1,
        ),
    )
    pcm_agg = HOPE.aggregate_gendata_pcm(pcm_raw, pcm_cfg)
    @test nrow(pcm_agg) == 1
    @test pcm_agg[1, :NumUnits] == 2
    @test pcm_agg[1, Symbol("ClusteredUnitPmax (MW)")] ≈ 150.0
    @test pcm_agg[1, Symbol("ClusteredUnitPmin (MW)")] ≈ 30.0

    uc_model = Model()
    input_data = Dict(
        "Gendata" => pcm_agg,
        "Loaddata" => DataFrame(Zone = [1.0, 1.0]),
    )
    @variable(uc_model, p[1:nrow(pcm_agg), 1:2] >= 0)
    HOPE.unit_commitment!(pcm_cfg, input_data, uc_model)
    @test upper_bound(uc_model[:o][1, 1]) == 2.0
    @test upper_bound(uc_model[:su][1, 1]) == 2.0
end
