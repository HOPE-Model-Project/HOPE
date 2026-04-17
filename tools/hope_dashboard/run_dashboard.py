from __future__ import annotations

import os
from pathlib import Path
import sys


THIS_DIR = Path(__file__).resolve().parent
if str(THIS_DIR) not in sys.path:
    sys.path.insert(0, str(THIS_DIR))

import app  # noqa: E402


if __name__ == "__main__":
    port = int(os.environ.get("HOPE_DASHBOARD_PORT", "8050"))
    print(f"Starting HOPE PCM Dashboard at http://127.0.0.1:{port}")
    app.app.run(debug=False, host="127.0.0.1", port=port)
