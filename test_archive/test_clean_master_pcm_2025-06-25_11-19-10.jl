#!/usr/bin/env julia
"""
Test the CLEAN MASTER PCM with original MD_PCM_Excel_case
No modifications - pure master branch code
"""

using Pkg
Pkg.activate(".")

# Use the clean HOPE module
using HOPE

println("🚀 TESTING CLEAN MASTER PCM")
println("=" ^ 50)
println("📋 Branch: master (clean)")
println("📁 Case: ModelCases/MD_PCM_Excel_case/")

try
    println("🔧 Running clean master PCM...")
    result = HOPE.run_hope("ModelCases/MD_PCM_Excel_case/")
    println("   ✅ Clean master PCM completed successfully!")
catch e
    println("   ❌ Clean master PCM failed: $(typeof(e))")
    println("   Error: $e")
    for (i, bt) in enumerate(stacktrace(catch_backtrace()))
        println("     $i. $bt")
        if i > 10  # Limit stack trace length
            break
        end
    end
end

println("🏁 TEST FINISHED")
