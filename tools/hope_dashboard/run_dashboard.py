from __future__ import annotations

from pathlib import Path
import sys


THIS_DIR = Path(__file__).resolve().parent
if str(THIS_DIR) not in sys.path:
    sys.path.insert(0, str(THIS_DIR))

import app  # noqa: E402


if __name__ == "__main__":
    app.app.run(debug=False, host="127.0.0.1", port=8050)
