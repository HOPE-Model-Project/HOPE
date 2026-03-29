# Germany Next-Step Congestion Assessment

## Scope

This assessment now reflects the current structural-load baselines:

- `ModelCases/GERMANY_PCM_nodal_jan_2day_rescaled_case`
- `ModelCases/GERMANY_PCM_nodal_jan_week1_connected_case`

The refreshed hotspot table is in `germany_current_hotspot_geo_summary.csv`.

## Spatial read of current hotspots

### 2-day structural case

Top hotspot region counts:

 From_zone        RegionLabel  Count
   Amprion       west_central      4
    TenneT  northwest_coastal      2
   50Hertz north_or_northeast      1
   Amprion            central      1
    TenneT            central      1
TransnetBW          southwest      1

Read:

- `TransnetBW` southwest stress is still present.
- `Amprion` west-central and central corridors remain important.
- `TenneT` contributes northern / northwestern hotspots without falling back to the old weak coastal radial artifact.

### Week1 structural case

Top hotspot region counts:

 From_zone        RegionLabel  Count
    TenneT  northwest_coastal      4
   Amprion       west_central      3
    TenneT            central      2
TransnetBW          southwest      1

Read:

- `TenneT` northwestern internal stress is now the clearest northern export-area signal.
- `Amprion` west-central congestion remains prominent.
- `TransnetBW` southwest stress remains active.
- The strongest bottlenecks are now internal lines inside major TSO footprints rather than the earlier suspicious coastal radial lines.

## Interpretation Against The Germany Benchmark

The current pattern is directionally plausible and compatible with the broad German congestion story:

- northern / northwestern congestion is still present,
- southwest receiving-area stress is still present,
- west-central `Amprion` congestion remains meaningful,
- the earlier fake coastal lines `138` and `673` no longer dominate.

This is not full validation yet, because both windows are still short and the load model still lacks real eGon industry demand and distributed-PV net-load correction.

## Recommendation

Do **not** do another immediate offshore topology redesign.

The current baseline is good enough to move forward with the next realism upgrade on the load side.

Recommended next priority:

1. add a distributed-PV / prosumer net-load correction if we can source defensible spatial data,
2. otherwise continue the search for the missing eGon industry demand table and use that as the next load upgrade.
