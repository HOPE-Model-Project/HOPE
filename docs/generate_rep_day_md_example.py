from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd


ROOT = Path(__file__).resolve().parents[1]
CASE = ROOT / "ModelCases" / "MD_GTEP_clean_case" / "Data_100RPS" / "load_timeseries_regional.csv"
OUT = ROOT / "docs" / "src" / "assets" / "rep_day_md_case_example.png"

TIME_PERIODS = {
    1: (3, 20, 6, 20, "Mar 20 to Jun 20", (5, 19), 93),
    2: (6, 21, 9, 21, "Jun 21 to Sep 21", (8, 31), 93),
    3: (9, 22, 12, 20, "Sep 22 to Dec 20", (12, 7), 90),
    4: (12, 21, 3, 19, "Dec 21 to Mar 19", (1, 13), 89),
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


def main() -> None:
    df = pd.read_csv(CASE)
    zone_cols = [c for c in df.columns if c not in {"Time Period", "Month", "Day", "Hours", "NI"}]
    df["system_load"] = df[zone_cols].sum(axis=1)

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

    fig.savefig(OUT, dpi=180, bbox_inches="tight")
    print(OUT)


if __name__ == "__main__":
    main()
