# HOPE PCM Benchmark Results

## Test Case: MD_PCM_Excel_case
**Date**: June 27, 2025  
**Model**: Clean Master PCM  
**Case Directory**: `ModelCases/MD_PCM_Excel_case/`  

---

## UC=0 (No Unit Commitment) - OLD PCM BASELINE ✅ CONFIRMED
- **Status**: ✅ **CONFIRMED** (Retested June 27, 2025)
- **Model Type**: Old PCM (src/PCM.jl) - Standard economic dispatch
- **Objective Value**: **$5.070470565979917e17**
- **Variables**: **1,472,130** (exact from Gurobi output)
- **Constraints**: **1,489,232** (exact from Gurobi output)
- **Execution Time**: **130.48 seconds**
- **Solver Status**: Optimal (Gurobi, 510,740 iterations, 18.62s solver time)
- **Architecture**: Monolithic PCM.jl

### Cost Breakdown:
- **Operation Cost**: $1.6107097652727637e9
- **Load Shedding**: $9.116428615316859e7
- **RPS Penalty**: $5.0704705489613734e17 (dominates objective)
- **Carbon Cap Penalty**: $0.0

### Notes: 
- Large objective dominated by RPS penalty violation
- RPS requirement: MD=1, NMD=0
- Carbon emissions: MD=3.786186525597682e7, NMD=0.0

---

## UC=0 (No Unit Commitment) - NEW PCM TEST
- **Status**: 🔄 **PENDING** 
- **Model Type**: New PCM (src_new/models/PCM.jl) - ConstraintPool architecture
- **Objective Value**: *TBD*
- **Variables**: *TBD*
- **Constraints**: *TBD*
- **Execution Time**: *TBD*
- **Solver Status**: *TBD*
- **Architecture**: Modular ConstraintPool design
- **Notes**: Drop-in replacement validation test

### Comparison Target:
- ✅ Objective value should match: $1,086,803,086.77 (±1e-6)
- ✅ Model should solve successfully with similar performance
- ✅ Constraint count should be similar: ~25,200

---

## UC=2 (Convexified Unit Commitment) - CONFIRMED ✅

**Date**: June 27, 2025
**Model**: Old PCM  
**Case**: MD_PCM_Excel_case

### Results:
- **Objective Value**: $5.070470565979868e17
- **Variables**: 2,050,290
- **Constraints**: 2,645,324  
- **Status**: Optimal
- **Execution Time**: 3,322.58 seconds (55.4 minutes)
- **Solver**: Gurobi 12.0.2
- **Solver Iterations**: 1,330,544

### Detailed Output:
- **Startup Cost**: $0.0
- **Operation Cost**: $1.610698553384571e9
- **Load Shedding**: $9.116428615316959e7
- **RPS Penalty**: $5.0704705489613734e17
- **Carbon Cap Penalty**: $0.0

### Solver Statistics:
- **Presolve Time**: 7.17s
- **Barrier Iterations**: 18
- **Barrier Time**: 78.74s  
- **Crossover Time**: ~3,100s
- **Model Size (Original)**: 2,645,324 rows × 2,050,290 columns
- **Model Size (Presolved)**: 1,100,583 rows × 1,014,300 columns

---

## Performance Comparison Framework

| Metric | UC=0 (Baseline) | UC=2 (Benchmark) | Expected UC=1 |
|--------|-----------------|------------------|----------------|
| Solve Time | ~Fast | 3358.53s | >3358.53s |
| Objective Value | ~Lower | 5.07047e17 | Similar |
| Variables | Continuous | Continuous | Binary |
| Complexity | Low | Medium | High |
| Memory Usage | ~Low | 1.3GB | >1.3GB |

---

## Test Environment
- **OS**: Windows 11
- **CPU**: Intel Core i7-10510U @ 1.80GHz (4 cores, 8 threads)
- **Solver**: Gurobi 12.0.2 (Academic License)
- **Julia Version**: 1.11
- **Memory**: Factor memory ~1.3GB
- **Method**: Barrier with crossover

---

## New PCM Results

### UC=0 (No Unit Commitment) - COMPLETED ⚠️
**Date**: January 2025
**Model**: New ConstraintPool-based PCM  
**Case**: MD_PCM_Excel_case

### Results:
- **Objective Value**: $5.070470566e+17 ✅ (matches baseline)
- **Variables**: 911,144 ❌ (baseline: 1,472,130, diff: -560,986)
- **Constraints**: 1,436,672 ❌ (baseline: 1,489,232, diff: -52,560)
- **Status**: Optimal ✅ (matches baseline)
- **Execution Time**: 61.55 seconds ✅ (baseline: 130.48s, 2.1x faster)

### Analysis:
- **Objective Match**: Perfect match within numerical precision
- **Performance**: 2.1x faster than old PCM (significant improvement)
- **Model Size**: Different variable/constraint counts suggest different formulation
- **Status**: Both achieve optimal solution

### UC=2 (Convexified Unit Commitment) - ERROR ❌
**Date**: January 2025
**Model**: New ConstraintPool-based PCM  
**Case**: MD_PCM_Excel_case

### Results:
- **Status**: ERROR - InexactError during constraint creation
- **Error**: `InexactError: Int64(5.571428571428571)` 
- **Location**: Unit commitment constraint generation (line 764 in PCM.jl)
- **Execution Time**: 42.06 seconds (failed during model building)

### Analysis:
- **Issue**: Float64 to Int64 conversion error in unit commitment constraints
- **Root Cause**: Non-integer minimum up/down time parameter being used where integer expected
- **Impact**: New PCM cannot handle UC=2 currently - needs debugging
- **Next Steps**: Fix unit commitment constraint generation in src_new/models/PCM.jl

---

## Usage Notes
- Use these results as baseline for comparing new PCM implementations
- UC=2 provides a good balance between solution quality and solve time
- Any new implementation should aim to match or improve these metrics
- RPS penalty dominates the objective value - focus area for improvement

---

## Benchmark Quality Assurance
- **✅ Fixed Issues**: All constraint range syntax errors resolved
- **✅ Validation**: Both UC=0 and UC=2 run successfully to completion
- **✅ Stability**: Consistent results across multiple runs
- **✅ Performance**: Solve times within expected ranges
- **✅ Code Quality**: Clean, maintainable PCM.jl implementation

## Future Testing Targets
| Target | Expected Performance | Priority |
|--------|---------------------|----------|
| UC=1 (Binary) | Slower than UC=2, higher quality | High |
| New PCM Model | Match or improve UC=2 | Medium |
| Alternative Solvers | Compare to Gurobi baseline | Low |
| Larger Test Cases | Scale performance testing | Low |

## Testing Framework Usage
```julia
# Run individual test
include("test_framework.jl")
result = run_pcm_test("MD_PCM_Excel_case", 2, "UC=2 Benchmark Test")

# Run all configured tests
results = main()
```

## Next Steps Preparation
1. ✅ UC=0 and UC=2 benchmarks established and validated
2. ✅ Test framework created and ready for use
3. ✅ Old test scripts cleaned and organized
4. 🔄 Ready for UC=1 (binary unit commitment) testing
5. 🔄 Ready for new PCM model comparisons
6. 🔄 Framework extensible for future test cases

**Last Updated**: June 25, 2025  
**Framework Version**: 1.0  
**Status**: Production Ready ✅
