# Germany Raw Drop Checklist

This is the exact first-pass data drop expected by the current Germany preprocessing scripts.

## Recommended first drop

If you want the smallest workable first dataset, provide these five files:

1. `tools/germany_pcm_case_related/raw_sources/osm_europe_grid/buses.csv`
2. `tools/germany_pcm_case_related/raw_sources/osm_europe_grid/lines.csv`
3. `tools/germany_pcm_case_related/raw_sources/osm_europe_grid/transformers.csv`
4. `tools/germany_pcm_case_related/raw_sources/powerplantmatching/germany_powerplantmatching.csv`
5. `tools/germany_pcm_case_related/raw_sources/smard_2025/germany_hourly_chronology.csv`

Optional but helpful:
- `tools/germany_pcm_case_related/raw_sources/osm_europe_grid/links.csv`
- either one combined helper file in `raw_sources/opsd_time_series/germany_tso_hourly_load.csv`
- or four separate SMARD control-area load files in `raw_sources/smard_2025/`
- any validation files under `raw_sources/mastr/`
- any validation files under `raw_sources/kraftwerksliste/`
- `tools/germany_pcm_case_related/raw_sources/reference_geo/germany_states_simplify200.geojson` if you want to rebuild the dashboard TSO overlay locally

## Important note on 2025 zonal helper data

For a 2025 case, prefer separate SMARD control-area downloads over OPSD.
The OPSD time-series package is convenient, but the currently listed package version covers data only through mid-2020, so it is not a like-for-like 2025 helper chronology. Source: https://data.open-power-system-data.org/time_series/

## 1. Network backbone drop

Folder:
- `tools/germany_pcm_case_related/raw_sources/osm_europe_grid/`

Accepted filenames:
- buses: `buses.csv` or `germany_network_buses.csv`
- lines: `lines.csv` or `germany_network_lines.csv`
- transformers: `transformers.csv` or `germany_network_transformers.csv`
- links: `links.csv` or `germany_network_links.csv`

### Minimum bus columns

Preferred:
- `name`
- `x`
- `y`
- `v_nom`
- `country`
- `carrier`

Also accepted by the cleaner:
- `SourceBusName`
- `Longitude`
- `Latitude`
- `V_nom_kV`
- `Country`
- `Carrier`

Notes:
- `x` should be longitude
- `y` should be latitude
- if `name` is missing, the cleaner can still assign internal IDs, but line endpoint resolution is better if bus names exist

### Minimum line columns

Preferred:
- `bus0`
- `bus1`
- `length`
- `v_nom`
- `s_nom`
- `r`
- `x`
- `num_parallel`
- `carrier`

Optional:
- `name`

### Minimum transformer columns

Preferred:
- `bus0`
- `bus1`
- `s_nom`
- `x`

Optional:
- `name`

### Minimum link columns

Preferred:
- `bus0`
- `bus1`
- `p_nom`
- `length`
- `carrier`

Optional:
- `name`

## 2. Generator fleet drop

Folder:
- `tools/germany_pcm_case_related/raw_sources/powerplantmatching/`

Accepted filenames:
- `germany_powerplantmatching.csv`
- `powerplants.csv`
- `powerplantmatching_germany.csv`

### Minimum generator columns

At least one country field:
- `country` or `Country` or `country_code` or `Country_Code`
- optional alternative: `country_long` or `Country_Long` or `CountryName` or `country_name`

At least one plant-name field:
- `name` or `Name` or `plant_name` or `PlantName`

At least one plant-id field:
- `projectID` or `project_id` or `id` or `EIC` or `eic_code`

At least one fuel field:
- `fueltype` or `Fueltype` or `FuelType` or `fuel`

At least one technology field:
- `technology` or `Technology` or `set` or `Set`

At least one status field:
- `status` or `Status` or `project_status` or `ProjectStatus`

At least one capacity field:
- `capacity_net_bnetza`
- `capacity_net_mw`
- `capacity`
- `capacity_net`
- `capacity_gross_uba`
- `Capacity_MW`

Coordinate fields:
- `lat` or `latitude` or `Latitude`
- `lon` or `longitude` or `Longitude`

Notes:
- the current builder drops retired plants and plants with missing or non-positive capacity
- generator-to-bus assignment works best when coordinates are present

## 3. National chronology drop

Folder:
- `tools/germany_pcm_case_related/raw_sources/smard_2025/`

Accepted filenames:
- `germany_hourly_chronology.csv`
- `smard_hourly_balance.csv`
- `germany_hourly_balance.csv`

### Required timestamp field

One of:
- `TimestampUTC`
- `timestamp_utc`
- `utc_timestamp`
- `timestamp`
- `date_time`
- `Datetime`

### Required load field

One of:
- `Load_MW`
- `load_mw`
- `load`
- `DE_load_actual_entsoe_power_statistics`

### Optional renewable and interchange fields

Wind onshore:
- `WindOnshore_MW` or `wind_onshore_mw` or `wind_onshore` or `onshore_wind` or `Wind onshore`

Wind offshore:
- `WindOffshore_MW` or `wind_offshore_mw` or `wind_offshore` or `offshore_wind` or `Wind offshore`

Solar:
- `SolarPV_MW` or `solar_pv_mw` or `solar` or `solar_mw` or `Solar`

Hydro:
- `Hydro_MW` or `hydro` or `hydro_mw` or `Hydro`

Biomass:
- `Biomass_MW` or `biomass` or `biomass_mw` or `Biomass`

Other renewables:
- `OtherRenewables_MW` or `other_renewables_mw` or `other_renewables` or `renewables_other`

Net imports:
- `NetImports_MW` or `net_imports_mw` or `net_imports` or `interchange` or `imports_minus_exports`

## 4. Preferred 2025 TSO load helper drop

Folder:
- `tools/germany_pcm_case_related/raw_sources/smard_2025/`

Preferred filenames:
- `load_50Hertz_hourly.csv`
- `load_Amprion_hourly.csv`
- `load_TenneT_hourly.csv`
- `load_TransnetBW_hourly.csv`

Accepted alternative names:
- `smard_load_50Hertz_hourly.csv`
- `smard_load_Amprion_hourly.csv`
- `smard_load_TenneT_hourly.csv`
- `smard_load_TransnetBW_hourly.csv`
- `50Hertz_hourly_load.csv`
- `Amprion_hourly_load.csv`
- `TenneT_hourly_load.csv`
- `TransnetBW_hourly_load.csv`

### Required timestamp field

One of:
- `TimestampUTC`
- `timestamp_utc`
- `utc_timestamp`
- `timestamp`
- `date_time`
- `Datetime`

### Required load field in each zone file

50Hertz file:
- `Load_50Hertz_MW` or `50Hertz` or `DE_50hertz_load_actual_entsoe_power_statistics`

Amprion file:
- `Load_Amprion_MW` or `Amprion` or `DE_amprion_load_actual_entsoe_power_statistics`

TenneT file:
- `Load_TenneT_MW` or `TenneT` or `DE_tennet_load_actual_entsoe_power_statistics`

TransnetBW file:
- `Load_TransnetBW_MW` or `TransnetBW` or `DE_transnetbw_load_actual_entsoe_power_statistics`

## 5. Optional OPSD helper drop

Folder:
- `tools/germany_pcm_case_related/raw_sources/opsd_time_series/`

Accepted filenames:
- `germany_tso_hourly_load.csv`
- `opsd_tso_hourly.csv`
- `tso_hourly_load.csv`

Use this only as a convenience or fallback layer, not as the preferred 2025 zonal helper source.

## 6. What to run after the first drop

From repo root:

```powershell
python tools/germany_pcm_case_related/build_germany_network_backbone.py
python tools/germany_pcm_case_related/build_germany_bus_zone_map.py
python tools/germany_pcm_case_related/build_germany_generator_fleet.py
python tools/germany_pcm_case_related/build_germany_chronology.py
```

## 7. First-pass success criteria

The first drop is good enough if:
- the four scripts above run without errors
- `references/germany_network_buses_clean.csv` is populated
- `references/germany_bus_zone_map.csv` has very few or zero unresolved buses
- `references/germany_generator_fleet_clean.csv` is populated
- `references/germany_hourly_chronology_clean.csv` has the intended hourly study window
- `references/germany_zone_hourly_load_reference.csv` contains zonal load shares if the helper files were provided

## 8. Best practical advice

For the first pass, don’t over-optimize the raw files.
Use the accepted filenames above, keep the original source columns when possible, and only filter to Germany if that is easy and well documented.
