from __future__ import annotations

import json
import sys
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "iso_ne_250bus_case_related"))
from isone_osm_seams import build_seam_scorecard, summarize_supported_seams


CASE_DIR = ROOT / "ModelCases" / "ISONE_PCM_250bus_case" / "Data_ISONE_PCM_250bus"
REF_DIR = ROOT / "tools" / "iso_ne_250bus_case_related" / "references"


def main() -> None:
    bus = pd.read_csv(CASE_DIR / "busdata.csv")[["Bus_id", "Zone_id", "Latitude", "Longitude"]].copy()
    branch = pd.read_csv(CASE_DIR / "branchdata.csv").copy()
    corridor_points = REF_DIR / "osm_corridor_points.csv"
    scorecard = build_seam_scorecard(bus, branch, corridor_points)
    out_csv = REF_DIR / "osm_synthetic_seam_scorecard.csv"
    out_csv.parent.mkdir(parents=True, exist_ok=True)
    scorecard.to_csv(out_csv, index=False)
    payload = {
        "scorecard_csv": str(out_csv),
        "summary": summarize_supported_seams(scorecard),
    }
    print(json.dumps(payload, indent=2))


if __name__ == "__main__":
    main()
