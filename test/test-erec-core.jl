using DataFrames

@testset "EREC Core Helpers" begin
    aggregated = HOPE.aggregate_gendata_gtep(DataFrame(
        :Zone => ["APS_MD", "APS_MD"],
        :Type => ["NGCT_CCS", "NGCT_CCS"],
        Symbol("Pmax (MW)") => [10.0, 30.0],
        Symbol("Pmin (MW)") => [1.0, 3.0],
        Symbol("Cost (\$/MWh)") => [20.0, 40.0],
        :EF => [0.5, 0.7],
        :CC => [0.8, 0.9],
        :AF => [0.6, 1.0],
        :FOR => [0.1, 0.3],
        :Flag_thermal => [1, 1],
        :Flag_VRE => [0, 0],
        :Flag_RET => [0, 1],
        :Flag_mustrun => [0, 0],
        :Flag_RPS => [0, 0],
    ))
    @test nrow(aggregated) == 1
    @test aggregated[1, "FOR"] ≈ 0.25
    @test aggregated[1, "AF"] ≈ 0.9

    aggregated_af = HOPE.aggregate_afdata_gtep(
        DataFrame(
            :Zone => ["APS_MD", "APS_MD"],
            :Type => ["WindOn", "WindOn"],
            Symbol("Pmax (MW)") => [10.0, 30.0],
        ),
        DataFrame(
            :Zone => ["APS_MD"],
            :Type => ["WindOn"],
            Symbol("Pmax (MW)") => [40.0],
        ),
        DataFrame(
            :Zone => ["APS_MD"],
            :Type => ["SolarPV"],
            Symbol("Pmax (MW)") => [5.0],
        ),
        DataFrame(
            Symbol("Time Period") => [1, 1],
            :Hours => [1, 2],
            :G1 => [0.2, 0.4],
            :G2 => [0.6, 0.8],
            :G3 => [0.1, 0.3],
        ),
    )
    @test string.(names(aggregated_af)) == ["Time Period", "Hours", "G1", "G2"]
    @test aggregated_af[!, "G1"] ≈ [0.5, 0.7]
    @test aggregated_af[!, "G2"] == [0.1, 0.3]

    @test HOPE.normalize_erec_resource_types(["generator", "storage", "generator"]) == ["generator", "storage"]
    @test_throws ArgumentError HOPE.normalize_erec_resource_types(["generator", "bad_type"])

    base_input = Dict(
        "Gendata" => DataFrame(
            Symbol("Pmax (MW)") => [10.0, 20.0],
            :AF => [0.9, 0.8],
        ),
        "Gendata_candidate" => DataFrame(
            Symbol("Pmax (MW)") => [30.0, 40.0],
            :AF => [0.6, 0.4],
        ),
        "AFdata" => DataFrame(
            Symbol("Time Period") => [1, 1],
            :Hours => [1, 2],
            :G1 => [0.11, 0.12],
            :G2 => [0.21, 0.22],
            :G3 => [0.31, 0.32],
            :G4 => [0.41, 0.42],
        ),
    )

    fixed_gendata = DataFrame(
        :AF => [0.8, 0.6, 1.0],
        :EREC_Source => ["existing", "candidate", "reference"],
        :EREC_OrigIndex => [2, 1, 0],
        :EREC_Label => ["existing_2", "candidate_1", "reference_same_zone"],
    )

    rebuilt_af = HOPE.rebuild_fixed_fleet_afdata(base_input, fixed_gendata)
    @test string.(names(rebuilt_af)) == ["Time Period", "Hours", "G1", "G2", "G3"]
    @test rebuilt_af[!, "G1"] == base_input["AFdata"][!, :G2]
    @test rebuilt_af[!, "G2"] == base_input["AFdata"][!, :G3]
    @test rebuilt_af[!, "G3"] == [1.0, 1.0]

    input_for_reference = Dict(
        "Gendata" => DataFrame(
            :Zone => ["APS_MD"],
            :Type => ["NGCT_CCS"],
            Symbol("Pmax (MW)") => [5.0],
            Symbol("Pmin (MW)") => [1.0],
            Symbol("Cost (\$/MWh)") => [25.0],
            :EF => [0.5],
            :FOR => [0.1],
            :CC => [0.9],
            :AF => [0.8],
            :Flag_RET => [1],
            :Flag_thermal => [0],
            :Flag_VRE => [1],
            :Flag_mustrun => [1],
            :Flag_RPS => [1],
            :EREC_Source => ["existing"],
            :EREC_OrigIndex => [1],
            :EREC_Label => ["existing_1"],
        ),
    )

    HOPE.append_perfect_reference_generator!(input_for_reference, "PEPCO", 1.0)
    perfect_row = input_for_reference["Gendata"][end, :]
    @test perfect_row["Zone"] == "PEPCO"
    @test perfect_row["Type"] == "ERECPerfect"
    @test perfect_row["Pmax (MW)"] == 1.0
    @test perfect_row["Pmin (MW)"] == 0.0
    @test perfect_row["AF"] == 1.0
    @test perfect_row["FOR"] == 0.0
    @test perfect_row["Flag_thermal"] == 1
    @test perfect_row["Flag_VRE"] == 0
    @test perfect_row["EREC_Source"] == "reference"

    fixed_input = Dict(
        "Gendata" => DataFrame(
            :CC => [0.1, 0.2],
            :Type => ["Hydro", "WindOn"],
        ),
        "Storagedata" => DataFrame(
            :CC => [0.3],
            :Type => ["Battery"],
        ),
    )
    erec_results = DataFrame(
        ResourceType = ["generator", "generator", "storage"],
        ResourceIndex = [1, 2, 1],
        EREC = [0.95, NaN, 0.85],
    )

    cc_gendata, cc_storagedata = HOPE.build_cc_export_tables(Dict("Gendata" => DataFrame(), "Gendata_candidate" => DataFrame(), "Storagedata" => DataFrame(), "Estoragedata_candidate" => DataFrame()), fixed_input, erec_results)
    @test cc_gendata[1, "CC"] == 0.95
    @test cc_gendata[2, "CC"] == 0.2
    @test cc_storagedata[1, "CC"] == 0.85

    fixed_input_all = Dict(
        "Gendata" => DataFrame(
            :Zone => ["APS_MD", "PEPCO"],
            Symbol("Pmax (MW)") => [10.0, 15.0],
            :Type => ["Hydro", "NGCT_CCS"],
            :CC => [0.1, 0.2],
            :EREC_Source => ["existing", "candidate"],
            :EREC_OrigIndex => [1, 1],
            :EREC_Label => ["existing_1", "candidate_1"],
        ),
        "Storagedata" => DataFrame(
            :Zone => ["APS_MD"],
            Symbol("Max Power (MW)") => [5.0],
            Symbol("Capacity (MWh)") => [20.0],
            :Type => ["Battery"],
            :CC => [0.3],
            :EREC_Source => ["existing"],
            :EREC_OrigIndex => [1],
            :EREC_Label => ["existing_1"],
        ),
    )
    base_input_all = Dict(
        "Gendata" => DataFrame(
            :Zone => ["APS_MD", "APS_MD"],
            Symbol("Pmax (MW)") => [10.0, 20.0],
            :Type => ["Hydro", "WindOn"],
            :CC => [0.1, 0.15],
        ),
        "Gendata_candidate" => DataFrame(
            :Zone => ["PEPCO", "PEPCO"],
            Symbol("Pmax (MW)") => [15.0, 25.0],
            :Type => ["NGCT_CCS", "SolarPV"],
            :CC => [0.2, 0.25],
        ),
        "Storagedata" => DataFrame(
            :Zone => ["APS_MD"],
            Symbol("Max Power (MW)") => [5.0],
            Symbol("Capacity (MWh)") => [20.0],
            :Type => ["Battery"],
            :CC => [0.3],
        ),
        "Estoragedata_candidate" => DataFrame(
            :Zone => ["PEPCO"],
            Symbol("Max Power (MW)") => [8.0],
            Symbol("Capacity (MWh)") => [32.0],
            :Type => ["Battery"],
            :CC => [0.4],
        ),
    )
    erec_results_all = DataFrame(
        ResourceType = ["generator", "generator", "storage"],
        ResourceIndex = [1, 0, 1],
        Source = ["existing", "candidate", "candidate"],
        SourceIndex = [2, 2, 1],
        EREC = [0.91, 0.42, 0.77],
    )

    cc_gendata_all, cc_storagedata_all = HOPE.build_cc_export_tables(base_input_all, fixed_input_all, erec_results_all; resource_scope="all")
    @test nrow(cc_gendata_all) == 4
    @test nrow(cc_storagedata_all) == 2
    @test cc_gendata_all[2, "CC"] == 0.91
    @test cc_gendata_all[4, "CC"] == 0.42
    @test cc_storagedata_all[2, "CC"] == 0.77

    custom_resources = HOPE.normalize_custom_erec_resources(Dict(
        "generators" => ["existing_1", "candidate_2"],
        "storages" => [1, "candidate_1"],
    ))
    @test ("existing", 1) in custom_resources["generator"]
    @test ("candidate", 2) in custom_resources["generator"]
    @test ("existing", 1) in custom_resources["storage"]
    @test ("candidate", 1) in custom_resources["storage"]
    @test_throws ArgumentError HOPE.normalize_custom_erec_resources(Dict("badkey" => [1]))
    @test_throws ArgumentError HOPE.normalize_custom_erec_resources(Dict("generators" => ["badlabel"]))

    custom_targets = HOPE.build_eval_targets(
        base_input_all,
        fixed_input_all,
        ["generator", "storage"],
        "custom";
        custom_resources=custom_resources,
    )
    @test nrow(custom_targets) == 4
    @test Set(custom_targets.Label) == Set(["existing_1", "candidate_2", "existing_1", "candidate_1"])
    @test custom_targets[(custom_targets.ResourceType .== "generator") .& (custom_targets.Label .== "existing_1"), "EvalMode"][1] == "fixed"
    @test custom_targets[custom_targets.Label .== "candidate_2", "EvalMode"][1] == "virtual"
    @test custom_targets[(custom_targets.ResourceType .== "storage") .& (custom_targets.Label .== "existing_1"), "EvalMode"][1] == "fixed"
    @test custom_targets[(custom_targets.ResourceType .== "storage") .& (custom_targets.Label .== "candidate_1"), "EvalMode"][1] == "virtual"
end
