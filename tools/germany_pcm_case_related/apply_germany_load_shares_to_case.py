from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import pandas as pd


def _load_datacase(case_dir: Path) -> str:
    settings_path = case_dir / 'Settings' / 'HOPE_model_settings.yml'
    for raw_line in settings_path.read_text(encoding='utf-8').splitlines():
        line = raw_line.split('#', 1)[0].strip()
        if line.startswith('DataCase:'):
            return line.split(':', 1)[1].strip().strip("'\"")
    raise ValueError(f'Could not find DataCase in {settings_path}')


def apply_load_shares(case_dir: Path, shares_file: Path) -> Path:
    data_case = _load_datacase(case_dir)
    busdata_path = case_dir / data_case / 'busdata.csv'

    busdata = pd.read_csv(busdata_path)
    shares = pd.read_csv(shares_file, usecols=['Bus_id', 'Zone_id', 'Load_share'])

    busdata['Bus_id'] = busdata['Bus_id'].astype(str)
    busdata['Zone_id'] = busdata['Zone_id'].astype(str)
    shares['Bus_id'] = shares['Bus_id'].astype(str)
    shares['Zone_id'] = shares['Zone_id'].astype(str)
    shares['Load_share'] = pd.to_numeric(shares['Load_share'], errors='coerce').fillna(0.0).clip(lower=0.0)
    shares = shares.groupby(['Bus_id', 'Zone_id'], as_index=False)['Load_share'].sum()

    zone_peak = busdata.groupby('Zone_id', as_index=False)['Demand (MW)'].sum().rename(columns={'Demand (MW)': 'ZonePeakMW'})
    old_share = pd.to_numeric(busdata['Load_share'], errors='coerce').fillna(0.0).clip(lower=0.0)
    old_share_sum = old_share.groupby(busdata['Zone_id']).transform('sum')
    busdata['Load_share_old'] = np.where(old_share_sum > 0, old_share / old_share_sum, 0.0)

    updated = busdata.merge(shares.rename(columns={'Load_share': 'Load_share_new'}), on=['Bus_id', 'Zone_id'], how='left')
    updated['Load_share_new'] = pd.to_numeric(updated['Load_share_new'], errors='coerce').fillna(0.0).clip(lower=0.0)
    new_zone_total = updated.groupby('Zone_id')['Load_share_new'].transform('sum')
    updated['Load_share'] = np.where(
        new_zone_total > 0,
        updated['Load_share_new'] / new_zone_total,
        updated['Load_share_old'],
    )
    updated = updated.merge(zone_peak, on='Zone_id', how='left')
    updated['Demand (MW)'] = updated['ZonePeakMW'] * updated['Load_share']
    updated = updated.drop(columns=['Load_share_old', 'Load_share_new', 'ZonePeakMW'])
    updated.to_csv(busdata_path, index=False)
    return busdata_path


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description='Apply frozen Germany nodal load shares to a HOPE case busdata.csv.')
    parser.add_argument('--case-dir', type=Path, required=True, help='Case directory containing Settings/HOPE_model_settings.yml')
    parser.add_argument('--shares-file', type=Path, required=True, help='Frozen Germany spatial load-share CSV')
    return parser.parse_args()


if __name__ == '__main__':
    args = _parse_args()
    out_path = apply_load_shares(args.case_dir, args.shares_file)
    print(f'Updated {out_path}')
