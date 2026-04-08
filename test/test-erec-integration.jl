using JuMP
using DataFrames
using CSV
using YAML

const EREC_PROJECT_ROOT = normpath(joinpath(@__DIR__, ".."))

@testset "EREC Integration" begin
    if get(ENV, "HOPE_RUN_EREC_INTEGRATION", "0") != "1"
        @info "Skipping EREC integration test. Set HOPE_RUN_EREC_INTEGRATION=1 to enable."
    else
        required_cases = [
            "MD_GTEP_erec_test_case",
            "MD_GTEP_erec_stressed_case",
            "MD_GTEP_erec_candidate_case",
            "MD_GTEP_erec_fullchron_stressed_case",
            "MD_GTEP_erec_linebuild_case",
        ]
        missing_cases = [
            case_name for case_name in required_cases if
            !isdir(joinpath(EREC_PROJECT_ROOT, "ModelCases", case_name))
        ]

        if !isempty(missing_cases)
            @info "Skipping EREC integration test because local fixture cases are not present." missing_cases
        else
            @testset "Candidate Build Reconstruction" begin
                mktempdir() do tmpdir
                    src_case =
                        joinpath(EREC_PROJECT_ROOT, "ModelCases", "MD_GTEP_erec_test_case")
                    tmp_case = joinpath(tmpdir, "MD_GTEP_erec_test_case")
                    cp(src_case, tmp_case; force = true)

                    res = HOPE.calculate_erec(
                        tmp_case;
                        resource_types = ["generator", "storage"],
                        output_dir_name = "output_erec_candidate",
                        write_cc_to_tables = 0,
                    )

                    @test res["baseline_eue"] <= 1.0e-6
                    @test nrow(res["erec_results"]) == 0

                    fixed_gens = res["fixed_fleet_input"]["Gendata"]
                    fixed_storage = res["fixed_fleet_input"]["Storagedata"]
                    @test any(string.(fixed_gens[:, "EREC_Source"]) .== "candidate")
                    @test any(string.(fixed_storage[:, "EREC_Source"]) .== "candidate")

                    candidate_gen_rows =
                        fixed_gens[string.(fixed_gens[:, "EREC_Source"]) .== "candidate", :]
                    candidate_storage_rows = fixed_storage[
                        string.(fixed_storage[:, "EREC_Source"]) .== "candidate",
                        :,
                    ]
                    @test all(
                        HOPE.to_float_erec.(candidate_gen_rows[:, "Pmax (MW)"]) .> 0.0,
                    )
                    @test all(
                        HOPE.to_float_erec.(candidate_storage_rows[:, "Max Power (MW)"]) .>
                        0.0,
                    )

                    afdata = res["fixed_fleet_input"]["AFdata"]
                    @test size(afdata, 2) == nrow(fixed_gens) + 4
                    @test all(("G$(i)" in names(afdata)) for i = 1:nrow(fixed_gens))
                end
            end

            @testset "Candidate Scope All" begin
                mktempdir() do tmpdir
                    src_case = joinpath(
                        EREC_PROJECT_ROOT,
                        "ModelCases",
                        "MD_GTEP_erec_candidate_case",
                    )
                    tmp_case = joinpath(tmpdir, "MD_GTEP_erec_candidate_case")
                    cp(src_case, tmp_case; force = true)

                    res = HOPE.calculate_erec(
                        tmp_case;
                        resource_types = ["generator"],
                        resource_scope = "all",
                        output_dir_name = "output_erec_all",
                        write_cc_to_tables = 1,
                    )

                    @test res["baseline_eue"] > 0.0
                    results = res["erec_results"]
                    @test nrow(results) == 10
                    @test sum(results.Source .== "existing") == 6
                    @test sum(results.Source .== "candidate") == 4
                    @test count(results.BaselinePowerMW .> 0.0) == 7
                    @test count(results.BaselinePowerMW .== 0.0) == 3
                    @test any(
                        (results.Source .== "candidate") .&
                        (results.BaselinePowerMW .> 0.0),
                    )
                    @test any(
                        (results.Source .== "candidate") .&
                        (results.BaselinePowerMW .== 0.0),
                    )
                    @test all((isnan(x) || x <= 1.0 + 1.0e-8) for x in results.EREC)

                    @test haskey(res["output_paths"], "gendata_with_erec_cc")
                    cc_gendata =
                        CSV.read(res["output_paths"]["gendata_with_erec_cc"], DataFrame)
                    @test nrow(cc_gendata) == 10
                end
            end

            @testset "Aggregated Full Chronology Regression" begin
                mktempdir() do tmpdir
                    src_case = joinpath(
                        EREC_PROJECT_ROOT,
                        "ModelCases",
                        "MD_GTEP_erec_fullchron_stressed_case",
                    )
                    tmp_case = joinpath(tmpdir, "MD_GTEP_erec_fullchron_stressed_case")
                    cp(src_case, tmp_case; force = true)

                    config = open(
                        joinpath(tmp_case, "Settings", "HOPE_model_settings.yml"),
                    ) do io
                        YAML.load(io)
                    end
                    input = HOPE.load_data(config, tmp_case)
                    gendata = input["Gendata"]
                    afdata = input["AFdata"]

                    @test "FOR" in names(gendata)

                    wind_rows = findall(
                        (string.(gendata[:, "Zone"]) .== "APS_MD") .&
                        (string.(gendata[:, "Type"]) .== "WindOn"),
                    )
                    solar_rows = findall(
                        (string.(gendata[:, "Zone"]) .== "APS_MD") .&
                        (string.(gendata[:, "Type"]) .== "SolarPV"),
                    )
                    thermal_rows = findall(
                        (string.(gendata[:, "Zone"]) .== "PEPCO") .&
                        (string.(gendata[:, "Type"]) .== "NGCC_CCS"),
                    )

                    @test length(wind_rows) == 1
                    @test length(solar_rows) == 1
                    @test length(thermal_rows) == 1
                    @test HOPE.to_float_erec(gendata[thermal_rows[1], "FOR"]) > 0.0

                    wind_col = "G$(wind_rows[1])"
                    solar_col = "G$(solar_rows[1])"
                    @test wind_col in names(afdata)
                    @test solar_col in names(afdata)
                    @test minimum(Float64.(afdata[:, wind_col])) <
                          maximum(Float64.(afdata[:, wind_col]))
                    @test minimum(Float64.(afdata[:, solar_col])) <
                          maximum(Float64.(afdata[:, solar_col]))

                    res = HOPE.calculate_erec(
                        tmp_case;
                        output_dir_name = "output_erec_fullchron_regression",
                        write_cc_to_tables = 0,
                    )

                    @test res["baseline_eue"] > 0.0
                    results = res["erec_results"]
                    @test nrow(results) == 8
                    @test all((isnan(x) || x <= 1.0 + 1.0e-8) for x in results.EREC)

                    wind_erec = results[
                        (results.Technology .== "WindOn") .& (results.Zone .== "APS_MD"),
                        "EREC",
                    ][1]
                    solar_erec = results[
                        (results.Technology .== "SolarPV") .& (results.Zone .== "APS_MD"),
                        "EREC",
                    ][1]
                    thermal_erec = results[
                        (results.Technology .== "NGCC_CCS") .& (results.Zone .== "PEPCO"),
                        "EREC",
                    ][1]
                    hydro_erec = results[
                        (results.Technology .== "Hydro") .& (results.Zone .== "APS_MD"),
                        "EREC",
                    ][1]

                    @test wind_erec < 0.9
                    @test solar_erec < 0.9
                    @test thermal_erec < 1.0
                    @test thermal_erec > 0.9
                    @test hydro_erec > 0.99
                end
            end

            @testset "Full Chronology Storage Regression" begin
                mktempdir() do tmpdir
                    src_case = joinpath(
                        EREC_PROJECT_ROOT,
                        "ModelCases",
                        "MD_GTEP_erec_fullchron_stressed_case",
                    )
                    tmp_case = joinpath(tmpdir, "MD_GTEP_erec_fullchron_stressed_case")
                    cp(src_case, tmp_case; force = true)

                    res = HOPE.calculate_erec(
                        tmp_case;
                        resource_types = ["storage"],
                        resource_scope = "built_only",
                        output_dir_name = "output_erec_fullchron_storage_regression",
                        write_cc_to_tables = 0,
                    )

                    @test res["baseline_eue"] > 0.0
                    results = res["erec_results"]
                    @test nrow(results) == 1
                    @test all(results.ResourceType .== "storage")
                    @test all(
                        (isnan(x) || (x >= -1.0e-8 && x <= 1.0 + 1.0e-8)) for
                        x in results.EREC
                    )

                    battery_row = results[1, :]
                    @test battery_row["Technology"] == "Battery"
                    @test battery_row["Zone"] == "APS_MD"
                    @test battery_row["BaselinePowerMW"] ≈ 11.0
                    @test battery_row["BaselineEnergyMWh"] ≈ 44.0
                    @test battery_row["BaselineEnergyMWh"] /
                          battery_row["BaselinePowerMW"] ≈ 4.0
                    @test battery_row["EREC"] > 0.0
                    @test battery_row["EREC"] < 1.0
                    @test battery_row["EUEResource"] < battery_row["EUEBase"]
                    @test battery_row["EUEPerfect"] < battery_row["EUEResource"]

                    fixed_storage = res["fixed_fleet_input"]["Storagedata"]
                    @test nrow(fixed_storage) == 1
                    @test fixed_storage[1, "Type"] == "Battery"
                    @test fixed_storage[1, "Zone"] == "APS_MD"
                    @test HOPE.to_float_erec(fixed_storage[1, "Capacity (MWh)"]) /
                          HOPE.to_float_erec(fixed_storage[1, "Max Power (MW)"]) ≈ 4.0

                    for file_key in ("erec_results", "erec_summary")
                        @test haskey(res["output_paths"], file_key)
                        @test isfile(res["output_paths"][file_key])
                    end
                end
            end

            @testset "Full Chronology Storage All Scope" begin
                mktempdir() do tmpdir
                    src_case = joinpath(
                        EREC_PROJECT_ROOT,
                        "ModelCases",
                        "MD_GTEP_erec_fullchron_stressed_case",
                    )
                    tmp_case = joinpath(tmpdir, "MD_GTEP_erec_fullchron_stressed_case")
                    cp(src_case, tmp_case; force = true)

                    res = HOPE.calculate_erec(
                        tmp_case;
                        resource_types = ["storage"],
                        resource_scope = "all",
                        output_dir_name = "output_erec_fullchron_storage_all_regression",
                        write_cc_to_tables = 1,
                    )

                    @test res["baseline_eue"] > 0.0
                    results = res["erec_results"]
                    @test nrow(results) == 5
                    @test all(results.ResourceType .== "storage")
                    @test sum(results.Source .== "existing") == 1
                    @test sum(results.Source .== "candidate") == 4
                    @test count(results.BaselinePowerMW .> 0.0) == 1
                    @test count(results.BaselinePowerMW .== 0.0) == 4
                    @test all(
                        (isnan(x) || (x >= -1.0e-8 && x <= 1.0 + 1.0e-8)) for
                        x in results.EREC
                    )

                    existing_row = results[results.Source .== "existing", :][1, :]
                    @test existing_row["Technology"] == "Battery"
                    @test existing_row["Zone"] == "APS_MD"
                    @test existing_row["BaselinePowerMW"] ≈ 11.0
                    @test existing_row["BaselineEnergyMWh"] ≈ 44.0

                    candidate_rows = results[results.Source .== "candidate", :]
                    @test Set(candidate_rows.Zone) ==
                          Set(["APS_MD", "BGE", "DPL_MD", "PEPCO"])
                    @test all(candidate_rows.BaselinePowerMW .== 0.0)
                    @test all(candidate_rows.BaselineEnergyMWh .== 0.0)
                    @test any(candidate_rows.EREC .> existing_row["EREC"])

                    @test haskey(res["output_paths"], "storagedata_with_erec_cc")
                    cc_storagedata =
                        CSV.read(res["output_paths"]["storagedata_with_erec_cc"], DataFrame)
                    @test nrow(cc_storagedata) == 5
                end
            end

            @testset "Transmission Build Reconstruction" begin
                mktempdir() do tmpdir
                    src_case = joinpath(
                        EREC_PROJECT_ROOT,
                        "ModelCases",
                        "MD_GTEP_erec_linebuild_case",
                    )
                    tmp_case = joinpath(tmpdir, "MD_GTEP_erec_linebuild_case")
                    cp(src_case, tmp_case; force = true)

                    res = HOPE.calculate_erec(
                        tmp_case;
                        resource_types = ["storage"],
                        resource_scope = "built_only",
                        output_dir_name = "output_erec_linebuild_regression",
                        write_cc_to_tables = 0,
                    )

                    @test res["baseline_eue"] > 0.0
                    @test nrow(res["erec_results"]) == 1
                    @test all(
                        (isnan(x) || (x >= -1.0e-8 && x <= 1.0 + 1.0e-8)) for
                        x in res["erec_results"].EREC
                    )

                    line_builds = [
                        value(res["baseline_model"][:y][l]) for
                        l in axes(res["baseline_model"][:y], 1)
                    ]
                    @test any(line_builds .> 0.0)

                    fixed_lines = res["fixed_fleet_input"]["Linedata"]
                    @test nrow(fixed_lines) == 2
                    @test sum(HOPE.to_float_erec.(fixed_lines[:, "Capacity (MW)"])) > 75.0
                    @test any(HOPE.to_float_erec.(fixed_lines[:, "Capacity (MW)"]) .< 1.0)
                    @test Set(string.(fixed_lines[:, "From_zone"])) == Set(["PEPCO"])
                    @test Set(string.(fixed_lines[:, "To_zone"])) == Set(["APS_MD"])

                    for file_key in ("erec_results", "erec_summary")
                        @test haskey(res["output_paths"], file_key)
                        @test isfile(res["output_paths"][file_key])
                    end
                end
            end

            mktempdir() do tmpdir
                src_case =
                    joinpath(EREC_PROJECT_ROOT, "ModelCases", "MD_GTEP_erec_stressed_case")
                tmp_case = joinpath(tmpdir, "MD_GTEP_erec_stressed_case")
                cp(src_case, tmp_case; force = true)

                res = HOPE.calculate_erec(
                    tmp_case;
                    resource_types = ["generator", "storage"],
                    output_dir_name = "output_erec_test",
                    write_cc_to_tables = 0,
                )

                @test res["baseline_eue"] > 0.0
                results = res["erec_results"]
                @test nrow(results) == 7
                @test all((isnan(x) || x <= 1.0 + 1.0e-8) for x in results.EREC)

                model = res["fixed_fleet_model"]
                input_data = res["fixed_fleet_input"]
                load = input_data["Loaddata"]
                weights_df = input_data["RepWeightData"]
                weights = Dict(
                    Int(row["Time Period"]) => Float64(row["Weight"]) for
                    row in eachrow(weights_df)
                )
                I = axes(model[:p_LS], 1)
                H = axes(model[:p_LS], 2)

                eue_hours_unweighted = 0
                eue_hours_weighted = 0.0
                for h in H
                    ls = sum(value(model[:p_LS][i, h]) for i in I)
                    if ls > 1.0e-6
                        eue_hours_unweighted += 1
                        eue_hours_weighted += weights[Int(load[h, "Time Period"])]
                    end
                end

                @test eue_hours_unweighted > 0
                @test eue_hours_unweighted < length(H)
                @test eue_hours_weighted > 0.0
                @test eue_hours_weighted <
                      sum(Float64(row["Weight"]) * 24.0 for row in eachrow(weights_df))

                for file_key in ("erec_results", "erec_summary")
                    @test haskey(res["output_paths"], file_key)
                    @test isfile(res["output_paths"][file_key])
                end
            end
        end
    end
end
