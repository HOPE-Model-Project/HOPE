from __future__ import annotations

from pathlib import Path
from typing import Iterable

import numpy as np
import pandas as pd


HOPE_ZONE_ORDER = ["Maine", "NNE", "ROP", "SENE"]
SUPPORTED_INTERNAL_SEAMS = {"Maine-NNE", "NNE-ROP", "NNE-SENE", "ROP-SENE"}
UNSUPPORTED_INTERNAL_SEAM_CAP_MW = 100.0
UNSUPPORTED_SEAM_REROUTE_FACTOR = 1.0


def seam_name(zone_a: str, zone_b: str) -> str:
    return "-".join(sorted((str(zone_a), str(zone_b))))


def _point_zone_assignment(
    points_df: pd.DataFrame,
    bus_geo: pd.DataFrame,
) -> np.ndarray:
    bus = bus_geo[["Zone_id", "Latitude", "Longitude"]].copy()
    bus["Latitude"] = pd.to_numeric(bus["Latitude"], errors="coerce")
    bus["Longitude"] = pd.to_numeric(bus["Longitude"], errors="coerce")
    bus = bus.loc[pd.notna(bus["Latitude"]) & pd.notna(bus["Longitude"])].copy()
    point_coords = points_df[["Latitude", "Longitude"]].to_numpy(dtype=float)
    bus_coords = bus[["Latitude", "Longitude"]].to_numpy(dtype=float)
    # Approximate mileage scaling consistent with the rest of the builder.
    dlat = (point_coords[:, None, 0] - bus_coords[None, :, 0]) * 69.0
    dlon = (point_coords[:, None, 1] - bus_coords[None, :, 1]) * 53.0
    dist_sq = dlat * dlat + dlon * dlon
    nearest_idx = np.argmin(dist_sq, axis=1)
    return bus["Zone_id"].to_numpy()[nearest_idx]


def build_osm_seam_metrics(
    bus_geo: pd.DataFrame,
    corridor_points_path: Path,
) -> pd.DataFrame:
    points = pd.read_csv(corridor_points_path)
    if points.empty:
        return pd.DataFrame(columns=["Seam", "OSMLineCount", "OSMWeight", "OSMAvgVoltageKV"])

    points["Latitude"] = pd.to_numeric(points["Latitude"], errors="coerce")
    points["Longitude"] = pd.to_numeric(points["Longitude"], errors="coerce")
    points["VoltageKV"] = pd.to_numeric(points.get("VoltageKV"), errors="coerce")
    points["AnchorWeight"] = pd.to_numeric(points.get("AnchorWeight"), errors="coerce").fillna(1.0)
    points = points.loc[pd.notna(points["Latitude"]) & pd.notna(points["Longitude"])].copy()
    if points.empty:
        return pd.DataFrame(columns=["Seam", "OSMLineCount", "OSMWeight", "OSMAvgVoltageKV"])

    points["AssignedZone"] = _point_zone_assignment(points, bus_geo)
    seam_rows: list[dict[str, float | str]] = []

    for osm_id, grp in points.groupby("OSMId", sort=False):
        ordered = grp.sort_values("PointIndex").copy()
        seq: list[str] = []
        for zone in ordered["AssignedZone"]:
            zone_str = str(zone)
            if not seq or seq[-1] != zone_str:
                seq.append(zone_str)
        seams_seen: set[str] = set()
        for zone_a, zone_b in zip(seq[:-1], seq[1:]):
            seam = seam_name(zone_a, zone_b)
            if seam not in SUPPORTED_INTERNAL_SEAMS:
                continue
            seams_seen.add(seam)
        if not seams_seen:
            continue
        weight = float(ordered["AnchorWeight"].max())
        avg_voltage = float(ordered["VoltageKV"].dropna().mean()) if ordered["VoltageKV"].notna().any() else np.nan
        for seam in seams_seen:
            seam_rows.append(
                {
                    "Seam": seam,
                    "OSMId": str(osm_id),
                    "OSMWeight": weight,
                    "OSMAvgVoltageKV": avg_voltage,
                }
            )

    if not seam_rows:
        return pd.DataFrame(columns=["Seam", "OSMLineCount", "OSMWeight", "OSMAvgVoltageKV"])

    seam_df = pd.DataFrame(seam_rows)
    return (
        seam_df.groupby("Seam", as_index=False)
        .agg(
            OSMLineCount=("OSMId", "nunique"),
            OSMWeight=("OSMWeight", "sum"),
            OSMAvgVoltageKV=("OSMAvgVoltageKV", "mean"),
        )
        .sort_values("Seam")
        .reset_index(drop=True)
    )


def build_synthetic_seam_metrics(branch_df: pd.DataFrame) -> pd.DataFrame:
    inter = branch_df.loc[branch_df["From_zone"] != branch_df["To_zone"]].copy()
    if inter.empty:
        return pd.DataFrame(columns=["Seam", "SyntheticBranchCount", "SyntheticCapacityMW", "SyntheticAvgX"])
    inter["Seam"] = inter.apply(lambda row: seam_name(row["From_zone"], row["To_zone"]), axis=1)
    inter = inter.loc[inter["Seam"].isin(SUPPORTED_INTERNAL_SEAMS)].copy()
    if inter.empty:
        return pd.DataFrame(columns=["Seam", "SyntheticBranchCount", "SyntheticCapacityMW", "SyntheticAvgX"])
    return (
        inter.groupby("Seam", as_index=False)
        .agg(
            SyntheticBranchCount=("Capacity (MW)", "size"),
            SyntheticCapacityMW=("Capacity (MW)", "sum"),
            SyntheticAvgX=("X", "mean"),
        )
        .sort_values("Seam")
        .reset_index(drop=True)
    )


def build_seam_scorecard(
    bus_geo: pd.DataFrame,
    branch_df: pd.DataFrame,
    corridor_points_path: Path,
) -> pd.DataFrame:
    osm = build_osm_seam_metrics(bus_geo, corridor_points_path)
    syn = build_synthetic_seam_metrics(branch_df)
    seams = pd.DataFrame({"Seam": sorted(SUPPORTED_INTERNAL_SEAMS)})
    score = seams.merge(osm, on="Seam", how="left").merge(syn, on="Seam", how="left")
    score["OSMLineCount"] = score["OSMLineCount"].fillna(0).astype(int)
    for col in ("OSMWeight", "OSMAvgVoltageKV", "SyntheticBranchCount", "SyntheticCapacityMW", "SyntheticAvgX"):
        score[col] = pd.to_numeric(score[col], errors="coerce")
    score["SyntheticBranchCount"] = score["SyntheticBranchCount"].fillna(0).astype(int)
    osm_weight_total = float(score["OSMWeight"].fillna(0.0).sum())
    syn_capacity_total = float(score["SyntheticCapacityMW"].fillna(0.0).sum())
    if osm_weight_total > 0.0 and syn_capacity_total > 0.0:
        score["TargetCapacityMW"] = score["OSMWeight"].fillna(0.0) / osm_weight_total * syn_capacity_total
    else:
        score["TargetCapacityMW"] = score["SyntheticCapacityMW"].fillna(0.0)
    score["CapacityGapMW"] = score["TargetCapacityMW"] - score["SyntheticCapacityMW"].fillna(0.0)
    score["RecommendedFloorMW"] = np.where(
        score["CapacityGapMW"] > 1.0,
        score["TargetCapacityMW"],
        score["SyntheticCapacityMW"].fillna(0.0),
    )
    score["RecommendedScale"] = np.where(
        score["SyntheticCapacityMW"].fillna(0.0) > 0.0,
        score["RecommendedFloorMW"] / score["SyntheticCapacityMW"].fillna(0.0),
        1.0,
    )
    return score


def apply_seam_capacity_tuning(branch_df: pd.DataFrame, seam_scorecard: pd.DataFrame) -> pd.DataFrame:
    tuned = branch_df.copy()
    if tuned.empty or seam_scorecard.empty:
        return tuned
    scale_map = {
        str(row.Seam): float(row.RecommendedScale)
        for row in seam_scorecard.itertuples(index=False)
        if float(row.RecommendedScale) > 1.0001
    }
    if not scale_map:
        return tuned
    tuned["Seam"] = tuned.apply(lambda row: seam_name(row["From_zone"], row["To_zone"]), axis=1)
    tuned["Capacity (MW)"] = tuned.apply(
        lambda row: float(row["Capacity (MW)"]) * scale_map.get(str(row["Seam"]), 1.0)
        if str(row["From_zone"]) != str(row["To_zone"])
        else float(row["Capacity (MW)"]),
        axis=1,
    )
    return tuned.drop(columns=["Seam"])


def cap_unsupported_internal_seams(
    branch_df: pd.DataFrame,
    *,
    cap_mw: float = UNSUPPORTED_INTERNAL_SEAM_CAP_MW,
) -> pd.DataFrame:
    tuned = branch_df.copy()
    if tuned.empty:
        return tuned
    tuned["Seam"] = tuned.apply(lambda row: seam_name(row["From_zone"], row["To_zone"]), axis=1)
    mask = (
        (tuned["From_zone"] != tuned["To_zone"])
        & tuned["From_zone"].isin(HOPE_ZONE_ORDER)
        & tuned["To_zone"].isin(HOPE_ZONE_ORDER)
        & ~tuned["Seam"].isin(SUPPORTED_INTERNAL_SEAMS)
    )
    if mask.any():
        tuned.loc[mask, "Capacity (MW)"] = np.minimum(
            tuned.loc[mask, "Capacity (MW)"].to_numpy(dtype=float),
            float(cap_mw),
        )
    return tuned.drop(columns=["Seam"])


def reroute_unsupported_internal_seams(
    branch_df: pd.DataFrame,
    *,
    cap_mw: float = UNSUPPORTED_INTERNAL_SEAM_CAP_MW,
    reroute_factor: float = UNSUPPORTED_SEAM_REROUTE_FACTOR,
) -> pd.DataFrame:
    tuned = branch_df.copy()
    if tuned.empty:
        return tuned
    tuned["Seam"] = tuned.apply(lambda row: seam_name(row["From_zone"], row["To_zone"]), axis=1)

    unsupported = tuned.loc[
        (tuned["From_zone"] != tuned["To_zone"])
        & tuned["From_zone"].isin(HOPE_ZONE_ORDER)
        & tuned["To_zone"].isin(HOPE_ZONE_ORDER)
        & ~tuned["Seam"].isin(SUPPORTED_INTERNAL_SEAMS),
        ["Seam", "Capacity (MW)"],
    ].copy()
    if unsupported.empty:
        return tuned.drop(columns=["Seam"])

    unsupported["RemovedMW"] = np.maximum(unsupported["Capacity (MW)"].to_numpy(dtype=float) - float(cap_mw), 0.0)
    removed_by_seam = unsupported.groupby("Seam")["RemovedMW"].sum().to_dict()

    # First cap the unsupported shortcuts.
    mask_unsupported = tuned["Seam"].isin(removed_by_seam.keys())
    tuned.loc[mask_unsupported, "Capacity (MW)"] = np.minimum(
        tuned.loc[mask_unsupported, "Capacity (MW)"].to_numpy(dtype=float),
        float(cap_mw),
    )

    seam_additions = {
        "Maine-NNE": float(removed_by_seam.get("Maine-ROP", 0.0) + removed_by_seam.get("Maine-SENE", 0.0)) * float(reroute_factor),
        "NNE-ROP": float(removed_by_seam.get("Maine-ROP", 0.0)) * float(reroute_factor),
        "NNE-SENE": float(removed_by_seam.get("Maine-SENE", 0.0)) * float(reroute_factor),
    }
    for seam, add_mw in seam_additions.items():
        if add_mw <= 0.0:
            continue
        mask = tuned["Seam"] == seam
        if not mask.any():
            continue
        current_total = float(tuned.loc[mask, "Capacity (MW)"].sum())
        if current_total <= 0.0:
            continue
        scale = (current_total + add_mw) / current_total
        tuned.loc[mask, "Capacity (MW)"] = tuned.loc[mask, "Capacity (MW)"].to_numpy(dtype=float) * scale

    return tuned.drop(columns=["Seam"])


def summarize_supported_seams(scorecard: pd.DataFrame) -> str:
    rows: list[str] = []
    for row in scorecard.itertuples(index=False):
        rows.append(
            f"{row.Seam}: synthetic={float(row.SyntheticCapacityMW):.1f} MW, "
            f"target={float(row.TargetCapacityMW):.1f} MW, "
            f"scale={float(row.RecommendedScale):.3f}"
        )
    return "; ".join(rows)
