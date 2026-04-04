using CSV
using DataFrames

default_repo_root() = normpath(joinpath(@__DIR__, "..", "..", ".."))

const TARGET_CASES = [
    "MD_GTEP_clean_case_methods_original",
    "MD_GTEP_clean_case_methods_basic",
    "MD_GTEP_clean_case_methods_feature",
]

const SOURCE_CASE = "MD_GTEP_clean_case"
const THERMAL_GROUPS = Set([
    ("BGE", "NGCT_CCS"),
    ("DPL_MD", "NGCC_CCS"),
    ("DPL_MD", "NGCT_CCS"),
    ("PEPCO", "NGCC_CCS"),
    ("PEPCO", "NGCT_CCS"),
])
const SOLAR_GROUPS = Set([
    ("APS_MD", "SolarPV"),
    ("BGE", "SolarPV"),
    ("DPL_MD", "SolarPV"),
    ("PEPCO", "SolarPV"),
])
const TIME_COLS = Set(["Time Period", "Month", "Day", "Hours"])

function overwrite_lines!(path::String, lines::Vector{String})
    open(path, "w") do io
        for line in lines
            println(io, line)
        end
    end
end

function set_case_switches!(settings_path::String, replacements::Dict{String,String})
    lines = readlines(settings_path)
    for i in eachindex(lines)
        stripped = strip(lines[i])
        for (key, value) in replacements
            startswith(stripped, key * ":") || continue
            comment = occursin("#", lines[i]) ? "  #" * split(lines[i], "#"; limit=2)[2] : ""
            lines[i] = key * ": " * value * comment
            break
        end
    end
    overwrite_lines!(settings_path, lines)
end

function copy_case_tree!(repo_root::String)
    for target in TARGET_CASES
        src = joinpath(repo_root, "ModelCases", SOURCE_CASE)
        dst = joinpath(repo_root, "ModelCases", target)
        isdir(dst) && continue
        cp(src, dst; force=true)
    end
end

function write_aggregation_settings!(path::String; method::String="basic")
    lines = String[
        "write_aggregation_audit: 1        # 1 write aggregation mapping/summary audit CSVs into output/; 0 disable",
        "aggregation_method: $(method)     # basic = keyed aggregation, feature_based = keyed groups split by clustering features",
        "grouping_keys:",
        "  - Zone",
        "  - Type",
        "  - Flag_RET",
        "  - Flag_mustrun",
        "  - Flag_VRE",
        "  - Flag_thermal",
        "pcm_additional_grouping_keys:",
        "  - Flag_UC",
        "clustered_thermal_commitment: 1   # used only in PCM with UC",
        "clustering_feature_columns:",
        raw"  - Cost (\$/MWh)",
        "  - FOR",
        raw"  - Pmax (MW)",
        raw"  - Pmin (MW)",
        "clustering_target_cluster_size: 4",
        "clustering_max_clusters_per_group: 6",
        "normalize_clustering_features: 1",
        "aggregate_technologies: []",
        "keep_separate_technologies: []",
    ]
    overwrite_lines!(path, lines)
end

function configure_cases!(repo_root::String)
    common = Dict(
        "solver" => "gurobi",
        "summary_table" => "1",
        "resource_aggregation" => "1",
        "planning_reserve_mode" => "1",
        "operation_reserve_mode" => "0",
        "clean_energy_policy" => "1",
        "carbon_policy" => "1",
    )
    set_case_switches!(
        joinpath(repo_root, "ModelCases", "MD_GTEP_clean_case_methods_original", "Settings", "HOPE_model_settings.yml"),
        merge(copy(common), Dict("resource_aggregation" => "0"))
    )
    set_case_switches!(
        joinpath(repo_root, "ModelCases", "MD_GTEP_clean_case_methods_basic", "Settings", "HOPE_model_settings.yml"),
        common
    )
    set_case_switches!(
        joinpath(repo_root, "ModelCases", "MD_GTEP_clean_case_methods_feature", "Settings", "HOPE_model_settings.yml"),
        common
    )
    write_aggregation_settings!(joinpath(repo_root, "ModelCases", "MD_GTEP_clean_case_methods_basic", "Settings", "HOPE_aggregation_settings.yml"); method="basic")
    write_aggregation_settings!(joinpath(repo_root, "ModelCases", "MD_GTEP_clean_case_methods_feature", "Settings", "HOPE_aggregation_settings.yml"); method="feature_based")
end

function value_columns(df::DataFrame)
    [name for name in names(df) if !(name in TIME_COLS) && name != "NI"]
end

function scale_load!(df::DataFrame, factor::Float64)
    for col in value_columns(df)
        df[!, col] = Float64.(df[!, col]) .* factor
    end
    if "NI" in names(df)
        df[!, "NI"] = Float64.(df[!, "NI"]) .* factor
    end
end

function redistribute_pmax!(gdf::SubDataFrame)
    n = nrow(gdf)
    total = sum(Float64.(gdf[!, Symbol("Pmax (MW)")]))
    n <= 1 && return
    weights = [i <= ceil(Int, n / 3) ? 2.2 : (i <= ceil(Int, 2n / 3) ? 1.0 : 0.45) for i in 1:n]
    weights = weights ./ sum(weights)
    perm = sortperm(Float64.(gdf[!, Symbol("Pmax (MW)")]); rev=true)
    for (pos, local_idx) in enumerate(perm)
        gdf[local_idx, Symbol("Pmax (MW)")] = total * weights[pos]
    end
end

function hidden_cc_factor(idx::Int, is_thermal::Bool)
    if is_thermal
        pattern = (0.45, 0.95, 0.70)
    else
        pattern = (0.08, 0.30, 0.18)
    end
    return pattern[mod1(idx, length(pattern))]
end

function perturb_thermal_group!(gdf::SubDataFrame)
    redistribute_pmax!(gdf)
    n = nrow(gdf)
    order = sortperm(Float64.(gdf[!, Symbol("Pmax (MW)")]); rev=true)
    n_a = ceil(Int, n / 3)
    n_b = ceil(Int, 2n / 3)
    for (pos, local_idx) in enumerate(order)
        kind = pos <= n_a ? 1 : (pos <= n_b ? 2 : 3)
        if kind == 1
            cost_factor, for_factor = 0.62, 0.70
        elseif kind == 2
            cost_factor, for_factor = 0.95, 1.05
        else
            cost_factor, for_factor = 1.45, 1.55
        end
        pmax = Float64(gdf[local_idx, Symbol("Pmax (MW)")])
        gdf[local_idx, Symbol("Cost (\$/MWh)")] = Float64(gdf[local_idx, Symbol("Cost (\$/MWh)")]) * cost_factor
        gdf[local_idx, :FOR] = min(0.35, max(0.0, Float64(gdf[local_idx, :FOR]) * for_factor))
        gdf[local_idx, Symbol("Pmin (MW)")] = kind == 1 ? 0.35 * pmax : (kind == 2 ? 0.18 * pmax : 0.06 * pmax)
    end
    for (idx, local_idx) in enumerate(1:nrow(gdf))
        gdf[local_idx, :CC] = hidden_cc_factor(idx, true)
    end
end

function perturb_solar_group!(gdf::SubDataFrame)
    redistribute_pmax!(gdf)
    for (idx, local_idx) in enumerate(1:nrow(gdf))
        gdf[local_idx, :CC] = hidden_cc_factor(idx, false)
    end
end

function tighten_carbon_cap!(cbp::DataFrame)
    for r in 1:nrow(cbp)
        state = string(cbp[r, "State"])
        cbp[r, Symbol("Allowance (tons)")] = state == "MD" ? 2.0e8 : 1.0e9
    end
end

function modify_case_data!(case_dir::String)
    data_dir = joinpath(case_dir, "Data_100RPS")
    gendata_path = joinpath(data_dir, "gendata.csv")
    load_path = joinpath(data_dir, "load_timeseries_regional.csv")
    carbon_path = joinpath(data_dir, "carbonpolicies.csv")

    gendata = CSV.read(gendata_path, DataFrame)
    loaddata = CSV.read(load_path, DataFrame)
    carbon = CSV.read(carbon_path, DataFrame)

    available_cols = Set(Symbol.(names(gendata)))
    for col in [Symbol("Pmax (MW)"), Symbol("Pmin (MW)"), Symbol("Cost (\$/MWh)"), :FOR, :CC, :EF]
        if col in available_cols
            gendata[!, col] = Float64.(gendata[!, col])
        end
    end
    if Symbol("Allowance (tons)") in Symbol.(names(carbon))
        carbon[!, Symbol("Allowance (tons)")] = Float64.(carbon[!, Symbol("Allowance (tons)")])
    end

    scale_load!(loaddata, 1.10)
    tighten_carbon_cap!(carbon)

    touched = DataFrame(Zone=String[], Type=String[], GroupSize=Int[], MinCost=Float64[], MaxCost=Float64[], MinCC=Float64[], MaxCC=Float64[])
    for gdf in groupby(gendata, [:Zone, :Type])
        zone = string(first(gdf.Zone))
        tech = string(first(gdf.Type))
        if (zone, tech) in THERMAL_GROUPS && nrow(gdf) >= 4
            perturb_thermal_group!(gdf)
        elseif (zone, tech) in SOLAR_GROUPS && nrow(gdf) >= 10
            perturb_solar_group!(gdf)
        else
            continue
        end
        push!(touched, (
            zone,
            tech,
            nrow(gdf),
            minimum(Float64.(gdf[!, Symbol("Cost (\$/MWh)")])),
            maximum(Float64.(gdf[!, Symbol("Cost (\$/MWh)")])),
            minimum(Float64.(gdf[!, :CC])),
            maximum(Float64.(gdf[!, :CC])),
        ))
    end

    CSV.write(gendata_path, gendata)
    CSV.write(load_path, loaddata)
    CSV.write(carbon_path, carbon)
    return touched
end

function main()
    repo_root = length(ARGS) >= 1 ? abspath(ARGS[1]) : default_repo_root()
    copy_case_tree!(repo_root)
    configure_cases!(repo_root)

    original_case = joinpath(repo_root, "ModelCases", "MD_GTEP_clean_case_methods_original")
    touched = modify_case_data!(original_case)
    src_dir = joinpath(original_case, "Data_100RPS")
    gendata = CSV.read(joinpath(src_dir, "gendata.csv"), DataFrame)
    loaddata = CSV.read(joinpath(src_dir, "load_timeseries_regional.csv"), DataFrame)
    carbon = CSV.read(joinpath(src_dir, "carbonpolicies.csv"), DataFrame)
    for target in TARGET_CASES[2:end]
        data_dir = joinpath(repo_root, "ModelCases", target, "Data_100RPS")
        CSV.write(joinpath(data_dir, "gendata.csv"), gendata)
        CSV.write(joinpath(data_dir, "load_timeseries_regional.csv"), loaddata)
        CSV.write(joinpath(data_dir, "carbonpolicies.csv"), carbon)
    end

    println("Created GTEP resource aggregation method comparison cases:")
    for target in TARGET_CASES
        println("  - ", target)
    end
    println()
    println("Touched resource groups:")
    show(stdout, MIME("text/plain"), touched)
    println()
end

main()
