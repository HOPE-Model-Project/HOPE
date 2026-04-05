include(joinpath(@__DIR__, "plotting_common.jl"))

function build_operation_plot(case_arg::AbstractString; hours_to_show::Int=168)
    paths = resolve_case_paths(case_arg)
    ensure_plots_path(paths.plots_path)

    power_filename = isfile(joinpath(paths.output_path, "power_hourly.csv")) ? "power_hourly.csv" : "power.csv"
    power_df = load_output_csv(paths.output_path, power_filename)
    hourly_cols = filter(name -> startswith(String(name), "h"), names(power_df))
    if isempty(hourly_cols)
        hourly_cols = filter(name -> startswith(String(name), "t"), names(power_df))
    end
    isempty(hourly_cols) && error("No hourly dispatch columns found in $(joinpath(paths.output_path, power_filename)).")
    keep_cols = hourly_cols[1:min(hours_to_show, length(hourly_cols))]

    tech_hourly = Dict{String,Vector{Float64}}()
    for row in eachrow(power_df)
        tech = string(row[:Technology])
        vals = [to_float_plot(row[c], 0.0) for c in keep_cols]
        tech_hourly[tech] = get(tech_hourly, tech, zeros(Float64, length(keep_cols))) .+ vals
    end
    techs = sort(collect(keys(tech_hourly)))
    traces = Vector{GenericTrace{Dict{Symbol,Any}}}()
    for tech in techs
        push!(traces, scatter(
            x = 1:length(keep_cols),
            y = tech_hourly[tech],
            mode = "lines",
            stackgroup = "one",
            name = tech,
            line = attr(color = default_plot_color(tech)),
        ))
    end

    fig = Plot(traces, Layout(
        title = "Operation Mix Snapshot: $(case_label_from_path(paths.case_path))",
        xaxis_title = "Hour Index",
        yaxis_title = "Dispatch (MW)",
        showlegend = true,
    ))

    outfile = joinpath(paths.plots_path, "operation_mix_snapshot.html")
    save_plot_html(fig, outfile)
    println("Wrote $outfile")
    return outfile
end

if abspath(PROGRAM_FILE) == @__FILE__
    isempty(ARGS) && error("Usage: julia --project=. tools/plotting/plot_output_operation.jl <case_path>")
    build_operation_plot(ARGS[1])
end
