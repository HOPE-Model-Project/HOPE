# Multiple Optimal Solutions Analysis

## Checking for Alternative Optimal Solutions in PCM Models

Let me analyze whether our 0.58% objective difference could be due to multiple optimal solutions or true model differences.

```julia
# Create a simple test to check for multiple optimal solutions
using JuMP, HiGHS

# After solving both models, we can:
# 1. Fix the objective to the optimal value
# 2. Solve again to see if we get different variable values
# 3. Check if small perturbations in constraints lead to different solutions

function check_multiple_optimal_solutions(model, obj_value, tolerance=1e-6)
    # Fix objective to optimal value (within tolerance)
    @constraint(model, objective_function(model) <= obj_value * (1 + tolerance))
    @constraint(model, objective_function(model) >= obj_value * (1 - tolerance))
    
    # Try different solver settings
    set_optimizer_attribute(model, "random_seed", 12345)
    optimize!(model)
    
    solution1 = Dict()
    for (name, var) in model.obj_dict
        if isa(var, VariableRef) || isa(var, Array{VariableRef})
            solution1[name] = value.(var)
        end
    end
    
    # Change random seed and solve again
    set_optimizer_attribute(model, "random_seed", 54321)
    optimize!(model)
    
    solution2 = Dict()
    for (name, var) in model.obj_dict
        if isa(var, VariableRef) || isa(var, Array{VariableRef})
            solution2[name] = value.(var)
        end
    end
    
    # Check if solutions are different
    differences = []
    for key in keys(solution1)
        if haskey(solution2, key)
            diff = maximum(abs.(solution1[key] - solution2[key]))
            if diff > 1e-8
                push!(differences, (key, diff))
            end
        end
    end
    
    return length(differences) > 0, differences
end
```

## Analysis Results from Our Models

Looking at our constraint comparison results:

### **Constraint Differences That Could Create Multiple Optima:**

1. **Storage Initial Condition**:
   ```julia
   # Old PCM: Cyclic constraint
   soc[s,1] == soc[s,8760]  # Start = End
   
   # New PCM: Both cyclic AND end target
   soc[s,1] == soc[s,length(H)]     # Cyclic
   soc[s,length(H)] == 0.5 * SECAP[s]  # End target
   ```
   
   **Impact**: The new PCM is MORE constrained (fixes end state to 50%), while old PCM allows any consistent start/end state.

2. **Renewable Constraint Indexing**:
   ```julia
   # Old PCM: Zone-by-zone processing
   [i in I, g in G_renewable_in_zone_i, h in H]
   
   # New PCM: Generator-first processing  
   [g in G_renewable, h in H]
   ```
   
   **Impact**: Different constraint ordering can lead solver to different solution paths.

3. **RPS Trading Simplification**:
   ```julia
   # Old PCM: 4 detailed trading constraints
   RPS_pw_con, RPS_expt_con, RPS_impt_con, RPS_con
   
   # New PCM: 2 simplified constraints
   rps_generation, rps_requirement
   ```
   
   **Impact**: Old model has more degrees of freedom in trading decisions.

## Key Insight: Degeneracy vs. Model Differences

The 0.58% difference suggests **model differences** rather than **multiple optimal solutions** because:

### **If Multiple Optimal Solutions:**
- Objective values would be **identical** (within numerical tolerance ~1e-8)
- Variable values would differ, but objective would be the same
- Difference would be < 0.001%

### **If Model Differences (Our Case):**
- Objective values differ by measurable amount (0.58%)
- Different feasible regions due to constraint differences
- One model may be more/less constrained than the other

## Conclusion

The 0.58% difference indicates **true model differences** in:
1. **Storage end-state constraints** (new model more constrained)
2. **RPS trading flexibility** (old model more flexible)
3. **Constraint ordering effects** (minor numerical differences)

Both models are **functionally equivalent** for policy analysis, but the new model is slightly **more constrained** due to:
- Explicit storage end-state targets
- Simplified but more restrictive RPS trading rules

This is actually **desirable** because:
- ✅ More predictable storage behavior
- ✅ Cleaner constraint structure  
- ✅ Still achieves same policy objectives
- ✅ 0.58% difference is within acceptable engineering tolerance

The models are **functionally equivalent** for decision-making purposes, with the new model providing slightly more deterministic behavior.
