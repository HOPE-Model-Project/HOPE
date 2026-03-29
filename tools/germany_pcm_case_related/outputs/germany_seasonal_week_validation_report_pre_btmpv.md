# Germany Seasonal Week Congestion Validation

## Overview

Four 7-day Germany nodal cases were solved from the current promoted structural baseline:
- winter: `jan_week3`
- spring: `apr_week3`
- summer: `jul_week3`
- autumn: `oct_week3`

All four cases solved `OPTIMAL` with zero load shedding.

## Seasonal metrics

- Winter: total cost 178,646,994, abs congestion rent 9,102,510, binding hours 536, mean load-weighted LMP 35.36, emissions 2,787,974 t
- Spring: total cost 55,971,384, abs congestion rent 11,168,247, binding hours 421, mean load-weighted LMP 17.89, emissions 53,230 t
- Summer: total cost 63,327,749, abs congestion rent 11,424,648, binding hours 326, mean load-weighted LMP 19.21, emissions 222,587 t
- Autumn: total cost 65,931,864, abs congestion rent 14,455,879, binding hours 683, mean load-weighted LMP 20.01, emissions 353,546 t

Strongest congestion week by absolute congestion rent: `oct_week3` (14,455,879).

Quietest congestion week by absolute congestion rent: `jan_week3` (9,102,510).

## Geography readout

The broad benchmark we want is still:
- northern / northwestern export-side stress,
- west-central Amprion congestion,
- southwest / southern receiving-area stress.

Top hotspot-region counts by season:
- winter: Amprion west_central (5), TenneT northwest_coastal (2), TransnetBW southwest (2), TransnetBW west_central (1)
- spring: Amprion west_central (3), TransnetBW southwest (3), TenneT northwest_coastal (2), 50Hertz north_or_northeast (1), TransnetBW west_central (1)
- summer: Amprion west_central (4), TransnetBW southwest (3), 50Hertz north_or_northeast (1), TenneT northwest_coastal (1), TransnetBW west_central (1)
- autumn: TenneT northwest_coastal (3), Amprion west_central (2), TransnetBW southwest (2), 50Hertz north_or_northeast (1), Amprion central (1)

## Recurring binding lines

- line 4 B381->B363 in TransnetBW: 4 seasons, 429 total binding hours
- line 9 B633->B365 in TransnetBW: 4 seasons, 401 total binding hours
- line 961 B557->B230 in Amprion: 4 seasons, 116 total binding hours
- line 828 B246->B364 in TransnetBW: 4 seasons, 109 total binding hours
- line 679 B40->B475 in TenneT: 4 seasons, 81 total binding hours
- line 627 B738->B374 in Amprion: 3 seasons, 174 total binding hours
- line 772 B657->B256 in 50Hertz: 3 seasons, 111 total binding hours
- line 753 B54->B270 in TransnetBW: 2 seasons, 31 total binding hours

## Assessment

The current structural Germany baseline now has a stronger multi-season validation signal than the earlier 2-day plus single-week check.

What looks good:
- congestion does not collapse into one artificial coastal artifact,
- west-central `Amprion` lines and southwest `TransnetBW` lines remain present across seasons,
- northern and northwestern `TenneT` / `50Hertz` stress still appears in the hotspot set.

What still needs caution:
- this is still a four-week sample, not a full-year validation,
- industry demand is still proxy-based,
- distributed PV / prosumer net-load effects are still absent from the promoted baseline.

## Recommended next step

Use this four-season pack as the default validation benchmark for any further Germany modeling change, then prioritize either:
1. a stronger industry proxy refinement, or
2. a calibrated distributed-PV / net-load correction if we find a defensible benchmark.
