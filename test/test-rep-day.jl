using DataFrames
using CSV

function build_three_day_timeseries()
    month = Int[]
    day = Int[]
    hour = Int[]
    time_period = Int[]
    load = Float64[]
    af = Float64[]
    for d in 1:3
        for h in 1:24
            push!(month, 1)
            push!(day, d)
            push!(hour, h)
            push!(time_period, 1)
            push!(load, d == 1 ? 0.0 : (d == 2 ? 5.0 : 10.0))
            push!(af, d == 1 ? 1.0 : (d == 2 ? 0.5 : 0.0))
        end
    end
    loaddata = DataFrame(Symbol("Time Period") => time_period, :Month => month, :Day => day, :Hours => hour, :Z1 => load, :NI => zeros(length(load)))
    afdata = DataFrame(Symbol("Time Period") => time_period, :Month => month, :Day => day, :Hours => hour, :G1 => af)
    return loaddata, afdata
end

function build_four_day_extreme_timeseries(load_levels, af_levels)
    month = Int[]
    day = Int[]
    hour = Int[]
    time_period = Int[]
    load = Float64[]
    af = Float64[]
    for d in 1:4
        for h in 1:24
            push!(month, 1)
            push!(day, d)
            push!(hour, h)
            push!(time_period, 1)
            push!(load, load_levels[d])
            push!(af, af_levels[d])
        end
    end
    loaddata = DataFrame(Symbol("Time Period") => time_period, :Month => month, :Day => day, :Hours => hour, :Z1 => load, :NI => zeros(length(load)))
    afdata = DataFrame(Symbol("Time Period") => time_period, :Month => month, :Day => day, :Hours => hour, :G1 => af)
    return loaddata, afdata
end

@testset "Representative Day Helpers" begin
    mktempdir() do tmpdir
        case_dir = joinpath(tmpdir, "case")
        settings_dir = joinpath(case_dir, "Settings")
        mkpath(settings_dir)

        open(joinpath(settings_dir, "HOPE_rep_day_settings.yml"), "w") do io
            write(io, """
time_periods:
  1: [1, 1, 1, 3]
clustering_method: kmedoids
feature_mode: joint_daily
include_load: 1
include_af: 1
normalize_features: 1
""")
        end

        config = Dict{String,Any}(
            "time_periods" => Dict(1 => [2, 1, 2, 28]),
            "endogenous_rep_day" => 1,
        )
        rep_settings = HOPE.load_rep_day_settings(case_dir, config)
        @test rep_settings["clustering_method"] == "kmedoids"
        @test rep_settings["feature_mode"] == "joint_daily"
        resolved = HOPE.resolve_rep_day_time_periods(Dict("rep_day_settings" => rep_settings))
        @test resolved == [1 => (1, 1, 1, 3)]
    end

    loaddata, afdata = build_three_day_timeseries()
    config = Dict{String,Any}(
        "rep_day_settings" => Dict(
            "time_periods" => Dict(1 => [1, 1, 1, 3]),
            "clustering_method" => "kmedoids",
            "feature_mode" => "joint_daily",
            "include_load" => 1,
            "include_af" => 1,
            "include_dr" => 0,
            "normalize_features" => 1,
        ),
    )
    rep = HOPE.build_endogenous_rep_periods(loaddata, afdata, ["Z1"], ["G1"], config)
    @test rep["N"][1] == 3.0
    @test rep["metadata"][1, "SelectedMonth"] == 1
    @test rep["metadata"][1, "SelectedDay"] == 2
    @test rep["Load_rep"][1][!, "Z1"] == loaddata[25:48, "Z1"]
    @test rep["AF_rep"][1][!, "G1"] == afdata[25:48, "G1"]

    multi_load = DataFrame(
        Symbol("Time Period") => repeat([1], 96),
        :Month => repeat([1], 96),
        :Day => vcat(fill(1, 24), fill(2, 24), fill(3, 24), fill(4, 24)),
        :Hours => repeat(collect(1:24), 4),
        :Z1 => vcat(fill(0.0, 24), fill(0.0, 24), fill(10.0, 24), fill(10.0, 24)),
        :NI => zeros(96),
    )
    multi_af = DataFrame(
        Symbol("Time Period") => repeat([1], 96),
        :Month => repeat([1], 96),
        :Day => vcat(fill(1, 24), fill(2, 24), fill(3, 24), fill(4, 24)),
        :Hours => repeat(collect(1:24), 4),
        :G1 => vcat(fill(1.0, 24), fill(1.0, 24), fill(0.0, 24), fill(0.0, 24)),
    )
    multi_config = Dict{String,Any}(
        "rep_day_settings" => Dict(
            "time_periods" => Dict(1 => [1, 1, 1, 4]),
            "clustering_method" => "kmedoids",
            "feature_mode" => "joint_daily",
            "representative_days_per_period" => 2,
            "include_load" => 1,
            "include_af" => 1,
            "include_dr" => 0,
            "normalize_features" => 1,
        ),
    )
    rep_multi = HOPE.build_endogenous_rep_periods(multi_load, multi_af, ["Z1"], ["G1"], multi_config)
    @test rep_multi["T"] == [1, 2]
    @test sort(collect(values(rep_multi["N"]))) == [2.0, 2.0]
    @test nrow(rep_multi["metadata"]) == 2
    @test sort(rep_multi["metadata"][!, "RepresentativeIndex"]) == [1, 2]
    selected_days = sort(rep_multi["metadata"][!, "SelectedDay"])
    @test (selected_days == [1, 3]) || (selected_days == [1, 4]) || (selected_days == [2, 3]) || (selected_days == [2, 4])
    rep_profiles = [rep_multi["Load_rep"][t][!, "Z1"] for t in rep_multi["T"]]
    @test any(profile == multi_load[1:24, "Z1"] for profile in rep_profiles)
    @test any(profile == multi_load[49:72, "Z1"] for profile in rep_profiles)

    linked_config = Dict{String,Any}(
        "rep_day_settings" => Dict(
            "time_periods" => Dict(1 => [1, 1, 1, 4]),
            "clustering_method" => "kmedoids",
            "feature_mode" => "joint_daily",
            "representative_days_per_period" => 2,
            "link_storage_rep_days" => 1,
            "include_load" => 1,
            "include_af" => 1,
            "include_dr" => 0,
            "normalize_features" => 1,
        ),
    )
    rep_linked = HOPE.build_endogenous_rep_periods(multi_load, multi_af, ["Z1"], ["G1"], linked_config)
    linkage = rep_linked["storage_linkage"]
    @test linkage !== nothing
    @test nrow(linkage["day_assignments"]) == 4
    @test sort(linkage["day_assignments"][!, "RepresentativePeriod"]) == [1, 1, 2, 2]
    @test sort(linkage["predecessors"][1]) == [1, 2]
    @test sort(linkage["predecessors"][2]) == [1, 2]
    @test linkage["predecessor_weight"][(1, 1)] ≈ 0.5
    @test linkage["predecessor_weight"][(2, 1)] ≈ 0.5
    @test linkage["predecessor_weight"][(1, 2)] ≈ 0.5
    @test linkage["predecessor_weight"][(2, 2)] ≈ 0.5
    run_stats = linkage["run_stats"]
    @test all(run_stats[!, "MaxRunLength"] .== 2)

    planning_load, planning_af = build_three_day_timeseries()
    planning_af[!, "G2"] = vcat(fill(0.0, 24), fill(1.0, 24), fill(0.0, 24))
    planning_config = Dict{String,Any}(
        "rep_day_settings" => Dict(
            "time_periods" => Dict(1 => [1, 1, 1, 3]),
            "clustering_method" => "kmedoids",
            "feature_mode" => "planning_features",
            "planning_feature_set" => ["system_load"],
            "representative_days_per_period" => 1,
            "include_load" => 1,
            "include_af" => 1,
            "include_dr" => 0,
            "normalize_features" => 1,
        ),
    )
    planning_generator_df = DataFrame(
        "Zone" => ["Z1", "Z1"],
        "Type" => ["NGCC_CCS", "NGCT_CCS"],
        "Pmax (MW)" => [100.0, 100.0],
    )
    rep_planning = HOPE.build_endogenous_rep_periods(planning_load, planning_af, ["Z1"], ["G1", "G2"], planning_config; generator_data=planning_generator_df)
    @test rep_planning["metadata"][1, "SelectedDay"] == 2
    @test rep_planning["metadata"][1, "Method"] == "planning_features_kmedoids"

    extreme_load, extreme_af = build_four_day_extreme_timeseries([0.0, 1.0, 2.0, 10.0], [1.0, 1.0, 1.0, 1.0])
    extreme_config = Dict{String,Any}(
        "rep_day_settings" => Dict(
            "time_periods" => Dict(1 => [1, 1, 1, 4]),
            "clustering_method" => "kmedoids",
            "feature_mode" => "joint_daily",
            "representative_days_per_period" => 1,
            "add_extreme_days" => 1,
            "extreme_day_metrics" => ["peak_load"],
            "include_load" => 1,
            "include_af" => 1,
            "include_dr" => 0,
            "normalize_features" => 1,
        ),
    )
    generator_df = DataFrame("Pmax (MW)" => [100.0], "Type" => ["NGCC_CCS"])
    rep_extreme = HOPE.build_endogenous_rep_periods(extreme_load, extreme_af, ["Z1"], ["G1"], extreme_config; generator_data=generator_df)
    @test rep_extreme["T"] == [1, 2]
    @test rep_extreme["metadata"][1, "SelectionType"] == "cluster_medoid"
    @test rep_extreme["metadata"][2, "SelectionType"] == "extreme_day"
    @test rep_extreme["metadata"][2, "ExtremeMetric"] == "peak_load"
    @test sort(rep_extreme["metadata"][!, "SelectedDay"]) == [3, 4]
    @test sort(collect(values(rep_extreme["N"]))) == [1.0, 3.0]
    @test sum(values(rep_extreme["N"])) == 4.0

    wind_load, wind_af = build_four_day_extreme_timeseries([5.0, 5.0, 5.0, 5.0], [0.9, 0.8, 0.7, 0.1])
    wind_config = Dict{String,Any}(
        "rep_day_settings" => Dict(
            "time_periods" => Dict(1 => [1, 1, 1, 4]),
            "clustering_method" => "kmedoids",
            "feature_mode" => "joint_daily",
            "representative_days_per_period" => 1,
            "add_extreme_days" => 1,
            "extreme_day_metrics" => ["min_wind"],
            "include_load" => 1,
            "include_af" => 1,
            "include_dr" => 0,
            "normalize_features" => 1,
        ),
    )
    wind_generator_df = DataFrame("Pmax (MW)" => [50.0], "Type" => ["WindOn"])
    rep_wind_extreme = HOPE.build_endogenous_rep_periods(wind_load, wind_af, ["Z1"], ["G1"], wind_config; generator_data=wind_generator_df)
    @test rep_wind_extreme["T"] == [1, 2]
    @test rep_wind_extreme["metadata"][2, "ExtremeMetric"] == "min_wind"
    @test 4 in rep_wind_extreme["metadata"][!, "SelectedDay"]
    @test sum(values(rep_wind_extreme["N"])) == 4.0

    wrap_loaddata = DataFrame(
        Symbol("Time Period") => vcat(fill(1, 24), fill(1, 24)),
        :Month => vcat(fill(12, 24), fill(1, 24)),
        :Day => vcat(fill(31, 24), fill(1, 24)),
        :Hours => repeat(collect(1:24), 2),
        :Z1 => ones(48),
        :NI => zeros(48),
    )
    wrap_config = Dict{String,Any}(
        "rep_day_settings" => Dict(
            "time_periods" => Dict(1 => [12, 31, 1, 1]),
        ),
    )
    wrap_af = DataFrame(
        Symbol("Time Period") => vcat(fill(1, 24), fill(1, 24)),
        :Month => vcat(fill(12, 24), fill(1, 24)),
        :Day => vcat(fill(31, 24), fill(1, 24)),
        :Hours => repeat(collect(1:24), 2),
        :G1 => ones(48),
    )
    weights = HOPE.endogenous_rep_day_weights(wrap_loaddata, wrap_af, ["Z1"], ["G1"], wrap_config)
    @test weights[1] == 2.0

    refine_load, refine_af = build_four_day_extreme_timeseries([0.0, 1.0, 2.0, 10.0], [1.0, 1.0, 1.0, 1.0])
    refine_load = vcat(refine_load, DataFrame(Symbol("Time Period") => fill(1, 24), :Month => fill(1, 24), :Day => fill(5, 24), :Hours => collect(1:24), :Z1 => fill(20.0, 24), :NI => zeros(24)))
    refine_af = vcat(refine_af, DataFrame(Symbol("Time Period") => fill(1, 24), :Month => fill(1, 24), :Day => fill(5, 24), :Hours => collect(1:24), :G1 => ones(24)))
    refine_config = Dict{String,Any}(
        "rep_day_settings" => Dict(
            "time_periods" => Dict(1 => [1, 1, 1, 5]),
            "clustering_method" => "kmedoids",
            "feature_mode" => "joint_daily",
            "representative_days_per_period" => 1,
            "iterative_refinement" => 1,
            "iterative_refinement_days_per_period" => 1,
            "include_load" => 1,
            "include_af" => 1,
            "include_dr" => 0,
            "normalize_features" => 1,
        ),
    )
    refine_generator_df = DataFrame("Pmax (MW)" => [100.0], "Type" => ["NGCC_CCS"])
    rep_refine = HOPE.build_endogenous_rep_periods(refine_load, refine_af, ["Z1"], ["G1"], refine_config; generator_data=refine_generator_df)
    @test rep_refine["T"] == [1, 2]
    @test sum(values(rep_refine["N"])) == 5.0
    @test sort(collect(values(rep_refine["N"]))) == [1.0, 4.0]
    @test rep_refine["metadata"][2, "SelectionType"] == "refinement_day"
    @test rep_refine["metadata"][2, "RefinementScore"] > 0.0
    selected_days = sort(rep_refine["metadata"][!, "SelectedDay"])
    @test length(selected_days) == 2
    @test maximum(selected_days) >= 4

    overlap_config = Dict{String,Any}(
        "rep_day_settings" => Dict(
            "time_periods" => Dict(
                1 => [1, 1, 1, 2],
                2 => [1, 2, 1, 3],
            ),
        ),
    )
    @test_throws ArgumentError HOPE.build_endogenous_rep_periods(loaddata, afdata, ["Z1"], ["G1"], overlap_config)

    gap_config = Dict{String,Any}(
        "rep_day_settings" => Dict(
            "time_periods" => Dict(
                1 => [1, 1, 1, 1],
                2 => [1, 3, 1, 3],
            ),
        ),
    )
    @test_throws ArgumentError HOPE.build_endogenous_rep_periods(loaddata, afdata, ["Z1"], ["G1"], gap_config)

    external_load = loaddata[1:24, :]
    external_af = afdata[1:24, :]

    external_weight_df = DataFrame(Symbol("Time Period") => [1, 1], :Weight => [1.0, 2.0])
    @test_throws ArgumentError HOPE.validate_external_rep_day_inputs(external_load, external_af, external_weight_df)

    external_bad_weight_df = DataFrame(Symbol("Time Period") => [1], :Weight => [0.0])
    @test_throws ArgumentError HOPE.validate_external_rep_day_inputs(external_load, external_af, external_bad_weight_df)

    external_ok_weight_df = DataFrame(Symbol("Time Period") => [1], :Weight => [3.0])
    external_n = HOPE.validate_external_rep_day_inputs(external_load, external_af, external_ok_weight_df)
    @test external_n[1] == 3.0

    mktempdir() do outdir
        HOPE.write_rep_day_audit_outputs(outdir, 1, 0, rep_refine["N"]; rep_period_data=rep_refine)
        @test isfile(joinpath(outdir, "representative_period_weights.csv"))
        @test isfile(joinpath(outdir, "representative_period_metadata.csv"))
        @test isfile(joinpath(outdir, "representative_period_assignments.csv"))
        @test isfile(joinpath(outdir, "representative_period_weight_check.csv"))
        weight_check = CSV.read(joinpath(outdir, "representative_period_weight_check.csv"), DataFrame)
        @test nrow(weight_check) == 1
        @test weight_check[1, "OriginalDays"] == 5
        @test weight_check[1, "RepresentativeWeightDays"] == 5.0
        @test weight_check[1, "WeightDifferenceDays"] == 0.0
    end
end
