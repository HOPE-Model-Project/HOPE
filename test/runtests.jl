using HOPE
using Test

@testset "HOPE.jl" begin
    include("test-basic-test.jl")
    include("test-erec-core.jl")
    include("test-erec-integration.jl")
    include("test-erec-settings.jl")
    include("test-lmp-sign-regression.jl")
end
