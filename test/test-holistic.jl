using CSV
using DataFrames

@testset "Holistic helpers" begin
	@test HOPE.pcm_clamp_availability_factor(-0.001411903) == 0.0
	@test HOPE.pcm_clamp_availability_factor(1.25) == 1.0
	@test HOPE.pcm_clamp_availability_factor(0.42) == 0.42
	@test HOPE.pcm_clamp_availability_factor(NaN) == 0.0

    generation_df = DataFrame(
        :Zone => String[],
        :Technology => String[],
        :New_Build => Float64[],
        Symbol("Capacity_FIN (MW)") => Float64[],
    )
    new_generation = HOPE.extract_new_generation_rows(generation_df)
    @test names(new_generation) == ["Zone", "Type", "Pmax (MW)"]
    @test nrow(new_generation) == 0

    storage_df = DataFrame(
        :Zone => String[],
        :Technology => String[],
        :New_Build => Float64[],
        Symbol("Capacity (MW)") => Float64[],
        Symbol("EnergyCapacity (MWh)") => Float64[],
    )
    new_storage = HOPE.extract_new_storage_rows(storage_df)
    @test names(new_storage) == ["Zone", "Type", "Capacity (MWh)", "Max Power (MW)"]
    @test nrow(new_storage) == 0

    fill_df = DataFrame(
        :Zone => ["Z1", "Z2", "Z3"],
        :Type => ["SolarPV", "SolarPV", "SolarPV"],
        Symbol("Pmin (MW)") => [0.0, NaN, missing],
        Symbol("Cost (\$/MWh)") => [14.0, NaN, missing],
        :FOR => [0.0, NaN, missing],
    )
    filled = HOPE.holistic_fill_columns(fill_df, [[:Zone, :Type], [:Type]], [Symbol("Pmin (MW)"), Symbol("Cost (\$/MWh)"), :FOR])
    @test filled[2, Symbol("Pmin (MW)")] == 0.0
    @test filled[3, Symbol("Pmin (MW)")] == 0.0
    @test filled[2, Symbol("Cost (\$/MWh)")] == 14.0
    @test filled[3, Symbol("Cost (\$/MWh)")] == 14.0
    @test filled[2, :FOR] == 0.0
    @test filled[3, :FOR] == 0.0

    @testset "PCM handoff integrity" begin
        gtep_output = Dict(
            "capacity" => DataFrame(
                :Technology => ["SolarPV", "SolarPV", "WindOn", "NGCC"],
                :Zone => ["APS_MD", "APS_MD", "BGE", "BGE"],
                :EC_Category => ["Candidate", "Candidate", "Candidate", "Existing"],
                :New_Build => [1.0, 1.0, 1.0, 0.0],
                Symbol("Capacity_INI (MW)") => [0.0, 0.0, 0.0, 200.0],
                Symbol("Capacity_RET (MW)") => [0.0, 0.0, 0.0, 0.0],
                Symbol("Capacity_FIN (MW)") => [100.0, 50.0, 75.0, 200.0],
            ),
            "es_capacity" => DataFrame(
                :Technology => ["Battery", "Battery", "Battery", "Battery"],
                :Zone => ["APS_MD", "APS_MD", "BGE", "BGE"],
                :EC_Category => ["Candidate", "Candidate", "Candidate", "Existing"],
                :New_Build => [1.0, 1.0, 1.0, 0.0],
                Symbol("EnergyCapacity (MWh)") => [400.0, 200.0, 120.0, 100.0],
                Symbol("Capacity (MW)") => [100.0, 50.0, 30.0, 25.0],
            ),
            "line" => DataFrame(
                :From_zone => ["APS_MD"],
                :To_zone => ["BGE"],
                :New_Build => [1.0],
                Symbol("Capacity (MW)") => [25.0],
            ),
        )

        pcm_input = Dict(
            "Gendata" => DataFrame(
                :Zone => String[],
                :Type => String[],
                Symbol("Pmax (MW)") => Float64[],
                Symbol("Pmin (MW)") => Float64[],
                Symbol("Cost (\$/MWh)") => Float64[],
                :EF => Float64[],
                :CC => Float64[],
                :FOR => Float64[],
                :RM_SPIN => Float64[],
                :RU => Float64[],
                :RD => Float64[],
                :Flag_thermal => Float64[],
                :Flag_VRE => Float64[],
                :Flag_mustrun => Float64[],
            ),
            "Storagedata" => DataFrame(
                :Zone => String[],
                :Type => String[],
                Symbol("Capacity (MWh)") => Float64[],
                Symbol("Max Power (MW)") => Float64[],
                Symbol("Charging efficiency") => Float64[],
                Symbol("Discharging efficiency") => Float64[],
                Symbol("Cost (\$/MWh)") => Float64[],
                :EF => Float64[],
                :CC => Float64[],
                Symbol("Charging Rate") => Float64[],
                Symbol("Discharging Rate") => Float64[],
            ),
            "Linedata" => DataFrame(
                :From_zone => ["BGE"],
                :To_zone => ["APS_MD"],
                Symbol("Capacity (MW)") => [100.0],
            ),
        )

        pcm_config = Dict(
            "resource_aggregation" => 0,
            "unit_commitment" => 0,
        )

        updated_input = HOPE.prepare_pcm_inputs_from_gtep(gtep_output, pcm_input, pcm_config)

        observed_generation = select(updated_input["Gendata"], :Zone, :Type, Symbol("Pmax (MW)"))
        sort!(observed_generation, [:Zone, :Type])
        expected_generation = DataFrame(
            :Zone => ["APS_MD", "BGE"],
            :Type => ["SolarPV", "WindOn"],
            Symbol("Pmax (MW)") => [150.0, 75.0],
        )
        @test observed_generation == expected_generation

        observed_storage = select(updated_input["Storagedata"], :Zone, :Type, Symbol("Capacity (MWh)"), Symbol("Max Power (MW)"))
        sort!(observed_storage, [:Zone, :Type])
        expected_storage = DataFrame(
            :Zone => ["APS_MD", "BGE"],
            :Type => ["Battery", "Battery"],
            Symbol("Capacity (MWh)") => [600.0, 120.0],
            Symbol("Max Power (MW)") => [150.0, 30.0],
        )
        @test observed_storage == expected_storage

        @test updated_input["Linedata"][1, Symbol("Capacity (MW)")] == 125.0
    end

    @testset "PCM handoff persistence" begin
        gtep_output = Dict(
            "capacity" => DataFrame(
                :Technology => ["SolarPV"],
                :Zone => ["APS_MD"],
                :EC_Category => ["Candidate"],
                :New_Build => [1.0],
                Symbol("Capacity_INI (MW)") => [0.0],
                Symbol("Capacity_RET (MW)") => [0.0],
                Symbol("Capacity_FIN (MW)") => [100.0],
            ),
            "es_capacity" => DataFrame(
                :Technology => String[],
                :Zone => String[],
                :EC_Category => String[],
                :New_Build => Float64[],
                Symbol("EnergyCapacity (MWh)") => Float64[],
                Symbol("Capacity (MW)") => Float64[],
            ),
            "line" => DataFrame(
                :From_zone => String[],
                :To_zone => String[],
                :New_Build => Float64[],
                Symbol("Capacity (MW)") => Float64[],
            ),
        )

        raw_gendata = DataFrame(
            :Zone => ["APS_MD"],
            :Type => ["SolarPV"],
            Symbol("Pmax (MW)") => [50.0],
            Symbol("Pmin (MW)") => [0.0],
            Symbol("Cost (\$/MWh)") => [0.0],
            :EF => [0.0],
            :CC => [0.35],
            :FOR => [0.0],
            :RM_SPIN => [0.0],
            :RU => [1.0],
            :RD => [1.0],
            :Flag_thermal => [0],
            :Flag_VRE => [1],
            :Flag_mustrun => [0],
        )

        pcm_input = Dict{String,Any}(
            "Gendata" => copy(raw_gendata),
            "GendataRaw" => copy(raw_gendata),
            "Storagedata" => DataFrame(
                :Zone => String[],
                :Type => String[],
                Symbol("Capacity (MWh)") => Float64[],
                Symbol("Max Power (MW)") => Float64[],
                Symbol("Charging efficiency") => Float64[],
                Symbol("Discharging efficiency") => Float64[],
                Symbol("Cost (\$/MWh)") => Float64[],
                :EF => Float64[],
                :CC => Float64[],
                Symbol("Charging Rate") => Float64[],
                Symbol("Discharging Rate") => Float64[],
            ),
            "Linedata" => DataFrame(
                :From_zone => ["APS_MD"],
                :To_zone => ["BGE"],
                Symbol("Capacity (MW)") => [100.0],
            ),
        )

        pcm_config = Dict(
            "resource_aggregation" => 1,
            "unit_commitment" => 0,
            "DataCase" => "Data_PCM2035",
        )

        updated_input = HOPE.prepare_pcm_inputs_from_gtep(gtep_output, pcm_input, pcm_config)
        @test haskey(updated_input, "GendataRaw")
        @test nrow(updated_input["GendataRaw"]) == 2
        @test updated_input["Gendata"][1, Symbol("Pmax (MW)")] == 150.0

        mktempdir() do tmpdir
            case_dir = joinpath(tmpdir, "pcm_case")
            paths = HOPE.persist_pcm_inputs_for_holistic(case_dir, pcm_config, updated_input)

            persisted_gendata = CSV.read(paths["gendata"], DataFrame)
            @test nrow(persisted_gendata) == 2

            observed_raw = select(persisted_gendata, :Zone, :Type, Symbol("Pmax (MW)"))
            sort!(observed_raw, [:Zone, :Type, Symbol("Pmax (MW)")])
            expected_raw = DataFrame(
                :Zone => ["APS_MD", "APS_MD"],
                :Type => ["SolarPV", "SolarPV"],
                Symbol("Pmax (MW)") => [50.0, 100.0],
            )
            @test observed_raw == expected_raw

            persisted_linedata = CSV.read(paths["linedata"], DataFrame)
            @test persisted_linedata[1, Symbol("Capacity (MW)")] == 100.0
        end
    end

    @testset "Fresh holistic case clone" begin
        mktempdir() do tmpdir
            source_case = joinpath(tmpdir, "pcm_case")
            mkpath(joinpath(source_case, "Settings"))
            mkpath(joinpath(source_case, "Data"))
            mkpath(joinpath(source_case, "output"))
            mkpath(joinpath(source_case, "output_holistic"))
            mkpath(joinpath(source_case, "plot_output"))
            mkpath(joinpath(source_case, "backup"))
            mkpath(joinpath(source_case, "debug_report"))
            mkpath(joinpath(source_case, "output_backup_legacy"))

            write(joinpath(source_case, "Settings", "HOPE_model_settings.yml"), "model_mode: PCM\ndebug_stage_file: \"old/debug_stage.txt\"\n")
            write(joinpath(source_case, "Data", "keep.txt"), "keep")
            write(joinpath(source_case, "output", "drop.txt"), "drop")

            debug_stage_file = joinpath(tmpdir, "fresh", "debug_stage.txt")
            fresh_case = HOPE.prepare_fresh_holistic_case(source_case, "test_run"; debug_stage_file=debug_stage_file)

            @test fresh_case != source_case
            @test isdir(fresh_case)
            @test isfile(joinpath(fresh_case, "Data", "keep.txt"))
            @test !isdir(joinpath(fresh_case, "output"))
            @test !isdir(joinpath(fresh_case, "output_holistic"))
            @test !isdir(joinpath(fresh_case, "plot_output"))
            @test !isdir(joinpath(fresh_case, "backup"))
            @test !isdir(joinpath(fresh_case, "debug_report"))
            @test !isdir(joinpath(fresh_case, "output_backup_legacy"))

            settings_text = read(joinpath(fresh_case, "Settings", "HOPE_model_settings.yml"), String)
            expected_debug_stage_file = replace(normpath(debug_stage_file), "\\" => "/")
            @test occursin("debug_stage_file: \"$(expected_debug_stage_file)\"", settings_text)
        end
    end
end