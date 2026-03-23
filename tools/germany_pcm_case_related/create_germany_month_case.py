from __future__ import annotations

import argparse
import shutil
from pathlib import Path

import pandas as pd


REPO_ROOT = Path(__file__).resolve().parents[2]
TIME_SERIES_FILES = (
    'load_timeseries_regional.csv',
    'load_timeseries_nodal.csv',
    'wind_timeseries_regional.csv',
    'solar_timeseries_regional.csv',
)


def _slice_month(frame: pd.DataFrame, month: int) -> pd.DataFrame:
    if 'Month' not in frame.columns:
        raise ValueError('Expected a Month column in time-series input.')
    month_frame = frame.loc[pd.to_numeric(frame['Month'], errors='coerce') == month].copy()
    if month_frame.empty:
        raise ValueError(f'No rows found for month {month}.')
    return month_frame.reset_index(drop=True)


def _month_tag(month: int) -> str:
    return f'{month:02d}'


def create_month_case(source_case: Path, target_case: Path, data_folder: str, month: int) -> None:
    if not source_case.exists():
        raise FileNotFoundError(f'Source case not found: {source_case}')
    if target_case.exists():
        shutil.rmtree(target_case)

    shutil.copytree(source_case, target_case)

    source_data_dirs = [path for path in target_case.iterdir() if path.is_dir() and path.name.startswith('Data_')]
    if len(source_data_dirs) != 1:
        raise ValueError(f'Expected exactly one Data_ folder in {target_case}, found {len(source_data_dirs)}')

    target_data_dir = target_case / data_folder
    source_data_dir = source_data_dirs[0]
    if source_data_dir != target_data_dir:
        source_data_dir.rename(target_data_dir)

    for filename in TIME_SERIES_FILES:
        path = target_data_dir / filename
        if not path.exists():
            continue
        frame = pd.read_csv(path)
        _slice_month(frame, month).to_csv(path, index=False)

    settings_path = target_case / 'Settings' / 'HOPE_model_settings.yml'
    settings_text = settings_path.read_text(encoding='utf-8')
    source_data_name = source_data_dir.name if source_data_dir == target_data_dir else source_data_dirs[0].name
    settings_text = settings_text.replace(source_data_name + '/', data_folder + '/')
    settings_path.write_text(settings_text, encoding='utf-8')

    readme_text = (
        f'# {target_case.name}\n\n'
        f'January-style monthly derivative of `{source_case.name}` for faster nodal debugging.\n\n'
        f'- Source case: `{source_case.as_posix()}`\n'
        f'- Study month: `{month}`\n'
        '- Static network, generator, storage, and policy tables are copied unchanged.\n'
        '- Hourly load and renewable time-series files are sliced to the selected month only.\n'
    )
    (target_case / 'README.md').write_text(readme_text, encoding='utf-8')


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description='Create a monthly derivative of an existing Germany PCM case.')
    parser.add_argument('--source-case', required=True, help='Source case directory, relative to repo root.')
    parser.add_argument('--target-case', required=True, help='Target case directory, relative to repo root.')
    parser.add_argument('--data-folder', required=True, help='Data folder name to use inside the target case.')
    parser.add_argument('--month', type=int, required=True, help='Calendar month number (1-12).')
    return parser


def main() -> None:
    parser = _build_parser()
    args = parser.parse_args()
    create_month_case(
        source_case=REPO_ROOT / args.source_case,
        target_case=REPO_ROOT / args.target_case,
        data_folder=args.data_folder,
        month=args.month,
    )
    print(f'Created monthly case at {REPO_ROOT / args.target_case}')


if __name__ == '__main__':
    main()
