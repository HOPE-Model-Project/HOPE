module HOPECPLEXExt

using CPLEX
using HOPE
using JuMP: optimizer_with_attributes

worldsafe_cplex_optimizer() = Base.invokelatest(CPLEX.Optimizer)

function HOPE._cplex_optimizer(solver_settings::AbstractDict)
    Myfeasib_Tol = 1e-7
    if haskey(solver_settings, "Feasib_Tol")
        Myfeasib_Tol = solver_settings["Feasib_Tol"]
    end
    MyOptimal_Tol = 1e-4
    if haskey(solver_settings, "Optimal_Tol")
        MyOptimal_Tol = solver_settings["Optimal_Tol"]
    end
    MyAggFill = 10
    if haskey(solver_settings, "AggFill")
        MyAggFill = solver_settings["AggFill"]
    end
    Mypre_dual = 0
    if haskey(solver_settings, "PreDual")
        Mypre_dual = solver_settings["PreDual"]
    end
    Myseconds = 1e+75
    if haskey(solver_settings, "TimeLimit")
        Myseconds = solver_settings["TimeLimit"]
    end
    MyMIPGap = 1e-3
    if haskey(solver_settings, "MIPGap")
        MyMIPGap = solver_settings["MIPGap"]
    end
    Mymethod = 0
    if haskey(solver_settings, "Method")
        Mymethod = solver_settings["Method"]
    end
    Mypre_solve = 1
    if haskey(solver_settings, "Pre_Solve")
        Mypre_solve = solver_settings["Pre_Solve"]
    end
    MyBarConvTol = 1e-8
    if haskey(solver_settings, "BarConvTol")
        MyBarConvTol = solver_settings["BarConvTol"]
    end
    MyNumericFocus = 0
    if haskey(solver_settings, "NumericFocus")
        MyNumericFocus = solver_settings["NumericFocus"]
    end
    MyBarObjRng = 1e+75
    if haskey(solver_settings, "BarObjRng")
        MyBarObjRng = solver_settings["BarObjRng"]
    end
    MySolutionType = 2
    if haskey(solver_settings, "SolutionType")
        MySolutionType = solver_settings["SolutionType"]
    end

    return optimizer_with_attributes(
        worldsafe_cplex_optimizer,
        "CPX_PARAM_EPRHS" => Myfeasib_Tol,
        "CPX_PARAM_EPOPT" => MyOptimal_Tol,
        "CPX_PARAM_AGGFILL" => MyAggFill,
        "CPX_PARAM_PREDUAL" => Mypre_dual,
        "CPX_PARAM_TILIM" => Myseconds,
        "CPX_PARAM_EPGAP" => MyMIPGap,
        "CPX_PARAM_LPMETHOD" => Mymethod,
        "CPX_PARAM_PREIND" => Mypre_solve,
        "CPX_PARAM_BAREPCOMP" => MyBarConvTol,
        "CPX_PARAM_NUMERICALEMPHASIS" => MyNumericFocus,
        "CPX_PARAM_BAROBJRNG" => MyBarObjRng,
        "CPX_PARAM_SOLUTIONTYPE" => MySolutionType,
    )
end

end
