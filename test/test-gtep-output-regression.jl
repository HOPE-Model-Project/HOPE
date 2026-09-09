@testset "GTEP candidate output and investment-cost regression" begin
    @test HOPE.scaled_candidate_output_values([100.0, 40.0], [0.5, 0.25], 1:2) ==
          [50.0, 10.0]
    @test_throws DimensionMismatch HOPE.scaled_candidate_output_values(
        [100.0],
        [0.5, 0.25],
        1:2,
    )

    mktempdir() do tmpdir
        tables = build_tiny_erec_case_tables()

        candidate = deepcopy(tables["gendata.csv"])
        insertcols!(candidate, 4, Symbol("Cost (\$/MW/yr)") => [10.0])
        candidate[!, :Type] .= "NGCC_NEW"
        candidate[!, Symbol("Pmax (MW)")] .= 100.0
        candidate[!, Symbol("Pmin (MW)")] .= 0.0
        tables["gendata_candidate.csv"] = candidate
        tables["gen_availability_timeseries.csv"][!, :G2] .= 1.0
        tables["single_parameter.csv"][!, :Inv_bugt_gen] .= 1.0e9

        # Remove the small existing-storage contribution so the 120 MW peak forces
        # a fractional build from the 100 MW candidate block.
        tables["storagedata.csv"][!, Symbol("Capacity (MWh)")] .= 0.0
        tables["storagedata.csv"][!, Symbol("Max Power (MW)")] .= 0.0

        case_dir = write_tiny_erec_case(
            joinpath(tmpdir, "fractional_candidate_case");
            tables = tables,
        )
        run_res = HOPE.run_hope(case_dir)
        model = run_res["solved_model"]
        x_value = value(model[:x][2])
        @test 0.0 < x_value < 1.0

        # The assumptions returned by run_hope remain the unscaled candidate block.
        @test run_res["input"]["Gendata_candidate"][1, "Pmax (MW)"] == 100.0

        capacity = run_res["output"]["capacity"]
        candidate_capacity = capacity[capacity.EC_Category .== "Candidate", :]
        @test nrow(candidate_capacity) == 1
        @test isapprox(
            candidate_capacity[1, Symbol("Capacity_FIN (MW)")],
            100.0 * x_value;
            atol = 1.0e-6,
            rtol = 0.0,
        )

        system_cost = run_res["output"]["system_cost"]
        @test isapprox(
            sum(system_cost[!, Symbol("Inv_cost (\$)")]),
            value(model[:INVCost]);
            atol = 1.0e-6,
            rtol = 0.0,
        )

        # Rewriting the same solved model from the preserved inputs is idempotent.
        repeated_output = HOPE.write_output(
            joinpath(tmpdir, "repeated_output"),
            run_res["config"],
            run_res["input"],
            model,
        )
        repeated_candidate =
            repeated_output["capacity"][repeated_output["capacity"].EC_Category .== "Candidate", :]
        @test repeated_candidate[1, Symbol("Capacity_FIN (MW)")] ==
              candidate_capacity[1, Symbol("Capacity_FIN (MW)")]
        @test repeated_output["system_cost"][!, Symbol("Inv_cost (\$)")] ==
              system_cost[!, Symbol("Inv_cost (\$)")]
    end
end
