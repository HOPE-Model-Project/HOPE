using DataFrames

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
    weights = HOPE.endogenous_rep_day_weights(wrap_loaddata, wrap_config)
    @test weights[1] == 2.0
end
