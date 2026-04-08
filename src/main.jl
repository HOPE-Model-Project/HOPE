"""
Legacy script entrypoint for running a single HOPE case from the command line.

Preferred usage:
    julia --project=. src/main.jl ModelCases/<case_name>

This file is intentionally kept as a thin wrapper around `HOPE.run_hope` so
older workflows still have a simple script entrypoint.
"""

include("HOPE.jl")
using .HOPE

function print_main_usage_and_exit()
    println("Usage: julia --project=. src/main.jl <case_path>")
    println("Example: julia --project=. src/main.jl ModelCases/MD_GTEP_clean_case")
    exit(1)
end

function main(args::Vector{String})
    isempty(args) && print_main_usage_and_exit()
    case = args[1]
    results = HOPE.run_hope(case)
    case_path = results["case_path"]
    output_path = results["output_path"]
    println("HOPE run completed successfully.")
    println("Case: $case_path")
    println("Output: $output_path")
    return results
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
