using HOPE

default_repo_root() = normpath(joinpath(@__DIR__, "..", "..", ".."))

const CASES = [
    "MD_PCM_Excel_case_aggmethods_1month_original",
    "MD_PCM_Excel_case_aggmethods_1month_basic",
    "MD_PCM_Excel_case_aggmethods_1month_feature",
]

repo_root = length(ARGS) >= 1 ? abspath(ARGS[1]) : default_repo_root()

for case_name in CASES
    println()
    println("=== Running $(case_name) ===")
    HOPE.run_hope(joinpath(repo_root, "ModelCases", case_name))
end
