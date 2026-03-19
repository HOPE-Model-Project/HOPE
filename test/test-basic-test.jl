@testset "HOPE Smoke" begin
    @test isdefined(HOPE, :run_hope)
    @test isdefined(HOPE, :create_PCM_model)
    @test isdefined(HOPE, :marginal_load_price_from_dual)
end
