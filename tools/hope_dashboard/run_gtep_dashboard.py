"""Launch the HOPE GTEP Dashboard on port 8051."""
import sys
from pathlib import Path

# Ensure the hope_dashboard directory is on the path
dashboard_dir = Path(__file__).resolve().parent
if str(dashboard_dir) not in sys.path:
    sys.path.insert(0, str(dashboard_dir))

from gtep_app import app

if __name__ == "__main__":
    print("Starting HOPE GTEP Dashboard at http://127.0.0.1:8051")
    app.run(debug=False, port=8051, host="127.0.0.1")
