using YAML
using JuMP
using Cbc
using DataFrames

include(joinpath(@__DIR__, "..", "..", "src", "HOPE.jl"))
using .HOPE

case_dir = joinpath("ModelCases", "USA_64zone_GTEP_case")
settings_path = joinpath(case_dir, "Settings", "HOPE_model_settings.yml")
config_set = YAML.load_file(settings_path)

input_data = HOPE.load_data(config_set, case_dir)
println("load_ok")
println("  load rows: ", nrow(input_data["Loaddata"]))
println("  AF rows: ", nrow(input_data["AFdata"]))
if haskey(input_data, "RepWeightData")
    println("  rep periods: ", nrow(input_data["RepWeightData"]))
end

optimizer = optimizer_with_attributes(Cbc.Optimizer, "seconds" => 1.0, "logLevel" => 0)
model = HOPE.create_GTEP_model(config_set, input_data, optimizer)
println("build_ok")
println("  variables: ", JuMP.num_variables(model))
println("  constraints: ", JuMP.num_constraints(model; count_variable_in_set_constraints = false))
