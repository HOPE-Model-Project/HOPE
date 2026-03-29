# Germany Structural Congestion Validation Readout

## Benchmark reminder

The external benchmark still points to a structural German pattern of northern and northwestern renewable-export stress interacting with southern and southwestern receiving areas. In practice that means we want to see at least part of the hotspot set land in northern or northwestern corridors and part in southern or southwestern corridors, with western / central Amprion stress also plausible.

## Current hotspot geography

Refreshed hotspot table: `germany_current_hotspot_geo_summary.csv`

### 2-day structural case

Dominant hotspot zones: Amprion (5), TenneT (3), TransnetBW (1), 50Hertz (1)

Dominant regions in the top 10 binding lines:
- central, north_or_northeast, northwest_coastal, southwest, west_central

Read:
- The 2-day case still shows a mixed but credible pattern.
- `TransnetBW` southwest stress is present.
- `Amprion` west-central and central corridors are present.
- `TenneT` no longer depends on the artificial weak coastal radial bottlenecks, but it still contributes northern / northwestern stress.

### Week1 structural case

Dominant hotspot zones: TenneT (6), Amprion (3), TransnetBW (1)

Dominant regions in the top 10 binding lines:
- central, northwest_coastal, southwest, west_central

Read:
- The week1 case gives the stronger validation signal.
- `Amprion` west-central congestion remains prominent.
- `TransnetBW` southwest stress remains active.
- `TenneT` and `50Hertz` still contribute northern or northwestern hotspots, which is directionally consistent with the export-heavy north.
- The strongest remaining bottlenecks are internal lines inside major TSO footprints, which is acceptable for a nodal model and no longer looks dominated by the earlier coastal artifact.

## Overall assessment

The refreshed structural baseline is directionally consistent with the general German congestion story.

Why this looks better now:
- northern / northwestern hotspots are still present,
- southwest / southern receiving-area stress is still present,
- west-central `Amprion` congestion remains meaningful,
- the earlier fake offshore-to-radial coastal bottlenecks are no longer the main drivers.

What is still not fully proven:
- these are still short windows, especially the 2-day run,
- the model still lacks real eGon industry demand,
- distributed PV / prosumer net-load effects are not yet represented.

## Recommendation

The current Germany baseline is strong enough to proceed with the next realism upgrade on the load side rather than another topology redesign.

Best next candidate:
1. add net-load correction from distributed PV / prosumer effects if we have usable spatial data,
2. otherwise keep searching for the missing industry demand table and use that as the next load upgrade.
