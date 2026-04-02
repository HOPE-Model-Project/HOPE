from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd


ROOT = Path(__file__).resolve().parents[1]
CASE = ROOT / "ModelCases" / "MD_GTEP_clean_case" / "Data_100RPS" / "load_timeseries_regional.csv"
OUT_FEATURE1 = ROOT / "docs" / "src" / "assets" / "rep_day_md_case_example.png"
OUT_FEATURE2 = ROOT / "docs" / "src" / "assets" / "rep_day_md_case_feature2.png"

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


def main() -> None:
    df = prepare_load_df()
    plot_feature1(df)
    plot_feature2(df)
    print(OUT_FEATURE1)
    print(OUT_FEATURE2)


if __name__ == "__main__":
    main()
