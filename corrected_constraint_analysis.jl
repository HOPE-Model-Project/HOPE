"""
Corrected Constraint Analysis
============================
Fix the function boundary detection to properly count @constraint statements
"""

using Pkg
Pkg.activate(".")

function analyze_constraint_functions_correctly()
    """Properly analyze constraint functions by tracking function boundaries"""
    
    println("🔍 CORRECTED CONSTRAINT ANALYSIS")
    println("="^60)
    
    # Read the ConstraintPool file
    constraint_pool_content = read("src_new/core/ConstraintPool.jl", String)
    lines = split(constraint_pool_content, '\n')
    
    functions = []
    current_function = nothing
    function_depth = 0
    constraint_count = 0
    
    for (i, line) in enumerate(lines)
        stripped_line = strip(line)
        
        # Function start
        if contains(line, "function add_") && contains(line, "_con!")
            if current_function !== nothing
                # Save previous function
                current_function["constraint_count"] = constraint_count
                push!(functions, current_function)
            end
            
            func_name = extract_function_name(line)
            current_function = Dict(
                "name" => func_name,
                "line" => i,
                "content" => line
            )
            constraint_count = 0
            function_depth = 1
        end
        
        # Track depth for proper function boundary detection
        if current_function !== nothing
            # Count function/if/for/while starts
            if contains(stripped_line, r"function|if |for |while ")
                function_depth += 1
            end
            
            # Count ends
            if stripped_line == "end"
                function_depth -= 1
            end
            
            # Count @constraint statements
            if contains(line, "@constraint")
                constraint_count += 1
                println("   🔍 Found @constraint in $(current_function["name"]) at line $i")
            end
            
            # Function actually ends when depth reaches 0
            if function_depth == 0
                current_function["constraint_count"] = constraint_count
                push!(functions, current_function)
                current_function = nothing
                constraint_count = 0
            end
        end
    end
    
    # Handle last function if file ends
    if current_function !== nothing
        current_function["constraint_count"] = constraint_count
        push!(functions, current_function)
    end
    
    println("\\n📊 CORRECTED RESULTS:")
    println("   ✅ Found $(length(functions)) constraint functions")
    
    complete_functions = 0
    incomplete_functions = 0
    
    for func in functions
        status = func["constraint_count"] > 0 ? "✅" : "❌"
        constraint_text = func["constraint_count"] > 0 ? "$(func["constraint_count"]) @constraints" : "NO @constraints"
        println("   $status $(func["name"]) - $constraint_text")
        
        if func["constraint_count"] > 0
            complete_functions += 1
        else
            incomplete_functions += 1
        end
    end
    
    println("\\n📊 SUMMARY:")
    println("   ✅ Complete functions: $complete_functions")
    println("   ❌ Incomplete functions: $incomplete_functions")
    println("   📊 Completion rate: $(round(complete_functions / length(functions) * 100, digits=1))%")
    
    return functions
end

function extract_function_name(line)
    """Extract function name from function definition line"""
    match_result = match(r"function\\s+(add_[^!]+_con!)", line)
    if match_result !== nothing
        return match_result.captures[1]
    else
        return "unknown"
    end
end

# Run the corrected analysis
if abspath(PROGRAM_FILE) == @__FILE__
    analyze_constraint_functions_correctly()
end
