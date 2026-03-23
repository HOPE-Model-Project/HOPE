from __future__ import annotations

from pathlib import Path
import csv

import pandas as pd


TOOLS_DIR = Path(__file__).resolve().parent
RAW_DIR = TOOLS_DIR / 'raw_sources'
REF_DIR = TOOLS_DIR / 'references'

SMARD_DIR = RAW_DIR / 'smard_2025'
OPSD_DIR = RAW_DIR / 'opsd_time_series'

NATIONAL_LOAD_CANDIDATES = (
    SMARD_DIR / 'germany_actual_load_hourly.csv',
    SMARD_DIR / 'germany_hourly_chronology.csv',
    SMARD_DIR / 'smard_hourly_balance.csv',
    SMARD_DIR / 'germany_hourly_balance.csv',
)

NATIONAL_GENERATION_CANDIDATES = (
    SMARD_DIR / 'germany_actual_generation_hourly.csv',
    SMARD_DIR / 'germany_generation_hourly.csv',
    SMARD_DIR / 'smard_generation_hourly.csv',
)

ZONAL_CANDIDATES = (
    OPSD_DIR / 'germany_tso_hourly_load.csv',
    OPSD_DIR / 'opsd_tso_hourly.csv',
    OPSD_DIR / 'tso_hourly_load.csv',
)

SMARD_ZONE_FILE_CANDIDATES = {
    'Load_50Hertz_MW': (
        SMARD_DIR / 'load_50Hertz_hourly.csv',
        SMARD_DIR / 'smard_load_50Hertz_hourly.csv',
        SMARD_DIR / '50Hertz_hourly_load.csv',
    ),
    'Load_Amprion_MW': (
        SMARD_DIR / 'load_Amprion_hourly.csv',
        SMARD_DIR / 'smard_load_Amprion_hourly.csv',
        SMARD_DIR / 'Amprion_hourly_load.csv',
    ),
    'Load_TenneT_MW': (
        SMARD_DIR / 'load_TenneT_hourly.csv',
        SMARD_DIR / 'smard_load_TenneT_hourly.csv',
        SMARD_DIR / 'TenneT_hourly_load.csv',
    ),
    'Load_TransnetBW_MW': (
        SMARD_DIR / 'load_TransnetBW_hourly.csv',
        SMARD_DIR / 'smard_load_TransnetBW_hourly.csv',
        SMARD_DIR / 'TransnetBW_hourly_load.csv',
    ),
}

NATIONAL_OUT = REF_DIR / 'germany_hourly_chronology_clean.csv'
ZONAL_OUT = REF_DIR / 'germany_zone_hourly_load_reference.csv'
STUDY_START = pd.Timestamp('2025-01-01 00:00:00')
STUDY_END = pd.Timestamp('2026-01-01 00:00:00')

LOAD_FIELD_ALIASES = {
    'Load_MW': (
        'Load_MW',
        'load_mw',
        'load',
        'DE_load_actual_entsoe_power_statistics',
        'grid load [MWh] Calculated resolutions',
        'Grid load [MWh] Calculated resolutions',
    ),
    'NetImports_MW': (
        'NetImports_MW',
        'net_imports_mw',
        'net_imports',
        'interchange',
        'imports_minus_exports',
    ),
}

GENERATION_FIELD_ALIASES = {
    'WindOnshore_MW': (
        'WindOnshore_MW',
        'wind_onshore_mw',
        'wind_onshore',
        'Wind onshore',
        'Wind onshore [MWh] Calculated resolutions',
    ),
    'WindOffshore_MW': (
        'WindOffshore_MW',
        'wind_offshore_mw',
        'wind_offshore',
        'Wind offshore',
        'Wind offshore [MWh] Calculated resolutions',
    ),
    'SolarPV_MW': (
        'SolarPV_MW',
        'solar_pv_mw',
        'solar',
        'solar_mw',
        'Photovoltaics',
        'Photovoltaics [MWh] Calculated resolutions',
    ),
    'Hydro_MW': (
        'Hydro_MW',
        'hydro',
        'hydro_mw',
        'Hydro',
        'Hydropower [MWh] Calculated resolutions',
    ),
    'Biomass_MW': (
        'Biomass_MW',
        'biomass',
        'biomass_mw',
        'Biomass',
        'Biomass [MWh] Calculated resolutions',
    ),
    'OtherRenewables_MW': (
        'OtherRenewables_MW',
        'other_renewables_mw',
        'other_renewables',
        'renewables_other',
        'Other renewable',
        'Other renewable [MWh] Calculated resolutions',
    ),
}

ZONE_FIELD_ALIASES = {
    'Load_50Hertz_MW': ('Load_50Hertz_MW', '50Hertz', 'DE_50hertz_load_actual_entsoe_power_statistics', 'grid load [MWh] Calculated resolutions', 'Grid load [MWh] Calculated resolutions'),
    'Load_Amprion_MW': ('Load_Amprion_MW', 'Amprion', 'DE_amprion_load_actual_entsoe_power_statistics', 'grid load [MWh] Calculated resolutions', 'Grid load [MWh] Calculated resolutions'),
    'Load_TenneT_MW': ('Load_TenneT_MW', 'TenneT', 'DE_tennet_load_actual_entsoe_power_statistics', 'grid load [MWh] Calculated resolutions', 'Grid load [MWh] Calculated resolutions'),
    'Load_TransnetBW_MW': ('Load_TransnetBW_MW', 'TransnetBW', 'DE_transnetbw_load_actual_entsoe_power_statistics', 'grid load [MWh] Calculated resolutions', 'Grid load [MWh] Calculated resolutions'),
}


def _first_existing(paths: tuple[Path, ...]) -> Path | None:
    for path in paths:
        if path.exists():
            return path
    return None


def _read_csv_with_auto_sep(path: Path) -> pd.DataFrame:
    with path.open('r', encoding='utf-8-sig', newline='') as handle:
        sample = handle.read(4096)
        handle.seek(0)
        try:
            dialect = csv.Sniffer().sniff(sample, delimiters=';,	,')
            sep = dialect.delimiter
        except csv.Error:
            sep = ','
    return pd.read_csv(path, sep=sep)


def _read_required(paths: tuple[Path, ...], label: str) -> pd.DataFrame:
    path = _first_existing(paths)
    if path is None:
        names = ', '.join(p.name for p in paths)
        raise FileNotFoundError(f'Could not find {label}. Expected one of: {names}')
    df = _read_csv_with_auto_sep(path)
    if df.empty:
        raise ValueError(f'{label} is empty: {path}')
    df.attrs['source_path'] = str(path)
    return df


def _read_optional(paths: tuple[Path, ...]) -> pd.DataFrame:
    path = _first_existing(paths)
    if path is None:
        return pd.DataFrame()
    df = _read_csv_with_auto_sep(path)
    df.attrs['source_path'] = str(path)
    return df


def _timestamp_series(df: pd.DataFrame) -> pd.Series:
    for col in ('TimestampUTC', 'timestamp_utc', 'utc_timestamp', 'timestamp', 'date_time', 'Datetime', 'Start date'):
        if col in df.columns:
            series = pd.to_datetime(df[col], errors='coerce')
            if series.notna().any():
                return series
    raise ValueError('Could not find a parseable timestamp column.')


def _pick_numeric_column(df: pd.DataFrame, candidates: tuple[str, ...]) -> pd.Series:
    for col in candidates:
        if col in df.columns:
            series = df[col].astype(str).str.replace(',', '', regex=False)
            return pd.to_numeric(series, errors='coerce')
    return pd.Series([pd.NA] * len(df), index=df.index, dtype='Float64')


def _prepare_time_index(df: pd.DataFrame) -> pd.DataFrame:
    ts = _timestamp_series(df)
    out = pd.DataFrame({'TimestampUTC': ts})
    out = out.loc[out['TimestampUTC'].notna()].copy()
    out = out.loc[(out['TimestampUTC'] >= STUDY_START) & (out['TimestampUTC'] < STUDY_END)].copy()
    out = out.reset_index()
    out['_Occurrence'] = out.groupby('TimestampUTC').cumcount()
    return out


def _normalize_load(df: pd.DataFrame) -> pd.DataFrame:
    base = _prepare_time_index(df)
    out = base[['TimestampUTC', '_Occurrence']].copy()
    for field, aliases in LOAD_FIELD_ALIASES.items():
        out[field] = _pick_numeric_column(df.loc[base['index']], aliases).to_numpy()
    out['LoadSourceDataset'] = Path(df.attrs.get('source_path', '')).name
    out = out.loc[out['Load_MW'].notna()].reset_index(drop=True)
    out.insert(0, 'HourIndex', range(1, len(out) + 1))
    return out[['HourIndex', 'TimestampUTC', '_Occurrence', 'Load_MW', 'NetImports_MW', 'LoadSourceDataset']]


def _normalize_generation(df: pd.DataFrame, load_hours: pd.DataFrame) -> pd.DataFrame:
    if df.empty:
        out = load_hours[['HourIndex', 'TimestampUTC', '_Occurrence']].copy()
        for field in GENERATION_FIELD_ALIASES:
            out[field] = pd.NA
        out['GenerationSourceDataset'] = pd.NA
        return out
    base = _prepare_time_index(df)
    out = base[['TimestampUTC', '_Occurrence']].copy()
    for field, aliases in GENERATION_FIELD_ALIASES.items():
        out[field] = _pick_numeric_column(df.loc[base['index']], aliases).to_numpy()
    out['GenerationSourceDataset'] = Path(df.attrs.get('source_path', '')).name
    out = load_hours[['HourIndex', 'TimestampUTC', '_Occurrence']].merge(out, on=['TimestampUTC', '_Occurrence'], how='left')
    return out


def _merge_national(load_df: pd.DataFrame, generation_df: pd.DataFrame) -> pd.DataFrame:
    merged = load_df.merge(generation_df, on=['HourIndex', 'TimestampUTC', '_Occurrence'], how='left')
    merged['SourceDataset'] = merged['LoadSourceDataset'].fillna('')
    generation_source = merged['GenerationSourceDataset'].fillna('')
    merged.loc[generation_source != '', 'SourceDataset'] = merged.loc[generation_source != '', 'SourceDataset'] + ';' + generation_source[generation_source != '']
    merged['SourceDataset'] = merged['SourceDataset'].str.strip(';')
    merged['Notes'] = ''
    return merged[['HourIndex', 'TimestampUTC', '_Occurrence', 'Load_MW', 'WindOnshore_MW', 'WindOffshore_MW', 'SolarPV_MW', 'Hydro_MW', 'Biomass_MW', 'OtherRenewables_MW', 'NetImports_MW', 'SourceDataset', 'Notes']]


def _normalize_combined_zonal(df: pd.DataFrame, national_hours: pd.DataFrame) -> pd.DataFrame:
    if df.empty:
        return pd.DataFrame()
    base = _prepare_time_index(df)
    out = base[['TimestampUTC', '_Occurrence']].copy()
    for field, aliases in ZONE_FIELD_ALIASES.items():
        out[field] = _pick_numeric_column(df.loc[base['index']], aliases).to_numpy()
    out = national_hours[['HourIndex', 'TimestampUTC', '_Occurrence']].merge(out, on=['TimestampUTC', '_Occurrence'], how='left')
    out['SourceDataset'] = Path(df.attrs.get('source_path', '')).name
    out['Notes'] = ''
    return out


def _load_smard_zone_series() -> dict[str, tuple[pd.DataFrame, str]]:
    zone_frames: dict[str, tuple[pd.DataFrame, str]] = {}
    for field, candidates in SMARD_ZONE_FILE_CANDIDATES.items():
        path = _first_existing(candidates)
        if path is None:
            continue
        df = _read_csv_with_auto_sep(path)
        if df.empty:
            continue
        df.attrs['source_path'] = str(path)
        zone_frames[field] = (df, path.name)
    return zone_frames


def _normalize_smard_zone_file(df: pd.DataFrame, field_name: str) -> pd.DataFrame:
    base = _prepare_time_index(df)
    out = base[['TimestampUTC', '_Occurrence']].copy()
    out[field_name] = _pick_numeric_column(df.loc[base['index']], ZONE_FIELD_ALIASES[field_name]).to_numpy()
    return out[['TimestampUTC', '_Occurrence', field_name]]


def _normalize_zonal_from_smard_files(national_hours: pd.DataFrame) -> pd.DataFrame:
    zone_frames = _load_smard_zone_series()
    if not zone_frames:
        return pd.DataFrame()
    out = national_hours[['HourIndex', 'TimestampUTC', '_Occurrence']].copy()
    source_names: list[str] = []
    for field, (df, source_name) in zone_frames.items():
        source_names.append(source_name)
        zone_df = _normalize_smard_zone_file(df, field)
        out = out.merge(zone_df, on=['TimestampUTC', '_Occurrence'], how='left')
    out['SourceDataset'] = ';'.join(source_names)
    out['Notes'] = 'built_from_separate_smard_control_area_files'
    return out


def _finalize_zonal(zonal: pd.DataFrame) -> pd.DataFrame:
    if zonal.empty:
        return pd.DataFrame(columns=['HourIndex', 'TimestampUTC', 'Load_50Hertz_MW', 'Load_Amprion_MW', 'Load_TenneT_MW', 'Load_TransnetBW_MW', 'Share_50Hertz', 'Share_Amprion', 'Share_TenneT', 'Share_TransnetBW', 'SourceDataset', 'Notes'])
    for field in ZONE_FIELD_ALIASES:
        if field not in zonal.columns:
            zonal[field] = pd.NA
    total = zonal[['Load_50Hertz_MW', 'Load_Amprion_MW', 'Load_TenneT_MW', 'Load_TransnetBW_MW']].sum(axis=1, min_count=1)
    zonal['Share_50Hertz'] = zonal['Load_50Hertz_MW'] / total
    zonal['Share_Amprion'] = zonal['Load_Amprion_MW'] / total
    zonal['Share_TenneT'] = zonal['Load_TenneT_MW'] / total
    zonal['Share_TransnetBW'] = zonal['Load_TransnetBW_MW'] / total
    return zonal[['HourIndex', 'TimestampUTC', 'Load_50Hertz_MW', 'Load_Amprion_MW', 'Load_TenneT_MW', 'Load_TransnetBW_MW', 'Share_50Hertz', 'Share_Amprion', 'Share_TenneT', 'Share_TransnetBW', 'SourceDataset', 'Notes']]


def build_germany_chronology() -> tuple[pd.DataFrame, pd.DataFrame]:
    load_raw = _read_required(NATIONAL_LOAD_CANDIDATES, 'Germany national load chronology extract')
    generation_raw = _read_optional(NATIONAL_GENERATION_CANDIDATES)
    zonal_raw = _read_optional(ZONAL_CANDIDATES)

    national_load = _normalize_load(load_raw)
    national_generation = _normalize_generation(generation_raw, national_load)
    national = _merge_national(national_load, national_generation)

    zonal = _normalize_combined_zonal(zonal_raw, national)
    if zonal.empty:
        zonal = _normalize_zonal_from_smard_files(national)
    zonal = _finalize_zonal(zonal)

    national.drop(columns=['_Occurrence']).to_csv(NATIONAL_OUT, index=False)
    zonal.to_csv(ZONAL_OUT, index=False)
    return national.drop(columns=['_Occurrence']), zonal


if __name__ == '__main__':
    national, zonal = build_germany_chronology()
    print(f'Wrote {NATIONAL_OUT}')
    print(f'Wrote {ZONAL_OUT}')
    print(f'National hours: {len(national)} | Zonal helper hours: {len(zonal)}')
