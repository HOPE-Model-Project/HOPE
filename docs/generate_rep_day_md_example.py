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


def main() -> None:
    df = prepare_load_df()
    plot_feature1(df)
    plot_feature2(df)
    plot_feature3(df)
    print(OUT_FEATURE1)
    print(OUT_FEATURE2)
    print(OUT_FEATURE3)


if __name__ == "__main__":
    main()
