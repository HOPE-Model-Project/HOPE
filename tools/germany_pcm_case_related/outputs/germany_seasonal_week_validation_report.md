# Germany Seasonal Week Congestion Validation

## Overview

Four 7-day Germany nodal cases were solved from the current promoted Germany nodal baseline:
- winter: `jan_week3`
- spring: `apr_week3`
- summer: `jul_week3`
- autumn: `oct_week3`

All four cases solved `OPTIMAL` with zero load shedding.

## Seasonal metrics

- Winter: total cost 176,145,296, abs congestion rent 9,149,195, binding hours 537, mean load-weighted LMP 35.31, emissions 2,723,999 t
- Spring: total cost 52,782,165, abs congestion rent 10,370,608, binding hours 371, mean load-weighted LMP 17.14, emissions 44,680 t
- Summer: total cost 58,615,658, abs congestion rent 10,590,848, binding hours 308, mean load-weighted LMP 18.19, emissions 176,873 t
- Autumn: total cost 63,363,978, abs congestion rent 13,451,075, binding hours 684, mean load-weighted LMP 19.04, emissions 314,236 t

Strongest congestion week by absolute congestion rent: `oct_week3` (13,451,075).

Quietest congestion week by absolute congestion rent: `jan_week3` (9,149,195).

## Geography readout

The broad benchmark we want is still:
- northern / northwestern export-side stress,
- west-central Amprion congestion,
- southwest / southern receiving-area stress.

Top hotspot-region counts by season:
- winter: Amprion west_central (4), TransnetBW southwest (3), TenneT northwest_coastal (2), TransnetBW west_central (1)
- spring: Amprion west_central (3), TransnetBW southwest (3), 50Hertz north_or_northeast (1), Amprion central (1), TenneT northwest_coastal (1)
- summer: Amprion west_central (4), TransnetBW southwest (3), 50Hertz north_or_northeast (1), TenneT central (1), TransnetBW west_central (1)
- autumn: TenneT northwest_coastal (3), Amprion west_central (2), TransnetBW southwest (2), 50Hertz north_or_northeast (1), Amprion central (1)

## Recurring binding lines

- line 4 B381->B363 in TransnetBW: 4 seasons, 419 total binding hours
- line 9 B633->B365 in TransnetBW: 4 seasons, 375 total binding hours
- line 828 B246->B364 in TransnetBW: 4 seasons, 108 total binding hours
- line 627 B738->B374 in Amprion: 3 seasons, 199 total binding hours
- line 772 B657->B256 in 50Hertz: 3 seasons, 106 total binding hours
- line 961 B557->B230 in Amprion: 3 seasons, 100 total binding hours
- line 679 B40->B475 in TenneT: 3 seasons, 72 total binding hours
- line 753 B54->B270 in TransnetBW: 3 seasons, 20 total binding hours

## Assessment

The current Germany baseline now has a stronger multi-season validation signal than the earlier 2-day plus single-week check.

What looks good:
- congestion does not collapse into one artificial coastal artifact,
- west-central `Amprion` lines and southwest `TransnetBW` lines remain present across seasons,
- northern and northwestern `TenneT` / `50Hertz` stress still appears in the hotspot set.

What still needs caution:
- this is still a four-week sample, not a full-year validation,
- industry demand is still proxy-based,
- the promoted baseline includes calibrated base BTM-PV, but broader prosumer effects like EV charging and heat pumps are still absent.

## Recommended next step

Use this four-season pack as the default validation benchmark for any further Germany modeling change, then prioritize either:
1. stronger empirical validation against redispatch or corridor evidence, or
2. a better industry data/proxy refinement.
