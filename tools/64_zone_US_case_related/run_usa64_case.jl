include(joinpath(@__DIR__, "..", "..", "src", "HOPE.jl"))
using .HOPE
using JuMP

results = HOPE.run_hope(joinpath("ModelCases", "USA_64zone_GTEP_case"))
println("run_ok")
model = results["solved_model"]
println("termination_status=", termination_status(model))
println("primal_status=", primal_status(model))
if primal_status(model) in (MOI.FEASIBLE_POINT, MOI.NEARLY_FEASIBLE_POINT)
    println("objective=", objective_value(model))
else
    println("objective=NA")
end
