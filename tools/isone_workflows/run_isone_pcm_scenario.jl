include(joinpath(@__DIR__, "..", "..", "src", "HOPE.jl"))
using .HOPE
using YAML
using JuMP

const MOI = JuMP.MOI

function parse_bool_arg(value::AbstractString)
    lowercase(value) in ("1", "true", "yes", "y")
end

function parse_optional_args(args::Vector{String})
    output_path = ""
    solver_override = nothing
    settings_path = nothing
    i = 1
    while i <= length(args)
        arg = args[i]
        if arg == "--output-path"
            i += 1
            i <= length(args) || error("Missing value for --output-path")
            output_path = args[i]
        elseif arg == "--solver"
            i += 1
            i <= length(args) || error("Missing value for --solver")
            solver_override = args[i]
        elseif arg == "--settings-path"
            i += 1
            i <= length(args) || error("Missing value for --settings-path")
            settings_path = args[i]
        else
            if isempty(output_path)
                output_path = arg
            elseif isnothing(solver_override)
                solver_override = arg
            elseif isnothing(settings_path)
                settings_path = arg
            else
                error("Unexpected argument: $arg")
            end
        end
        i += 1
    end
    return output_path, solver_override, settings_path
end

function case_config(case_path::String; settings_path::Union{Nothing, String}=nothing)
    resolved_settings = isnothing(settings_path) ? joinpath(case_path, "Settings", "HOPE_model_settings.yml") : settings_path
    YAML.load(open(resolved_settings))
end

function solve_case(
    case_path::String;
    network_model::Int,
    use_nodal_ni::Bool,
    solver_override::Union{Nothing, String}=nothing,
    settings_path::Union{Nothing, String}=nothing,
)
    config = deepcopy(case_config(case_path; settings_path=settings_path))
    config["network_model"] = network_model
    if !isnothing(solver_override)
        config["solver"] = solver_override
    end
    optimizer = HOPE.initiate_solver(case_path, String(config["solver"]))
    input_data = HOPE.load_data(config, case_path)
    if !use_nodal_ni && haskey(input_data, "NodalNIdata")
        delete!(input_data, "NodalNIdata")
    end
    model = HOPE.create_PCM_model(config, input_data, optimizer)
    solved_model = HOPE.solve_model(config, input_data, model)
    load_shedding_total = try
        sum(value.(solved_model[:p_LS]))
    catch
        missing
    end
    objective = try
        objective_value(solved_model)
    catch
        missing
    end
    return config, input_data, solved_model, (
        termination_status = string(termination_status(solved_model)),
        primal_status = string(primal_status(solved_model)),
        load_shedding_total = load_shedding_total,
        objective = objective,
    )
end

function main()
    if length(ARGS) < 3
        error("Usage: julia --project=. tools/isone_workflows/run_isone_pcm_scenario.jl <case_path> <network_model> <use_nodal_ni:true|false> [--output-path <path>] [--solver <name>] [--settings-path <path>]")
    end

    case_path = ARGS[1]
    network_model = parse(Int, ARGS[2])
    use_nodal_ni = parse_bool_arg(ARGS[3])
    output_path, solver_override, settings_path = parse_optional_args(ARGS[4:end])

    config, input_data, solved_model, summary = solve_case(
        case_path;
        network_model=network_model,
        use_nodal_ni=use_nodal_ni,
        solver_override=solver_override,
        settings_path=settings_path,
    )

    if !isempty(output_path) && summary.primal_status in ("FEASIBLE_POINT", "NEARLY_FEASIBLE_POINT")
        HOPE.mkdir_overwrite(output_path)
        HOPE.write_output(output_path, config, input_data, solved_model)
    end

    function json_value(value)
        if value === missing || value === nothing
            return "null"
        elseif value isa Bool
            return value ? "true" : "false"
        elseif value isa Number
            return string(value)
        else
            escaped = replace(string(value), "\\" => "\\\\", "\"" => "\\\"")
            return "\"" * escaped * "\""
        end
    end

    payload = Dict(
        "case_path" => case_path,
        "network_model" => network_model,
        "use_nodal_ni" => use_nodal_ni,
        "output_path" => output_path,
        "solver" => String(config["solver"]),
        "settings_path" => isnothing(settings_path) ? joinpath(case_path, "Settings", "HOPE_model_settings.yml") : settings_path,
        "termination_status" => summary.termination_status,
        "primal_status" => summary.primal_status,
        "load_shedding_total" => summary.load_shedding_total,
        "objective" => summary.objective,
    )
    ordered_keys = [
        "case_path",
        "network_model",
        "use_nodal_ni",
        "output_path",
        "solver",
        "settings_path",
        "termination_status",
        "primal_status",
        "load_shedding_total",
        "objective",
    ]
    json_line = "{" * join(["\"" * key * "\":" * json_value(payload[key]) for key in ordered_keys], ",") * "}"
    println(json_line)
end

main()
