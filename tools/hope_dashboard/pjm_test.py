import sys; sys.path.insert(0,'.')
from gtep_app import _load_pjm_geojson, _geo_pjm_boundary_traces
import plotly.graph_objects as go

fc = _load_pjm_geojson()
pjm_zones = list(set(f['properties']['zone_id'] for f in fc['features']))
traces = _geo_pjm_boundary_traces(pjm_zones)
print(f"Traces: {len(traces)}, type: {type(traces[0]).__name__ if traces else 'none'}")

fig = go.Figure()
for t in traces:
    fig.add_trace(t)
fig.update_layout(
    geo=dict(
        projection_type="albers usa",
        showland=True, landcolor="lightgray",
        showsubunits=True, subunitcolor="white",
    )
)
out = "data/pjm_boundary_test.html"
fig.write_html(out)
print(f"Written to {out}")
