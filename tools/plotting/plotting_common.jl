using CSV
using DataFrames
using PlotlyJS

const PLOT_COLOR_MAP = Dict(
    "Coal" => "#222222",
    "Oil" => "#d2b48c",
    "NGCT" => "#708090",
    "NGCT_CCS" => "#556b76",
    "NGCC" => "#9fbad6",
    "NGCC_CCS" => "#7e9fbc",
    "Hydro" => "#133c73",
    "Hydro_Pumped" => "#7c8cff",
    "NuC" => "#f39c12",
    "Nuc" => "#f39c12",
    "MSW" => "#8b4513",
    "Bio" => "#8bc34a",
    "Landfill_NG" => "#c9a227",
    "WindOn" => "#6bb6ff",
    "WindOff" => "#2f7fd3",
    "SolarPV" => "#f4d03f",
    "Battery" => "#7d3c98",
    "Other" => "#f5b7b1",
)

const PLOT_TECH_ORDER = [
    "Coal", "Oil", "NGCT", "NGCT_CCS", "NGCC", "NGCC_CCS", "NuC", "Nuc",
    "Hydro", "MSW", "Landfill_NG", "Bio", "WindOff", "WindOn", "SolarPV", "Battery", "Other",
]

default_plot_color(tech::AbstractString) = get(PLOT_COLOR_MAP, tech, "#b0b0b0")
to_float_plot(x, default::Float64=0.0) = ismissing(x) || x === nothing || string(x) == "" ? default : (x isa Number ? Float64(x) : parse(Float64, string(x)))

function resolve_case_paths(case_arg::AbstractString)
    repo_root = normpath(joinpath(@__DIR__, "..", ".."))
    candidate_paths = [
        case_arg,
        joinpath(repo_root, case_arg),
        joinpath(repo_root, "ModelCases", case_arg),
    ]
    for candidate in candidate_paths
        if isdir(candidate)
            return (
                case_path = normpath(candidate),
                output_path = joinpath(normpath(candidate), "output"),
                plots_path = joinpath(normpath(candidate), "plots"),
            )
        end
    end
    error("Could not resolve case directory from argument '$case_arg'.")
end

function ensure_plots_path(plots_path::AbstractString)
    isdir(plots_path) || mkpath(plots_path)
    return plots_path
end

function load_output_csv(output_path::AbstractString, filename::AbstractString)
    path = joinpath(output_path, filename)
    isfile(path) || throw(ArgumentError("Expected output file not found: $path"))
    return CSV.read(path, DataFrame)
end

function save_plot_html(fig, filepath::AbstractString)
    plot_obj = hasproperty(fig, :plot) ? getproperty(fig, :plot) : fig
    open(filepath, "w") do io
        PlotlyBase.to_html(io, plot_obj)
    end
    return filepath
end

function save_plot_outputs(fig, basepath::AbstractString; formats::Vector{String}=String["png"])
    plot_obj = hasproperty(fig, :plot) ? getproperty(fig, :plot) : fig
    outputs = String[]
    for fmt in formats
        path = "$(basepath).$(lowercase(fmt))"
        if lowercase(fmt) == "html"
            save_plot_html(fig, path)
        else
            savefig(plot_obj, path)
        end
        push!(outputs, path)
    end
    return outputs
end

function aggregate_by_technology(df::DataFrame, value_col::Symbol)
    work = combine(groupby(df, :Technology), value_col => sum => value_col)
    sort_technology_df!(work)
    return work
end

function aggregate_by_technology(df::DataFrame, value_col::AbstractString)
    return aggregate_by_technology(df, Symbol(value_col))
end

function aggregate_by_zone_technology(df::DataFrame, value_col::AbstractString)
    work = combine(groupby(df, [:Zone, :Technology]), Symbol(value_col) => sum => Symbol(value_col))
    sort!(work, [:Zone, :Technology])
    return work
end

function case_label_from_path(case_path::AbstractString)
    return splitpath(normpath(case_path))[end]
end

function sort_technology_df!(df::DataFrame)
    if :Technology in names(df)
        order_map = Dict(tech => idx for (idx, tech) in enumerate(PLOT_TECH_ORDER))
        df[!, :__order] = [get(order_map, string(t), length(order_map) + 100) for t in df.Technology]
        sort!(df, [:__order, :Technology])
        select!(df, Not(:__order))
    end
    return df
end

gw(x) = x / 1000.0
twh(x) = x / 1_000_000.0
billion(x) = x / 1_000_000_000.0

function publication_layout(; title::AbstractString)
    return Layout(
        title = attr(text=title, x=0.02, xanchor="left", font=attr(size=20)),
        font = attr(family="Arial, Helvetica, sans-serif", size=12, color="#222222"),
        paper_bgcolor = "white",
        plot_bgcolor = "white",
        margin = attr(l=70, r=30, t=80, b=60),
        showlegend = false,
    )
end

function single_panel_layout(; title::AbstractString, ytitle::AbstractString="", showlegend::Bool=false, width::Int=960, height::Int=520)
    return Layout(
        title = attr(text=title, x=0.02, xanchor="left", font=attr(size=20)),
        font = attr(family="Arial, Helvetica, sans-serif", size=12, color="#222222"),
        paper_bgcolor = "white",
        plot_bgcolor = "white",
        margin = attr(l=70, r=(showlegend ? 170 : 30), t=80, b=90),
        width = width,
        height = height,
        showlegend = showlegend,
        legend = attr(orientation="v", x=1.02, y=1.0, xanchor="left", yanchor="top", traceorder="normal"),
        xaxis = attr(showline=true, linecolor="#888888", tickangle=-30),
        yaxis = attr(title=ytitle, gridcolor="#e6e6e6", zeroline=false),
        barmode = "stack",
    )
end

function technology_order_present(techs)
    present = string.(techs)
    ordered = [tech for tech in PLOT_TECH_ORDER if tech in present]
    extras = sort([tech for tech in present if tech ∉ ordered])
    return vcat(ordered, extras)
end

function build_stacked_zone_figure(df::DataFrame, value_col::AbstractString; title::AbstractString, ytitle::AbstractString)
    traces = GenericTrace[]
    ordered_techs = technology_order_present(unique(string.(df.Technology)))
    ordered_zones = sort(unique(string.(df.Zone)))
    for tech in ordered_techs
        subset = df[df.Technology .== tech, :]
        zone_map = Dict(string(row.Zone) => to_float_plot(row[Symbol(value_col)], 0.0) for row in eachrow(subset))
        y = [get(zone_map, zone, 0.0) for zone in ordered_zones]
        push!(traces, bar(
            x=ordered_zones,
            y=y,
            name=tech,
            marker_color=default_plot_color(tech),
        ))
    end
    fig = plot(traces, single_panel_layout(title=title, ytitle=ytitle, showlegend=true))
    return fig
end

function build_simple_bar_figure(x, y; title::AbstractString, ytitle::AbstractString, colors=nothing)
    marker = colors === nothing ? attr() : attr(color=colors)
    fig = plot(
        bar(x=x, y=y, marker=marker),
        single_panel_layout(title=title, ytitle=ytitle, showlegend=false),
    )
    return fig
end
