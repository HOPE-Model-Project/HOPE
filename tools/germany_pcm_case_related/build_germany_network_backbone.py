from __future__ import annotations

from pathlib import Path

import pandas as pd


TOOLS_DIR = Path(__file__).resolve().parent
RAW_DIR = TOOLS_DIR / 'raw_sources'
REF_DIR = TOOLS_DIR / 'references'

RAW_SOURCE_DIRS = (
    RAW_DIR / 'osm_europe_grid',
    RAW_DIR / 'pypsa_eur_reference',
)

BUS_CANDIDATES = ('germany_network_buses.csv', 'buses.csv')
LINE_CANDIDATES = ('germany_network_lines.csv', 'lines.csv')
TRANSFORMER_CANDIDATES = ('germany_network_transformers.csv', 'transformers.csv')
LINK_CANDIDATES = ('germany_network_links.csv', 'links.csv')

BUSES_OUT = REF_DIR / 'germany_network_buses_clean.csv'
LINES_OUT = REF_DIR / 'germany_network_lines_clean.csv'
TRANSFORMERS_OUT = REF_DIR / 'germany_network_transformers_clean.csv'
LINKS_OUT = REF_DIR / 'germany_network_links_clean.csv'


def _first_existing(candidates: tuple[str, ...]) -> Path | None:
    for folder in RAW_SOURCE_DIRS:
        for name in candidates:
            path = folder / name
            if path.exists():
                return path
    return None


def _read_required(candidates: tuple[str, ...], label: str) -> pd.DataFrame:
    path = _first_existing(candidates)
    if path is None:
        names = ', '.join(candidates)
        raise FileNotFoundError(f'Could not find {label}. Expected one of: {names}')
    df = pd.read_csv(path, quotechar="'")
    if df.empty:
        raise ValueError(f'{label} input is empty: {path}')
    df.attrs['source_path'] = str(path)
    return df


def _read_optional(candidates: tuple[str, ...]) -> pd.DataFrame:
    path = _first_existing(candidates)
    if path is None:
        return pd.DataFrame()
    df = pd.read_csv(path, quotechar="'")
    df.attrs['source_path'] = str(path)
    return df


def _normalize_buses(df: pd.DataFrame) -> pd.DataFrame:
    work = df.copy()
    rename = {}
    if 'bus_id' in work.columns and 'RawBusKey' not in work.columns:
        rename['bus_id'] = 'RawBusKey'
    if 'name' in work.columns and 'SourceBusName' not in work.columns:
        rename['name'] = 'SourceBusName'
    if 'x' in work.columns and 'Longitude' not in work.columns:
        rename['x'] = 'Longitude'
    if 'y' in work.columns and 'Latitude' not in work.columns:
        rename['y'] = 'Latitude'
    if 'v_nom' in work.columns and 'V_nom_kV' not in work.columns:
        rename['v_nom'] = 'V_nom_kV'
    if 'voltage' in work.columns and 'V_nom_kV' not in work.columns:
        rename['voltage'] = 'V_nom_kV'
    if 'carrier' in work.columns and 'Carrier' not in work.columns:
        rename['carrier'] = 'Carrier'
    if 'country' in work.columns and 'Country' not in work.columns:
        rename['country'] = 'Country'
    work = work.rename(columns=rename)

    if 'RawBusKey' not in work.columns:
        raise ValueError('Bus table must contain bus_id or RawBusKey.')
    if 'SourceBusName' not in work.columns:
        work['SourceBusName'] = work['RawBusKey']

    work['Country'] = work.get('Country', '').astype(str)
    work = work.loc[work['Country'].str.upper().eq('DE')].copy()
    if work.empty:
        raise ValueError('No Germany buses remained after filtering Country == DE.')

    work['Bus_id'] = [f'B{i + 1}' for i in range(len(work))]
    work['Longitude'] = pd.to_numeric(work.get('Longitude'), errors='coerce')
    work['Latitude'] = pd.to_numeric(work.get('Latitude'), errors='coerce')
    work['V_nom_kV'] = pd.to_numeric(work.get('V_nom_kV'), errors='coerce')
    work['Carrier'] = work.get('Carrier', '')
    work['SourceDataset'] = Path(df.attrs.get('source_path', '')).name
    work['Notes'] = ''
    return work[['Bus_id', 'RawBusKey', 'SourceBusName', 'Longitude', 'Latitude', 'V_nom_kV', 'Country', 'Carrier', 'SourceDataset', 'Notes']].copy()


def _bus_lookup(clean_buses: pd.DataFrame) -> dict[str, str]:
    return dict(zip(clean_buses['RawBusKey'].astype(str), clean_buses['Bus_id'].astype(str)))


def _normalize_lines(df: pd.DataFrame, bus_lookup: dict[str, str]) -> pd.DataFrame:
    work = df.copy()
    rename = {}
    if 'line_id' in work.columns and 'Line_id' not in work.columns:
        rename['line_id'] = 'Line_id'
    if 'name' in work.columns and 'Line_id' not in work.columns:
        rename['name'] = 'Line_id'
    if 'length' in work.columns and 'Length_km' not in work.columns:
        rename['length'] = 'Length_km'
    if 'voltage' in work.columns and 'Voltage_kV' not in work.columns:
        rename['voltage'] = 'Voltage_kV'
    if 'v_nom' in work.columns and 'Voltage_kV' not in work.columns:
        rename['v_nom'] = 'Voltage_kV'
    if 's_nom' in work.columns and 'Capacity_MVA' not in work.columns:
        rename['s_nom'] = 'Capacity_MVA'
    if 'circuits' in work.columns and 'NumParallel' not in work.columns:
        rename['circuits'] = 'NumParallel'
    if 'num_parallel' in work.columns and 'NumParallel' not in work.columns:
        rename['num_parallel'] = 'NumParallel'
    if 'carrier' in work.columns and 'Carrier' not in work.columns:
        rename['carrier'] = 'Carrier'
    work = work.rename(columns=rename)

    if 'Line_id' not in work.columns:
        work['Line_id'] = [f'L{i + 1}' for i in range(len(work))]
    work['FromRawBus'] = work.get('bus0', work.get('FromBus', '')).astype(str)
    work['ToRawBus'] = work.get('bus1', work.get('ToBus', '')).astype(str)
    work = work.loc[work['FromRawBus'].isin(bus_lookup) & work['ToRawBus'].isin(bus_lookup)].copy()
    work['FromBus'] = work['FromRawBus'].map(bus_lookup)
    work['ToBus'] = work['ToRawBus'].map(bus_lookup)
    for col in ('Length_km', 'Voltage_kV', 'Capacity_MVA', 'r', 'x', 'NumParallel'):
        if col not in work.columns:
            work[col] = pd.NA
    work['R'] = pd.to_numeric(work.get('r', work.get('R')), errors='coerce')
    work['X'] = pd.to_numeric(work.get('x', work.get('X')), errors='coerce')
    work['Length_km'] = pd.to_numeric(work['Length_km'], errors='coerce')
    work['Voltage_kV'] = pd.to_numeric(work['Voltage_kV'], errors='coerce')
    work['Capacity_MVA'] = pd.to_numeric(work['Capacity_MVA'], errors='coerce')
    work['NumParallel'] = pd.to_numeric(work['NumParallel'], errors='coerce')
    work['Carrier'] = work.get('Carrier', '')
    work['SourceDataset'] = Path(df.attrs.get('source_path', '')).name
    work['Notes'] = ''
    return work[['Line_id', 'FromBus', 'ToBus', 'Length_km', 'Voltage_kV', 'Capacity_MVA', 'R', 'X', 'NumParallel', 'Carrier', 'SourceDataset', 'Notes']].copy()


def _normalize_transformers(df: pd.DataFrame, bus_lookup: dict[str, str]) -> pd.DataFrame:
    work = df.copy()
    rename = {}
    if 'transformer_id' in work.columns and 'Transformer_id' not in work.columns:
        rename['transformer_id'] = 'Transformer_id'
    if 'name' in work.columns and 'Transformer_id' not in work.columns:
        rename['name'] = 'Transformer_id'
    if 's_nom' in work.columns and 'S_nom_MVA' not in work.columns:
        rename['s_nom'] = 'S_nom_MVA'
    work = work.rename(columns=rename)

    if 'Transformer_id' not in work.columns:
        work['Transformer_id'] = [f'T{i + 1}' for i in range(len(work))]
    work['RawBus0'] = work.get('bus0', work.get('Bus0', '')).astype(str)
    work['RawBus1'] = work.get('bus1', work.get('Bus1', '')).astype(str)
    work = work.loc[work['RawBus0'].isin(bus_lookup) & work['RawBus1'].isin(bus_lookup)].copy()
    work['Bus0'] = work['RawBus0'].map(bus_lookup)
    work['Bus1'] = work['RawBus1'].map(bus_lookup)
    work['VoltageBus0_kV'] = pd.to_numeric(work.get('voltage_bus0', work.get('VoltageBus0_kV')), errors='coerce')
    work['VoltageBus1_kV'] = pd.to_numeric(work.get('voltage_bus1', work.get('VoltageBus1_kV')), errors='coerce')
    work['S_nom_MVA'] = pd.to_numeric(work.get('S_nom_MVA'), errors='coerce')
    work['X'] = pd.to_numeric(work.get('x', work.get('X')), errors='coerce')
    work['SourceDataset'] = Path(df.attrs.get('source_path', '')).name
    work['Notes'] = ''
    return work[['Transformer_id', 'Bus0', 'Bus1', 'VoltageBus0_kV', 'VoltageBus1_kV', 'S_nom_MVA', 'X', 'SourceDataset', 'Notes']].copy()


def _normalize_links(df: pd.DataFrame, bus_lookup: dict[str, str]) -> pd.DataFrame:
    if df.empty:
        return pd.DataFrame(columns=['Link_id', 'Bus0', 'Bus1', 'P_nom_MW', 'Length_km', 'Carrier', 'SourceDataset', 'Notes'])
    work = df.copy()
    rename = {}
    if 'link_id' in work.columns and 'Link_id' not in work.columns:
        rename['link_id'] = 'Link_id'
    if 'name' in work.columns and 'Link_id' not in work.columns:
        rename['name'] = 'Link_id'
    if 'p_nom' in work.columns and 'P_nom_MW' not in work.columns:
        rename['p_nom'] = 'P_nom_MW'
    if 'length' in work.columns and 'Length_km' not in work.columns:
        rename['length'] = 'Length_km'
    if 'carrier' in work.columns and 'Carrier' not in work.columns:
        rename['carrier'] = 'Carrier'
    work = work.rename(columns=rename)

    if 'Link_id' not in work.columns:
        work['Link_id'] = [f'K{i + 1}' for i in range(len(work))]
    work['RawBus0'] = work.get('bus0', work.get('Bus0', '')).astype(str)
    work['RawBus1'] = work.get('bus1', work.get('Bus1', '')).astype(str)
    work = work.loc[work['RawBus0'].isin(bus_lookup) & work['RawBus1'].isin(bus_lookup)].copy()
    work['Bus0'] = work['RawBus0'].map(bus_lookup)
    work['Bus1'] = work['RawBus1'].map(bus_lookup)
    work['P_nom_MW'] = pd.to_numeric(work.get('P_nom_MW'), errors='coerce')
    work['Length_km'] = pd.to_numeric(work.get('Length_km'), errors='coerce')
    work['Carrier'] = work.get('Carrier', '')
    work['SourceDataset'] = Path(df.attrs.get('source_path', '')).name
    work['Notes'] = ''
    return work[['Link_id', 'Bus0', 'Bus1', 'P_nom_MW', 'Length_km', 'Carrier', 'SourceDataset', 'Notes']].copy()


def build_germany_network_backbone() -> None:
    raw_buses = _read_required(BUS_CANDIDATES, 'bus table')
    raw_lines = _read_required(LINE_CANDIDATES, 'line table')
    raw_transformers = _read_required(TRANSFORMER_CANDIDATES, 'transformer table')
    raw_links = _read_optional(LINK_CANDIDATES)

    buses = _normalize_buses(raw_buses)
    bus_lookup = _bus_lookup(buses)
    lines = _normalize_lines(raw_lines, bus_lookup)
    transformers = _normalize_transformers(raw_transformers, bus_lookup)
    links = _normalize_links(raw_links, bus_lookup)

    buses.to_csv(BUSES_OUT, index=False)
    lines.to_csv(LINES_OUT, index=False)
    transformers.to_csv(TRANSFORMERS_OUT, index=False)
    links.to_csv(LINKS_OUT, index=False)


if __name__ == '__main__':
    build_germany_network_backbone()
    print(f'Wrote {BUSES_OUT}')
    print(f'Wrote {LINES_OUT}')
    print(f'Wrote {TRANSFORMERS_OUT}')
    print(f'Wrote {LINKS_OUT}')
