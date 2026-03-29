# Germany Structural Sector Weight Update

This note compares the refreshed 2-day Germany case before and after introducing structural sector weights.

## What changed

Instead of fitting households / CTS / industry weights directly on the short 2-day window, the 2-day case now reuses the full-year Germany sector weights and only applies the 2-day hourly activity patterns inside that structural mix.

## 2-day impact

- Pre-structural total cost: 9,612,806.55
- Structural total cost: 9,602,904.66
- Delta: -9,901.88 (-0.10%)
- Pre-structural total binding hours: 112
- Structural total binding hours: 155
- Pre-structural total congestion rent: 535,635.84
- Structural total congestion rent: 476,505.03
- Pre-structural mean load-weighted LMP: 6.200556
- Structural mean load-weighted LMP: 6.200255

### Largest congestion shifts

- Line 228 B543->B421: 0h -> 9h (delta +9h)
- Line 773 B304->B214: 0h -> 8h (delta +8h)
- Line 560 B460->B766: 0h -> 6h (delta +6h)
- Line 627 B738->B374: 3h -> 8h (delta +5h)
- Line 961 B557->B230: 19h -> 23h (delta +4h)

## Structural sector weights now used by short windows

- TransnetBW: households 0.272, CTS 0.319, industry 0.409 (structural_full_year_reference)
- Amprion: households 0.272, CTS 0.328, industry 0.400 (structural_full_year_reference)
- 50Hertz: households 0.291, CTS 0.307, industry 0.401 (structural_full_year_reference)
- TenneT: households 0.281, CTS 0.321, industry 0.398 (structural_full_year_reference)

## Read

This is a modeling-quality improvement more than an economics shock. The cost moves only slightly relative to the already refreshed baseline, which is a good sign: we made the short-window load model more structurally defensible without blowing up the system behavior. This should now be the preferred load construction for the Germany debug windows.
