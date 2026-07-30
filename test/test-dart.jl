using HOPE
using Test

single_bus() = DARTNetwork(bus_names = ["bus"])

function state(commitment, generation; service = trues(length(commitment)), soc = Float64[])
    return DARTState(
        commitment = commitment,
        generation_mw = generation,
        on_duration_hours = [status == 1 ? 10.0 : 0.0 for status in commitment],
        off_duration_hours = [status == 0 ? 10.0 : 0.0 for status in commitment],
        storage_soc_mwh = soc,
        generator_in_service = service,
    )
end

@testset "DART generator N-1 and reserve response" begin
    generators = [
        DARTGenerator(
            name = "energy",
            bus = "bus",
            pmax_mw = 80.0,
            variable_cost_per_mwh = 10.0,
            contingency_eligible = true,
        ),
        DARTGenerator(
            name = "response",
            bus = "bus",
            pmax_mw = 100.0,
            variable_cost_per_mwh = 30.0,
            ramp_up_mw_per_hour = 600.0,
            reserve_capability_mw = Dict(:spin => 100.0),
        ),
    ]
    data = DARTSystemData(generators = generators, network = single_bus())
    forecast = DARTForecast(
        interval_hours = 1.0,
        load_mw = fill(80.0, 1, 1),
        availability = ones(2, 1),
    )
    result = solve_dart_scuc(data, forecast, state([1, 1], [80.0, 0.0]))

    @test result.generation_mw[:, 1] ≈ [80.0, 0.0] atol = 1e-6
    @test result.generator_reserve_mw[:spin][2, 1] ≈ 80.0 atol = 1e-6
    @test sum(result.emergency_load_shed_mw) <= 1e-6
    @test result.contingency_generator_indices == [1]
end

@testset "DART product response limits and quick start" begin
    products = [
        DARTReserveProduct(name = :reg_up, direction = :up, response_minutes = 5),
        DARTReserveProduct(name = :spin, direction = :up, response_minutes = 10),
        DARTReserveProduct(
            name = :nspin,
            direction = :up,
            response_minutes = 30,
            requires_online = false,
        ),
    ]
    generators = [
        DARTGenerator(
            name = "outage",
            bus = "bus",
            pmax_mw = 15.0,
            variable_cost_per_mwh = 10.0,
            contingency_eligible = true,
        ),
        DARTGenerator(
            name = "online_response",
            bus = "bus",
            pmax_mw = 100.0,
            variable_cost_per_mwh = 30.0,
            ramp_up_mw_per_hour = 60.0,
            reserve_capability_mw = Dict(:reg_up => 100.0, :spin => 100.0),
        ),
    ]
    data = DARTSystemData(
        generators = generators,
        network = single_bus(),
        reserve_products = products,
    )
    forecast = DARTForecast(
        interval_hours = 1.0,
        load_mw = fill(15.0, 1, 1),
        availability = ones(2, 1),
    )
    config = DARTConfig(
        security_up_products = [:reg_up, :spin, :nspin],
        security_down_products = Symbol[],
    )
    result = solve_dart_scuc(data, forecast, state([1, 1], [15.0, 0.0]); config = config)

    @test result.generator_reserve_mw[:reg_up][2, 1] ≈ 5.0 atol = 1e-6
    @test result.generator_reserve_mw[:spin][2, 1] ≈ 10.0 atol = 1e-6
    @test sum(result.emergency_load_shed_mw) <= 1e-6

    quick_start = DARTGenerator(
        name = "quick_start",
        bus = "bus",
        pmax_mw = 20.0,
        variable_cost_per_mwh = 50.0,
        quick_start_eligible = true,
        quick_start_time_minutes = 20,
        reserve_capability_mw = Dict(:nspin => 20.0),
    )
    quick_data = DARTSystemData(
        generators = [generators[1], quick_start],
        network = single_bus(),
        reserve_products = products,
    )
    quick_result =
        solve_dart_scuc(quick_data, forecast, state([1, 0], [15.0, 0.0]); config = config)
    @test quick_result.commitment[2, 1] == 0
    @test quick_result.generator_reserve_mw[:nspin][2, 1] >= 15.0 - 1e-6
    @test quick_result.generator_reserve_mw[:nspin][2, 1] <= 20.0 + 1e-6
    @test sum(quick_result.emergency_load_shed_mw) <= 1e-6
end

@testset "DART real-time ramp and equipment transitions" begin
    generator = DARTGenerator(
        name = "unit",
        bus = "bus",
        pmax_mw = 100.0,
        startup_limit_mw = 5.0,
        shutdown_limit_mw = 30.0,
        real_time_ramp_up_mw_per_hour = 60.0,
        real_time_ramp_down_mw_per_hour = 60.0,
    )
    data = DARTSystemData(generators = [generator], network = single_bus())
    config = DARTConfig(
        security_up_products = [:reg_up, :spin, :nspin],
        security_down_products = [:reg_down],
    )

    forecast = DARTForecast(
        interval_hours = 1 / 12,
        load_mw = fill(15.0, 1, 1),
        availability = ones(1, 1),
    )
    ramp = solve_dart_sced(data, forecast, state([1], [10.0]), [1]; config = config)
    @test ramp.generation_mw[1, 1] ≈ 15.0 atol = 1e-6

    startup = solve_dart_sced(data, forecast, state([0], [0.0]), [1]; config = config)
    @test startup.generation_mw[1, 1] ≈ 5.0 atol = 1e-6
    @test startup.load_shed_mw[1, 1] ≈ 10.0 atol = 1e-6

    trip_forecast = DARTForecast(
        interval_hours = 1 / 12,
        load_mw = zeros(1, 1),
        availability = ones(1, 1),
        generator_in_service = falses(1, 1),
    )
    trip = solve_dart_sced(
        data,
        trip_forecast,
        state([1], [30.0]; service = [true]),
        [1];
        config = config,
    )
    @test trip.generation_mw[1, 1] <= 1e-8

    return_to_service = solve_dart_sced(
        data,
        forecast,
        state([1], [0.0]; service = [false]),
        [1];
        config = config,
    )
    @test return_to_service.generation_mw[1, 1] ≈ 5.0 atol = 1e-6
end

@testset "DART nodal PTDF and storage chronology" begin
    network = DARTNetwork(
        bus_names = ["one", "two"],
        line_names = ["one_to_two"],
        ptdf = reshape([0.0, -1.0], 1, 2),
        line_limit_mw = [20.0],
        emergency_line_limit_mw = [25.0],
    )
    generators = [
        DARTGenerator(
            name = "cheap",
            bus = "one",
            pmax_mw = 100.0,
            variable_cost_per_mwh = 10.0,
            commitment_required = false,
        ),
        DARTGenerator(
            name = "local",
            bus = "two",
            pmax_mw = 100.0,
            variable_cost_per_mwh = 30.0,
            commitment_required = false,
        ),
    ]
    data = DARTSystemData(generators = generators, network = network)
    forecast = DARTForecast(
        interval_hours = 1.0,
        load_mw = reshape([0.0, 40.0], 2, 1),
        availability = ones(2, 1),
    )
    result = solve_dart_scuc(data, forecast, default_dart_state(data))
    @test result.generation_mw[:, 1] ≈ [20.0, 20.0] atol = 1e-6
    @test result.line_flow_mw[1, 1] ≈ 20.0 atol = 1e-6
    @test result.lmp_per_mwh[:, 1] ≈ [10.0, 30.0] atol = 1e-6

    storage = DARTStorage(
        name = "battery",
        bus = "bus",
        energy_capacity_mwh = 10.0,
        charge_capacity_mw = 10.0,
        discharge_capacity_mw = 10.0,
    )
    storage_generator = DARTGenerator(
        name = "expensive",
        bus = "bus",
        pmax_mw = 100.0,
        variable_cost_per_mwh = 100.0,
        commitment_required = false,
    )
    storage_data = DARTSystemData(
        generators = [storage_generator],
        storage = [storage],
        network = single_bus(),
    )
    storage_forecast = DARTForecast(
        interval_hours = 1.0,
        load_mw = fill(10.0, 1, 1),
        availability = ones(1, 1),
    )
    storage_result =
        solve_dart_scuc(storage_data, storage_forecast, state([1], [0.0]; soc = [10.0]))
    @test storage_result.storage_discharge_mw[1, 1] ≈ 10.0 atol = 1e-6
    @test storage_result.storage_soc_mwh[1, 1] <= 1e-6
end

@testset "DART rolling simulation and settlements" begin
    generators = [
        DARTGenerator(
            name = "energy",
            bus = "bus",
            pmax_mw = 80.0,
            variable_cost_per_mwh = 10.0,
            contingency_eligible = true,
        ),
        DARTGenerator(
            name = "response",
            bus = "bus",
            pmax_mw = 100.0,
            variable_cost_per_mwh = 30.0,
            ramp_up_mw_per_hour = 600.0,
            real_time_ramp_up_mw_per_hour = 600.0,
            real_time_ramp_down_mw_per_hour = 600.0,
            reserve_capability_mw = Dict(:spin => 100.0),
        ),
    ]
    data = DARTSystemData(generators = generators, network = single_bus())
    day_ahead = DARTForecast(
        interval_hours = 1.0,
        load_mw = fill(70.0, 1, 1),
        availability = ones(2, 1),
    )
    real_time = DARTForecast(
        interval_hours = 1 / 12,
        load_mw = fill(70.0, 1, 12),
        availability = ones(2, 12),
    )
    rolling = run_dart_rolling(
        data,
        day_ahead,
        real_time,
        state([1, 1], [70.0, 0.0]);
        hours_to_run = 1,
        day_ahead_lookahead_hours = 1,
        real_time_lookahead_intervals = 3,
    )
    settlement = calculate_dart_settlements(data, rolling)

    @test length(rolling.day_ahead_results) == 1
    @test length(rolling.real_time_results) == 12
    @test all(result.generation_mw[1, 1] ≈ 70.0 for result in rolling.real_time_results)
    @test rolling.final_state.generation_mw ≈ [70.0, 0.0] atol = 1e-6
    @test settlement.settlement_balance ≈ 0.0 atol = 1e-6
end
