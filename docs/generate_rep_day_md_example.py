from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd


ROOT = Path(__file__).resolve().parents[1]
CASE = ROOT / "ModelCases" / "MD_GTEP_clean_case" / "Data_100RPS" / "load_timeseries_regional.csv"
OUT_FEATURE1 = ROOT / "docs" / "src" / "assets" / "rep_day_md_case_example.png"
OUT_FEATURE2 = ROOT / "docs" / "src" / "assets" / "rep_day_md_case_feature2.png"
OUT_FEATURE3 = ROOT / "docs" / "src" / "assets" / "rep_day_md_case_feature3.png"
OUT_FEATURE4 = ROOT / "docs" / "src" / "assets" / "rep_day_md_case_feature4.png"
OUT_FEATURE5 = ROOT / "docs" / "src" / "assets" / "rep_day_md_case_feature5.png"
OUT_FEATURE6 = ROOT / "docs" / "src" / "assets" / "rep_day_md_case_feature6.png"
GENDATA = ROOT / "ModelCases" / "MD_GTEP_clean_case" / "Data_100RPS" / "gendata.csv"
GENDATA_CAND = ROOT / "ModelCases" / "MD_GTEP_clean_case" / "Data_100RPS" / "gendata_candidate.csv"
AFDATA = ROOT / "ModelCases" / "MD_GTEP_clean_case" / "Data_100RPS" / "gen_availability_timeseries.csv"

TIME_PERIODS = {
    1: (3, 20, 6, 20, "Mar 20 to Jun 20", (5, 19), 93),
    2: (6, 21, 9, 21, "Jun 21 to Sep 21", (8, 31), 93),
    3: (9, 22, 12, 20, "Sep 22 to Dec 20", (12, 7), 90),
    4: (12, 21, 3, 19, "Dec 21 to Mar 19", (1, 13), 89),
}

TIME_PERIODS_FEATURE2 = {
    1: (3, 20, 6, 20, "Mar 20 to Jun 20", [((4, 22), 45), ((5, 7), 48)]),
    2: (6, 21, 9, 21, "Jun 21 to Sep 21", [((7, 29), 54), ((8, 15), 39)]),
    3: (9, 22, 12, 20, "Sep 22 to Dec 20", [((10, 28), 38), ((11, 26), 52)]),
    4: (12, 21, 3, 19, "Dec 21 to Mar 19", [((1, 28), 64), ((3, 18), 25)]),
}

TIME_PERIODS_FEATURE3 = {
    1: (3, 20, 6, 20, "Mar 20 to Jun 20", {"medoid": ((5, 27), 90), "peak_load": ((3, 20), 1), "peak_net_load": ((4, 1), 1), "max_ramp": ((4, 11), 1)}),
    2: (6, 21, 9, 21, "Jun 21 to Sep 21", {"medoid": ((9, 17), 90), "peak_load": ((6, 21), 1), "peak_net_load": ((9, 10), 1), "max_ramp": ((8, 4), 1)}),
    3: (9, 22, 12, 20, "Sep 22 to Dec 20", {"medoid": ((11, 3), 87), "peak_load": ((9, 22), 1), "peak_net_load": ((10, 8), 1), "max_ramp": ((12, 5), 1)}),
    4: (12, 21, 3, 19, "Dec 21 to Mar 19", {"medoid": ((2, 12), 86), "peak_load": ((1, 1), 1), "peak_net_load": ((3, 11), 1), "max_ramp": ((1, 19), 1)}),
}

TIME_PERIODS_FEATURE4 = {
    1: (3, 20, 6, 20, "Mar 20 to Jun 20", (5, 27), 93),
    2: (6, 21, 9, 21, "Jun 21 to Sep 21", (7, 8), 93),
    3: (9, 22, 12, 20, "Sep 22 to Dec 20", (12, 7), 90),
    4: (12, 21, 3, 19, "Dec 21 to Mar 19", (1, 13), 89),
}

TIME_PERIODS_FEATURE5 = {
    1: (3, 20, 6, 20, "Mar 20 to Jun 20", {"medoid": ((5, 27), 89), "peak_load": ((6, 17), 1), "peak_net_load": ((4, 1), 1), "max_ramp": ((4, 11), 1), "refinement": ((5, 29), 1)}),
    2: (6, 21, 9, 21, "Jun 21 to Sep 21", {"medoid": ((7, 8), 89), "peak_load": ((8, 9), 1), "peak_net_load": ((9, 10), 1), "max_ramp": ((8, 4), 1), "refinement": ((7, 9), 1)}),
    3: (9, 22, 12, 20, "Sep 22 to Dec 20", {"medoid": ((12, 7), 86), "peak_load": ((12, 14), 1), "peak_net_load": ((10, 8), 1), "max_ramp": ((12, 5), 1), "refinement": ((12, 17), 1)}),
    4: (12, 21, 3, 19, "Dec 21 to Mar 19", {"medoid": ((1, 13), 85), "peak_load": ((1, 27), 1), "peak_net_load": ((3, 11), 1), "max_ramp": ((1, 19), 1), "refinement": ((12, 23), 1)}),
}

TIME_PERIODS_FEATURE6 = {
    1: (3, 20, 6, 20, "Mar 20 to Jun 20", {"medoid": ((5, 27), 89), "peak_load": ((6, 17), 1), "peak_net_load": ((4, 1), 1), "max_ramp": ((4, 11), 1), "refinement": ((5, 29), 1)}, "Medoid predecessors:\nself 94.4%, winter medoid 1.1%\nadded days 4 x 1.1%"),
    2: (6, 21, 9, 21, "Jun 21 to Sep 21", {"medoid": ((7, 8), 89), "peak_load": ((8, 9), 1), "peak_net_load": ((9, 10), 1), "max_ramp": ((8, 4), 1), "refinement": ((7, 9), 1)}, "Medoid predecessors:\nself 94.4%, spring medoid 1.1%\nadded days 4 x 1.1%"),
    3: (9, 22, 12, 20, "Sep 22 to Dec 20", {"medoid": ((12, 7), 86), "peak_load": ((12, 14), 1), "peak_net_load": ((10, 8), 1), "max_ramp": ((12, 5), 1), "refinement": ((12, 17), 1)}, "Medoid predecessors:\nself 94.2%, summer medoid 1.2%\nadded days 4 x 1.2%"),
    4: (12, 21, 3, 19, "Dec 21 to Mar 19", {"medoid": ((1, 13), 85), "peak_load": ((1, 27), 1), "peak_net_load": ((3, 11), 1), "max_ramp": ((1, 19), 1), "refinement": ((12, 23), 1)}, "Medoid predecessors:\nself 94.1%, fall medoid 1.2%\nadded days 4 x 1.2%"),
}


def day_of_year(month: int, day: int) -> int:
    return pd.Timestamp(year=2021, month=month, day=day).dayofyear


def in_window(month: int, day: int, spec) -> bool:
    sm, sd, em, ed = spec[:4]
    start = day_of_year(sm, sd)
    end = day_of_year(em, ed)
    cur = day_of_year(month, day)
    if start <= end:
        return start <= cur <= end
    return cur >= start or cur <= end


def prepare_load_df() -> pd.DataFrame:
    df = pd.read_csv(CASE)
    zone_cols = [c for c in df.columns if c not in {"Time Period", "Month", "Day", "Hours", "NI"}]
    df["system_load"] = df[zone_cols].sum(axis=1)
    return df


def prepare_feature4_daily_metrics() -> pd.DataFrame:
    load_df = pd.read_csv(CASE)
    af_df = pd.read_csv(AFDATA)
    gen_existing = pd.read_csv(GENDATA)
    gen_candidate = pd.read_csv(GENDATA_CAND)
    gen_df = pd.concat([gen_existing, gen_candidate], ignore_index=True)
    zone_cols = [c for c in load_df.columns if c not in {"Time Period", "Month", "Day", "Hours", "NI"}]

    wind_zone_map = {z: [] for z in zone_cols}
    solar_zone_map = {z: [] for z in zone_cols}
    for idx, row in gen_df.iterrows():
        col = f"G{idx + 1}"
        if col not in af_df.columns:
            continue
        zone = str(row["Zone"])
        tech = str(row["Type"]).strip().lower()
        pmax = float(row["Pmax (MW)"])
        if zone not in wind_zone_map:
            continue
        if tech in {"windon", "windoff"}:
            wind_zone_map[zone].append((col, pmax))
        elif tech == "solarpv":
            solar_zone_map[zone].append((col, pmax))

    rows = []
    for (month, day), block in load_df.groupby(["Month", "Day"], sort=False):
        system_load_hourly = block[zone_cols].sum(axis=1).to_numpy()
        ni = block["NI"].to_numpy() if "NI" in block.columns else 0.0
        system_wind = 0.0 * system_load_hourly
        system_solar = 0.0 * system_load_hourly
        for zone in zone_cols:
            if wind_zone_map[zone]:
                cols, weights = zip(*wind_zone_map[zone])
                weights = pd.Series(weights, dtype=float).to_numpy()
                system_wind += af_df.loc[block.index, list(cols)].to_numpy() @ (weights / weights.sum())
            if solar_zone_map[zone]:
                cols, weights = zip(*solar_zone_map[zone])
                weights = pd.Series(weights, dtype=float).to_numpy()
                system_solar += af_df.loc[block.index, list(cols)].to_numpy() @ (weights / weights.sum())
        system_net = system_load_hourly - ni - system_wind - system_solar
        system_ramp = pd.Series(system_net).diff().fillna(0.0).to_numpy()
        rows.append(
            {
                "Month": int(month),
                "Day": int(day),
                "peak_system_load": float(system_load_hourly.max()),
                "peak_system_net_load": float(system_net.max()),
                "max_system_ramp": float(system_ramp.max()),
            }
        )
    return pd.DataFrame(rows)


def plot_feature1(df: pd.DataFrame) -> None:
    fig, axes = plt.subplots(
        nrows=4,
        ncols=2,
        figsize=(14, 14),
        gridspec_kw={"width_ratios": [1.1, 1.0]},
        constrained_layout=True,
    )
    fig.suptitle(
        "Feature 1: Joint Medoid Representative-Day Selection in MD_GTEP_clean_case\n"
        "One actual observed day is selected per seasonal window using joint load + AF features",
        fontsize=18,
        fontweight="bold",
    )

    for row_idx, period in enumerate([1, 2, 3, 4]):
        spec = TIME_PERIODS[period]
        selected_month, selected_day = spec[5]
        weight_days = spec[6]
        season = df[df.apply(lambda r: in_window(int(r["Month"]), int(r["Day"]), spec), axis=1)].copy()
        season["date_key"] = list(zip(season["Month"], season["Day"]))

        daily = (
            season.groupby(["Month", "Day"], sort=False)["system_load"]
            .sum()
            .reset_index()
        )
        daily["season_day_idx"] = range(1, len(daily) + 1)
        daily["label"] = daily.apply(lambda r: f"{int(r['Month'])}/{int(r['Day'])}", axis=1)
        selected_mask = (daily["Month"] == selected_month) & (daily["Day"] == selected_day)
        selected_daily = daily[selected_mask].iloc[0]

        ax_left = axes[row_idx, 0]
        ax_left.plot(daily["season_day_idx"], daily["system_load"], color="#a7b6c2", lw=1.8)
        ax_left.scatter(
            daily["season_day_idx"],
            daily["system_load"],
            s=18,
            color="#c7d2db",
            zorder=2,
        )
        ax_left.scatter(
            [selected_daily["season_day_idx"]],
            [selected_daily["system_load"]],
            s=85,
            color="#c84b31",
            zorder=3,
        )
        ax_left.axvline(selected_daily["season_day_idx"], color="#c84b31", lw=1.5, ls="--", alpha=0.8)
        ax_left.set_title(f"Period {period}: {spec[4]}", fontsize=12, loc="left")
        ax_left.set_ylabel("Daily total load")
        ax_left.grid(alpha=0.18)
        ax_left.text(
            0.98,
            0.92,
            f"Selected: {selected_month}/{selected_day}\nWeight = {weight_days} days",
            ha="right",
            va="top",
            transform=ax_left.transAxes,
            fontsize=10,
            bbox=dict(boxstyle="round,pad=0.3", fc="#fff6ef", ec="#e1b382"),
        )
        if row_idx == 3:
            ax_left.set_xlabel("Day index within seasonal window")

        ax_right = axes[row_idx, 1]
        for (_, _), block in season.groupby(["Month", "Day"], sort=False):
            ax_right.plot(block["Hours"], block["system_load"], color="#cfd8df", lw=0.8, alpha=0.45)
        selected_profile = season[(season["Month"] == selected_month) & (season["Day"] == selected_day)]
        ax_right.plot(
            selected_profile["Hours"],
            selected_profile["system_load"],
            color="#c84b31",
            lw=2.4,
            label=f"Selected {selected_month}/{selected_day}",
        )
        seasonal_mean = season.groupby("Hours", sort=True)["system_load"].mean().reset_index()
        ax_right.plot(
            seasonal_mean["Hours"],
            seasonal_mean["system_load"],
            color="#2a5b84",
            lw=1.6,
            ls="--",
            label="Seasonal mean",
        )
        ax_right.set_title("24-hour total load profile", fontsize=12, loc="left")
        ax_right.set_ylabel("System load")
        ax_right.set_xlim(1, 24)
        ax_right.grid(alpha=0.18)
        ax_right.legend(loc="upper right", fontsize=9, frameon=True)
        if row_idx == 3:
            ax_right.set_xlabel("Hour of day")

    fig.savefig(OUT_FEATURE1, dpi=180, bbox_inches="tight")
    plt.close(fig)


def plot_feature2(df: pd.DataFrame) -> None:
    selected_colors = ["#c84b31", "#d98f2b"]
    fig, axes = plt.subplots(
        nrows=4,
        ncols=2,
        figsize=(15, 14.5),
        gridspec_kw={"width_ratios": [1.1, 1.0]},
        constrained_layout=True,
    )
    fig.suptitle(
        "Feature 2: Multiple Representative Days per Time Period in MD_GTEP_clean_case\n"
        "Two actual observed days are selected per seasonal window using joint load + AF features",
        fontsize=18,
        fontweight="bold",
    )

    for row_idx, period in enumerate([1, 2, 3, 4]):
        spec = TIME_PERIODS_FEATURE2[period]
        season = df[df.apply(lambda r: in_window(int(r["Month"]), int(r["Day"]), spec), axis=1)].copy()
        daily = (
            season.groupby(["Month", "Day"], sort=False)["system_load"]
            .sum()
            .reset_index()
        )
        daily["season_day_idx"] = range(1, len(daily) + 1)

        ax_left = axes[row_idx, 0]
        ax_left.plot(daily["season_day_idx"], daily["system_load"], color="#a7b6c2", lw=1.8)
        ax_left.scatter(
            daily["season_day_idx"],
            daily["system_load"],
            s=18,
            color="#c7d2db",
            zorder=2,
        )
        ax_left.set_title(f"Period {period}: {spec[4]}", fontsize=12, loc="left")
        ax_left.set_ylabel("Daily total load")
        ax_left.grid(alpha=0.18)

        note_lines = []
        for idx, (date_key, weight_days) in enumerate(spec[5], start=1):
            month, day = date_key
            selected_row = daily[(daily["Month"] == month) & (daily["Day"] == day)].iloc[0]
            ax_left.scatter(
                [selected_row["season_day_idx"]],
                [selected_row["system_load"]],
                s=90,
                color=selected_colors[idx - 1],
                zorder=3,
            )
            ax_left.axvline(selected_row["season_day_idx"], color=selected_colors[idx - 1], lw=1.4, ls="--", alpha=0.8)
            note_lines.append(f"Rep {idx}: {month}/{day} (w={weight_days})")
        ax_left.text(
            0.98,
            0.92,
            "\n".join(note_lines),
            ha="right",
            va="top",
            transform=ax_left.transAxes,
            fontsize=9.5,
            bbox=dict(boxstyle="round,pad=0.3", fc="#fff6ef", ec="#e1b382"),
        )
        if row_idx == 3:
            ax_left.set_xlabel("Day index within seasonal window")

        ax_right = axes[row_idx, 1]
        for (_, _), block in season.groupby(["Month", "Day"], sort=False):
            ax_right.plot(block["Hours"], block["system_load"], color="#cfd8df", lw=0.8, alpha=0.45)
        for idx, (date_key, _) in enumerate(spec[5], start=1):
            month, day = date_key
            selected_profile = season[(season["Month"] == month) & (season["Day"] == day)]
            ax_right.plot(
                selected_profile["Hours"],
                selected_profile["system_load"],
                color=selected_colors[idx - 1],
                lw=2.4,
                label=f"Rep {idx}: {month}/{day}",
            )
        seasonal_mean = season.groupby("Hours", sort=True)["system_load"].mean().reset_index()
        ax_right.plot(
            seasonal_mean["Hours"],
            seasonal_mean["system_load"],
            color="#2a5b84",
            lw=1.6,
            ls="--",
            label="Seasonal mean",
        )
        ax_right.set_title("24-hour total load profiles", fontsize=12, loc="left")
        ax_right.set_ylabel("System load")
        ax_right.set_xlim(1, 24)
        ax_right.grid(alpha=0.18)
        ax_right.legend(loc="upper right", fontsize=8.5, frameon=True)
        if row_idx == 3:
            ax_right.set_xlabel("Hour of day")

    fig.savefig(OUT_FEATURE2, dpi=180, bbox_inches="tight")
    plt.close(fig)


def plot_feature3(df: pd.DataFrame) -> None:
    colors = {
        "medoid": "#2a5b84",
        "peak_load": "#c84b31",
        "peak_net_load": "#3f8f5a",
        "max_ramp": "#d98f2b",
    }
    labels = {
        "medoid": "Medoid",
        "peak_load": "Peak load",
        "peak_net_load": "Peak net load",
        "max_ramp": "Max ramp",
    }
    fig, axes = plt.subplots(nrows=2, ncols=2, figsize=(11.2, 7.4), constrained_layout=True)
    fig.suptitle(
        "Feature 3: Extreme-Day Augmentation in MD_GTEP_clean_case\n"
        "One medoid day per season plus added extreme days with weight 1",
        fontsize=15,
        fontweight="bold",
    )

    for ax, period in zip(axes.flatten(), [1, 2, 3, 4]):
        spec = TIME_PERIODS_FEATURE3[period]
        season = df[df.apply(lambda r: in_window(int(r["Month"]), int(r["Day"]), spec), axis=1)].copy()
        daily = (
            season.groupby(["Month", "Day"], sort=False)["system_load"]
            .sum()
            .reset_index()
        )
        daily["season_day_idx"] = range(1, len(daily) + 1)
        ax.plot(daily["season_day_idx"], daily["system_load"], color="#bfc9d2", lw=1.4)
        ax.scatter(daily["season_day_idx"], daily["system_load"], s=12, color="#d8dfe5", zorder=1)
        ax.set_title(f"Period {period}: {spec[4]}", fontsize=11, loc="left")
        ax.grid(alpha=0.18)

        text_lines = []
        for key in ["medoid", "peak_load", "peak_net_load", "max_ramp"]:
            (month, day), weight = spec[5][key]
            selected_row = daily[(daily["Month"] == month) & (daily["Day"] == day)].iloc[0]
            ax.scatter(
                [selected_row["season_day_idx"]],
                [selected_row["system_load"]],
                s=65 if key == "medoid" else 48,
                color=colors[key],
                zorder=3,
                label=labels[key],
            )
            ax.axvline(selected_row["season_day_idx"], color=colors[key], lw=1.0, ls="--", alpha=0.75)
            weight_label = f"w={weight}" if key == "medoid" else "w=1"
            text_lines.append(f"{labels[key]}: {month}/{day} ({weight_label})")

        ax.text(
            0.98,
            0.97,
            "\n".join(text_lines),
            ha="right",
            va="top",
            transform=ax.transAxes,
            fontsize=8.2,
            bbox=dict(boxstyle="round,pad=0.25", fc="#ffffff", ec="#d8dfe5"),
        )
        ax.set_ylabel("Daily total load", fontsize=9)
        ax.set_xlabel("Day index in seasonal window", fontsize=9)
        handles, handle_labels = ax.get_legend_handles_labels()
        by_label = dict(zip(handle_labels, handles))
        ax.legend(by_label.values(), by_label.keys(), loc="lower left", fontsize=7.8, frameon=True, ncol=2)

    fig.savefig(OUT_FEATURE3, dpi=180, bbox_inches="tight")
    plt.close(fig)


def plot_feature4(df: pd.DataFrame) -> None:
    daily_metrics = prepare_feature4_daily_metrics()
    fig, axes = plt.subplots(nrows=2, ncols=2, figsize=(10.5, 6.9), constrained_layout=True)
    fig.suptitle(
        "Feature 4: Planning-Focused Feature Engineering in MD_GTEP_clean_case\n"
        "Clustering uses compact planning signals instead of raw hourly generator columns",
        fontsize=14.5,
        fontweight="bold",
    )

    for ax, period in zip(axes.flatten(), [1, 2, 3, 4]):
        spec = TIME_PERIODS_FEATURE4[period]
        selected_month, selected_day = spec[5]
        season = daily_metrics[daily_metrics.apply(lambda r: in_window(int(r["Month"]), int(r["Day"]), spec), axis=1)].copy()
        season["season_day_idx"] = range(1, len(season) + 1)
        selected = season[(season["Month"] == selected_month) & (season["Day"] == selected_day)].iloc[0]

        ax.plot(season["season_day_idx"], season["peak_system_load"], color="#c8d0d8", lw=1.5, label="Peak system load")
        ax.plot(season["season_day_idx"], season["peak_system_net_load"], color="#2a5b84", lw=1.7, label="Peak system net load")
        ax.plot(season["season_day_idx"], season["max_system_ramp"], color="#d98f2b", lw=1.4, label="Max system ramp")
        ax.axvline(selected["season_day_idx"], color="#c84b31", lw=1.5, ls="--")
        ax.scatter([selected["season_day_idx"]], [selected["peak_system_net_load"]], s=60, color="#c84b31", zorder=4)
        ax.set_title(f"Period {period}: {spec[4]}", fontsize=11, loc="left")
        ax.grid(alpha=0.18)
        ax.text(
            0.98,
            0.96,
            f"Selected: {selected_month}/{selected_day}\nWeight = {spec[6]}",
            ha="right",
            va="top",
            transform=ax.transAxes,
            fontsize=8.4,
            bbox=dict(boxstyle="round,pad=0.25", fc="#ffffff", ec="#d8dfe5"),
        )
        ax.set_ylabel("MW", fontsize=9)
        ax.set_xlabel("Day index in seasonal window", fontsize=9)
        ax.legend(loc="lower left", fontsize=7.4, frameon=True)

    fig.savefig(OUT_FEATURE4, dpi=180, bbox_inches="tight")
    plt.close(fig)


def plot_feature5(df: pd.DataFrame) -> None:
    daily_metrics = prepare_feature4_daily_metrics()
    colors = {
        "medoid": "#2a5b84",
        "peak_load": "#c84b31",
        "peak_net_load": "#3f8f5a",
        "max_ramp": "#d98f2b",
        "refinement": "#7b5ea7",
    }
    labels = {
        "medoid": "Medoid",
        "peak_load": "Peak load",
        "peak_net_load": "Peak net load",
        "max_ramp": "Max ramp",
        "refinement": "Refinement",
    }
    fig, axes = plt.subplots(nrows=2, ncols=2, figsize=(10.5, 6.9), constrained_layout=True)
    fig.suptitle(
        "Feature 5: Iterative Representative-Day Refinement in MD_GTEP_clean_case\n"
        "One extra day is added where the current representative set still leaves the largest mismatch",
        fontsize=14.5,
        fontweight="bold",
    )

    for ax, period in zip(axes.flatten(), [1, 2, 3, 4]):
        spec = TIME_PERIODS_FEATURE5[period]
        season = daily_metrics[daily_metrics.apply(lambda r: in_window(int(r["Month"]), int(r["Day"]), spec), axis=1)].copy()
        season["season_day_idx"] = range(1, len(season) + 1)
        ax.plot(season["season_day_idx"], season["peak_system_net_load"], color="#c8d0d8", lw=1.6)
        ax.set_title(f"Period {period}: {spec[4]}", fontsize=11, loc="left")
        ax.grid(alpha=0.18)

        text_lines = []
        for key in ["medoid", "peak_load", "peak_net_load", "max_ramp", "refinement"]:
            (month, day), weight = spec[5][key]
            selected = season[(season["Month"] == month) & (season["Day"] == day)].iloc[0]
            ax.scatter(
                [selected["season_day_idx"]],
                [selected["peak_system_net_load"]],
                s=62 if key in {"medoid", "refinement"} else 46,
                color=colors[key],
                zorder=4,
                label=labels[key],
            )
            ax.axvline(selected["season_day_idx"], color=colors[key], lw=1.0, ls="--", alpha=0.72)
            weight_label = f"w={weight}"
            text_lines.append(f"{labels[key]}: {month}/{day} ({weight_label})")

        ax.text(
            0.98,
            0.97,
            "\n".join(text_lines),
            ha="right",
            va="top",
            transform=ax.transAxes,
            fontsize=8.0,
            bbox=dict(boxstyle="round,pad=0.22", fc="#ffffff", ec="#d8dfe5"),
        )
        ax.set_ylabel("Daily peak system net load", fontsize=9)
        ax.set_xlabel("Day index in seasonal window", fontsize=9)
        handles, handle_labels = ax.get_legend_handles_labels()
        by_label = dict(zip(handle_labels, handles))
        ax.legend(by_label.values(), by_label.keys(), loc="lower left", fontsize=7.2, frameon=True, ncol=2)

    fig.savefig(OUT_FEATURE5, dpi=180, bbox_inches="tight")
    plt.close(fig)


def plot_feature6(df: pd.DataFrame) -> None:
    colors = {
        "medoid": "#2a5b84",
        "peak_load": "#c84b31",
        "peak_net_load": "#3f8f5a",
        "max_ramp": "#d98f2b",
        "refinement": "#7b5ea7",
    }
    fig, axes = plt.subplots(nrows=2, ncols=2, figsize=(10.5, 6.7), constrained_layout=True)
    fig.suptitle(
        "Feature 6: Linked Representative Days for Storage in MD_GTEP_clean_case\n"
        "Long-duration storage uses actual day-to-representative mapping to build predecessor weights",
        fontsize=14.3,
        fontweight="bold",
    )

    for ax, period in zip(axes.flatten(), [1, 2, 3, 4]):
        spec = TIME_PERIODS_FEATURE6[period]
        season = df[df.apply(lambda r: in_window(int(r["Month"]), int(r["Day"]), spec), axis=1)].copy()
        daily = season.groupby(["Month", "Day"], sort=False)["system_load"].sum().reset_index()
        daily["season_day_idx"] = range(1, len(daily) + 1)
        daily["assigned"] = "medoid"
        for key in ["peak_load", "peak_net_load", "max_ramp", "refinement"]:
            month, day = spec[5][key][0]
            daily.loc[(daily["Month"] == month) & (daily["Day"] == day), "assigned"] = key

        ax.plot(daily["season_day_idx"], [0.5] * len(daily), color="#d8dfe5", lw=10, solid_capstyle="butt", zorder=1)
        for key, color in colors.items():
            mask = daily["assigned"] == key
            if mask.any():
                ax.scatter(daily.loc[mask, "season_day_idx"], [0.5] * mask.sum(), s=58, color=color, marker="s", zorder=3)

        medoid_month, medoid_day = spec[5]["medoid"][0]
        medoid_row = daily[(daily["Month"] == medoid_month) & (daily["Day"] == medoid_day)].iloc[0]
        ax.axvline(medoid_row["season_day_idx"], color=colors["medoid"], lw=1.2, ls="--", alpha=0.75)
        ax.set_title(f"Period {period}: {spec[4]}", fontsize=11, loc="left")
        ax.set_xlim(0, len(daily) + 1)
        ax.set_ylim(0.1, 0.9)
        ax.set_yticks([])
        ax.grid(axis="x", alpha=0.12)
        ax.set_xlabel("Day index in seasonal window", fontsize=9)
        ax.text(
            0.98,
            0.94,
            spec[6],
            ha="right",
            va="top",
            transform=ax.transAxes,
            fontsize=8.1,
            bbox=dict(boxstyle="round,pad=0.24", fc="#ffffff", ec="#d8dfe5"),
        )

    fig.savefig(OUT_FEATURE6, dpi=180, bbox_inches="tight")
    plt.close(fig)


def main() -> None:
    df = prepare_load_df()
    plot_feature1(df)
    plot_feature2(df)
    plot_feature3(df)
    plot_feature4(df)
    plot_feature5(df)
    plot_feature6(df)
    print(OUT_FEATURE1)
    print(OUT_FEATURE2)
    print(OUT_FEATURE3)
    print(OUT_FEATURE4)
    print(OUT_FEATURE5)
    print(OUT_FEATURE6)


if __name__ == "__main__":
    main()
