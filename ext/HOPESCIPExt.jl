module HOPESCIPExt

using HOPE
using SCIP
using JuMP: optimizer_with_attributes

worldsafe_scip_optimizer() = Base.invokelatest(SCIP.Optimizer)

function HOPE._scip_optimizer(solver_settings::AbstractDict)
    MyDispverblevel = 0
    if haskey(solver_settings, "Dispverblevel")
        MyDispverblevel = solver_settings["Dispverblevel"]
    end
    Mylimitsgap = 0.05
    if haskey(solver_settings, "limitsgap")
        Mylimitsgap = solver_settings["limitsgap"]
    end

    return optimizer_with_attributes(
        worldsafe_scip_optimizer,
        "display_verblevel" => MyDispverblevel,
        "limits_gap" => Mylimitsgap,
    )
end

end
