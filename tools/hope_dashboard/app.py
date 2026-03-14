from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd
import plotly.graph_objects as go
from plotly.subplots import make_subplots
from dash import Dash, Input, Output, State, dcc, html, ctx, no_update

from data_loader import CaseData, load_case


DEFAULT_CASE = "ModelCases/RTS24_PCM_multizone4_congested_1month_case"

APP_FONT = "'Segoe UI Variable', 'Avenir Next', 'Segoe UI', 'Helvetica Neue', Arial, sans-serif"
GRID_LAYOUT_DEFAULT = [
    {"top": "12px", "left": "0px", "width": "68%", "height": "430px", "zIndex": 3},
    {"top": "12px", "left": "70%", "width": "30%", "height": "430px", "zIndex": 2},
    {"top": "458px", "left": "0px", "width": "100%", "height": "320px", "zIndex": 1},
]


def _line_metric_spec(rank_metric: str) -> tuple[str, str, str, str]:
    metric_map = {
        "congestion_rent": ("abs_rent", "|Hourly congestion rent|", "Hourly congestion rent ($)", "#dc2626"),
        "shadow_price": ("abs_shadow", "|Shadow price|", "Shadow price ($/MWh)", "#2563eb"),
        "loading_pct": ("Loading_pct", "Loading", "Loading (%)", "#7c3aed"),
        "line_loss": ("LineLoss_MW", "Line loss", "Line loss (MW)", "#0f766e"),
    }
    return metric_map[rank_metric]


def _theme_palette(theme: str) -> dict:
    if theme == "dark":
        return {
            "bg": "#0b1220",
            "card": "#121a2b",
            "plot": "#0f1726",
            "text": "#e5edf7",
            "muted": "#9fb1c7",
            "grid": "#243146",
            "zone_line": "#50617d",
        }
    return {
        "bg": "#eef3f8",
        "card": "#ffffff",
        "plot": "#f8fafc",
        "text": "#0f172a",
        "muted": "#475569",
        "grid": "#d9e2ec",
        "zone_line": "#94a3b8",
    }


def _line_width(loading_pct: float) -> float:
    if loading_pct >= 80.0:
        return 4.2
    if loading_pct >= 50.0:
        return 2.8
    return 1.5


def _line_color(shadow: float) -> str:
    if abs(shadow) <= 1e-8:
        return "#7b8794"
    if abs(shadow) < 1.0:
        return "#e67e22"
    return "#e63946"


def _network_figure(case: CaseData, hour: int, selected_bus: str, ref_bus: str, map_layer: str, theme: str, selected_line: int | None) -> go.Figure:
    hourly_line = case.line_hourly[case.line_hourly["Hour"] == hour].copy()
    hourly_node = case.nodal_price[case.nodal_price["Hour"] == hour].copy()
    palette = _theme_palette(theme)
    layer_col = {
        "LMP": "LMP",
        "Energy": "Energy",
        "Congestion": "Congestion",
        "Loss": "Loss",
    }[map_layer]

    fig = go.Figure()

    # Zone panels.
    for z, (x0, y0, x1, y1) in case.zone_rect.items():
        fill = case.zone_colors.get(z, "#f1f5f9")
        fig.add_shape(
            type="rect",
            x0=x0,
            y0=y0,
            x1=x1,
            y1=y1,
            line=dict(color=palette["zone_line"], width=1, dash="dot"),
            fillcolor=fill,
            opacity=0.28 if theme == "dark" else 0.45,
            layer="below",
        )
        fig.add_annotation(
            x=x0 + 0.18,
            y=y1 + 0.16,
            text=z,
            showarrow=False,
            xanchor="left",
            yanchor="bottom",
            font=dict(size=14, color=palette["text"]),
        )

    # Lines.
    for row in hourly_line.itertuples(index=False):
        fb = str(row.From_bus)
        tb = str(row.To_bus)
        if fb not in case.bus_xy or tb not in case.bus_xy:
            continue
        x0, y0 = case.bus_xy[fb]
        x1, y1 = case.bus_xy[tb]
        shadow = float(row.ShadowPrice) if row.ShadowPrice == row.ShadowPrice else 0.0
        fig.add_trace(
            go.Scatter(
                x=[x0, x1],
                y=[y0, y1],
                mode="lines",
                line=dict(width=_line_width(float(row.Loading_pct)), color=_line_color(shadow)),
                hoverinfo="text",
                text=(
                    f"Line {row.Line}: {fb}->{tb}<br>"
                    f"Flow={float(row.Flow_MW):.1f} MW<br>"
                    f"Line loss={float(row.LineLoss_MW):.2f} MW<br>"
                    f"Loading={float(row.Loading_pct):.1f}%<br>"
                    f"Shadow={shadow:.3f}<br>"
                    f"Rent={float(row.CongestionRent):.2f}"
                ),
                showlegend=False,
            )
        )

    if selected_line is not None:
        selected_rows = hourly_line[hourly_line["Line"] == selected_line]
        if not selected_rows.empty:
            row = selected_rows.iloc[0]
            fb = str(row["From_bus"])
            tb = str(row["To_bus"])
            if fb in case.bus_xy and tb in case.bus_xy:
                x0, y0 = case.bus_xy[fb]
                x1, y1 = case.bus_xy[tb]
                fig.add_trace(
                    go.Scatter(
                        x=[x0, x1],
                        y=[y0, y1],
                        mode="lines+markers",
                        line=dict(width=7.0, color="#22c55e"),
                        marker=dict(size=11, color="#22c55e", line=dict(width=1, color=palette["card"])),
                        hoverinfo="text",
                        text=(
                            f"Selected line L{int(row['Line'])}: {fb}->{tb}<br>"
                            f"Flow={float(row['Flow_MW']):.1f} MW<br>"
                            f"Loading={float(row['Loading_pct']):.1f}%<br>"
                            f"Shadow={float(row['ShadowPrice']):.2f} $/MWh<br>"
                            f"Rent={float(row['CongestionRent']):.2f} $<br>"
                            f"Line loss={float(row['LineLoss_MW']):.2f} MW"
                        ),
                        showlegend=False,
                    )
                )

    # Nodes.
    node_x, node_y, node_text, node_color, node_size = [], [], [], [], []
    for row in hourly_node.itertuples(index=False):
        b = str(row.Bus)
        if b not in case.bus_xy:
            continue
        x, y = case.bus_xy[b]
        lmp = float(row.LMP)
        layer_value = float(getattr(row, layer_col))
        node_x.append(x)
        node_y.append(y)
        node_color.append(layer_value)
        size = 16
        if b == selected_bus:
            size = 22
        elif b == ref_bus:
            size = 20
        node_size.append(size)
        node_text.append(
            f"Bus {b} | Zone {row.Zone}<br>"
            f"Map layer {map_layer}={layer_value:.2f} $/MWh<br>"
            f"LMP={lmp:.2f} $/MWh<br>"
            f"Energy component (ref)={float(row.Energy):.2f} $/MWh<br>"
            f"Congestion component vs ref={float(row.Congestion):.2f} $/MWh<br>"
            f"Loss component={float(row.Loss):.2f} $/MWh"
        )

    cmin = float(np.nanmin(node_color)) if node_color else 0.0
    cmax = float(np.nanmax(node_color)) if node_color else 1.0
    if abs(cmax - cmin) <= 1.0e-9:
        cmin -= 1.0
        cmax += 1.0

    fig.add_trace(
        go.Scatter(
            x=node_x,
            y=node_y,
            mode="markers+text",
            text=[f"{b}" for b in hourly_node["Bus"].astype(str).tolist()],
            textposition="top center",
            customdata=[["bus", str(b)] for b in hourly_node["Bus"].astype(str).tolist()],
            marker=dict(
                size=node_size,
                color=node_color,
                colorscale="RdYlBu_r",
                cmin=cmin,
                cmax=cmax,
                colorbar=dict(title=map_layer),
                line=dict(color=palette["text"], width=0.8),
            ),
            hoverinfo="text",
            hovertext=node_text,
            showlegend=False,
        )
    )

    fig.update_layout(
        autosize=True,
        margin=dict(l=10, r=10, t=10, b=10),
        plot_bgcolor=palette["plot"],
        paper_bgcolor=palette["card"],
        font=dict(family=APP_FONT, size=12, color=palette["text"]),
        xaxis=dict(visible=False),
        yaxis=dict(visible=False, scaleanchor="x", scaleratio=1),
    )
    return fig


def _timeseries_figure(case: CaseData, selected_bus: str, compare_bus: str, ref_bus: str, theme: str) -> go.Figure:
    bus = case.nodal_price[case.nodal_price["Bus"] == selected_bus].sort_values("Hour")
    comp = case.nodal_price[case.nodal_price["Bus"] == compare_bus].sort_values("Hour")
    ref = case.nodal_price[case.nodal_price["Bus"] == ref_bus].sort_values("Hour")
    if bus.empty or comp.empty or ref.empty:
        return go.Figure()
    palette = _theme_palette(theme)
    merged = (
        bus[["Hour", "LMP", "Congestion", "Loss"]]
        .merge(comp[["Hour", "LMP"]], on="Hour", suffixes=("", "_compare"))
        .merge(ref[["Hour", "LMP"]], on="Hour", suffixes=("", "_ref"))
    )
    merged["Energy_ref"] = merged["LMP_ref"]
    merged["Basis_compare"] = merged["LMP"] - merged["LMP_compare"]

    fig = make_subplots(
        rows=2,
        cols=1,
        shared_xaxes=True,
        vertical_spacing=0.14,
        row_heights=[0.64, 0.36],
        subplot_titles=(
            f"Bus {selected_bus} Price Decomposition",
            f"Basis vs Bus {compare_bus}",
        ),
    )
    fig.add_trace(
        go.Scatter(
            x=merged["Hour"],
            y=merged["LMP"],
            mode="lines",
            name=f"Bus {selected_bus} LMP",
            line=dict(color="#2563eb", width=2.0),
        ),
        row=1,
        col=1,
    )
    fig.add_trace(
        go.Scatter(
            x=merged["Hour"],
            y=merged["Energy_ref"],
            mode="lines",
            name=f"Energy component (bus {ref_bus})",
            line=dict(color="#64748b", width=1.8),
        ),
        row=1,
        col=1,
    )
    fig.add_trace(
        go.Scatter(
            x=merged["Hour"],
            y=merged["Congestion"],
            mode="lines",
            name=f"Congestion component (vs bus {ref_bus})",
            line=dict(color="#d97706", width=1.7, dash="dot"),
        ),
        row=1,
        col=1,
    )
    fig.add_trace(
        go.Scatter(
            x=merged["Hour"],
            y=merged["Loss"],
            mode="lines",
            name="Loss component",
            line=dict(color="#0f766e", width=1.5, dash="dash"),
        ),
        row=1,
        col=1,
    )
    fig.add_trace(
        go.Scatter(
            x=merged["Hour"],
            y=merged["LMP_compare"],
            mode="lines",
            name=f"Bus {compare_bus} LMP",
            line=dict(color="#94a3b8", width=1.8),
        ),
        row=2,
        col=1,
    )
    fig.add_trace(
        go.Scatter(
            x=merged["Hour"],
            y=merged["Basis_compare"],
            mode="lines",
            name=f"Basis: bus {selected_bus} - bus {compare_bus}",
            line=dict(color="#dc2626", width=2.0),
            fill="tozeroy",
            fillcolor="rgba(220, 38, 38, 0.10)",
        ),
        row=2,
        col=1,
    )
    fig.update_layout(
        autosize=True,
        template="plotly_white",
        margin=dict(l=36, r=20, t=88, b=70),
        legend=dict(
            orientation="h",
            yanchor="bottom",
            y=1.12,
            xanchor="left",
            x=0.0,
        ),
        paper_bgcolor=palette["card"],
        plot_bgcolor=palette["card"],
        font=dict(family=APP_FONT, size=12, color=palette["text"]),
    )
    fig.update_xaxes(
        gridcolor=palette["grid"],
        zerolinecolor=palette["grid"],
        title_text="Hour",
        title_standoff=24,
        row=2,
        col=1,
    )
    fig.update_yaxes(gridcolor=palette["grid"], zerolinecolor=palette["grid"], color=palette["text"], title_text="$ / MWh", row=1, col=1)
    fig.update_yaxes(gridcolor=palette["grid"], zerolinecolor=palette["grid"], color=palette["text"], title_text="$ / MWh", row=2, col=1)
    fig.update_layout(
        legend_font_color=palette["text"],
    )
    for annot in fig.layout.annotations:
        annot.font.color = palette["text"]
    return fig


def _line_ranking_figure(case: CaseData, hour: int, rank_metric: str, theme: str, selected_line: int | None) -> go.Figure:
    hourly = case.line_hourly[case.line_hourly["Hour"] == hour].copy()
    palette = _theme_palette(theme)
    hourly["abs_shadow"] = hourly["ShadowPrice"].abs()
    hourly["abs_rent"] = hourly["CongestionRent"].abs()
    hourly["line_name"] = hourly.apply(lambda r: f"L{int(r['Line'])} {r['From_bus']}->{r['To_bus']}", axis=1)
    metric_col, trace_name, y_title, color = _line_metric_spec(rank_metric)
    top = hourly.sort_values(metric_col, ascending=False).head(12)
    marker_colors = ["#f59e0b" if selected_line is not None and int(line) == int(selected_line) else color for line in top["Line"]]
    marker_line_width = [2 if selected_line is not None and int(line) == int(selected_line) else 0 for line in top["Line"]]
    if selected_line is None or selected_line not in hourly["Line"].astype(int).tolist():
        selected_line = int(top.iloc[0]["Line"]) if not top.empty else None

    fig = make_subplots(
        rows=2,
        cols=1,
        row_heights=[0.60, 0.40],
        vertical_spacing=0.32,
        subplot_titles=("Top Congested Constraints", "Top Bus Congestion Contributors"),
    )
    fig.add_trace(
        go.Bar(
            x=top["line_name"],
            y=top[metric_col],
            name=trace_name,
            marker_color=marker_colors,
            marker_line=dict(color=palette["text"], width=marker_line_width),
            hovertemplate=(
                "Line %{x}<br>"
                + f"{trace_name} = %{{y:.2f}}<br>"
                + "Flow = %{customdata[3]:.1f} MW<br>"
                + "Loading = %{customdata[4]:.1f}%<br>"
                + "Shadow = %{customdata[5]:.2f} $/MWh<br>"
                + "Rent = %{customdata[6]:.2f} $<br>"
                + "Line loss = %{customdata[7]:.2f} MW<extra></extra>"
            ),
            customdata=top[["Line", "From_bus", "To_bus", "Flow_MW", "Loading_pct", "ShadowPrice", "CongestionRent", "LineLoss_MW"]].to_numpy(),
        ),
        row=1,
        col=1,
    )

    driver_rows = case.node_driver_hourly[
        (case.node_driver_hourly["Hour"] == int(hour))
        & (case.node_driver_hourly["Line"].astype(int) == int(selected_line))
    ].copy()
    if not driver_rows.empty:
        driver_rows["abs_contrib"] = driver_rows["Contribution"].abs()
        driver_top = driver_rows.sort_values("abs_contrib", ascending=False).head(10)
        driver_top = driver_top.sort_values("Contribution", ascending=True)
        driver_colors = ["#2563eb" if val < 0 else "#ef4444" for val in driver_top["Contribution"]]
        fig.add_trace(
            go.Bar(
                x=driver_top["Contribution"],
                y=[f"Bus {bus}" for bus in driver_top["Bus"]],
                orientation="h",
                name="Congestion contribution",
                marker_color=driver_colors,
                customdata=driver_top[["Zone", "PTDF", "DeltaPTDF", "ShadowPrice", "Contribution"]].to_numpy(),
                hovertemplate=(
                    "%{y}<br>"
                    + "Contribution = %{x:.3f} $/MWh<br>"
                    + "Zone = %{customdata[0]}<br>"
                    + "PTDF = %{customdata[1]:.4f}<br>"
                    + "Delta PTDF = %{customdata[2]:.4f}<br>"
                    + "Shadow = %{customdata[3]:.2f} $/MWh<extra></extra>"
                ),
                showlegend=False,
            ),
            row=2,
            col=1,
        )
        fig.add_vline(x=0.0, line_width=1, line_dash="dot", line_color=palette["grid"], row=2, col=1)
    else:
        fig.add_annotation(
            x=0.5,
            y=0.16,
            xref="paper",
            yref="paper",
            text="No congestion-driver data available for the selected line/hour.",
            showarrow=False,
            font=dict(family=APP_FONT, size=12, color=palette["muted"]),
        )

    fig.update_layout(
        autosize=True,
        template="plotly_white",
        margin=dict(l=36, r=20, t=88, b=36),
        showlegend=False,
        paper_bgcolor=palette["card"],
        plot_bgcolor=palette["card"],
        font=dict(family=APP_FONT, size=12, color=palette["text"]),
    )
    fig.update_annotations(font=dict(family=APP_FONT, size=12, color=palette["text"]))
    if len(fig.layout.annotations) >= 2:
        fig.layout.annotations[0].y = fig.layout.annotations[0].y + 0.05
        fig.layout.annotations[1].y = fig.layout.annotations[1].y + 0.05
    fig.update_xaxes(
        title_text="",
        tickangle=-28,
        gridcolor=palette["grid"],
        zerolinecolor=palette["grid"],
        tickfont=dict(size=11),
        row=1,
        col=1,
    )
    fig.update_yaxes(
        title_text=y_title,
        gridcolor=palette["grid"],
        zerolinecolor=palette["grid"],
        color=palette["text"],
        row=1,
        col=1,
    )
    fig.update_xaxes(
        title_text="Contribution ($/MWh)",
        gridcolor=palette["grid"],
        zerolinecolor=palette["grid"],
        color=palette["text"],
        row=2,
        col=1,
    )
    fig.update_yaxes(
        title_text="Bus",
        gridcolor=palette["grid"],
        zerolinecolor=palette["grid"],
        color=palette["text"],
        row=2,
        col=1,
    )
    return fig


def _selected_line_detail(case: CaseData, hour: int, selected_line: int | None, rank_metric: str) -> html.Div:
    metric_col, _, _, _ = _line_metric_spec(rank_metric)
    hourly_line = case.line_hourly[case.line_hourly["Hour"] == hour].copy()
    hourly_line["abs_shadow"] = hourly_line["ShadowPrice"].abs()
    hourly_line["abs_rent"] = hourly_line["CongestionRent"].abs()
    if hourly_line.empty:
        return html.Div()
    if selected_line is None or selected_line not in hourly_line["Line"].astype(int).tolist():
        selected_row = hourly_line.sort_values(metric_col, ascending=False).iloc[0]
    else:
        selected_row = hourly_line.loc[hourly_line["Line"].astype(int) == int(selected_line)].iloc[0]
    line_label = f"L{int(selected_row['Line'])} {selected_row['From_bus']}->{selected_row['To_bus']}"
    return html.Div(
        [
            html.Span(f"Active Constraint {line_label}", className="constraint-pill constraint-pill-active"),
            html.Span(f"Flow {float(selected_row['Flow_MW']):.1f} MW", className="constraint-pill"),
            html.Span(f"Loading {float(selected_row['Loading_pct']):.1f}%", className="constraint-pill"),
            html.Span(f"Shadow {float(selected_row['ShadowPrice']):.2f} $/MWh", className="constraint-pill"),
            html.Span(f"Rent {float(selected_row['CongestionRent']):.2f} $", className="constraint-pill"),
            html.Span(f"Line Loss {float(selected_row['LineLoss_MW']):.2f} MW", className="constraint-pill"),
        ],
        className="constraint-detail",
    )


def _case_summary_block(case: CaseData) -> html.Div:
    buses = int(case.busdata["Bus_id"].astype(str).nunique())
    zones = int(case.busdata["Zone_id"].astype(str).nunique())
    lines = int(case.line_hourly["Line"].astype(int).nunique()) if not case.line_hourly.empty else 0
    hours = int(case.nodal_price["Hour"].astype(int).nunique()) if not case.nodal_price.empty else 0

    peak_spread_hour = 1
    peak_spread = 0.0
    if not case.nodal_price.empty:
        spread_tbl = (
            case.nodal_price.groupby("Hour")["LMP"]
            .agg(lambda s: float(s.max() - s.min()))
            .reset_index(name="Spread")
        )
        if not spread_tbl.empty:
            peak_row = spread_tbl.sort_values("Spread", ascending=False).iloc[0]
            peak_spread_hour = int(peak_row["Hour"])
            peak_spread = float(peak_row["Spread"])

    peak_rent_hour = 1
    peak_rent = 0.0
    if not case.line_hourly.empty:
        rent_tbl = (
            case.line_hourly.groupby("Hour")["CongestionRent"]
            .sum()
            .reset_index(name="Rent")
        )
        if not rent_tbl.empty:
            peak_row = rent_tbl.sort_values("Rent", ascending=False).iloc[0]
            peak_rent_hour = int(peak_row["Hour"])
            peak_rent = float(peak_row["Rent"])

    return html.Div(
        [
            html.Span(f"Case {case.case_path.name}", className="case-summary-pill case-summary-pill-primary"),
            html.Span(f"Buses {buses}", className="case-summary-pill"),
            html.Span(f"Zones {zones}", className="case-summary-pill"),
            html.Span(f"Lines {lines}", className="case-summary-pill"),
            html.Span(f"Hours {hours}", className="case-summary-pill"),
            html.Span(f"Peak Spread Hr {peak_spread_hour} ({peak_spread:.2f} $/MWh)", className="case-summary-pill"),
            html.Span(f"Peak Rent Hr {peak_rent_hour} ({peak_rent:.2f} $)", className="case-summary-pill"),
        ],
        className="case-summary-strip",
    )


def _kpi_block(case: CaseData, hour: int, selected_bus: str, compare_bus: str) -> html.Div:
    hourly_node = case.nodal_price[case.nodal_price["Hour"] == hour]
    hourly_line = case.line_hourly[case.line_hourly["Hour"] == hour]
    hourly_system = case.system_hourly[case.system_hourly["Hour"] == hour]
    spread = float(hourly_node["LMP"].max() - hourly_node["LMP"].min()) if not hourly_node.empty else 0.0
    binding = int((hourly_line["BindingSide"] != "None").sum()) if not hourly_line.empty else 0
    rent = float(hourly_line["CongestionRent"].sum()) if not hourly_line.empty else 0.0
    avg_load = float(hourly_line["Loading_pct"].mean()) if not hourly_line.empty else 0.0
    tx_loss = float(hourly_system["TransmissionLoss_MW"].iloc[0]) if not hourly_system.empty else 0.0
    basis_val = 0.0
    if not hourly_node.empty and selected_bus and compare_bus:
        focus_rows = hourly_node[hourly_node["Bus"].astype(str) == str(selected_bus)]
        compare_rows = hourly_node[hourly_node["Bus"].astype(str) == str(compare_bus)]
        if not focus_rows.empty and not compare_rows.empty:
            basis_val = float(focus_rows["LMP"].iloc[0] - compare_rows["LMP"].iloc[0])
    return html.Div(
        [
            html.Span(f"Hour {hour}", className="kpi-pill kpi-pill-hour"),
            html.Span(f"LMP Spread {spread:.2f} $/MWh", className="kpi-pill"),
            html.Span(f"Basis {selected_bus}-{compare_bus} {basis_val:.2f} $/MWh", className="kpi-pill"),
            html.Span(f"Binding Lines {binding}", className="kpi-pill"),
            html.Span(f"Congestion Rent {rent:.2f} $", className="kpi-pill"),
            html.Span(f"Tx Loss {tx_loss:.2f} MW", className="kpi-pill"),
            html.Span(f"Avg Loading {avg_load:.1f}%", className="kpi-pill"),
        ],
        className="kpi-strip",
    )


def _interesting_hour_options(case: CaseData, metric: str) -> list[dict]:
    nodal = case.nodal_price.copy()
    line = case.line_hourly.copy()
    spread = (
        nodal.groupby("Hour")["LMP"]
        .agg(lambda s: float(s.max() - s.min()))
        .rename("lmp_spread")
        .reset_index()
    )
    line_metrics = (
        line.groupby("Hour")
        .agg(
            congestion_rent=("CongestionRent", lambda s: float(s.sum())),
            binding_lines=("BindingSide", lambda s: int((s != "None").sum())),
            avg_loading=("Loading_pct", lambda s: float(s.mean())),
        )
        .reset_index()
    )
    summary = spread.merge(line_metrics, on="Hour", how="outer").fillna(0.0)
    label_map = {
        "lmp_spread": "Spread",
        "congestion_rent": "Rent",
        "binding_lines": "Binding",
        "avg_loading": "Loading",
    }
    format_map = {
        "lmp_spread": lambda v: f"{v:.2f} $/MWh",
        "congestion_rent": lambda v: f"{v:.2f} $",
        "binding_lines": lambda v: f"{int(round(v))} lines",
        "avg_loading": lambda v: f"{v:.1f}%",
    }
    top = summary.sort_values(metric, ascending=False).head(12)
    return [
        {
            "label": f"Hour {int(row['Hour'])} | {label_map[metric]} {format_map[metric](float(row[metric]))}",
            "value": int(row["Hour"]),
        }
        for _, row in top.iterrows()
    ]


def _resolve_selected_line(case: CaseData, hour: int, rank_metric: str, selected_line: int | None) -> int | None:
    hourly_line = case.line_hourly[case.line_hourly["Hour"] == int(hour)].copy()
    if hourly_line.empty:
        return None
    hourly_line["abs_shadow"] = hourly_line["ShadowPrice"].abs()
    hourly_line["abs_rent"] = hourly_line["CongestionRent"].abs()
    if selected_line is not None and selected_line in hourly_line["Line"].astype(int).tolist():
        return int(selected_line)
    metric_col, _, _, _ = _line_metric_spec(str(rank_metric))
    return int(hourly_line.sort_values(metric_col, ascending=False).iloc[0]["Line"])


app = Dash(__name__, assets_folder=str(Path(__file__).with_name("assets")))
app.title = "HOPE Dashboard - PCM Nodal Market View"


def _panel_card(title: str, inner: html.Div) -> html.Div:
    return html.Div(
        [
            html.Div(
                [
                    html.Span("::", className="panel-handle-glyph"),
                    html.Span(title),
                ],
                className="panel-drag-handle",
            ),
            html.Div(
                inner,
                className="panel-inner",
            ),
        ],
        className="panel-card",
    )


def _panel_outer_style(index: int) -> dict:
    base = GRID_LAYOUT_DEFAULT[index]
    return {
        "position": "absolute",
        "top": base["top"],
        "left": base["left"],
        "width": base["width"],
        "height": base["height"],
        "zIndex": base["zIndex"],
    }

app.layout = html.Div(
    [
        html.Div(
            [
                html.Div(
                    [
                        html.Img(src="/assets/hope-dashboard-icon.png", className="dashboard-header-logo", alt="HOPE charger logo"),
                        html.Div(
                            [
                                html.H2(
                                    "HOPE Dashboard: PCM Nodal Market View",
                                    style={"margin": "0", "fontWeight": 850, "letterSpacing": "0.1px"},
                                ),
                                html.Div(
                                    "Map-first LMP, congestion, and loss analysis for HOPE PCM nodal outputs.",
                                    className="dashboard-subtitle",
                                ),
                            ],
                            className="dashboard-header-copy",
                        ),
                    ],
                    className="dashboard-header-row",
                ),
                html.Div(
                    [
                        dcc.Input(
                            id="case-path",
                            type="text",
                            value=DEFAULT_CASE,
                            className="hope-text-input",
                            style={"width": "420px"},
                        ),
                        html.Button(
                            "Load Case",
                            id="load-case",
                            n_clicks=0,
                            className="hope-button hope-button-primary",
                        ),
                        html.Button(
                            "Reset Panel Layout",
                            id="reset-layout",
                            n_clicks=0,
                            className="hope-button hope-button-secondary",
                        ),
                        html.Button(
                            "Save Layout",
                            id="save-layout",
                            n_clicks=0,
                            className="hope-button hope-button-secondary",
                        ),
                        html.Button(
                            "Restore Saved",
                            id="restore-saved-layout",
                            n_clicks=0,
                            className="hope-button hope-button-secondary",
                        ),
                        html.Button(
                            "Export Hour CSV",
                            id="export-hour",
                            n_clicks=0,
                            className="hope-button hope-button-secondary",
                        ),
                        html.Button(
                            "Export Analysis CSV",
                            id="export-analysis",
                            n_clicks=0,
                            className="hope-button hope-button-secondary",
                        ),
                        html.Button(
                            "Screenshot PNG",
                            id="screenshot-dashboard",
                            n_clicks=0,
                            className="hope-button hope-button-secondary",
                        ),
                        html.Div(
                            [
                                html.Button(
                                    "Hide Controls",
                                    id="controls-toggle",
                                    n_clicks=0,
                                    className="hope-button hope-button-secondary toolbar-action-button",
                                ),
                                html.Button(
                                    "Help",
                                    id="help-toggle",
                                    n_clicks=0,
                                    className="hope-button hope-button-secondary toolbar-action-button",
                                ),
                                html.Button(
                                    "Dark Mode",
                                    id="theme-toggle",
                                    n_clicks=0,
                                    className="hope-button hope-button-secondary toolbar-action-button",
                                ),
                            ],
                            className="toolbar-action-stack",
                        ),
                    ],
                    className="toolbar-row toolbar-row-top",
                ),
                html.Div(id="status", className="dashboard-status-row"),
                html.Div(id="case-summary"),
                html.Div(
                    [
                        html.P(
                            "Use the dashboard in three steps: find a congested hour, identify the active line, then compare the buses most affected by that line.",
                            className="dashboard-help-intro",
                        ),
                        html.Ul(
                            [
                                html.Li("LMP Spread is the system-wide maximum minus minimum bus LMP at the selected hour."),
                                html.Li("Use the Interesting Hours controls or the << / < / > / >> buttons to jump quickly between the most important hours or move through time."),
                                html.Li("Basis is the Focus Bus LMP minus the Compare Bus LMP, so it is a pair-specific price difference."),
                                html.Li("Focus Bus is the main bus you analyze; Compare Bus is the second bus used for basis and price-difference comparison."),
                                html.Li("Constraint / Line Ranking shows the most important lines at the selected hour by the chosen ranking metric."),
                                html.Li("Top Bus Congestion Contributors shows how the selected line affects bus congestion prices: positive bars increase bus prices and negative bars reduce them."),
                                html.Li("Click a bus on the network map to set it as the Focus Bus, or Shift+click a bus to set it as the Compare Bus."),
                                html.Li("Use the map and the basis chart together: click a ranked line, then inspect which buses separate the most over time."),
                            ],
                            className="dashboard-help-list",
                        ),
                    ],
                    id="dashboard-help-panel",
                    className="dashboard-help",
                    style={"display": "none"},
                ),
                html.Div(id="kpi"),
                html.Div(id="line-detail"),
                html.Div(
                    [
                        html.Div(
                            [
                                html.Div(
                                    [
                                        html.Label("Hour", style={"fontWeight": 700, "fontSize": "13px"}),
                                        html.Div(
                                            [
                                                html.Button("<<", id="hour-prev-day", n_clicks=0, className="hope-button hope-button-secondary hour-step-button"),
                                                html.Button("<", id="hour-prev", n_clicks=0, className="hope-button hope-button-secondary hour-step-button"),
                                                html.Button(">", id="hour-next", n_clicks=0, className="hope-button hope-button-secondary hour-step-button"),
                                                html.Button(">>", id="hour-next-day", n_clicks=0, className="hope-button hope-button-secondary hour-step-button"),
                                            ],
                                            className="hour-step-group",
                                        ),
                                    ],
                                    className="hour-header-row",
                                ),
                                dcc.Slider(
                                    id="hour-slider",
                                    min=1,
                                    max=744,
                                    value=1,
                                    step=1,
                                    marks={1: "1", 744: "744"},
                                    updatemode="drag",
                                    tooltip={"placement": "bottom", "always_visible": False},
                                ),
                                html.Div(
                                    [
                                        html.Div(
                                            [
                                                html.Label("Interesting Hours", style={"fontWeight": 700, "fontSize": "13px"}),
                                                dcc.Dropdown(
                                                    id="hour-rank-metric",
                                                    options=[
                                                        {"label": "LMP Spread", "value": "lmp_spread"},
                                                        {"label": "Congestion Rent", "value": "congestion_rent"},
                                                        {"label": "Binding Lines", "value": "binding_lines"},
                                                        {"label": "Average Loading", "value": "avg_loading"},
                                                    ],
                                                    value="lmp_spread",
                                                    clearable=False,
                                                ),
                                            ],
                                            className="toolbar-block hour-finder-metric",
                                        ),
                                        html.Div(
                                            [
                                                html.Label("Jump To", style={"fontWeight": 700, "fontSize": "13px"}),
                                                dcc.Dropdown(
                                                    id="interesting-hour-dropdown",
                                                    options=[],
                                                    placeholder="Select a high-impact hour",
                                                    clearable=True,
                                                ),
                                            ],
                                            className="toolbar-block hour-finder-select",
                                        ),
                                    ],
                                    className="hour-finder-row",
                                ),
                            ],
                            className="toolbar-block toolbar-block-hour",
                        ),
                        html.Div(
                            [
                                html.Div(
                                    [html.Label("Focus Bus", style={"fontWeight": 700, "fontSize": "13px"}), dcc.Dropdown(id="bus-dropdown")],
                                    className="toolbar-block toolbar-block-select",
                                ),
                                html.Div(
                                    [html.Label("Compare Bus", style={"fontWeight": 700, "fontSize": "13px"}), dcc.Dropdown(id="compare-bus-dropdown")],
                                    className="toolbar-block toolbar-block-select",
                                ),
                                html.Div(
                                    [html.Label("Reference Bus", style={"fontWeight": 700, "fontSize": "13px"}), dcc.Dropdown(id="ref-bus-dropdown")],
                                    className="toolbar-block toolbar-block-select",
                                ),
                                html.Div(
                                    [
                                        html.Label("Map Layer", style={"fontWeight": 700, "fontSize": "13px"}),
                                        dcc.Dropdown(
                                            id="map-layer-dropdown",
                                            options=[
                                                {"label": "LMP", "value": "LMP"},
                                                {"label": "Energy", "value": "Energy"},
                                                {"label": "Congestion", "value": "Congestion"},
                                                {"label": "Loss", "value": "Loss"},
                                            ],
                                            value="LMP",
                                            clearable=False,
                                        ),
                                    ],
                                    className="toolbar-block toolbar-block-toggle",
                                ),
                                html.Div(
                                    [
                                        html.Label("Ranking Metric", style={"fontWeight": 700, "fontSize": "13px"}),
                                        dcc.Dropdown(
                                            id="rank-metric-dropdown",
                                            options=[
                                                {"label": "Congestion Rent", "value": "congestion_rent"},
                                                {"label": "Shadow Price", "value": "shadow_price"},
                                                {"label": "Loading", "value": "loading_pct"},
                                                {"label": "Line Loss", "value": "line_loss"},
                                            ],
                                            value="congestion_rent",
                                            clearable=False,
                                        ),
                                    ],
                                    className="toolbar-block toolbar-block-toggle",
                                ),
                            ],
                            className="toolbar-row toolbar-row-controls",
                        ),
                    ],
                    className="toolbar-row toolbar-row-bottom",
                ),
            ],
            id="dashboard-toolbar",
            className="dashboard-toolbar",
            style={
                "position": "sticky",
                "top": "0",
                "zIndex": 5000,
                "overflow": "visible",
                "padding": "14px 16px",
                "marginBottom": "10px",
            },
        ),
        dcc.Store(id="case-store", data=DEFAULT_CASE),
        dcc.Store(id="theme-store", data="light"),
        dcc.Store(id="selected-line-store", data=None),
        dcc.Store(id="map-click-store", data=None),
        dcc.Download(id="download-hour"),
        dcc.Download(id="download-analysis"),
        html.Div(
            id="panel-canvas",
            className="panel-canvas",
            style={"position": "relative", "height": "1700px", "minHeight": "1700px", "marginTop": "8px", "paddingBottom": "420px"},
            children=[
                html.Div(
                    id="panel-network",
                    className="floating-panel",
                    style=_panel_outer_style(0),
                    children=_panel_card(
                        "Nodal Network Map",
                        dcc.Graph(
                            id="network-graph",
                            style={"height": "100%", "width": "100%"},
                            config={"displayModeBar": False, "responsive": True},
                        ),
                    ),
                ),
                html.Div(
                    id="panel-ranking",
                    className="floating-panel",
                    style=_panel_outer_style(1),
                    children=_panel_card(
                        "Constraint / Line Ranking",
                        dcc.Graph(
                            id="line-rank",
                            style={"height": "100%", "width": "100%"},
                            config={"displayModeBar": False, "responsive": True},
                        ),
                    ),
                ),
                html.Div(
                    id="panel-timeseries",
                    className="floating-panel",
                    style=_panel_outer_style(2),
                    children=_panel_card(
                        "Selected Bus Price / Basis Analysis",
                        dcc.Graph(
                            id="bus-ts",
                            style={"height": "100%", "width": "100%"},
                            config={"displayModeBar": False, "responsive": True},
                        ),
                    ),
                ),
            ],
        ),
    ],
    id="app-root",
    className="hope-dashboard theme-light",
    style={
        "padding": "12px 14px",
        "fontFamily": APP_FONT,
        "minHeight": "100vh",
        "paddingBottom": "420px",
    },
)


@app.callback(
    Output("panel-network", "style"),
    Output("panel-ranking", "style"),
    Output("panel-timeseries", "style"),
    Input("reset-layout", "n_clicks"),
)
def reset_panel_layout(_n_clicks: int):
    return _panel_outer_style(0), _panel_outer_style(1), _panel_outer_style(2)


@app.callback(
    Output("theme-store", "data"),
    Output("app-root", "className"),
    Output("theme-toggle", "children"),
    Input("theme-toggle", "n_clicks"),
)
def toggle_theme(n_clicks: int):
    theme = "dark" if (n_clicks or 0) % 2 == 1 else "light"
    button_text = "Light Mode" if theme == "dark" else "Dark Mode"
    return theme, f"hope-dashboard theme-{theme}", button_text


@app.callback(
    Output("dashboard-toolbar", "className"),
    Output("controls-toggle", "children"),
    Input("controls-toggle", "n_clicks"),
)
def toggle_controls_panel(n_clicks: int):
    collapsed = (n_clicks or 0) % 2 == 1
    class_name = "dashboard-toolbar toolbar-collapsed" if collapsed else "dashboard-toolbar"
    button_text = "Show Controls" if collapsed else "Hide Controls"
    return class_name, button_text


@app.callback(
    Output("dashboard-help-panel", "style"),
    Input("help-toggle", "n_clicks"),
)
def toggle_help_panel(n_clicks: int):
    if (n_clicks or 0) % 2 == 1:
        return {"display": "block"}
    return {"display": "none"}


@app.callback(
    Output("selected-line-store", "data"),
    Input("line-rank", "clickData"),
    prevent_initial_call=True,
)
def select_line_from_chart(click_data):
    if not click_data or "points" not in click_data or not click_data["points"]:
        return None
    custom = click_data["points"][0].get("customdata")
    if not custom:
        return None
    return int(custom[0])


@app.callback(
    Output("bus-dropdown", "value", allow_duplicate=True),
    Output("compare-bus-dropdown", "value", allow_duplicate=True),
    Input("map-click-store", "data"),
    State("bus-dropdown", "value"),
    State("compare-bus-dropdown", "value"),
    prevent_initial_call=True,
)
def update_buses_from_map_click(map_click_data, current_focus, current_compare):
    if not map_click_data or not isinstance(map_click_data, dict):
        return no_update, no_update
    clicked_bus = map_click_data.get("bus")
    if clicked_bus is None:
        return no_update, no_update
    clicked_bus = str(clicked_bus)
    if bool(map_click_data.get("shiftKey")):
        if clicked_bus != str(current_compare):
            return no_update, clicked_bus
        return no_update, no_update
    if clicked_bus != str(current_focus):
        return clicked_bus, no_update
    return no_update, no_update


@app.callback(
    Output("status", "children"),
    Output("case-store", "data"),
    Output("hour-slider", "max"),
    Output("hour-slider", "marks"),
    Output("hour-rank-metric", "value"),
    Output("interesting-hour-dropdown", "value"),
    Output("bus-dropdown", "options"),
    Output("bus-dropdown", "value"),
    Output("ref-bus-dropdown", "options"),
    Output("ref-bus-dropdown", "value"),
    Output("compare-bus-dropdown", "options"),
    Output("compare-bus-dropdown", "value"),
    Input("load-case", "n_clicks"),
    State("case-path", "value"),
)
def load_case_callback(_n_clicks: int, case_path: str):
    try:
        case = load_case(case_path, refresh=True)
    except Exception as exc:  # pragma: no cover - runtime UI guard
        return f"Load failed: {exc}", case_path, 744, {1: "1", 744: "744"}, "lmp_spread", None, [], None, [], None, [], None

    h_max = int(case.nodal_price["Hour"].max())
    bus_list = sorted(case.nodal_price["Bus"].astype(str).unique().tolist(), key=lambda x: int(x) if x.isdigit() else x)
    options = [{"label": f"Bus {b}", "value": b} for b in bus_list]
    compare_default = bus_list[1] if len(bus_list) > 1 else (bus_list[0] if bus_list else None)
    return (
        f"Loaded: {Path(case_path).name}",
        case_path,
        h_max,
        {1: "1", h_max: str(h_max)},
        "lmp_spread",
        None,
        options,
        bus_list[0] if bus_list else None,
        options,
        bus_list[0] if bus_list else None,
        options,
        compare_default,
    )


@app.callback(
    Output("interesting-hour-dropdown", "options"),
    Input("case-store", "data"),
    Input("hour-rank-metric", "value"),
)
def update_interesting_hour_options(case_path: str, metric: str):
    case = load_case(case_path, refresh=False)
    return _interesting_hour_options(case, str(metric))


@app.callback(
    Output("case-summary", "children"),
    Input("case-store", "data"),
)
def update_case_summary(case_path: str):
    case = load_case(case_path, refresh=False)
    return _case_summary_block(case)


@app.callback(
    Output("hour-slider", "value"),
    Input("case-store", "data"),
    Input("hour-prev-day", "n_clicks"),
    Input("hour-prev", "n_clicks"),
    Input("hour-next", "n_clicks"),
    Input("hour-next-day", "n_clicks"),
    Input("interesting-hour-dropdown", "value"),
    State("hour-slider", "value"),
    State("hour-slider", "max"),
    prevent_initial_call=False,
)
def update_hour_value(
    case_path: str,
    prev_day_clicks: int,
    prev_clicks: int,
    next_clicks: int,
    next_day_clicks: int,
    selected_hour: int | None,
    current_hour: int | None,
    max_hour: int | None,
):
    trigger = ctx.triggered_id
    current = int(current_hour or 1)
    max_hour = int(max_hour or 1)
    if trigger == "case-store":
        return 1
    if trigger == "hour-prev-day":
        return max(1, current - 24)
    if trigger == "hour-prev":
        return max(1, current - 1)
    if trigger == "hour-next":
        return min(max_hour, current + 1)
    if trigger == "hour-next-day":
        return min(max_hour, current + 24)
    if trigger == "interesting-hour-dropdown" and selected_hour is not None:
        return int(selected_hour)
    if current_hour is not None:
        return current
    return no_update


@app.callback(
    Output("download-hour", "data"),
    Input("export-hour", "n_clicks"),
    State("case-store", "data"),
    State("hour-slider", "value"),
    prevent_initial_call=True,
)
def export_hour_snapshot(_n_clicks: int, case_path: str, hour: int):
    case = load_case(case_path, refresh=False)
    hour = int(hour or 1)
    bus_rows = case.nodal_price[case.nodal_price["Hour"] == hour].copy()
    line_rows = case.line_hourly[case.line_hourly["Hour"] == hour].copy()
    system_rows = case.system_hourly[case.system_hourly["Hour"] == hour].copy()

    export_cols = [
        "RecordType", "Hour", "Bus", "Zone", "LMP", "Energy", "Congestion", "Loss",
        "Line", "From_bus", "To_bus", "Flow_MW", "Loading_pct", "ShadowPrice",
        "CongestionRent", "LineLoss_MW", "TransmissionLoss_MW",
    ]

    bus_export = pd.DataFrame({
        "RecordType": "Bus",
        "Hour": bus_rows["Hour"],
        "Bus": bus_rows["Bus"],
        "Zone": bus_rows["Zone"],
        "LMP": bus_rows["LMP"],
        "Energy": bus_rows["Energy"],
        "Congestion": bus_rows["Congestion"],
        "Loss": bus_rows["Loss"],
    }).reindex(columns=export_cols)

    line_export = pd.DataFrame({
        "RecordType": "Line",
        "Hour": line_rows["Hour"],
        "Line": line_rows["Line"],
        "From_bus": line_rows["From_bus"],
        "To_bus": line_rows["To_bus"],
        "Flow_MW": line_rows["Flow_MW"],
        "Loading_pct": line_rows["Loading_pct"],
        "ShadowPrice": line_rows["ShadowPrice"],
        "CongestionRent": line_rows["CongestionRent"],
        "LineLoss_MW": line_rows["LineLoss_MW"],
    }).reindex(columns=export_cols)

    system_export = pd.DataFrame({
        "RecordType": ["System"] * len(system_rows),
        "Hour": system_rows["Hour"],
        "TransmissionLoss_MW": system_rows["TransmissionLoss_MW"],
    }).reindex(columns=export_cols)

    export_df = pd.concat([bus_export, line_export, system_export], ignore_index=True)
    filename = f"{case.case_path.name}_hour_{hour}_snapshot.csv"
    return dcc.send_data_frame(export_df.to_csv, filename, index=False)


@app.callback(
    Output("download-analysis", "data"),
    Input("export-analysis", "n_clicks"),
    State("case-store", "data"),
    State("bus-dropdown", "value"),
    State("compare-bus-dropdown", "value"),
    State("ref-bus-dropdown", "value"),
    State("rank-metric-dropdown", "value"),
    State("selected-line-store", "data"),
    State("hour-slider", "value"),
    prevent_initial_call=True,
)
def export_analysis_snapshot(
    _n_clicks: int,
    case_path: str,
    bus: str,
    compare_bus: str,
    ref_bus: str,
    rank_metric: str,
    selected_line: int | None,
    hour: int,
):
    case = load_case(case_path, refresh=False)
    bus = str(bus)
    compare_bus = str(compare_bus)
    ref_bus = str(ref_bus)
    selected_line = _resolve_selected_line(case, int(hour or 1), str(rank_metric), selected_line)

    focus = case.nodal_price[case.nodal_price["Bus"] == bus][["Hour", "LMP", "Energy", "Congestion", "Loss"]].copy()
    focus = focus.rename(columns={
        "LMP": "FocusLMP",
        "Energy": "FocusEnergy",
        "Congestion": "FocusCongestion",
        "Loss": "FocusLoss",
    })
    focus["FocusBus"] = bus

    compare = case.nodal_price[case.nodal_price["Bus"] == compare_bus][["Hour", "LMP"]].copy()
    compare = compare.rename(columns={"LMP": "CompareLMP"})
    compare["CompareBus"] = compare_bus

    ref = case.nodal_price[case.nodal_price["Bus"] == ref_bus][["Hour", "LMP"]].copy()
    ref = ref.rename(columns={"LMP": "ReferenceLMP"})
    ref["ReferenceBus"] = ref_bus

    merged = focus.merge(compare, on="Hour", how="left").merge(ref, on="Hour", how="left")
    merged["Basis_FocusMinusCompare"] = merged["FocusLMP"] - merged["CompareLMP"]

    system = case.system_hourly[["Hour", "TransmissionLoss_MW"]].copy()
    merged = merged.merge(system, on="Hour", how="left")

    if selected_line is not None:
        line = case.line_hourly[case.line_hourly["Line"].astype(int) == int(selected_line)][
            ["Hour", "Line", "From_bus", "To_bus", "Flow_MW", "Loading_pct", "ShadowPrice", "CongestionRent", "LineLoss_MW"]
        ].copy()
        line = line.rename(columns={
            "Line": "SelectedLine",
            "From_bus": "SelectedLineFromBus",
            "To_bus": "SelectedLineToBus",
            "Flow_MW": "SelectedLineFlow_MW",
            "Loading_pct": "SelectedLineLoading_pct",
            "ShadowPrice": "SelectedLineShadowPrice",
            "CongestionRent": "SelectedLineCongestionRent",
            "LineLoss_MW": "SelectedLineLoss_MW",
        })
        merged = merged.merge(line, on="Hour", how="left")

    filename = f"{case.case_path.name}_{bus}_vs_{compare_bus}_analysis.csv"
    return dcc.send_data_frame(merged.to_csv, filename, index=False)


@app.callback(
    Output("kpi", "children"),
    Output("line-detail", "children"),
    Output("network-graph", "figure"),
    Output("bus-ts", "figure"),
    Output("line-rank", "figure"),
    Input("hour-slider", "value"),
    Input("bus-dropdown", "value"),
    Input("ref-bus-dropdown", "value"),
    Input("compare-bus-dropdown", "value"),
    Input("map-layer-dropdown", "value"),
    Input("rank-metric-dropdown", "value"),
    Input("case-store", "data"),
    Input("theme-store", "data"),
    Input("selected-line-store", "data"),
)
def refresh_views(hour: int, bus: str, ref_bus: str, compare_bus: str, map_layer: str, rank_metric: str, case_path: str, theme: str, selected_line: int | None):
    case = load_case(case_path, refresh=False)
    bus_list = sorted(case.nodal_price["Bus"].astype(str).unique().tolist())
    if bus is None:
        bus = bus_list[0]
    if ref_bus is None:
        ref_bus = bus
    if compare_bus is None:
        compare_bus = bus_list[1] if len(bus_list) > 1 else bus
    hourly_line = case.line_hourly[case.line_hourly["Hour"] == int(hour)].copy()
    hourly_line["abs_shadow"] = hourly_line["ShadowPrice"].abs()
    hourly_line["abs_rent"] = hourly_line["CongestionRent"].abs()
    if selected_line is None or selected_line not in hourly_line["Line"].astype(int).tolist():
        metric_col, _, _, _ = _line_metric_spec(str(rank_metric))
        selected_line = int(hourly_line.sort_values(metric_col, ascending=False).iloc[0]["Line"]) if not hourly_line.empty else None
    kpi = _kpi_block(case, int(hour), str(bus), str(compare_bus))
    line_detail = _selected_line_detail(case, int(hour), selected_line, str(rank_metric))
    network_fig = _network_figure(case, int(hour), str(bus), str(ref_bus), str(map_layer), str(theme), selected_line)
    ts_fig = _timeseries_figure(case, str(bus), str(compare_bus), str(ref_bus), str(theme))
    line_fig = _line_ranking_figure(case, int(hour), str(rank_metric), str(theme), selected_line)
    return kpi, line_detail, network_fig, ts_fig, line_fig


if __name__ == "__main__":
    app.run(debug=True, host="127.0.0.1", port=8050)
