# HOPE PCM Validation Test Suite
# Clean, organized validation tools for the new transparent PCM

## Main Files for PCM Validation

### 1. Core Integration Test
- `full_integration_test.jl` - Complete comparison between old and new PCM models

### 2. Diagnostic Tools  
- `pcm_diagnostics.jl` - Model structure and constraint analysis tools
- `results_interpreter.jl` - Results analysis and debugging guide

### 3. Test Cases (Established ModelCases)
- `ModelCases/PJM_MD100_PCM_case/` - Primary CSV-based test case
- `ModelCases/MD_PCM_clean_case_holistic_test/` - Excel-based test case
- `ModelCases/MD_PCM_Excel_case/` - Additional Excel case
- `ModelCases/MD_PCM_Excel_DR_case/` - Demand response case

## Usage

### Quick Validation
```bash
julia --project=. full_integration_test.jl
```

### With Diagnostics
```bash
julia --project=. pcm_diagnostics.jl
julia --project=. results_interpreter.jl
```

## Status
✅ New transparent PCM model (`src_new/models/PCM.jl`) completed
✅ Test files cleaned up and organized
✅ Ready for comprehensive validation against established ModelCases

## Next Steps
1. Run integration test on `PJM_MD100_PCM_case` (CSV-based)
2. Compare results between old and new PCM implementations
3. Debug any discrepancies using diagnostic tools
4. Extend validation to other ModelCases
