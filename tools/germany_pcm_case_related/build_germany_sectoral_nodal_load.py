from __future__ import annotations

import argparse
import csv
from pathlib import Path
from datetime import date

import numpy as np
import pandas as pd

from build_germany_spatial_load_shares import (
    _discover_local_egon_sources,
    _load_egon_bus_coordinates_from_csv,
    _map_egon_points_to_hope_buses,
    _prepare_hope_buses,
)


csv.field_size_limit(2**31 - 1)

CASE_ROOT = Path(__file__).resolve().parents[2] / 'ModelCases'
DEFAULT_SHARE_FILE = Path(__file__).resolve().parent / 'references' / 'germany_spatial_load_shares.csv'
STRUCTURAL_WEIGHT_SOURCE_CASE = CASE_ROOT / 'GERMANY_PCM_nodal_case'
SHORT_HORIZON_THRESHOLD_HOURS = 24 * 30
SECTOR_BASE_WEIGHT = 0.85
INDUSTRY_BASE_WEIGHT = 0.15
SECTOR_CALIBRATION_BLEND = 0.40
CASE_YEAR = 2025
BTM_PV_ANNUAL_SELF_CONSUMPTION_MWH = 12.28e6
BTM_PV_HH_WEIGHT = 0.75
BTM_PV_CTS_WEIGHT = 0.25
BTM_PV_ZONE_SIGNAL_BLEND = 0.55
BTM_PV_ZONE_SIGNAL_MIN = 0.60
BTM_PV_ZONE_SIGNAL_MAX = 1.55
BTM_PV_MAX_NONINDUSTRY_OFFSET_FRACTION = 0.45
BTM_PV_DIAGNOSTICS_FILENAME = 'load_btmpv_diagnostics.csv'
INDUSTRY_WEEKDAY_PEAK = 1.08
INDUSTRY_WEEKDAY_SHOULDER = 0.96
INDUSTRY_WEEKDAY_NIGHT = 0.84
INDUSTRY_SATURDAY_DAY = 0.72
INDUSTRY_SATURDAY_NIGHT = 0.60
INDUSTRY_SUNDAY = 0.52
INDUSTRY_HOLIDAY = 0.46
INDUSTRY_SUMMER_FACTOR = 0.95
INDUSTRY_YEAR_END_FACTOR = 0.82
INDUSTRY_PROXY_FALLBACK_BLEND = 0.12
INDUSTRY_PROXY_SHARPEN_ALPHA = 1.35
INDUSTRY_PROXY_SIGNAL_EXPONENT = 0.35
INDUSTRY_VOLTAGE_EXPONENT = 0.20
INDUSTRY_BUS_PEAK_EXPONENT = 0.15
INDUSTRY_MIN_VOLTAGE_FACTOR = 0.82
INDUSTRY_MAX_VOLTAGE_FACTOR = 1.20
INDUSTRY_MIN_BUS_PEAK_FACTOR = 0.88
INDUSTRY_MAX_BUS_PEAK_FACTOR = 1.16
SECTOR_WEIGHT_RIDGE = 0.05


def _load_datacase(case_dir: Path) -> str:
    settings_path = case_dir / 'Settings' / 'HOPE_model_settings.yml'
    for raw_line in settings_path.read_text(encoding='utf-8').splitlines():
        line = raw_line.split('#', 1)[0].strip()
        if line.startswith('DataCase:'):
            return line.split(':', 1)[1].strip().strip("'\"")
    raise ValueError(f'Could not find DataCase in {settings_path}')


def _case_data_dir(case_dir: Path) -> Path:
    return case_dir / _load_datacase(case_dir)


def _case_hour_indices(load_regional: pd.DataFrame) -> np.ndarray:
    timestamps = pd.to_datetime(
        {
            'year': np.full(len(load_regional), CASE_YEAR),
            'month': pd.to_numeric(load_regional['Month'], errors='coerce').astype(int),
            'day': pd.to_numeric(load_regional['Day'], errors='coerce').astype(int),
        }
    ) + pd.to_timedelta(pd.to_numeric(load_regional['Hours'], errors='coerce').astype(int) - 1, unit='h')
    return (((timestamps.dt.dayofyear - 1) * 24) + timestamps.dt.hour).to_numpy(dtype=int)


def _synthetic_industry_activity(load_regional: pd.DataFrame) -> np.ndarray:
    timestamps = pd.to_datetime(
        {
            'year': np.full(len(load_regional), CASE_YEAR),
            'month': pd.to_numeric(load_regional['Month'], errors='coerce').astype(int),
            'day': pd.to_numeric(load_regional['Day'], errors='coerce').astype(int),
        }
    ) + pd.to_timedelta(pd.to_numeric(load_regional['Hours'], errors='coerce').astype(int) - 1, unit='h')

    activity = np.full(len(timestamps), INDUSTRY_WEEKDAY_NIGHT, dtype=float)
    weekday = timestamps.dt.weekday.to_numpy(dtype=int)
    hour = timestamps.dt.hour.to_numpy(dtype=int)
    day_values = timestamps.dt.date.to_numpy()

    holidays = _germany_public_holidays()
    holiday_mask = np.array([value in holidays for value in day_values], dtype=bool)

    weekday_mask = weekday <= 4
    saturday_mask = weekday == 5
    sunday_mask = weekday == 6
    day_mask = (hour >= 7) & (hour <= 18)
    shoulder_mask = ((hour >= 5) & (hour < 7)) | ((hour > 18) & (hour <= 21))

    activity[weekday_mask & shoulder_mask] = INDUSTRY_WEEKDAY_SHOULDER
    activity[weekday_mask & day_mask] = INDUSTRY_WEEKDAY_PEAK
    activity[saturday_mask] = INDUSTRY_SATURDAY_NIGHT
    activity[saturday_mask & day_mask] = INDUSTRY_SATURDAY_DAY
    activity[sunday_mask] = INDUSTRY_SUNDAY
    activity[holiday_mask] = INDUSTRY_HOLIDAY

    # German industrial demand tends to soften during the August holiday window
    # and in the Christmas / year-end shutdown period.
    month = timestamps.dt.month.to_numpy(dtype=int)
    day = timestamps.dt.day.to_numpy(dtype=int)
    activity[month == 8] *= INDUSTRY_SUMMER_FACTOR
    activity[(month == 12) & (day >= 24)] *= INDUSTRY_YEAR_END_FACTOR
    activity[(month == 1) & (day == 1)] *= INDUSTRY_YEAR_END_FACTOR

    mean_activity = float(activity.mean())
    return activity / mean_activity if mean_activity > 0 else np.ones(len(activity), dtype=float)


def _germany_public_holidays() -> set[date]:
    return {
        date(CASE_YEAR, 1, 1),
        date(CASE_YEAR, 4, 18),
        date(CASE_YEAR, 4, 21),
        date(CASE_YEAR, 5, 1),
        date(CASE_YEAR, 5, 29),
        date(CASE_YEAR, 6, 9),
        date(CASE_YEAR, 10, 3),
        date(CASE_YEAR, 12, 25),
        date(CASE_YEAR, 12, 26),
    }


def _refined_industry_static_share(
    bus_ids: list[str],
    sector_static: pd.DataFrame,
    static_share: dict[str, float],
    bus_peak: dict[str, float],
    bus_voltage: dict[str, float],
) -> np.ndarray:
    industry_static = np.array(
        [float(sector_static.at[bus_id, 'industry']) if bus_id in sector_static.index else 0.0 for bus_id in bus_ids],
        dtype=float,
    )
    fallback_static = np.array([float(static_share[bus_id]) for bus_id in bus_ids], dtype=float)
    fallback_sum = float(fallback_static.sum())
    if fallback_sum <= 0:
        fallback_static = np.full(len(bus_ids), 1.0 / max(len(bus_ids), 1), dtype=float)
    else:
        fallback_static = fallback_static / fallback_sum

    if float(industry_static.sum()) <= 0:
        return fallback_static
    industry_static = industry_static / float(industry_static.sum())

    voltage = np.array([float(bus_voltage.get(bus_id, np.nan)) for bus_id in bus_ids], dtype=float)
    voltage_base = np.where(np.isfinite(voltage) & (voltage > 0), voltage / 220.0, 1.0)
    voltage_factor = np.clip(
        np.power(voltage_base, INDUSTRY_VOLTAGE_EXPONENT),
        INDUSTRY_MIN_VOLTAGE_FACTOR,
        INDUSTRY_MAX_VOLTAGE_FACTOR,
    )

    bus_peak_values = np.array([float(bus_peak.get(bus_id, np.nan)) for bus_id in bus_ids], dtype=float)
    valid_peak = np.isfinite(bus_peak_values) & (bus_peak_values > 0)
    zone_peak_reference = float(np.nanmedian(bus_peak_values[valid_peak])) if np.any(valid_peak) else np.nan
    if np.isfinite(zone_peak_reference) and zone_peak_reference > 0:
        peak_base = np.where(valid_peak, bus_peak_values / zone_peak_reference, 1.0)
        bus_peak_factor = np.clip(
            np.power(peak_base, INDUSTRY_BUS_PEAK_EXPONENT),
            INDUSTRY_MIN_BUS_PEAK_FACTOR,
            INDUSTRY_MAX_BUS_PEAK_FACTOR,
        )
    else:
        bus_peak_factor = np.ones(len(bus_ids), dtype=float)

    signal_ratio = np.divide(
        industry_static,
        np.maximum(fallback_static, 1e-12),
        out=np.ones(len(bus_ids), dtype=float),
        where=fallback_static > 0,
    )
    signal_factor = np.power(np.clip(signal_ratio, 0.5, 4.0), INDUSTRY_PROXY_SIGNAL_EXPONENT)

    blended_signal = industry_static + (INDUSTRY_PROXY_FALLBACK_BLEND * fallback_static)
    refined = np.power(np.maximum(blended_signal, 1e-12), INDUSTRY_PROXY_SHARPEN_ALPHA)
    refined = refined * voltage_factor * bus_peak_factor * signal_factor

    refined_sum = float(refined.sum())
    if refined_sum <= 0:
        return fallback_static
    return refined / refined_sum


def _project_to_simplex(weights: np.ndarray) -> np.ndarray:
    values = np.asarray(weights, dtype=float).reshape(-1)
    if values.size == 0:
        return values
    if np.all(values <= 0):
        return np.full(values.size, 1.0 / values.size, dtype=float)
    sorted_vals = np.sort(values)[::-1]
    cssv = np.cumsum(sorted_vals)
    rho_candidates = sorted_vals * np.arange(1, values.size + 1) > (cssv - 1.0)
    rho = int(np.nonzero(rho_candidates)[0][-1])
    theta = float((cssv[rho] - 1.0) / (rho + 1))
    projected = np.maximum(values - theta, 0.0)
    total = float(projected.sum())
    if total <= 0:
        return np.full(values.size, 1.0 / values.size, dtype=float)
    return projected / total


def _estimate_zone_sector_weights(
    zone_total: np.ndarray,
    hh_activity: np.ndarray,
    cts_activity: np.ndarray,
    industry_activity: np.ndarray,
    fallback: np.ndarray,
) -> np.ndarray:
    target = np.asarray(zone_total, dtype=float).reshape(-1)
    if target.size == 0 or not np.any(np.isfinite(target)):
        return fallback
    mean_target = float(np.nanmean(target))
    if mean_target <= 0:
        return fallback

    normalized_target = np.nan_to_num(target / mean_target, nan=0.0)
    design = np.column_stack(
        [
            np.nan_to_num(hh_activity, nan=0.0),
            np.nan_to_num(cts_activity, nan=0.0),
            np.nan_to_num(industry_activity, nan=0.0),
        ]
    )
    if not np.any(design):
        return fallback

    # Ridge gently anchors the fit near the prior so noisy short windows do not
    # push the sector mix to extreme values.
    ridge = np.sqrt(SECTOR_WEIGHT_RIDGE) * np.eye(design.shape[1], dtype=float)
    augmented_design = np.vstack([design, ridge])
    augmented_target = np.concatenate([normalized_target, np.sqrt(SECTOR_WEIGHT_RIDGE) * fallback])

    try:
        fitted, *_ = np.linalg.lstsq(augmented_design, augmented_target, rcond=None)
    except np.linalg.LinAlgError:
        return fallback
    fitted = _project_to_simplex(fitted)
    blended = ((1.0 - SECTOR_CALIBRATION_BLEND) * fallback) + (SECTOR_CALIBRATION_BLEND * fitted)
    return _project_to_simplex(blended)


def _load_structural_zone_weights(case_dir: Path) -> pd.DataFrame | None:
    if case_dir.resolve() == STRUCTURAL_WEIGHT_SOURCE_CASE.resolve():
        return None
    diagnostics_path = STRUCTURAL_WEIGHT_SOURCE_CASE / 'Data_GERMANY_PCM_nodal' / 'load_sector_weight_diagnostics.csv'
    if not diagnostics_path.exists():
        return None
    diagnostics = pd.read_csv(diagnostics_path)
    required = {'Zone_id', 'households_weight', 'cts_weight', 'industry_weight'}
    if not required.issubset(diagnostics.columns):
        return None
    diagnostics['Zone_id'] = diagnostics['Zone_id'].astype(str)
    return diagnostics[['Zone_id', 'households_weight', 'cts_weight', 'industry_weight']].copy()


def _load_structural_btmpv_diagnostics(case_dir: Path) -> pd.DataFrame | None:
    if case_dir.resolve() == STRUCTURAL_WEIGHT_SOURCE_CASE.resolve():
        return None
    diagnostics_path = STRUCTURAL_WEIGHT_SOURCE_CASE / 'Data_GERMANY_PCM_nodal' / BTM_PV_DIAGNOSTICS_FILENAME
    if not diagnostics_path.exists():
        return None
    diagnostics = pd.read_csv(diagnostics_path)
    required = {'Zone_id', 'btm_pv_multiplier_mw'}
    if not required.issubset(diagnostics.columns):
        return None
    diagnostics['Zone_id'] = diagnostics['Zone_id'].astype(str)
    return diagnostics.copy()


def _build_assignment_table(case_bus_ids: list[str]) -> pd.DataFrame:
    bus_path, demand_paths = _discover_local_egon_sources()
    if bus_path is None or not demand_paths:
        raise FileNotFoundError('Missing local eGon bus or demand files under raw_sources/egon_data.')
    hope_buses = _prepare_hope_buses()
    hope_buses = hope_buses.loc[hope_buses['Bus_id'].astype(str).isin(case_bus_ids)].copy()
    egon_buses = _load_egon_bus_coordinates_from_csv(bus_path).rename(columns={'bus_id': 'egon_bus_id'})
    points = egon_buses.copy()
    points['Scenario'] = 'mapping'
    points['raw_weight'] = 1.0
    mapped = _map_egon_points_to_hope_buses(points, hope_buses, entity_col='egon_bus_id', scenario_col='Scenario')
    return mapped[['egon_bus_id', 'Bus_id', 'Zone_id', 'AssignmentWeight']].copy()


def _parse_hour_slice(raw: str, hour_indices: np.ndarray) -> np.ndarray:
    text = str(raw).strip()
    if text.startswith('[') and text.endswith(']'):
        text = text[1:-1]
    values = np.fromstring(text, sep=',', dtype=float)
    if values.size == 0:
        return np.zeros(len(hour_indices), dtype=float)
    return np.nan_to_num(values[hour_indices], nan=0.0)


def _load_sector_hourly_matrix(
    demand_path: Path,
    assignment_table: pd.DataFrame,
    case_bus_ids: list[str],
    hour_indices: np.ndarray,
) -> np.ndarray:
    bus_col_idx = {bus_id: idx for idx, bus_id in enumerate(case_bus_ids)}
    assignment_by_egon = {
        bus_id: group[['Bus_id', 'AssignmentWeight']].to_records(index=False)
        for bus_id, group in assignment_table.groupby('egon_bus_id', sort=False)
    }
    scenario_matrices: dict[str, np.ndarray] = {}

    with demand_path.open('r', encoding='utf-8', newline='') as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            egon_bus_id = str(row.get('bus_id', '')).strip()
            if not egon_bus_id or egon_bus_id not in assignment_by_egon:
                continue
            scenario = str(row.get('scn_name', 'unknown')).strip() or 'unknown'
            profile = _parse_hour_slice(row.get('p_set', ''), hour_indices)
            if not np.any(profile):
                continue
            matrix = scenario_matrices.setdefault(
                scenario,
                np.zeros((len(hour_indices), len(case_bus_ids)), dtype=float),
            )
            for bus_id, weight in assignment_by_egon[egon_bus_id]:
                matrix[:, bus_col_idx[str(bus_id)]] += profile * float(weight)

    if not scenario_matrices:
        return np.zeros((len(hour_indices), len(case_bus_ids)), dtype=float)
    return np.mean(np.stack(list(scenario_matrices.values()), axis=0), axis=0)


def _load_zone_solar_shape(data_dir: Path, zones: list[str]) -> dict[str, np.ndarray]:
    solar_regional = pd.read_csv(data_dir / 'solar_timeseries_regional.csv')
    zone_profiles: dict[str, np.ndarray] = {}
    for zone in zones:
        if zone in solar_regional.columns:
            zone_profiles[zone] = pd.to_numeric(solar_regional[zone], errors='coerce').fillna(0.0).to_numpy(dtype=float)
        else:
            zone_profiles[zone] = np.zeros(len(solar_regional), dtype=float)
    return zone_profiles


def _compute_zone_btm_pv_signal(data_dir: Path, zones: list[str], annual_zone_load_mwh: dict[str, float], zone_peak: dict[str, float]) -> dict[str, float]:
    gendata_path = data_dir / 'gendata.csv'
    if not gendata_path.exists():
        load_total = sum(annual_zone_load_mwh.values())
        return {
            zone: (annual_zone_load_mwh[zone] / load_total) if load_total > 0 else 1.0 / max(len(zones), 1)
            for zone in zones
        }

    gendata = pd.read_csv(gendata_path)
    solar = gendata.loc[gendata['Type'].astype(str).str.contains('Solar', case=False, na=False)].copy()
    solar_by_zone = solar.groupby('Zone')['Pmax (MW)'].sum().to_dict()
    load_total = sum(annual_zone_load_mwh.values())
    if load_total <= 0:
        return {zone: 1.0 / max(len(zones), 1) for zone in zones}

    load_share = {zone: annual_zone_load_mwh[zone] / load_total for zone in zones}
    solar_ratio = {
        zone: float(solar_by_zone.get(zone, 0.0)) / max(float(zone_peak.get(zone, 1.0)), 1.0)
        for zone in zones
    }
    weighted_mean_ratio = sum(load_share[zone] * solar_ratio[zone] for zone in zones)
    if weighted_mean_ratio <= 0:
        return load_share

    signal = {}
    for zone in zones:
        relative = solar_ratio[zone] / weighted_mean_ratio
        relative = float(np.clip(relative, BTM_PV_ZONE_SIGNAL_MIN, BTM_PV_ZONE_SIGNAL_MAX))
        signal[zone] = load_share[zone] * ((1.0 - BTM_PV_ZONE_SIGNAL_BLEND) + (BTM_PV_ZONE_SIGNAL_BLEND * relative))

    signal_total = sum(signal.values())
    if signal_total <= 0:
        return load_share
    return {zone: signal[zone] / signal_total for zone in zones}


def _solve_capped_btm_multiplier(solar_profile: np.ndarray, cap_profile: np.ndarray, target_energy: float) -> tuple[float, float]:
    solar = np.maximum(np.asarray(solar_profile, dtype=float), 0.0)
    caps = np.maximum(np.asarray(cap_profile, dtype=float), 0.0)
    if solar.size == 0 or caps.size == 0 or target_energy <= 0:
        return 0.0, 0.0

    max_realizable = float(caps.sum())
    if max_realizable <= 0 or not np.any(solar > 0):
        return 0.0, 0.0

    target = min(float(target_energy), max_realizable)
    low = 0.0
    high = 1.0
    while float(np.minimum(high * solar, caps).sum()) < target:
        high *= 2.0
        if high > 1e7:
            break

    for _ in range(60):
        mid = 0.5 * (low + high)
        realized = float(np.minimum(mid * solar, caps).sum())
        if realized >= target:
            high = mid
        else:
            low = mid

    multiplier = high
    realized = float(np.minimum(multiplier * solar, caps).sum())
    return multiplier, realized


def _cap_and_redistribute(target_total: float, weights: np.ndarray, caps: np.ndarray) -> np.ndarray:
    weights = np.maximum(np.asarray(weights, dtype=float), 0.0)
    caps = np.maximum(np.asarray(caps, dtype=float), 0.0)
    if target_total <= 0 or caps.size == 0 or float(caps.sum()) <= 0:
        return np.zeros_like(caps)

    remaining = min(float(target_total), float(caps.sum()))
    allocation = np.zeros_like(caps)
    active = caps > 1e-12
    if not np.any(active):
        return allocation

    active_weights = weights.copy()
    if float(active_weights[active].sum()) <= 0:
        active_weights[active] = 1.0

    for _ in range(len(caps) + 2):
        if remaining <= 1e-9 or not np.any(active):
            break
        scaled = active_weights * active.astype(float)
        scaled_sum = float(scaled.sum())
        if scaled_sum <= 0:
            scaled = active.astype(float)
            scaled_sum = float(scaled.sum())
        trial = remaining * scaled / scaled_sum
        headroom = np.maximum(caps - allocation, 0.0)
        increment = np.minimum(trial, headroom)
        allocation += increment
        remaining = min(float(target_total), float(caps.sum())) - float(allocation.sum())
        newly_saturated = headroom - increment <= 1e-9
        active = active & (~newly_saturated)
    return allocation


def build_sectoral_nodal_load(case_dir: Path, share_file: Path, btmpv_scale: float = 1.0) -> Path:
    data_dir = _case_data_dir(case_dir)
    busdata = pd.read_csv(data_dir / 'busdata.csv')
    zonedata = pd.read_csv(data_dir / 'zonedata.csv')
    load_regional = pd.read_csv(data_dir / 'load_timeseries_regional.csv')
    shares = pd.read_csv(share_file)

    case_bus_ids = busdata['Bus_id'].astype(str).tolist()
    assignment_table = _build_assignment_table(case_bus_ids)
    hour_indices = _case_hour_indices(load_regional)

    bus_path, demand_paths = _discover_local_egon_sources()
    assert bus_path is not None
    sector_matrices: dict[str, np.ndarray] = {}
    for demand_path in demand_paths:
        sector_name = demand_path.stem
        sector_matrices[sector_name] = _load_sector_hourly_matrix(demand_path, assignment_table, case_bus_ids, hour_indices)

    bus_zone = busdata.set_index('Bus_id')['Zone_id'].astype(str).to_dict()
    zone_peak = zonedata.set_index('Zone_id')['Demand (MW)'].astype(float).to_dict()
    bus_peak = busdata.set_index('Bus_id')['Demand (MW)'].astype(float).replace(0.0, np.nan).to_dict()
    static_share = busdata.set_index('Bus_id')['Load_share'].astype(float).to_dict()
    voltage_lookup = (
        _prepare_hope_buses()
        .loc[lambda df: df['Bus_id'].astype(str).isin(case_bus_ids), ['Bus_id', 'V_nom_kV']]
        .assign(Bus_id=lambda df: df['Bus_id'].astype(str))
        .set_index('Bus_id')['V_nom_kV']
        .astype(float)
        .to_dict()
    )

    share_cols = {
        'egon_etrago_electricity_households': 'egon_etrago_electricity_households',
        'egon_etrago_electricity_cts': 'egon_etrago_electricity_cts',
        'industry': 'industry',
    }
    for col in share_cols.values():
        if col not in shares.columns:
            shares[col] = 0.0
    sector_static = shares[['Bus_id', 'Zone_id', *share_cols.values()]].copy()
    sector_static['Bus_id'] = sector_static['Bus_id'].astype(str)
    sector_static['Zone_id'] = sector_static['Zone_id'].astype(str)
    sector_static = sector_static.groupby(['Bus_id', 'Zone_id'], as_index=False)[list(share_cols.values())].sum()
    sector_static = sector_static.set_index('Bus_id')

    zone_bus_ids: dict[str, list[str]] = {}
    for bus_id, zone_id in bus_zone.items():
        zone_bus_ids.setdefault(str(zone_id), []).append(str(bus_id))

    zone_order = zonedata['Zone_id'].astype(str).tolist()
    time_cols = ['Time Period', 'Month', 'Day', 'Hours']
    nodal_out = load_regional[time_cols].copy()
    zone_totals = {
        zone: pd.to_numeric(load_regional[zone], errors='coerce').fillna(0.0).to_numpy(dtype=float) * float(zone_peak[zone])
        for zone in zone_order
    }
    zone_solar_shape = _load_zone_solar_shape(data_dir, zone_order)
    annual_zone_load_mwh = {zone: float(zone_totals[zone].sum()) for zone in zone_order}
    btmpv_structural = _load_structural_btmpv_diagnostics(case_dir)
    btmpv_structural_lookup = (
        btmpv_structural.set_index('Zone_id').to_dict(orient='index')
        if btmpv_structural is not None and not btmpv_structural.empty
        else {}
    )
    local_btmpv_signal = _compute_zone_btm_pv_signal(data_dir, zone_order, annual_zone_load_mwh, zone_peak)
    local_btmpv_target = {
        zone: btmpv_scale * BTM_PV_ANNUAL_SELF_CONSUMPTION_MWH * float(local_btmpv_signal[zone])
        for zone in zone_order
    }

    hh_matrix = sector_matrices.get('egon_etrago_electricity_households', np.zeros((len(load_regional), len(case_bus_ids)), dtype=float))
    cts_matrix = sector_matrices.get('egon_etrago_electricity_cts', np.zeros((len(load_regional), len(case_bus_ids)), dtype=float))
    industry_matrix = sector_matrices.get('egon_etrago_electricity_industry', np.zeros((len(load_regional), len(case_bus_ids)), dtype=float))
    synthetic_industry_activity = _synthetic_industry_activity(load_regional)

    bus_idx = {bus_id: idx for idx, bus_id in enumerate(case_bus_ids)}
    hourly_load = np.zeros((len(load_regional), len(case_bus_ids)), dtype=float)
    sector_weight_rows: list[dict[str, float | str]] = []
    btmpv_rows: list[dict[str, float | str]] = []
    use_structural_weights = len(load_regional) < SHORT_HORIZON_THRESHOLD_HOURS
    structural_zone_weights = _load_structural_zone_weights(case_dir) if use_structural_weights else None
    structural_lookup = (
        structural_zone_weights.set_index('Zone_id').to_dict(orient='index')
        if structural_zone_weights is not None and not structural_zone_weights.empty
        else {}
    )

    for zone, bus_ids in zone_bus_ids.items():
        zone_indices = np.array([bus_idx[bus_id] for bus_id in bus_ids], dtype=int)
        hh_zone = hh_matrix[:, zone_indices]
        cts_zone = cts_matrix[:, zone_indices]
        industry_zone = industry_matrix[:, zone_indices]
        hh_total = hh_zone.sum(axis=1)
        cts_total = cts_zone.sum(axis=1)
        industry_total = industry_zone.sum(axis=1)

        fallback_static = np.array([static_share[bus_id] for bus_id in bus_ids], dtype=float)
        fallback_static = fallback_static / fallback_static.sum()
        industry_static = _refined_industry_static_share(
            bus_ids,
            sector_static,
            static_share,
            bus_peak,
            voltage_lookup,
        )

        if float(industry_total.mean()) > 0:
            industry_activity = industry_total / float(industry_total.mean())
        else:
            industry_activity = synthetic_industry_activity

        hh_mean = float(hh_total.mean())
        cts_mean = float(cts_total.mean())
        hh_activity = hh_total / hh_mean if hh_mean > 0 else np.zeros(len(load_regional), dtype=float)
        cts_activity = cts_total / cts_mean if cts_mean > 0 else np.zeros(len(load_regional), dtype=float)
        dynamic_mean = hh_mean + cts_mean
        if dynamic_mean > 0:
            fallback_weights = np.array(
                [
                    SECTOR_BASE_WEIGHT * hh_mean / dynamic_mean,
                    SECTOR_BASE_WEIGHT * cts_mean / dynamic_mean,
                    INDUSTRY_BASE_WEIGHT,
                ],
                dtype=float,
            )
        else:
            fallback_weights = np.array(
                [0.5 * SECTOR_BASE_WEIGHT, 0.5 * SECTOR_BASE_WEIGHT, INDUSTRY_BASE_WEIGHT],
                dtype=float,
            )
        fallback_weights = _project_to_simplex(fallback_weights)
        if zone in structural_lookup:
            zone_weights = _project_to_simplex(
                np.array(
                    [
                        float(structural_lookup[zone]['households_weight']),
                        float(structural_lookup[zone]['cts_weight']),
                        float(structural_lookup[zone]['industry_weight']),
                    ],
                    dtype=float,
                )
            )
            weight_source = 'structural_full_year_reference'
        else:
            zone_weights = _estimate_zone_sector_weights(
                zone_totals[zone],
                hh_activity,
                cts_activity,
                industry_activity,
                fallback_weights,
            )
            weight_source = 'case_local_fit'
        hh_base, cts_base, industry_base = zone_weights.tolist()

        hh_scaled_series = hh_base * hh_activity if hh_mean > 0 else np.zeros(len(load_regional), dtype=float)
        cts_scaled_series = cts_base * cts_activity if cts_mean > 0 else np.zeros(len(load_regional), dtype=float)
        industry_scaled_series = industry_base * industry_activity
        total_scaled_series = hh_scaled_series + cts_scaled_series + industry_scaled_series
        hh_weight_series = np.divide(
            hh_scaled_series,
            np.maximum(total_scaled_series, 1e-12),
            out=np.zeros(len(load_regional), dtype=float),
            where=total_scaled_series > 0,
        )
        cts_weight_series = np.divide(
            cts_scaled_series,
            np.maximum(total_scaled_series, 1e-12),
            out=np.zeros(len(load_regional), dtype=float),
            where=total_scaled_series > 0,
        )
        nonindustry_fraction = hh_weight_series + cts_weight_series
        zone_btmpv_cap = BTM_PV_MAX_NONINDUSTRY_OFFSET_FRACTION * zone_totals[zone] * nonindustry_fraction
        solar_profile = zone_solar_shape.get(zone, np.zeros(len(load_regional), dtype=float))
        if zone in btmpv_structural_lookup:
            btmpv_multiplier = btmpv_scale * float(btmpv_structural_lookup[zone]['btm_pv_multiplier_mw'])
            btmpv_source = 'structural_full_year_reference'
            target_btmpv = btmpv_scale * float(btmpv_structural_lookup[zone].get('target_annual_mwh', np.nan))
        else:
            btmpv_multiplier, _ = _solve_capped_btm_multiplier(solar_profile, zone_btmpv_cap, local_btmpv_target[zone])
            btmpv_source = 'case_local_fit'
            target_btmpv = local_btmpv_target[zone]
        zone_btmpv_offset = np.minimum(np.maximum(btmpv_multiplier, 0.0) * np.maximum(solar_profile, 0.0), zone_btmpv_cap)
        realized_btmpv = float(zone_btmpv_offset.sum())

        sector_weight_rows.append(
            {
                'Zone_id': zone,
                'weight_source': weight_source,
                'households_weight': hh_base,
                'cts_weight': cts_base,
                'industry_weight': industry_base,
                'fallback_households_weight': fallback_weights[0],
                'fallback_cts_weight': fallback_weights[1],
                'fallback_industry_weight': fallback_weights[2],
                'hh_mean_mw_proxy': hh_mean,
                'cts_mean_mw_proxy': cts_mean,
                'industry_mean_mw_proxy': float(industry_total.mean()),
            }
        )
        btmpv_rows.append(
            {
                'Zone_id': zone,
                'btm_pv_source': btmpv_source,
                'btm_pv_multiplier_mw': btmpv_multiplier,
                'target_annual_mwh': target_btmpv,
                'realized_window_mwh': realized_btmpv,
                'gross_load_window_mwh': float(zone_totals[zone].sum()),
                'realized_share_pct': 100.0 * realized_btmpv / max(float(zone_totals[zone].sum()), 1.0),
                'solar_signal_share': float(local_btmpv_signal.get(zone, 0.0)),
                'btm_pv_scale': float(btmpv_scale),
            }
        )

        for h in range(len(load_regional)):
            hh_scaled = hh_scaled_series[h]
            cts_scaled = cts_scaled_series[h]
            industry_scaled = industry_scaled_series[h]
            total_scaled = total_scaled_series[h]

            if total_scaled > 0:
                hh_weight = hh_weight_series[h]
                cts_weight = cts_weight_series[h]
                industry_weight = industry_scaled / total_scaled
                hh_share = hh_zone[h] / hh_total[h] if hh_total[h] > 0 else np.zeros(len(bus_ids), dtype=float)
                cts_share = cts_zone[h] / cts_total[h] if cts_total[h] > 0 else np.zeros(len(bus_ids), dtype=float)
                if industry_total[h] > 0:
                    industry_share = industry_zone[h] / industry_total[h]
                else:
                    industry_share = industry_static
                combined_share = hh_weight * hh_share + cts_weight * cts_share + industry_weight * industry_share
            else:
                hh_weight = 0.0
                cts_weight = 0.0
                combined_share = fallback_static
                hh_share = np.zeros(len(bus_ids), dtype=float)
                cts_share = np.zeros(len(bus_ids), dtype=float)
            share_sum = float(combined_share.sum())
            if share_sum <= 0:
                combined_share = fallback_static
                share_sum = float(combined_share.sum())
            combined_share = combined_share / share_sum
            bus_load = zone_totals[zone][h] * combined_share

            zone_btmpv_hour = float(zone_btmpv_offset[h])
            if zone_btmpv_hour > 0 and (hh_weight > 0 or cts_weight > 0):
                btmpv_distribution = (BTM_PV_HH_WEIGHT * hh_weight * hh_share) + (BTM_PV_CTS_WEIGHT * cts_weight * cts_share)
                dist_sum = float(btmpv_distribution.sum())
                if dist_sum <= 0:
                    btmpv_distribution = hh_weight * hh_share + cts_weight * cts_share
                    dist_sum = float(btmpv_distribution.sum())
                if dist_sum > 0:
                    btmpv_distribution = btmpv_distribution / dist_sum
                    bus_nonindustry_cap = BTM_PV_MAX_NONINDUSTRY_OFFSET_FRACTION * zone_totals[zone][h] * (
                        (hh_weight * hh_share) + (cts_weight * cts_share)
                    )
                    bus_btmpv = _cap_and_redistribute(zone_btmpv_hour, btmpv_distribution, bus_nonindustry_cap)
                    bus_load = np.maximum(bus_load - bus_btmpv, 0.0)

            hourly_load[h, zone_indices] = bus_load

    nodal_matrix = {}
    for bus_id in case_bus_ids:
        peak = float(bus_peak[bus_id]) if pd.notna(bus_peak[bus_id]) and float(bus_peak[bus_id]) > 0 else 1.0
        nodal_matrix[bus_id] = hourly_load[:, bus_idx[bus_id]] / peak
    nodal_out = pd.concat([nodal_out, pd.DataFrame(nodal_matrix)], axis=1)

    out_path = data_dir / 'load_timeseries_nodal.csv'
    nodal_out.to_csv(out_path, index=False)
    diagnostics_path = data_dir / 'load_sector_weight_diagnostics.csv'
    pd.DataFrame(sector_weight_rows).to_csv(diagnostics_path, index=False)
    btmpv_path = data_dir / BTM_PV_DIAGNOSTICS_FILENAME
    pd.DataFrame(btmpv_rows).to_csv(btmpv_path, index=False)
    return out_path


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description='Build sector-hourly Germany nodal load multipliers for a HOPE case.')
    parser.add_argument('--case-dir', type=Path, required=True, help='Case directory containing Settings/HOPE_model_settings.yml')
    parser.add_argument('--share-file', type=Path, default=DEFAULT_SHARE_FILE, help='Germany spatial load share reference CSV')
    parser.add_argument('--btm-pv-scale', type=float, default=1.0, help='Scale factor applied to calibrated BTM-PV self-consumption')
    return parser.parse_args()


if __name__ == '__main__':
    args = _parse_args()
    out_path = build_sectoral_nodal_load(args.case_dir, args.share_file, btmpv_scale=args.btm_pv_scale)
    print(f'Updated {out_path}')
