"""
    initiate_solver(case::AbstractString, solver::AbstractString) -> MOI.OptimizerWithAttributes

Read solver settings from `<case>/Settings/<solver>_settings.yml` and return a
`MOI.OptimizerWithAttributes` object that can be passed to `create_GTEP_model` or
`create_PCM_model`.

`solver` must be one of `"cbc"`, `"clp"`, `"glpk"`, `"highs"`, `"scip"`, `"gurobi"`, or
`"cplex"`.  Commercial solvers (`gurobi`, `scip`, `cplex`) require the corresponding
Julia package to be installed separately.
"""
const OPTIONAL_SOLVER_PACKAGES =
    Dict("cplex" => "CPLEX", "gurobi" => "Gurobi", "scip" => "SCIP")

function _optional_solver_error(solver::AbstractString, err = nothing)
    solver_name = lowercase(String(solver))
    package_name = get(OPTIONAL_SOLVER_PACKAGES, solver_name, solver)
    message = "solver='$(solver_name)' requested, but $(package_name).jl is unavailable in the active HOPE environment."
    if solver_name == "gurobi"
        message *= " Install/activate Gurobi.jl and make sure a valid Gurobi license is available."
    elseif solver_name == "cplex"
        message *= " Install/activate CPLEX.jl and make sure a valid CPLEX license is available."
    elseif solver_name == "scip"
        message *= " Install/activate SCIP.jl."
    else
        message *= " Install/activate $(package_name).jl."
    end
    if err !== nothing
        message *= " Original error: $(err)"
    end
    error(message)
end

function _ensure_optional_solver_loaded(solver::AbstractString)
    solver_name = lowercase(String(solver))
    package_name = get(OPTIONAL_SOLVER_PACKAGES, solver_name, nothing)
    package_name === nothing && return nothing
    if isdefined(@__MODULE__, Symbol(package_name)) || isdefined(Main, Symbol(package_name))
        return nothing
    end
    try
        Base.eval(Main, Meta.parse("using $(package_name)"))
    catch err
        _optional_solver_error(solver_name, err)
    end
    return nothing
end

function _gurobi_optimizer(solver_settings)
    _optional_solver_error("gurobi")
end

function _scip_optimizer(solver_settings)
    _optional_solver_error("scip")
end

function _cplex_optimizer(solver_settings)
    _optional_solver_error("cplex")
end

function _worldsafe_optimizer_with_attributes(opt)
    if !(opt isa MOI.OptimizerWithAttributes)
        return opt
    end
    if !hasfield(typeof(opt), :optimizer_constructor) || !hasfield(typeof(opt), :params)
        return opt
    end
    optimizer_constructor = getfield(opt, :optimizer_constructor)
    params = getfield(opt, :params)
    worldsafe_constructor = () -> Base.invokelatest(optimizer_constructor)
    return optimizer_with_attributes(worldsafe_constructor, params...)
end

instantiate_jump_model(optimizer) = Base.invokelatest(Model, optimizer)

instantiate_jump_direct_model(optimizer) = Base.invokelatest(direct_model, optimizer)

function initiate_solver(case::AbstractString, solver::AbstractString)
    solver_settings_path = joinpath(case, "Settings", solver * "_settings.yml")
    solver_settings = open(solver_settings_path) do io
        YAML.load(io)
    end
    if solver == "cbc"
        # Optional solver parameters ############################################
        Myseconds = 1e-6
        if (haskey(solver_settings, "TimeLimit"))
            Myseconds = solver_settings["TimeLimit"]
        end
        MylogLevel = 1e-6
        if (haskey(solver_settings, "logLevel"))
            MylogLevel = solver_settings["logLevel"]
        end
        MymaxSolutions = -1
        if (haskey(solver_settings, "maxSolutions"))
            MymaxSolutions = solver_settings["maxSolutions"]
        end
        MymaxNodes = -1
        if (haskey(solver_settings, "maxNodes"))
            MymaxNodes = solver_settings["maxNodes"]
        end
        MyallowableGap = -1
        if (haskey(solver_settings, "allowableGap"))
            MyallowableGap = solver_settings["allowableGap"]
        end
        MyratioGap = Inf
        if (haskey(solver_settings, "ratioGap"))
            MyratioGap = solver_settings["ratioGap"]
        end
        Mythreads = 1
        if (haskey(solver_settings, "threads"))
            Mythreads = solver_settings["threads"]
        end
        #########################################################################

        OPTIMIZER = optimizer_with_attributes(
            Cbc.Optimizer,
            "seconds" => Myseconds,
            "logLevel" => MylogLevel,
            "maxSolutions" => MymaxSolutions,
            "maxNodes" => MymaxNodes,
            "allowableGap" => MyallowableGap,
            "ratioGap" => MyratioGap,
            "threads" => Mythreads,
        )
    end
    if solver == "clp"
        # Optional solver parameters ############################################
        Myfeasib_Tol = 1e-7
        if (haskey(solver_settings, "Feasib_Tol"))
            Myfeasib_Tol = solver_settings["Feasib_Tol"]
        end
        Myseconds = -1
        if (haskey(solver_settings, "TimeLimit"))
            Myseconds = solver_settings["TimeLimit"]
        end
        Mypre_solve = 0
        if (haskey(solver_settings, "Pre_Solve"))
            Mypre_solve = solver_settings["Pre_Solve"]
        end
        Mymethod = 5
        if (haskey(solver_settings, "Method"))
            Mymethod = solver_settings["Method"]
        end
        MyDualObjectiveLimit = 1e308
        if (haskey(solver_settings, "DualObjectiveLimit"))
            MyDualObjectiveLimit = solver_settings["DualObjectiveLimit"]
        end
        MyMaximumIterations = 2147483647
        if (haskey(solver_settings, "MaximumIterations"))
            MyMaximumIterations = solver_settings["MaximumIterations"]
        end
        MyLogLevel = 1
        if (haskey(solver_settings, "LogLevel"))
            MyLogLevel = solver_settings["LogLevel"]
        end
        MyInfeasibleReturn = 0
        if (haskey(solver_settings, "InfeasibleReturn"))
            MyInfeasibleReturn = solver_settings["InfeasibleReturn"]
        end
        MyScaling = 3
        if (haskey(solver_settings, "Scaling"))
            MyScaling = solver_settings["Scaling"]
        end
        MyPerturbation = 100
        if (haskey(solver_settings, "Perturbation"))
            MyPerturbation = solver_settings["Perturbation"]
        end

        OPTIMIZER = optimizer_with_attributes(
            Clp.Optimizer,
            "PrimalTolerance" => Myfeasib_Tol,
            "DualObjectiveLimit" => MyDualObjectiveLimit,
            "MaximumIterations" => MyMaximumIterations,
            "MaximumSeconds" => Myseconds,
            "LogLevel" => MyLogLevel,
            "PresolveType" => Mypre_solve,
            "SolveType" => Mymethod,
            "InfeasibleReturn" => MyInfeasibleReturn,
            "Scaling" => MyScaling,
            "Perturbation" => MyPerturbation,
        )
    end

    if solver == "highs"
        # Optional solver parameters ############################################
        Myfeasib_Tol = 1e-6
        if (haskey(solver_settings, "Feasib_Tol"))
            Myfeasib_Tol = solver_settings["Feasib_Tol"]
        end
        MyOptimal_Tol = 1e-4
        if (haskey(solver_settings, "Optimal_Tol"))
            MyOptimal_Tol = solver_settings["Optimal_Tol"]
        end
        Myseconds = 1.0e23
        if (haskey(solver_settings, "TimeLimit"))
            Myseconds = solver_settings["TimeLimit"]
        end
        Mypre_solve = "choose"
        if (haskey(solver_settings, "Pre_Solve"))
            Mypre_solve = solver_settings["Pre_Solve"]
        end
        Mymethod = "ipm"
        if (haskey(solver_settings, "Method"))
            Mymethod = solver_settings["Method"]
        end

        OPTIMIZER = optimizer_with_attributes(
            HiGHS.Optimizer,
            "primal_feasibility_tolerance" => Myfeasib_Tol,
            "dual_feasibility_tolerance" => MyOptimal_Tol,
            "time_limit" => Myseconds,
            "presolve" => Mypre_solve,
            "solver" => Mymethod,
        )
    end

    if solver == "scip"
        _ensure_optional_solver_loaded(solver)
        OPTIMIZER = _worldsafe_optimizer_with_attributes(
            Base.invokelatest(_scip_optimizer, solver_settings),
        )
    end

    if solver == "cplex"
        _ensure_optional_solver_loaded(solver)
        OPTIMIZER = _worldsafe_optimizer_with_attributes(
            Base.invokelatest(_cplex_optimizer, solver_settings),
        )
    end
    if solver == "gurobi"
        _ensure_optional_solver_loaded(solver)
        OPTIMIZER = _worldsafe_optimizer_with_attributes(
            Base.invokelatest(_gurobi_optimizer, solver_settings),
        )
    end
    return OPTIMIZER
end
