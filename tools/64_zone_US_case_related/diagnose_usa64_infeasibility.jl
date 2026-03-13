include(joinpath(@__DIR__, "..", "..", "src", "HOPE.jl"))
using .HOPE
using JuMP
using YAML

const MOI = JuMP.MOI

case_path = joinpath("ModelCases", "USA_64zone_GTEP_case")
settings_file = joinpath(case_path, "Settings", "HOPE_model_settings.yml")
config_set = YAML.load(open(settings_file))

optimizer = HOPE.initiate_solver(case_path, String(config_set["solver"]))
input_data = HOPE.load_data(config_set, case_path)
model = HOPE.create_GTEP_model(config_set, input_data, optimizer)

println("Model built. Starting optimize...")
optimize!(model)

ts = termination_status(model)
ps = primal_status(model)
println("termination_status=", ts)
println("primal_status=", ps)

if ps in (MOI.FEASIBLE_POINT, MOI.NEARLY_FEASIBLE_POINT)
    println("objective=", objective_value(model))
    exit(0)
end

println("No primal solution. Starting conflict refinement...")
try
    compute_conflict!(model)
    cstat = get_attribute(model, MOI.ConflictStatus())
    println("conflict_status=", cstat)

    conflicted = Dict{String,Int}()
    conflicted_by_family = Dict{String,Int}()
    conflicted_examples = String[]
    local total_checked = 0
    for cref in all_constraints(model; include_variable_in_set_constraints = false)
        total_checked += 1
        ci = JuMP.index(cref)
        s = MOI.get(backend(model), MOI.ConstraintConflictStatus(), ci)
        if s != MOI.NOT_IN_CONFLICT
            key = string(s)
            conflicted[key] = get(conflicted, key, 0) + 1
            cname = name(cref)
            if isempty(cname)
                co = constraint_object(cref)
                cname = string(typeof(co.func), "::", typeof(co.set))
            end
            family = occursin("[", cname) ? first(split(cname, "[")) : cname
            conflicted_by_family[family] = get(conflicted_by_family, family, 0) + 1
            if length(conflicted_examples) < 40
                push!(conflicted_examples, cname)
            end
        end
    end
    println("conflict_scan_constraints=", total_checked)
    println("conflict_counts=", conflicted)
    sorted_families = sort(collect(conflicted_by_family), by=x->x[2], rev=true)
    println("top_conflict_families=", first(sorted_families, min(20, length(sorted_families))))
    println("conflict_examples=", conflicted_examples)
catch e
    println("Conflict refinement failed: ", e)
end
