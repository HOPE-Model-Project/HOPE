# HOPE Dashboard

This folder contains the local Dash dashboards used to explore HOPE results:

- PCM dashboard on port `8050`
- GTEP dashboard on port `8051`

## 1) Prepare output data

Run the RTS24 PCM case with dashboard-oriented settings:

- `network_model: 3`
- `unit_commitment: 2`
- `summary_table: 1`

Helper script:

```powershell
julia --project=. tools/hope_dashboard/run_rts24_dashboard_prep.jl
```

## 2) Install dashboard dependencies

```powershell
python -m pip install -r tools/hope_dashboard/requirements.txt
```

## 3) Run the dashboards

PCM:

```powershell
python tools/hope_dashboard/app.py
```

Open:

- http://127.0.0.1:8050

GTEP:

```powershell
python tools/hope_dashboard/run_gtep_dashboard.py
```

Open:

- http://127.0.0.1:8051

Windows helper scripts:

- `tools/hope_dashboard/start_dashboard.bat`
- `tools/hope_dashboard/start_gtep_dashboard.bat`

Both runner scripts also honor the `HOPE_DASHBOARD_PORT` environment variable,
which is how the HOPE MCP server launches them on a requested local port.

## MCP launch behavior

When Claude Desktop calls `hope_open_dashboard`, the MCP server launches the
dashboard from the HOPE repository root, sets `HOPE_MODELCASES_PATH`, and logs
startup output under `tools/hope_dashboard/logs/`.

If a dashboard does not open through Claude but works manually, compare the MCP
startup log with a working manual launch first.

## Current scope

- Draggable/resizable dashboard panels (drag from panel header)
- Reset button to restore default full-size panel layout
- Three-panel layout: map, line ranking, selected-bus detail
- Nodal network map (hourly)
- Map-layer toggle for `LMP`, `Energy`, `Congestion`, and `Loss`
- Line congestion overlays (loading, shadow, rent, line loss)
- Ranking-metric toggle for congestion rent, shadow price, loading, and line loss
- Bus-level LMP decomposition time series

## Notes

- This V1 uses a clean schematic network layout from `busdata.csv` and `Summary_Congestion_Line_Hourly.csv`.
- Transmission-loss analytics are folded into the map, KPI strip, ranking hover, and bus decomposition view rather than a dedicated loss panel.
- OpenStreetMap is not used in V1 because RTS24 bus inputs do not contain geospatial lat/lon coordinates.
- If a case has multiple output folders, the dashboard will use `dashboard_output.txt` or `dashboard_output_path.txt` in the case root when present; otherwise it falls back to `output/`, then to the newest valid `output*` folder.
