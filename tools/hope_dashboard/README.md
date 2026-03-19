# HOPE Dashboard (PCM Nodal Market View)

This folder contains a first interactive dashboard for HOPE PCM nodal LMP and congestion analysis.

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

## 3) Run the dashboard

```powershell
python tools/hope_dashboard/app.py
```

Open:

- http://127.0.0.1:8050

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
