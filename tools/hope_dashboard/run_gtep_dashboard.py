"""Launch the HOPE GTEP Dashboard on the configured local port."""
import os
import sys
from pathlib import Path

# Ensure the hope_dashboard directory is on the path
dashboard_dir = Path(__file__).resolve().parent
if str(dashboard_dir) not in sys.path:
    sys.path.insert(0, str(dashboard_dir))

from gtep_app import app

if __name__ == "__main__":
    port = int(os.environ.get("HOPE_DASHBOARD_PORT", "8051"))
    print(f"Starting HOPE GTEP Dashboard at http://127.0.0.1:{port}")
    app.run(debug=False, port=port, host="127.0.0.1")
