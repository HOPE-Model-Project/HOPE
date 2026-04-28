import Pkg

const PROJECT_ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const DEFAULT_MODELCASES_PATH = joinpath(PROJECT_ROOT, "HOPE", "ModelCases")

Pkg.activate(PROJECT_ROOT)

if isempty(get(ENV, "HOPE_MODELCASES_PATH", ""))
    ENV["HOPE_MODELCASES_PATH"] = DEFAULT_MODELCASES_PATH
end

using HOPE
using Test

include(joinpath(PROJECT_ROOT, "test", "test-lmp-sign-regression.jl"))
