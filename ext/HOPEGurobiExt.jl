module HOPEGurobiExt

using HOPE
using Gurobi
using JuMP: optimizer_with_attributes

worldsafe_gurobi_optimizer() = Base.invokelatest(Gurobi.Optimizer)

function HOPE._gurobi_optimizer(solver_settings::AbstractDict)
    MyFeasibilityTol = 1e-6
    if haskey(solver_settings, "Feasib_Tol")
        MyFeasibilityTol = solver_settings["Feasib_Tol"]
    end
    MyOptimalityTol = 1e-4
    if haskey(solver_settings, "Optimal_Tol")
        MyOptimalityTol = solver_settings["Optimal_Tol"]
    end
    MyPresolve = -1
    if haskey(solver_settings, "Pre_Solve")
        MyPresolve = solver_settings["Pre_Solve"]
    end
    MyAggFill = -1
    if haskey(solver_settings, "AggFill")
        MyAggFill = solver_settings["AggFill"]
    end
    MyPreDual = -1
    if haskey(solver_settings, "PreDual")
        MyPreDual = solver_settings["PreDual"]
    end
    MyTimeLimit = Inf
    if haskey(solver_settings, "TimeLimit")
        MyTimeLimit = solver_settings["TimeLimit"]
    end
    MyMIPGap = 1e-3
    if haskey(solver_settings, "MIPGap")
        MyMIPGap = solver_settings["MIPGap"]
    end
    MyCrossover = -1
    if haskey(solver_settings, "Crossover")
        MyCrossover = solver_settings["Crossover"]
    end
    MyMethod = -1
    if haskey(solver_settings, "Method")
        MyMethod = solver_settings["Method"]
    end
    MyBarConvTol = 1e-8
    if haskey(solver_settings, "BarConvTol")
        MyBarConvTol = solver_settings["BarConvTol"]
    end
    MyNumericFocus = 0
    if haskey(solver_settings, "NumericFocus")
        MyNumericFocus = solver_settings["NumericFocus"]
    end
    MyOutputFlag = 1
    if haskey(solver_settings, "OutputFlag")
        MyOutputFlag = solver_settings["OutputFlag"]
    end

    return optimizer_with_attributes(
        worldsafe_gurobi_optimizer,
        "OptimalityTol" => MyOptimalityTol,
        "FeasibilityTol" => MyFeasibilityTol,
        "Presolve" => MyPresolve,
        "AggFill" => MyAggFill,
        "PreDual" => MyPreDual,
        "TimeLimit" => MyTimeLimit,
        "MIPGap" => MyMIPGap,
        "Method" => MyMethod,
        "BarConvTol" => MyBarConvTol,
        "NumericFocus" => MyNumericFocus,
        "Crossover" => MyCrossover,
        "OutputFlag" => MyOutputFlag,
    )
end

end
