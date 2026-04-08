@testset "EREC Settings" begin
    @test isdefined(HOPE, :calculate_erec)
    @test isdefined(HOPE, :default_erec_settings)
    @test isdefined(HOPE, :load_erec_settings)

    defaults = HOPE.default_erec_settings()
    @test defaults["output_dir_name"] == "output_erec"
    @test defaults["resource_scope"] == "built_only"
    @test defaults["voll_override"] === nothing

    input_data = Dict("Singlepar" => DataFrame(VOLL = [15000.0]))
    HOPE.apply_erec_overrides!(input_data, defaults)
    @test input_data["Singlepar"][1, "VOLL"] == 15000.0

    warn_input = Dict("Singlepar" => DataFrame(VOLL = [15000.0]))
    @test_logs (:warn, r"differs from the baseline solved-case VOLL") HOPE.apply_erec_overrides!(
        warn_input,
        Dict("voll_override" => 20000.0);
        voll_warning_context = :solved_baseline,
    )
    @test warn_input["Singlepar"][1, "VOLL"] == 20000.0

    mktempdir() do tmpdir
        settings_dir = joinpath(tmpdir, "Settings")
        mkpath(settings_dir)
        open(joinpath(settings_dir, "HOPE_erec_settings.yml"), "w") do io
            write(
                io,
                """
enabled: 1
delta_mw: 2.5
resource_types:
  - generator
write_outputs: 0
""",
            )
        end
        loaded = HOPE.load_erec_settings(tmpdir)
        @test loaded["delta_mw"] == 2.5
        @test loaded["write_outputs"] == 0
        @test loaded["resource_types"] == ["generator"]
    end
end
