from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd


TOOLS_DIR = Path(__file__).resolve().parent
REPO_ROOT = TOOLS_DIR.parents[1]
NODAL_CASE_DIR = REPO_ROOT / 'ModelCases' / 'GERMANY_PCM_nodal_case'
ZONAL_CASE_DIR = REPO_ROOT / 'ModelCases' / 'GERMANY_PCM_zonal4_case'
NODAL_DATA_DIR = NODAL_CASE_DIR / 'Data_GERMANY_PCM_nodal'
ZONAL_DATA_DIR = ZONAL_CASE_DIR / 'Data_GERMANY_PCM_zonal4'
REF_DIR = TOOLS_DIR / 'references'


TIME_COLUMNS = ['Time Period', 'Month', 'Day', 'Hours']


def _weighted_average(values: pd.Series, weights: pd.Series, default: float = 0.0) -> float:
    numeric_values = pd.to_numeric(values, errors='coerce')
    numeric_weights = pd.to_numeric(weights, errors='coerce').fillna(0.0)
    mask = numeric_values.notna() & (numeric_weights > 0.0)
    if not mask.any():
        fallback = numeric_values.dropna()
        return float(fallback.iloc[0]) if not fallback.empty else default
    return float(np.average(numeric_values.loc[mask], weights=numeric_weights.loc[mask]))


def _required_paths() -> list[Path]:
    return [
        NODAL_DATA_DIR / 'zonedata.csv',
        NODAL_DATA_DIR / 'linedata.csv',
        NODAL_DATA_DIR / 'gendata.csv',
        NODAL_DATA_DIR / 'storagedata.csv',
        NODAL_DATA_DIR / 'load_timeseries_regional.csv',
        NODAL_DATA_DIR / 'wind_timeseries_regional.csv',
        NODAL_DATA_DIR / 'solar_timeseries_regional.csv',
        NODAL_DATA_DIR / 'carbonpolicies.csv',
        NODAL_DATA_DIR / 'rpspolicies.csv',
        NODAL_DATA_DIR / 'single_parameter.csv',
        REF_DIR / 'germany_bus_zone_map.csv',
    ]


def _load_zone_centroids() -> pd.DataFrame:
    bus_zone_map = pd.read_csv(REF_DIR / 'germany_bus_zone_map.csv')
    bus_zone_map['Latitude'] = pd.to_numeric(bus_zone_map['Latitude'], errors='coerce')
    bus_zone_map['Longitude'] = pd.to_numeric(bus_zone_map['Longitude'], errors='coerce')
    centroids = (
        bus_zone_map.dropna(subset=['Zone_id', 'Latitude', 'Longitude'])
        .groupby('Zone_id', as_index=False)[['Latitude', 'Longitude']]
        .mean()
        .rename(columns={'Zone_id': 'Zone'})
    )
    return centroids


def _build_interzonal_lines(nodal_lines: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    line_df = nodal_lines.copy()
    line_df['Capacity (MW)'] = pd.to_numeric(line_df['Capacity (MW)'], errors='coerce').fillna(0.0)
    line_df['Loss (%)'] = pd.to_numeric(line_df['Loss (%)'], errors='coerce').fillna(0.0)
    line_df = line_df.loc[line_df['From_zone'] != line_df['To_zone']].copy()
    if line_df.empty:
        raise ValueError('No interzonal seams were found in the Germany nodal linedata.')

    line_df['Zone_a'] = line_df[['From_zone', 'To_zone']].min(axis=1)
    line_df['Zone_b'] = line_df[['From_zone', 'To_zone']].max(axis=1)
    line_df['PairKey'] = line_df['Zone_a'] + '||' + line_df['Zone_b']

    interface_rows: list[dict[str, object]] = []
    summary_rows: list[dict[str, object]] = []

    for pair_key, group in line_df.groupby('PairKey', sort=True):
        ordered_group = group.sort_values('Capacity (MW)', ascending=False)
        representative = ordered_group.iloc[0]
        zone_a = representative['Zone_a']
        zone_b = representative['Zone_b']
        total_capacity = float(group['Capacity (MW)'].sum())
        interface_rows.append(
            {
                'From_zone': zone_a,
                'To_zone': zone_b,
                'from_bus': representative['from_bus'],
                'to_bus': representative['to_bus'],
                'KV': 380,
                'Capacity (MW)': round(total_capacity, 3),
                'Loss (%)': round(float(group['Loss (%)'].mean()), 4),
            }
        )
        summary_rows.append(
            {
                'Interface_id': f'{zone_a}__{zone_b}',
                'From_zone': zone_a,
                'To_zone': zone_b,
                'CrossBorderLineCount': int(len(group)),
                'CutsetCapacity_MW': round(total_capacity, 3),
                'RepresentativeFromBus': representative['from_bus'],
                'RepresentativeToBus': representative['to_bus'],
            }
        )

    interfaces = pd.DataFrame(interface_rows).sort_values(['From_zone', 'To_zone']).reset_index(drop=True)
    summary = pd.DataFrame(summary_rows).sort_values(['From_zone', 'To_zone']).reset_index(drop=True)
    return interfaces, summary


def _aggregate_gendata(nodal_gens: pd.DataFrame, zone_centroids: pd.DataFrame) -> pd.DataFrame:
    gen_df = nodal_gens.copy()
    gen_df['Pmax (MW)'] = pd.to_numeric(gen_df['Pmax (MW)'], errors='coerce').fillna(0.0)
    gen_df['Pmin (MW)'] = pd.to_numeric(gen_df['Pmin (MW)'], errors='coerce').fillna(0.0)
    for column in [
        'Latitude', 'Longitude', 'Cost ($/MWh)', 'EF', 'CC', 'AF', 'FOR', 'RM_SPIN',
        'RU', 'RD', 'Min_down_time', 'Min_up_time', 'Start_up_cost ($/MW)',
        'RM_REG_UP', 'RM_REG_DN', 'RM_NSPIN'
    ]:
        if column in gen_df.columns:
            gen_df[column] = pd.to_numeric(gen_df[column], errors='coerce')

    aggregated_rows: list[dict[str, object]] = []
    centroid_lookup = zone_centroids.set_index('Zone') if not zone_centroids.empty else pd.DataFrame()

    for (zone, gen_type), group in gen_df.groupby(['Zone', 'Type'], dropna=False, sort=True):
        weight = group['Pmax (MW)'].replace(0.0, np.nan)
        centroid = centroid_lookup.loc[zone] if zone in centroid_lookup.index else None
        aggregated_rows.append(
            {
                'PlantCode': f'DE_{zone}_{gen_type}',
                'PlantName': f'{zone} {gen_type}',
                'SourceTechnology': gen_type,
                'State': 'DE',
                'LoadZone': zone,
                'Latitude': float(centroid['Latitude']) if centroid is not None else np.nan,
                'Longitude': float(centroid['Longitude']) if centroid is not None else np.nan,
                'Pmax (MW)': round(float(group['Pmax (MW)'].sum()), 6),
                'Pmin (MW)': round(float(group['Pmin (MW)'].sum()), 6),
                'Zone': zone,
                'Bus_id': zone,
                'Type': gen_type,
                'Flag_thermal': int(group['Flag_thermal'].max()),
                'Flag_RET': int(group['Flag_RET'].max()),
                'Flag_VRE': int(group['Flag_VRE'].max()),
                'Flag_mustrun': int(group['Flag_mustrun'].max()),
                'Cost ($/MWh)': round(_weighted_average(group['Cost ($/MWh)'], weight, 0.0), 6),
                'EF': round(_weighted_average(group['EF'], weight, 0.0), 6),
                'CC': round(_weighted_average(group['CC'], weight, 1.0), 6),
                'AF': round(_weighted_average(group['AF'], weight, 1.0), 6),
                'FOR': round(_weighted_average(group['FOR'], weight, 0.0), 6),
                'RM_SPIN': round(_weighted_average(group['RM_SPIN'], weight, 0.0), 6),
                'RU': round(_weighted_average(group['RU'], weight, 1.0), 6),
                'RD': round(_weighted_average(group['RD'], weight, 1.0), 6),
                'Flag_UC': int(group['Flag_UC'].max()),
                'Min_down_time': round(_weighted_average(group['Min_down_time'], weight, 0.0), 6),
                'Min_up_time': round(_weighted_average(group['Min_up_time'], weight, 0.0), 6),
                'Start_up_cost ($/MW)': round(_weighted_average(group['Start_up_cost ($/MW)'], weight, 0.0), 6),
                'RM_REG_UP': round(_weighted_average(group['RM_REG_UP'], weight, 0.0), 6),
                'RM_REG_DN': round(_weighted_average(group['RM_REG_DN'], weight, 0.0), 6),
                'RM_NSPIN': round(_weighted_average(group['RM_NSPIN'], weight, 0.0), 6),
                'SourceCount': int(len(group)),
                'AggregationLevel': 'zone_type',
                'Notes': 'Aggregated from Germany nodal first-pass generator table',
            }
        )

    ordered_columns = list(nodal_gens.columns)
    if 'SourceCount' not in ordered_columns:
        ordered_columns.extend(['SourceCount', 'AggregationLevel', 'Notes'])
    zonal_gens = pd.DataFrame(aggregated_rows)
    return zonal_gens[ordered_columns]


def _aggregate_storagedata(nodal_storage: pd.DataFrame) -> pd.DataFrame:
    storage_df = nodal_storage.copy()
    for column in [
        'Capacity (MWh)', 'Max Power (MW)', 'Charging efficiency', 'Discharging efficiency',
        'Cost ($/MWh)', 'EF', 'CC', 'Charging Rate', 'Discharging Rate'
    ]:
        storage_df[column] = pd.to_numeric(storage_df[column], errors='coerce').fillna(0.0)

    aggregated_rows: list[dict[str, object]] = []
    for (zone, storage_type), group in storage_df.groupby(['Zone', 'Type'], dropna=False, sort=True):
        weight = group['Max Power (MW)'].replace(0.0, np.nan)
        aggregated_rows.append(
            {
                'Zone': zone,
                'Bus_id': zone,
                'Type': storage_type,
                'Capacity (MWh)': round(float(group['Capacity (MWh)'].sum()), 6),
                'Max Power (MW)': round(float(group['Max Power (MW)'].sum()), 6),
                'Charging efficiency': round(_weighted_average(group['Charging efficiency'], weight, 1.0), 6),
                'Discharging efficiency': round(_weighted_average(group['Discharging efficiency'], weight, 1.0), 6),
                'Cost ($/MWh)': round(_weighted_average(group['Cost ($/MWh)'], weight, 0.0), 6),
                'EF': round(_weighted_average(group['EF'], weight, 0.0), 6),
                'CC': round(_weighted_average(group['CC'], weight, 1.0), 6),
                'Charging Rate': round(_weighted_average(group['Charging Rate'], weight, 1.0), 6),
                'Discharging Rate': round(_weighted_average(group['Discharging Rate'], weight, 1.0), 6),
            }
        )

    zonal_storage = pd.DataFrame(aggregated_rows)
    return zonal_storage[nodal_storage.columns]


def _write_outputs(
    zonedata: pd.DataFrame,
    linedata: pd.DataFrame,
    gendata: pd.DataFrame,
    storagedata: pd.DataFrame,
    load_regional: pd.DataFrame,
    wind_regional: pd.DataFrame,
    solar_regional: pd.DataFrame,
    carbonpolicies: pd.DataFrame,
    rpspolicies: pd.DataFrame,
    single_parameter: pd.DataFrame,
    cutset_summary: pd.DataFrame,
) -> None:
    ZONAL_DATA_DIR.mkdir(parents=True, exist_ok=True)

    zonedata.to_csv(ZONAL_DATA_DIR / 'zonedata.csv', index=False)
    linedata.to_csv(ZONAL_DATA_DIR / 'linedata.csv', index=False)
    gendata.to_csv(ZONAL_DATA_DIR / 'gendata.csv', index=False)
    storagedata.to_csv(ZONAL_DATA_DIR / 'storagedata.csv', index=False)
    load_regional.to_csv(ZONAL_DATA_DIR / 'load_timeseries_regional.csv', index=False)
    wind_regional.to_csv(ZONAL_DATA_DIR / 'wind_timeseries_regional.csv', index=False)
    solar_regional.to_csv(ZONAL_DATA_DIR / 'solar_timeseries_regional.csv', index=False)
    carbonpolicies.to_csv(ZONAL_DATA_DIR / 'carbonpolicies.csv', index=False)
    rpspolicies.to_csv(ZONAL_DATA_DIR / 'rpspolicies.csv', index=False)
    single_parameter.to_csv(ZONAL_DATA_DIR / 'single_parameter.csv', index=False)
    cutset_summary.to_csv(REF_DIR / 'germany_interzonal_cutset_summary.csv', index=False)

    readme_text = (
        '# Germany PCM zonal 4-zone case\n\n'
        'This Germany zonal case is derived mechanically from the current Germany nodal master case.\n\n'
        '- Zones: 50Hertz, Amprion, TenneT, TransnetBW\n'
        '- Transmission seams: aggregated from nodal cross-zone cutsets\n'
        '- Generator and storage fleets: aggregated from nodal assets by zone and technology\n'
        '- Regional load chronology: copied directly from the nodal master regional chronology\n'
        '- Regional load chronology therefore inherits the promoted base BTM-PV Germany baseline assumptions\n'
        '- Renewable profiles: copied directly from the nodal master regional wind and solar profiles\n'
        '- This zonal case is intended as the consistency benchmark against the current nodal Germany baseline\n'
    )
    (ZONAL_DATA_DIR / 'README.md').write_text(readme_text, encoding='utf-8')


def build_germany_zonal_case() -> None:
    missing = [path for path in _required_paths() if not path.exists()]
    if missing:
        missing_text = ', '.join(str(path.name) for path in missing)
        raise FileNotFoundError(f'Required Germany nodal or reference inputs are missing: {missing_text}')

    zonedata = pd.read_csv(NODAL_DATA_DIR / 'zonedata.csv')
    nodal_lines = pd.read_csv(NODAL_DATA_DIR / 'linedata.csv')
    nodal_gens = pd.read_csv(NODAL_DATA_DIR / 'gendata.csv')
    nodal_storage = pd.read_csv(NODAL_DATA_DIR / 'storagedata.csv')
    load_regional = pd.read_csv(NODAL_DATA_DIR / 'load_timeseries_regional.csv')
    wind_regional = pd.read_csv(NODAL_DATA_DIR / 'wind_timeseries_regional.csv')
    solar_regional = pd.read_csv(NODAL_DATA_DIR / 'solar_timeseries_regional.csv')
    carbonpolicies = pd.read_csv(NODAL_DATA_DIR / 'carbonpolicies.csv')
    rpspolicies = pd.read_csv(NODAL_DATA_DIR / 'rpspolicies.csv')
    single_parameter = pd.read_csv(NODAL_DATA_DIR / 'single_parameter.csv')

    zone_centroids = _load_zone_centroids()
    linedata, cutset_summary = _build_interzonal_lines(nodal_lines)
    gendata = _aggregate_gendata(nodal_gens, zone_centroids)
    storagedata = _aggregate_storagedata(nodal_storage)

    _write_outputs(
        zonedata=zonedata,
        linedata=linedata,
        gendata=gendata,
        storagedata=storagedata,
        load_regional=load_regional,
        wind_regional=wind_regional,
        solar_regional=solar_regional,
        carbonpolicies=carbonpolicies,
        rpspolicies=rpspolicies,
        single_parameter=single_parameter,
        cutset_summary=cutset_summary,
    )

    print(f'Wrote first-pass Germany zonal PCM inputs to {ZONAL_DATA_DIR}')


if __name__ == '__main__':
    build_germany_zonal_case()
