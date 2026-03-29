# Germany Week1 Structural Sector Weight Update

This note compares the refreshed week1 Germany case before and after introducing structural sector weights.

## What changed

Instead of fitting households / CTS / industry weights directly on the short week1 window, the week1 case now reuses the full-year Germany sector weights and only applies the week1 hourly activity patterns inside that structural mix.

## Week1 impact

- Pre-structural total cost: 38,478,603.68
- Structural total cost: 38,347,584.77
- Delta: -131,018.91 (-0.34%)
- Pre-structural total binding hours: 1188
- Structural total binding hours: 1223
- Pre-structural total congestion rent: 5,720,224.88
- Structural total congestion rent: 5,171,181.42
- Pre-structural mean load-weighted LMP: 9.298590
- Structural mean load-weighted LMP: 9.139032

### Largest congestion shifts

- Line 679 B40->B475: 24h -> 75h (delta 51h)
- Line 228 B543->B421: 52h -> 68h (delta 16h)
- Line 480 B456->B477: 47h -> 32h (delta -15h)
- Line 483 B456->B477: 47h -> 32h (delta -15h)
- Line 521 B601->B23: 5h -> 14h (delta 9h)

## Read

This is again a modest economics change and a stronger modeling-structure change. The active week1 baseline now uses the same full-year-calibrated sector mix as the 2-day case, so the short Germany debug windows are aligned on one defensible nodal load design.
