# Germany Chronology Workflow

This note documents the intended workflow for freezing the hourly chronology used by both:
- `GERMANY_PCM_nodal_case`
- `GERMANY_PCM_zonal4_case`

## Goal

Build one canonical hourly Germany chronology on a shared study basis so the nodal and zonal cases differ only by network representation and aggregation, not by time-series assumptions.

## Preferred raw inputs

### Required national chronology backbone
- `raw_sources/smard_2025/`

### Optional zonal helper chronology
- `raw_sources/opsd_time_series/`

## Expected cleaned outputs

- `references/germany_hourly_chronology_clean.csv`
- `references/germany_zone_hourly_load_reference.csv`

## Minimum normalized national fields

- `HourIndex`
- `TimestampUTC`
- `Load_MW`
- `WindOnshore_MW`
- `WindOffshore_MW`
- `SolarPV_MW`
- `Hydro_MW`
- `Biomass_MW`
- `OtherRenewables_MW`
- `NetImports_MW`
- `SourceDataset`
- `Notes`

## Minimum zonal helper fields

- `HourIndex`
- `TimestampUTC`
- `Load_50Hertz_MW`
- `Load_Amprion_MW`
- `Load_TenneT_MW`
- `Load_TransnetBW_MW`
- `Share_50Hertz`
- `Share_Amprion`
- `Share_TenneT`
- `Share_TransnetBW`
- `SourceDataset`
- `Notes`

## Intended build logic

1. read a national Germany hourly chronology extracted from SMARD
2. normalize timestamps and core load / renewable / interchange fields
3. optionally read a TSO-area helper chronology from OPSD or another documented source
4. normalize the four TSO load series and convert them into hourly zonal shares
5. freeze both outputs so later nodal and zonal preprocessing reads the same chronology basis

## QA expectations

Before the chronology is treated as usable:
- timestamps should be hourly, unique, and contiguous for the selected study window
- `Load_MW` should be populated for every retained hour
- zonal shares should sum to approximately 1.0 whenever helper load data is present
- the selected study month and daylight-saving handling should be documented in `CASE_DATA_NOTES.md`
