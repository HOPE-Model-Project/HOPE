using XLSX
using DataFrames
using Statistics

default_repo_root() = normpath(joinpath(@__DIR__, "..", "..", ".."))

const TARGET_CASES = [
    "MD_PCM_Excel_case_aggmethods_1month_original",
    "MD_PCM_Excel_case_aggmethods_1month_basic",
    "MD_PCM_Excel_case_aggmethods_1month_feature",
]

const SOURCE_CASES = Dict(
    "MD_PCM_Excel_case_aggmethods_1month_original" => "MD_PCM_Excel_case_ucbenchmark_1month_original",
    "MD_PCM_Excel_case_aggmethods_1month_basic" => "MD_PCM_Excel_case_ucbenchmark_1month_single",
    "MD_PCM_Excel_case_aggmethods_1month_feature" => "MD_PCM_Excel_case_ucbenchmark_1month_single",
)

const TARGET_GROUPS = Set([
    ("BGE", "Coal"),
    ("BGE", "NGCT"),
    ("DPL_MD", "NGCT"),
    ("PEPCO", "NGCT"),
    ("BGE", "Oil"),
    ("DPL_MD", "Oil"),
    ("PEPCO", "Oil"),
    ("PEPCO", "NGCC"),
    ("DPL_MD", "NGCC"),
])

const TIME_COLS = Set(["Time Period", "Rep_Period", "Rep Period", "Period", "Hours", "Month", "Day", "Hour"])
const LOAD_SCALE_BASE = 0.78
const NI_SCALE = 1.05
const WIND_SCALE = 1.15
const SOLAR_SCALE = 1.60
const TOTAL_CARBON_ALLOWANCE = 2.25e6

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
    seed_root = joinpath(repo_root, "tools", "resource_aggregation_examples", "seed_cases")
    for target in TARGET_CASES
        src = joinpath(seed_root, SOURCE_CASES[target])
        dst = joinpath(repo_root, "ModelCases", target)
        if !isdir(dst)
            cp(src, dst; force=true)
        end
    end
end

function write_aggregation_settings!(path::String; method::String="basic", include_ef::Bool=false)
    feature_lines = String[
        raw"  - Cost (\$/MWh)",
    ]
    if include_ef
        push!(feature_lines, "  - EF")
    end
    append!(feature_lines, String[
        "  - FOR",
        "  - RU",
        "  - RD",
        "  - RM_SPIN",
        raw"  - Start_up_cost (\$/MW)",
        "  - Min_down_time",
        "  - Min_up_time",
        raw"  - Pmax (MW)",
        raw"  - Pmin (MW)",
    ])
    lines = String[
        "write_aggregation_audit: 1        # 1 write aggregation mapping/summary audit CSVs into output/; 0 disable",
        "aggregation_method: $(method)     # basic = keyed aggregation, feature_based = keyed groups split by clustering features",
        "grouping_keys:",
        "  - Zone",
        "  - Type",
        "  - Flag_mustrun",
        "  - Flag_VRE",
        "  - Flag_thermal",
        "pcm_additional_grouping_keys:",
        "  - Flag_UC",
        "clustered_thermal_commitment: 1   # PCM internal UC treatment for aggregated thermal resources",
        "clustering_feature_columns:",
        "clustering_target_cluster_size: 2",
        "clustering_max_clusters_per_group: 6",
        "normalize_clustering_features: 1",
        "aggregate_technologies: []",
        "keep_separate_technologies: []",
    ]
    insert_at = findfirst(==("clustering_target_cluster_size: 2"), lines)
    lines = vcat(lines[1:insert_at-1], feature_lines, lines[insert_at:end])
    overwrite_lines!(path, lines)
end

function configure_cases!(repo_root::String)
    common = Dict(
        "network_model" => "1",
        "operation_reserve_mode" => "1",
        "carbon_policy" => "1",
        "clean_energy_policy" => "0",
        "solver" => "gurobi",
        "summary_table" => "1",
    )
    set_case_switches!(
        joinpath(repo_root, "ModelCases", "MD_PCM_Excel_case_aggmethods_1month_original", "Settings", "HOPE_model_settings.yml"),
        merge(copy(common), Dict("resource_aggregation" => "0"))
    )
    set_case_switches!(
        joinpath(repo_root, "ModelCases", "MD_PCM_Excel_case_aggmethods_1month_basic", "Settings", "HOPE_model_settings.yml"),
        merge(copy(common), Dict("resource_aggregation" => "1"))
    )
    set_case_switches!(
        joinpath(repo_root, "ModelCases", "MD_PCM_Excel_case_aggmethods_1month_feature", "Settings", "HOPE_model_settings.yml"),
        merge(copy(common), Dict("resource_aggregation" => "1"))
    )
    write_aggregation_settings!(joinpath(repo_root, "ModelCases", "MD_PCM_Excel_case_aggmethods_1month_basic", "Settings", "HOPE_aggregation_settings.yml"); method="basic")
    write_aggregation_settings!(joinpath(repo_root, "ModelCases", "MD_PCM_Excel_case_aggmethods_1month_feature", "Settings", "HOPE_aggregation_settings.yml"); method="feature_based", include_ef=true)
end

function value_columns(df::DataFrame)
    [name for name in names(df) if !(name in TIME_COLS) && name != "NI"]
end

function load_hour_factor(hour::Int)
    if 11 <= hour <= 15
        return 0.80
    elseif 18 <= hour <= 21
        return 1.14
    elseif 1 <= hour <= 5
        return 0.88
    elseif 6 <= hour <= 8
        return 0.96
    else
        return 0.93
    end
end

function scale_load_shape!(df::DataFrame)
    cols = value_columns(df)
    has_hour = "Hour" in names(df)
    for r in 1:nrow(df)
        hour = has_hour ? round(Int, Float64(df[r, "Hour"])) : mod1(r, 24)
        factor = LOAD_SCALE_BASE * load_hour_factor(hour)
        for col in cols
            df[r, col] = max(0.0, Float64(df[r, col]) * factor)
        end
        if "NI" in names(df)
            df[r, "NI"] = Float64(df[r, "NI"]) * NI_SCALE
        end
    end
end

function scale_profile!(df::DataFrame, factor::Float64)
    for col in value_columns(df)
        df[!, col] = min.(1.0, max.(0.0, Float64.(df[!, col]) .* factor))
    end
end

function archetype_params(kind::Int)
    if kind == 1
        return (
            cost = 0.62,
            startup = 3.00,
            minup = 3.0,
            mindown = 3.0,
            ru = 0.35,
            rd = 0.35,
            spin = 0.60,
            for_rate = 0.85,
        )
    elseif kind == 2
        return (
            cost = 0.95,
            startup = 1.00,
            minup = 1.0,
            mindown = 1.0,
            ru = 1.00,
            rd = 1.00,
            spin = 1.00,
            for_rate = 1.00,
        )
    else
        return (
            cost = 1.55,
            startup = 0.25,
            minup = 0.5,
            mindown = 0.5,
            ru = 2.80,
            rd = 2.80,
            spin = 1.70,
            for_rate = 1.15,
        )
    end
end

function pmin_ratio_for(tech::AbstractString, kind::Int)
    if tech in ("Coal", "Nuc")
        return kind == 1 ? 0.60 : (kind == 2 ? 0.42 : 0.20)
    elseif tech == "NGCC"
        return kind == 1 ? 0.48 : (kind == 2 ? 0.28 : 0.14)
    else
        return kind == 1 ? 0.28 : (kind == 2 ? 0.15 : 0.06)
    end
end

function hidden_ef_factor(idx::Int)
    pattern = (1.70, 0.60, 1.15)
    return pattern[mod1(idx, length(pattern))]
end

function redistribute_pmax!(gdf::SubDataFrame)
    n = nrow(gdf)
    total = sum(Float64.(gdf[!, Symbol("Pmax (MW)")]))
    n <= 1 && return
    weights = [i <= ceil(Int, n / 3) ? 2.4 : (i <= ceil(Int, 2n / 3) ? 1.0 : 0.4) for i in 1:n]
    weights = weights ./ sum(weights)
    new_pmax = total .* weights
    perm = sortperm(Float64.(gdf[!, Symbol("Pmax (MW)")]); rev=true)
    for (pos, local_idx) in enumerate(perm)
        gdf[local_idx, Symbol("Pmax (MW)")] = new_pmax[pos]
    end
end

function perturb_group!(gdf::SubDataFrame)
    redistribute_pmax!(gdf)
    tech = string(first(gdf.Type))
    order = sortperm(Float64.(gdf[!, Symbol("Pmax (MW)")]); rev=true)
    n = length(order)
    n_a = ceil(Int, n / 3)
    n_b = ceil(Int, 2n / 3)
    for (pos, local_idx) in enumerate(order)
        kind = pos <= n_a ? 1 : (pos <= n_b ? 2 : 3)
        params = archetype_params(kind)
        pmax = Float64(gdf[local_idx, Symbol("Pmax (MW)")])
        gdf[local_idx, Symbol("Cost (\$/MWh)")] = Float64(gdf[local_idx, Symbol("Cost (\$/MWh)")]) * params.cost
        gdf[local_idx, Symbol("Start_up_cost (\$/MW)")] = Float64(gdf[local_idx, Symbol("Start_up_cost (\$/MW)")]) * params.startup
        gdf[local_idx, :Min_up_time] = max(1.0, round(Float64(gdf[local_idx, :Min_up_time]) * params.minup))
        gdf[local_idx, :Min_down_time] = max(1.0, round(Float64(gdf[local_idx, :Min_down_time]) * params.mindown))
        gdf[local_idx, :RU] = min(1.0, Float64(gdf[local_idx, :RU]) * params.ru)
        gdf[local_idx, :RD] = min(1.0, Float64(gdf[local_idx, :RD]) * params.rd)
        gdf[local_idx, :RM_SPIN] = min(1.0, Float64(gdf[local_idx, :RM_SPIN]) * params.spin)
        gdf[local_idx, :FOR] = min(0.35, max(0.0, Float64(gdf[local_idx, :FOR]) * params.for_rate))
        gdf[local_idx, Symbol("Pmin (MW)")] = pmax * pmin_ratio_for(tech, kind)
    end
    for (idx, local_idx) in enumerate(1:nrow(gdf))
        gdf[local_idx, :EF] = Float64(gdf[local_idx, :EF]) * hidden_ef_factor(idx)
    end
end

function tighten_carbon_cap!(cbp::DataFrame)
    total_allowance = TOTAL_CARBON_ALLOWANCE
    per_period = total_allowance / 4
    for r in 1:nrow(cbp)
        state = string(cbp[r, "State"])
        cbp[r, Symbol("Allowance (tons)")] = state == "MD" ? per_period : 0.0
    end
end

function modify_workbook!(xlsx_path::String)
    xf = XLSX.readxlsx(xlsx_path)
    gendata = DataFrame(XLSX.gettable(xf["gendata"]))
    loaddata = DataFrame(XLSX.gettable(xf["load_timeseries_regional"]))
    winddata = DataFrame(XLSX.gettable(xf["wind_timeseries_regional"]))
    solardata = DataFrame(XLSX.gettable(xf["solar_timeseries_regional"]))
    cbp = DataFrame(XLSX.gettable(xf["carbonpolicies"]))

    scale_load_shape!(loaddata)
    scale_profile!(winddata, WIND_SCALE)
    scale_profile!(solardata, SOLAR_SCALE)
    tighten_carbon_cap!(cbp)

    grouped = groupby(gendata, [:Zone, :Type, :Flag_UC, :Flag_thermal])
    touched = DataFrame(
        Zone = String[],
        Type = String[],
        GroupSize = Int[],
        MinCost = Float64[],
        MaxCost = Float64[],
        MinEF = Float64[],
        MaxEF = Float64[],
    )
    for gdf in grouped
        zone = string(first(gdf.Zone))
        tech = string(first(gdf.Type))
        is_uc = round(Int, Float64(first(gdf.Flag_UC))) == 1
        is_thermal = round(Int, Float64(first(gdf.Flag_thermal))) == 1
        if is_uc && is_thermal && (zone, tech) in TARGET_GROUPS && nrow(gdf) >= 6
            perturb_group!(gdf)
            cost_vals = Float64.(gdf[!, Symbol("Cost (\$/MWh)")])
            ef_vals = Float64.(gdf[!, :EF])
            push!(touched, (zone, tech, nrow(gdf), minimum(cost_vals), maximum(cost_vals), minimum(ef_vals), maximum(ef_vals)))
        end
    end

    XLSX.openxlsx(xlsx_path, mode="rw") do xwb
        XLSX.writetable!(xwb["gendata"], collect(eachcol(gendata)), names(gendata); anchor_cell=XLSX.CellRef("A1"))
        XLSX.writetable!(xwb["load_timeseries_regional"], collect(eachcol(loaddata)), names(loaddata); anchor_cell=XLSX.CellRef("A1"))
        XLSX.writetable!(xwb["wind_timeseries_regional"], collect(eachcol(winddata)), names(winddata); anchor_cell=XLSX.CellRef("A1"))
        XLSX.writetable!(xwb["solar_timeseries_regional"], collect(eachcol(solardata)), names(solardata); anchor_cell=XLSX.CellRef("A1"))
        XLSX.writetable!(xwb["carbonpolicies"], collect(eachcol(cbp)), names(cbp); anchor_cell=XLSX.CellRef("A1"))
    end
    return touched
end

function main()
    repo_root = length(ARGS) >= 1 ? abspath(ARGS[1]) : default_repo_root()
    copy_case_tree!(repo_root)
    configure_cases!(repo_root)

    workbook_path = joinpath(repo_root, "ModelCases", "MD_PCM_Excel_case_aggmethods_1month_original", "Data_PCM2035", "PCM_input_total.xlsx")
    touched = modify_workbook!(workbook_path)
    for target in TARGET_CASES[2:end]
        dst = joinpath(repo_root, "ModelCases", target, "Data_PCM2035", "PCM_input_total.xlsx")
        cp(workbook_path, dst; force=true)
    end

    println("Created PCM resource aggregation method comparison cases:")
    for target in TARGET_CASES
        println("  - ", target)
    end
    println()
    println("Touched thermal groups:")
    show(stdout, MIME("text/plain"), touched)
    println()
end

main()
