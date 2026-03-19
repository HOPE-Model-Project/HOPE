from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from iso_ne_250bus_case_related.isone_internal_supply import apply_internal_supply_adders


def main() -> None:
    parser = argparse.ArgumentParser(description="Apply predefined internal supply calibration adders to the ISO-NE 250-bus case.")
    parser.add_argument("--case-dir", type=Path, default=Path("ModelCases") / "ISONE_PCM_250bus_case")
    parser.add_argument(
        "--spec-path",
        type=Path,
        default=Path("tools") / "iso_ne_250bus_case_related" / "raw_sources" / "internal_supply_adders_live_case.csv",
    )
    parser.add_argument("--keep-existing", action="store_true")
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[2]
    case_dir = (root / args.case_dir).resolve() if not args.case_dir.is_absolute() else args.case_dir.resolve()
    spec_path = (root / args.spec_path).resolve() if not args.spec_path.is_absolute() else args.spec_path.resolve()
    result = apply_internal_supply_adders(case_dir, spec_path, replace_existing=not args.keep_existing)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
