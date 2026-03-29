# Germany Baseline Refresh Validation Note

## Scope

This note compares the active Germany 2-day rescaled nodal case before and after refreshing it from the current main Germany baseline, which now includes:
- improved dynamic nodal load allocation
- updated offshore-to-strong-bus generator mapping

The Germany week1 connected case is already current from the same baseline and is summarized here as the week-scale reference.

## 2-Day Comparison

- Old 2-day total cost: 9,996,855.04
- New 2-day total cost: 9,612,806.55
- Delta: -384,048.49 (-3.84%)
- Old total line-binding hours: 150
- New total line-binding hours: 112
- Old total congestion rent: 1,465,148.39
- New total congestion rent: 535,635.84
- Old total curtailment across hours: 1,092,348.31 MW-h-equivalent
- New total curtailment across hours: 1,048,578.94 MW-h-equivalent
- Old mean load-weighted LMP: 7.173356
- New mean load-weighted LMP: 6.200556

### Previously suspicious coastal lines

- Line 138: old 15h -> new 0h
- Line 673: old 16h -> new 0h

### Largest 2-day congestion changes

- Line 773 B304->B214: 24h -> 0h (delta -24h)
- Line 772 B657->B256: 0h -> 17h (delta +17h)
- Line 523 B309->B359: 17h -> 0h (delta -17h)
- Line 961 B557->B230: 3h -> 19h (delta +16h)
- Line 673 B562->B39: 16h -> 0h (delta -16h)

## Current Week1 Baseline

- Week1 total cost: 38,478,603.68
- Top current binding lines:
- Line 961 B557->B230 (Amprion->Amprion): 133 binding hours, max shadow 44.45
- Line 773 B304->B214 (Amprion->Amprion): 104 binding hours, max shadow 29.32
- Line 4 B381->B363 (TransnetBW->TransnetBW): 102 binding hours, max shadow 91.86
- Line 676 B339->B355 (Amprion->Amprion): 87 binding hours, max shadow 5.11
- Line 445 B555->B578 (TenneT->TenneT): 86 binding hours, max shadow 7.98
- Line 444 B555->B578 (TenneT->TenneT): 86 binding hours, max shadow 5.79
- Line 560 B460->B766 (TenneT->TenneT): 84 binding hours, max shadow 8.69
- Line 772 B657->B256 (50Hertz->50Hertz): 63 binding hours, max shadow 8.68

## Read

The refreshed 2-day case is cheaper and less congestion-heavy overall, while the week1 baseline still shows meaningful internal TSO congestion. The key modeling gain is that the weak coastal bottlenecks identified earlier no longer dominate the nodal picture. The remaining validation task is to decide whether the new congestion reduction is physically reasonable or whether some offshore generation is now concentrated too aggressively on a small set of stronger landing buses.
