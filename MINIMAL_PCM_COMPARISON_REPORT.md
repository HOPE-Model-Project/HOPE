# HOPE PCM Minimal Test Case Comparison Report

Generated: 2025-06-21T13:35:21.803

## Test Configuration
- **Test Case**: Minimal_PCM_Test_Case  
- **Time Horizon**: 24 hours
- **Solver**: HiGHS
- **Zones**: 2 (Zone1: 1000MW, Zone2: 500MW)
- **Generators**: 3 (Coal 800MW, NGCT 600MW, NGCT 400MW)
- **Storage**: 1 (Battery 100MW/400MWh)
- **Transmission**: 1 line (300MW capacity)

## Results Summary

### Solution Status
- **Old PCM**: N/A
- **New PCM**: N/A
- **Match**: true

### Objective Value
- **Old PCM**: $908420.62
- **New PCM**: $903118.62
- **Absolute Difference**: $5302.0
- **Relative Difference**: 0.5837%
- **Match**: false

### Solve Performance
- **Old PCM Time**: 0.012 seconds
- **New PCM Time**: 0.003 seconds

### Variable Comparisons
#### Generation
- **Maximum Difference**: 100.0
- **Mean Difference**: 15.05
- **Match**: false
#### Transmission
- **Maximum Difference**: 100.0
- **Mean Difference**: 23.233333
- **Match**: false
#### Storage Soc
- **Maximum Difference**: 105.263158
- **Mean Difference**: 26.845395
- **Match**: false
#### Load Shedding
- **Maximum Difference**: 0.0
- **Mean Difference**: 0.0
- **Match**: true

## Conclusion

**Overall Assessment**: ❌ FAIL - Models differ

The numerical comparison reveals discrepancies in the equivalence between old and new PCM implementations.
