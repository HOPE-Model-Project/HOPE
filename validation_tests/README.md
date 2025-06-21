# HOPE PCM Validation Tests

This directory contains test scripts and validation tools used during the HOPE PCM redesign and validation project.

## Test Files

### `numerical_comparison_test.jl`
**Purpose**: Comprehensive numerical comparison between the old and new PCM implementations

**Features**:
- Compares both models using identical test data (24-hour minimal test case)
- Tests with both HiGHS and Gurobi solvers
- Validates key outputs: objective value, generation, storage, transmission, load shedding
- Provides detailed difference analysis and reporting

**Usage**:
```julia
julia> include("numerical_comparison_test.jl")
```

**Key Results**:
- Objective difference reduced to ~0.58% after constraint fixes
- All key variables show good agreement between old and new models
- Storage and renewable constraints now functionally equivalent

## Test Data

The validation tests use the minimal test case located at:
`ModelCases/Minimal_PCM_Test_Case/Data_Minimal/`

This test case includes:
- 2 zones, 4 generators, 1 storage unit, 1 transmission line
- 24-hour time horizon for tractable testing
- All required CSV files with realistic but simplified data

## Validation Results

Detailed validation results are documented in:
- `../PCM_VALIDATION_FINAL_REPORT.md` - Comprehensive validation report
- `../NUMERICAL_COMPARISON_REPORT.md` - Detailed numerical comparison results
- `../CONSTRAINT_COMPARISON_ANALYSIS.md` - Line-by-line constraint analysis

## Running the Tests

To run the validation tests:

1. Ensure Julia environment is properly configured
2. Navigate to the HOPE project root directory
3. Run the test script:
   ```julia
   julia> include("validation_tests/numerical_comparison_test.jl")
   ```

## Key Findings

✅ **Model Equivalence**: New PCM produces nearly identical results to old PCM  
✅ **Constraint Validation**: All major constraints properly implemented  
✅ **Solver Compatibility**: Works with both HiGHS and Gurobi solvers  
✅ **Performance**: Comparable or better optimization performance  

## Notes

- Tests use reduced time horizon (24 hours) for computational efficiency
- Full year testing would require more computational resources
- Multiple optimal solutions may exist, explaining small numerical differences
- Constraint formulations are functionally equivalent but may differ in mathematical expression

---
*Last updated: December 2024*
