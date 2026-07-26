using DataFrames

@testset "Directional transmission input contract" begin
    asymmetric = DataFrame(
        :From_zone => ["A", "B"],
        :To_zone => ["B", "C"],
        Symbol("Forward Capacity (MW)") => [100.0, 55.0],
        Symbol("Reverse Capacity (MW)") => [40.0, 70.0],
    )
    forward, reverse =
        HOPE.parse_directional_line_limits(asymmetric; context = "test lines")
    @test forward == [100.0, 55.0]
    @test reverse == [40.0, 70.0]

    symmetric = DataFrame(
        :From_zone => ["A"],
        :To_zone => ["B"],
        Symbol("Forward Capacity (MW)") => [75.0],
        Symbol("Reverse Capacity (MW)") => [75.0],
    )
    forward, reverse = HOPE.parse_directional_line_limits(symmetric)
    @test forward == reverse == [75.0]

    empty_candidates = DataFrame(
        :From_zone => String[],
        :To_zone => String[],
        Symbol("Forward Capacity (MW)") => Float64[],
        Symbol("Reverse Capacity (MW)") => Float64[],
    )
    forward, reverse = HOPE.parse_directional_line_limits(
        empty_candidates;
        context = "linedata_candidate",
    )
    @test isempty(forward)
    @test isempty(reverse)

    missing_reverse = select(asymmetric, Not(Symbol("Reverse Capacity (MW)")))
    @test_throws ArgumentError HOPE.parse_directional_line_limits(missing_reverse)

    legacy = DataFrame(
        :From_zone => ["A"],
        :To_zone => ["B"],
        Symbol("Capacity (MW)") => [100.0],
    )
    @test_throws ArgumentError HOPE.parse_directional_line_limits(legacy)

    mixed = copy(asymmetric)
    mixed[!, Symbol("Capacity (MW)")] = [40.0, 55.0]
    @test_throws ArgumentError HOPE.parse_directional_line_limits(mixed)

    negative = copy(asymmetric)
    negative[1, Symbol("Reverse Capacity (MW)")] = -1.0
    @test_throws ArgumentError HOPE.parse_directional_line_limits(negative)
end
