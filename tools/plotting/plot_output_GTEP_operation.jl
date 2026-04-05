include(joinpath(@__DIR__, "plotting_common.jl"))

function build_gtep_operation_plot(case_arg::AbstractString; hours_to_show::Int=48)
    paths = resolve_case_paths(case_arg)
    ensure_plots_path(paths.plots_path)

    power_df = load_output_csv(paths.output_path, "power.csv")
    hourly_cols = filter(name -> startswith(String(name), "t"), names(power_df))
    isempty(hourly_cols) && error("No hourly representative-period columns found in $(joinpath(paths.output_path, "power.csv")).")
    keep_cols = hourly_cols[1:min(hours_to_show, length(hourly_cols))]

    plot_rows = filter(row -> sum(to_float_plot(row[c], 0.0) for c in keep_cols) > 0, eachrow(power_df))
    technologies = [string(row[:Technology]) for row in plot_rows]
    traces = Vector{GenericTrace{Dict{Symbol,Any}}}()
    for row in plot_rows
        tech = string(row[:Technology])
        push!(traces, scatter(
            x = 1:length(keep_cols),
            y = [to_float_plot(row[c], 0.0) for c in keep_cols],
            mode = "lines",
            name = tech,
            line = attr(color = default_plot_color(tech)),
        ))
    end

    fig = Plot(traces, Layout(
        title = "GTEP Operation Snapshot: $(case_label_from_path(paths.case_path))",
        xaxis_title = "Representative Hour Index",
        yaxis_title = "Dispatch (MW)",
        showlegend = true,
    ))

    outfile = joinpath(paths.plots_path, "gtep_operation_snapshot.html")
    save_plot_html(fig, outfile)
    println("Wrote $outfile")
    return outfile
end

if abspath(PROGRAM_FILE) == @__FILE__
    isempty(ARGS) && error("Usage: julia --project=. tools/plotting/plot_output_GTEP_operation.jl <case_path>")
    build_gtep_operation_plot(ARGS[1])
end
