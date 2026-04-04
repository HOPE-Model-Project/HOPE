from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd


ROOT = Path(r"e:\MIT Dropbox\Shen Wang\MIT\RA\HOPE_project")
ASSET_DIR = ROOT / "docs" / "src" / "assets"


def gtep_data():
    cases = {
        "Original": "MD_GTEP_clean_case_methods_original",
        "Basic": "MD_GTEP_clean_case_methods_basic",
        "Feature-Based": "MD_GTEP_clean_case_methods_feature",
    }
    solve_times = {
        "Original": 9.01,
        "Basic": 3.49,
        "Feature-Based": 3.11,
    }
    rows = []
    build_rows = []
    for label, case in cases.items():
        out = ROOT / "ModelCases" / case / "output"
        sc = pd.read_csv(out / "system_cost.csv")
        cap = pd.read_csv(out / "capacity.csv")
        es = pd.read_csv(out / "es_capacity.csv")
        line = pd.read_csv(out / "line.csv")
        agg_path = out / "resource_aggregation_summary.csv"
        agg_rows = len(pd.read_csv(agg_path)) if agg_path.exists() else 231

        inv = sc["Inv_cost ($)"].sum()
        opr = sc["Opr_cost ($)"].sum()
        total = sc["Total_cost ($)"].sum()

        build = cap.groupby("Technology")["Capacity_FIN (MW)"].sum() - cap.groupby("Technology")["Capacity_INI (MW)"].sum()
        for tech in ["NGCT_CCS", "WindOn", "SolarPV"]:
            build_rows.append({"Case": label, "Technology": tech, "MW": float(build.get(tech, 0.0))})
        storage_col = "Capacity (MW)" if "Capacity (MW)" in es.columns else [c for c in es.columns if "(MW)" in c][-1]
        build_rows.append({"Case": label, "Technology": "Battery", "MW": float(es[storage_col].sum())})
        build_rows.append({"Case": label, "Technology": "Line", "MW": float(line[[c for c in line.columns if "(MW)" in c][-1]].sum())})

        rows.append({
            "Case": label,
            "Investment": inv / 1e9,
            "Operation": opr / 1e9,
            "Total": total / 1e9,
            "Resources": agg_rows,
            "SolveTime": solve_times[label],
        })
    return pd.DataFrame(rows), pd.DataFrame(build_rows)


def pcm_data():
    cases = {
        "Original": "MD_PCM_Excel_case_aggmethods_1month_original",
        "Basic": "MD_PCM_Excel_case_aggmethods_1month_basic",
        "Feature-Based": "MD_PCM_Excel_case_aggmethods_1month_feature",
    }
    solve_times = {
        "Original": 77.49,
        "Basic": 16.29,
        "Feature-Based": 34.70,
    }
    rows = []
    original_total = None
    for label, case in cases.items():
        out = ROOT / "ModelCases" / case / "output"
        sc = pd.read_csv(out / "system_cost.csv")
        ls = pd.read_csv(out / "power_loadshedding.csv")
        total = sc["Total_cost ($)"].sum()
        opr = sc["Opr_cost ($)"].sum()
        lol = sc["LoL_plt ($)"].sum()
        shed = ls.iloc[:, 1:].sum().sum()
        emis = pd.read_csv(out / "emissions_state.csv")
        md_emis = float(emis.loc[emis["State"] == "MD", "Emissions_ton"].iloc[0])
        agg_path = out / "resource_aggregation_summary.csv"
        agg_rows = len(pd.read_csv(agg_path)) if agg_path.exists() else 285
        if label == "Original":
            original_total = total
        rows.append({
            "Case": label,
            "Operation": opr / 1e9,
            "LoL": lol / 1e9,
            "Total": total / 1e9,
            "LoadShedding": shed / 1000.0,
            "Emissions": md_emis / 1e6,
            "Resources": agg_rows,
            "SolveTime": solve_times[label],
            "TotalErrorPct": 0.0,
        })
    df = pd.DataFrame(rows)
    df["TotalErrorPct"] = (df["Total"] * 1e9 - original_total).abs() / original_total * 100.0
    return df


def style():
    plt.style.use("seaborn-v0_8-whitegrid")
    plt.rcParams.update({
        "font.size": 10,
        "axes.titlesize": 13,
        "axes.labelsize": 10,
        "figure.titlesize": 18,
    })


def plot_gtep(df, build_df):
    colors = {"Original": "#244c5a", "Basic": "#d67c2c", "Feature-Based": "#6d8fc7"}
    tech_colors = {
        "NGCT_CCS": "#cc5a49",
        "WindOn": "#4f9b7a",
        "SolarPV": "#d5a021",
        "Battery": "#7b66b3",
        "Line": "#7a7a7a",
    }
    fig, axes = plt.subplots(1, 3, figsize=(12.4, 3.8), constrained_layout=True)

    order = ["Original", "Basic", "Feature-Based"]
    x = range(len(order))
    inv = [df.loc[df.Case == c, "Investment"].iloc[0] for c in order]
    opr = [df.loc[df.Case == c, "Operation"].iloc[0] for c in order]
    axes[0].bar(x, inv, color="#8db3c7", label="Investment")
    axes[0].bar(x, opr, bottom=inv, color="#355c7d", label="Operation")
    axes[0].set_xticks(list(x), order)
    axes[0].set_ylabel("Cost (billion $)")
    axes[0].set_title("System Cost")
    axes[0].legend(frameon=True, fontsize=9)

    resources = [df.loc[df.Case == c, "Resources"].iloc[0] for c in order]
    solve = [df.loc[df.Case == c, "SolveTime"].iloc[0] for c in order]
    ax = axes[1]
    ax.bar(x, resources, color=[colors[c] for c in order])
    ax.set_xticks(list(x), order)
    ax.set_ylabel("Resources / Rows")
    ax.set_title("Model Size")
    ax2 = ax.twinx()
    ax2.plot(list(x), solve, color="#9b2f2f", marker="o", linewidth=2)
    ax2.set_ylabel("Solve time (s)")

    ax = axes[2]
    techs = ["NGCT_CCS", "WindOn", "SolarPV", "Battery", "Line"]
    width = 0.14
    base = [-2 * width, -width, 0, width, 2 * width]
    for off, tech in zip(base, techs):
        vals = [build_df[(build_df.Case == c) & (build_df.Technology == tech)]["MW"].iloc[0] / 1000.0 for c in order]
        ax.bar([i + off for i in x], vals, width=width, label=tech, color=tech_colors[tech])
    ax.set_xticks(list(x), order)
    ax.set_ylabel("Added capacity (GW)")
    ax.set_title("Build Outcome")
    ax.legend(frameon=True, fontsize=8, ncol=2)

    fig.suptitle("GTEP Aggregation Comparison", y=1.05)
    fig.savefig(ASSET_DIR / "resource_aggregation_gtep_comparison.png", dpi=180, bbox_inches="tight")
    plt.close(fig)


def plot_pcm(df):
    colors = {"Original": "#244c5a", "Basic": "#d67c2c", "Feature-Based": "#6d8fc7"}
    order = ["Original", "Basic", "Feature-Based"]
    fig, axes = plt.subplots(1, 3, figsize=(12.4, 3.8), constrained_layout=True)
    x = range(len(order))

    opr = [df.loc[df.Case == c, "Operation"].iloc[0] for c in order]
    axes[0].bar(x, opr, color="#355c7d")
    axes[0].set_xticks(list(x), order)
    axes[0].set_ylabel("Operation cost (billion $)")
    axes[0].set_title("System Cost")

    emissions = [df.loc[df.Case == c, "Emissions"].iloc[0] for c in order]
    axes[1].bar(x, emissions, color=[colors[c] for c in order])
    axes[1].set_xticks(list(x), order)
    axes[1].set_ylabel("MD emissions (million ton)")
    axes[1].set_title("Binding Carbon Outcome")

    ax = axes[2]
    for c in order:
        row = df[df.Case == c].iloc[0]
        ax.scatter(row["SolveTime"], row["TotalErrorPct"], s=120, color=colors[c], label=c)
        ax.text(row["SolveTime"] + 0.8, row["TotalErrorPct"] + 0.2, c, fontsize=9)
    ax.set_xlabel("Solve time (s)")
    ax.set_ylabel("Total-cost error vs original (%)")
    ax.set_title("Runtime vs Accuracy")
    ax.set_xlim(left=0)
    ax.set_ylim(bottom=0)

    fig.suptitle("PCM Aggregation Comparison", y=1.05)
    fig.savefig(ASSET_DIR / "resource_aggregation_pcm_comparison.png", dpi=180, bbox_inches="tight")
    plt.close(fig)


if __name__ == "__main__":
    style()
    gtep_df, gtep_build = gtep_data()
    pcm_df = pcm_data()
    plot_gtep(gtep_df, gtep_build)
    plot_pcm(pcm_df)
    print("Wrote:", ASSET_DIR / "resource_aggregation_gtep_comparison.png")
    print("Wrote:", ASSET_DIR / "resource_aggregation_pcm_comparison.png")
