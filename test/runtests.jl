using HOPE
using Test

@testset "HOPE.jl" begin
    include("test-basic-test.jl")
    include("test-lmp-sign-regression.jl")
end
