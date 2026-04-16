using HOPE

normalize_compare_path(path::AbstractString) = rstrip(abspath(normpath(String(path))), ['/', '\\'])

function print_usage()
    println(
        "Usage: julia --project=. tools/repo_utils/agent_preflight_check.jl [<case_path>] [--solver <name>]",
    )
    println(
        "Examples:",
    )
    println(
        "  julia --project=. tools/repo_utils/agent_preflight_check.jl ModelCases/MD_GTEP_clean_case",
    )
    println(
        "  julia --project=. tools/repo_utils/agent_preflight_check.jl MD_GTEP_clean_case --solver gurobi",
    )
end

function print_check(status::AbstractString, label::AbstractString, detail::AbstractString = "")
    if isempty(detail)
        println("[$(status)] $(label)")
    else
        println("[$(status)] $(label): $(detail)")
    end
end

function parse_args(args::Vector{String})
    case_arg = nothing
    solver_override = nothing

    i = 1
    while i <= length(args)
        arg = args[i]
        if arg == "--solver"
            i += 1
            i <= length(args) || throw(ArgumentError("Missing value for --solver"))
            solver_override = lowercase(strip(args[i]))
        elseif startswith(arg, "--")
            throw(ArgumentError("Unknown option: $(arg)"))
        elseif isnothing(case_arg)
            case_arg = arg
        else
            throw(ArgumentError("Unexpected extra positional argument: $(arg)"))
        end
        i += 1
    end

    return case_arg, solver_override
end

function run_optional_solver_probe(solver::AbstractString)
    solver_name = lowercase(String(solver))
    if solver_name == "gurobi"
        Base.eval(Main, :(import Gurobi))
        Base.invokelatest(() -> begin
            env = getfield(Main, :Gurobi).Env()
            finalize(env)
            nothing
        end)
        return "Gurobi.jl import and license handshake succeeded"
    elseif solver_name == "scip"
        Base.eval(Main, :(import SCIP))
        return "SCIP.jl import succeeded"
    elseif solver_name == "cplex"
        Base.eval(Main, :(import CPLEX))
        return "CPLEX.jl import succeeded"
    end
    return "No commercial solver probe needed"
end

function main(args::Vector{String})
    case_arg, solver_override = try
        parse_args(args)
    catch err
        print_check("FAIL", "Argument parsing", sprint(showerror, err))
        print_usage()
        return 2
    end

    repo_root = normalize_compare_path(joinpath(@__DIR__, "..", ".."))
    active_project = try
        Base.active_project()
    catch
        nothing
    end

    print_check("INFO", "Repo root", repo_root)
    print_check("INFO", "Active project", string(active_project))
    print_check(
        "INFO",
        "HOPE_MODELCASES_PATH",
        get(ENV, "HOPE_MODELCASES_PATH", "<unset>"),
    )

    if active_project === nothing
        print_check("FAIL", "Julia project", "No active Julia project detected")
        return 2
    end

    active_project_root = normalize_compare_path(dirname(String(active_project)))
    if active_project_root != repo_root
        print_check(
            "FAIL",
            "Julia project",
            "Expected HOPE repo project at $(repo_root), found $(active_project)",
        )
        return 2
    end
    print_check("PASS", "Julia project", "HOPE repo environment is active")

    hope_module_path = try
        pathof(HOPE)
    catch err
        print_check("FAIL", "Load HOPE", sprint(showerror, err))
        return 2
    end
    print_check("PASS", "Load HOPE", string(hope_module_path))

    if isnothing(case_arg)
        print_check("PASS", "Agent preflight", "Environment-only checks passed")
        println("AGENT_PREFLIGHT_STATUS=ok")
        return 0
    end

    case_path, config = try
        HOPE.load_case_config_for_holistic(case_arg; context = "agent_preflight_check")
    catch err
        print_check("FAIL", "Resolve case", sprint(showerror, err))
        println("AGENT_PREFLIGHT_STATUS=fail")
        return 2
    end
    print_check("PASS", "Resolve case", case_path)

    solver_name = lowercase(
        String(isnothing(solver_override) ? config["solver"] : solver_override),
    )
    print_check("INFO", "Requested solver", solver_name)
    print_check("INFO", "Model mode", String(get(config, "model_mode", "<missing>")))

    if solver_name in ("gurobi", "scip", "cplex")
        try
            detail = run_optional_solver_probe(solver_name)
            print_check("PASS", "Commercial solver probe", detail)
        catch err
            print_check("FAIL", "Commercial solver probe", sprint(showerror, err))
            println("AGENT_PREFLIGHT_STATUS=fail")
            return 2
        end
    else
        print_check("PASS", "Solver package", "Open-source solver requires no extra package probe")
    end

    try
        optimizer = HOPE.initiate_solver(case_path, solver_name)
        print_check("PASS", "HOPE solver initialization", string(typeof(optimizer)))
    catch err
        print_check("FAIL", "HOPE solver initialization", sprint(showerror, err))
        println("AGENT_PREFLIGHT_STATUS=fail")
        return 2
    end

    print_check("PASS", "Agent preflight", "All checks passed")
    println("AGENT_PREFLIGHT_STATUS=ok")
    return 0
end

exit(main(ARGS))
