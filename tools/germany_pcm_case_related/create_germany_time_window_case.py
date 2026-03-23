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


def _slice_window(frame: pd.DataFrame, start_ts: pd.Timestamp, end_ts: pd.Timestamp) -> pd.DataFrame:
    if 'Month' not in frame.columns or 'Day' not in frame.columns or 'Hours' not in frame.columns:
        raise ValueError('Expected Month, Day, and Hours columns in time-series input.')
    month = pd.to_numeric(frame['Month'], errors='coerce')
    day = pd.to_numeric(frame['Day'], errors='coerce')
    hour = pd.to_numeric(frame['Hours'], errors='coerce')
    timestamps = pd.to_datetime(
        {
            'year': start_ts.year,
            'month': month,
            'day': day,
            'hour': hour - 1,
        },
        errors='coerce',
    )
    window = frame.loc[(timestamps >= start_ts) & (timestamps < end_ts)].copy()
    if window.empty:
        raise ValueError(f'No rows found between {start_ts} and {end_ts}.')
    return window.reset_index(drop=True)


def create_time_window_case(
    source_case: Path,
    target_case: Path,
    data_folder: str,
    start_ts: pd.Timestamp,
    end_ts: pd.Timestamp,
) -> None:
    if not source_case.exists():
        raise FileNotFoundError(f'Source case not found: {source_case}')
    if target_case.exists():
        shutil.rmtree(target_case)

    shutil.copytree(source_case, target_case)

    data_dirs = [path for path in target_case.iterdir() if path.is_dir() and path.name.startswith('Data_')]
    if len(data_dirs) != 1:
        raise ValueError(f'Expected exactly one Data_ folder in {target_case}, found {len(data_dirs)}')

    original_data_dir = data_dirs[0]
    target_data_dir = target_case / data_folder
    if original_data_dir != target_data_dir:
        shutil.copytree(original_data_dir, target_data_dir)

    for filename in TIME_SERIES_FILES:
        path = target_data_dir / filename
        if not path.exists():
            continue
        frame = pd.read_csv(path)
        _slice_window(frame, start_ts, end_ts).to_csv(path, index=False)

    settings_path = target_case / 'Settings' / 'HOPE_model_settings.yml'
    settings_text = settings_path.read_text(encoding='utf-8')
    settings_text = settings_text.replace(original_data_dir.name + '/', data_folder + '/')
    settings_path.write_text(settings_text, encoding='utf-8')

    readme_text = (
        f'# {target_case.name}\n\n'
        f'Time-window derivative of `{source_case.name}` for faster nodal debugging.\n\n'
        f'- Source case: `{source_case.as_posix()}`\n'
        f'- Study window: `{start_ts}` to `{end_ts}` (exclusive end)\n'
        '- Static network, generator, storage, and policy tables are copied unchanged.\n'
        '- Hourly load and renewable time-series files are sliced to the selected time window only.\n'
        '- Nodal network resolution is unchanged from the source case.\n'
    )
    (target_case / 'README.md').write_text(readme_text, encoding='utf-8')


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description='Create a time-window derivative of an existing Germany PCM case.')
    parser.add_argument('--source-case', required=True, help='Source case directory, relative to repo root.')
    parser.add_argument('--target-case', required=True, help='Target case directory, relative to repo root.')
    parser.add_argument('--data-folder', required=True, help='Data folder name to use inside the target case.')
    parser.add_argument('--start', required=True, help='Inclusive start timestamp, e.g. 2025-01-01 00:00:00')
    parser.add_argument('--end', required=True, help='Exclusive end timestamp, e.g. 2025-01-08 00:00:00')
    return parser


def main() -> None:
    parser = _build_parser()
    args = parser.parse_args()
    create_time_window_case(
        source_case=REPO_ROOT / args.source_case,
        target_case=REPO_ROOT / args.target_case,
        data_folder=args.data_folder,
        start_ts=pd.Timestamp(args.start),
        end_ts=pd.Timestamp(args.end),
    )
    print(f'Created time-window case at {REPO_ROOT / args.target_case}')


if __name__ == '__main__':
    main()
