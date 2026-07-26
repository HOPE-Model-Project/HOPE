using DataFrames

@testset "Full chronological time mapping" begin
    full_year_sample = DataFrame(
        Symbol("Time Period") => fill(1, 3),
        :Hours => [1, 2, 3],
    )
    time_periods, hours_by_period, all_hours, has_custom_periods =
        HOPE.build_time_period_hours(full_year_sample)

    @test HOPE.validate_full_chronological_time_periods(time_periods)
    @test HOPE.validate_full_chronological_time_periods(fill(1, 8760))
    @test time_periods == [1]
    @test hours_by_period == [[1, 2, 3]]
    @test all_hours == [1, 2, 3]
    @test !has_custom_periods
    @test sum(length(hours) - 1 for hours in hours_by_period) == 2

    singleton_periods = DataFrame(
        Symbol("Time Period") => [1, 2, 3],
        :Hours => [1, 2, 3],
    )
    bad_periods, bad_hours_by_period, _, _ =
        HOPE.build_time_period_hours(singleton_periods)

    @test sum(length(hours) - 1 for hours in bad_hours_by_period) == 0
    @test_throws ArgumentError HOPE.validate_full_chronological_time_periods(bad_periods)
    @test_throws ArgumentError HOPE.validate_full_chronological_time_periods([1, 1, 2])
end
