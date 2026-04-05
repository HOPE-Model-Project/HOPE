include(joinpath(@__DIR__, "plotting_common.jl"))

function build_generation_plots(case_arg::AbstractString; formats::Vector{String}=String["png"])
    paths = resolve_case_paths(case_arg)
    ensure_plots_path(paths.plots_path)

    power_df = load_output_csv(paths.output_path, "power.csv")
    gen_by_tech = aggregate_by_technology(power_df, "AnnSum")
    gen_by_tech[!, :Generation_TWh] = twh.(gen_by_tech[!, :AnnSum])
    gen_by_tech = gen_by_tech[gen_by_tech.Generation_TWh .> 1e-6, [:Technology, :Generation_TWh]]

    gen_by_zone = aggregate_by_zone_technology(power_df, "AnnSum")
    gen_by_zone[!, :Generation_TWh] = twh.(gen_by_zone[!, :AnnSum])
    gen_by_zone = gen_by_zone[gen_by_zone.Generation_TWh .> 1e-6, [:Zone, :Technology, :Generation_TWh]]

    curtail_by_tech = DataFrame(Technology=String[], Curtailment_TWh=Float64[])
    curt_path = joinpath(paths.output_path, "power_renewable_curtailment.csv")
    if isfile(curt_path)
        curt_df = CSV.read(curt_path, DataFrame)
        if nrow(curt_df) > 0
            tmp = aggregate_by_technology(curt_df, "AnnSum")
            tmp[!, :Curtailment_TWh] = twh.(tmp[!, :AnnSum])
            curtail_by_tech = tmp[tmp.Curtailment_TWh .> 1e-6, [:Technology, :Curtailment_TWh]]
        end
    end

    cost_df = load_output_csv(paths.output_path, "system_cost.csv")
    total_inv = "Inv_cost (\$)" in names(cost_df) ? sum(to_float_plot(v, 0.0) for v in cost_df[!, "Inv_cost (\$)"]) : 0.0
    total_opr = "Opr_cost (\$)" in names(cost_df) ? sum(to_float_plot(v, 0.0) for v in cost_df[!, "Opr_cost (\$)"]) : 0.0
    total_lol = "LoL_plt (\$)" in names(cost_df) ? sum(to_float_plot(v, 0.0) for v in cost_df[!, "LoL_plt (\$)"]) : 0.0
    cost_split = DataFrame(
        Category=["Investment", "Operation", "Load shedding"],
        Value=[billion(total_inv), billion(total_opr), billion(total_lol)],
    )

    label = case_label_from_path(paths.case_path)

    generation_fig = build_simple_bar_figure(
        gen_by_tech.Technology,
        gen_by_tech.Generation_TWh;
        title="Annual Generation by Technology: $label",
        ytitle="TWh",
        colors=[default_plot_color(string(t)) for t in gen_by_tech.Technology],
    )
    save_plot_outputs(generation_fig, joinpath(paths.plots_path, "generation_by_technology"); formats=formats)

    zonal_generation_fig = build_stacked_zone_figure(
        rename(gen_by_zone, :Generation_TWh => :Value),
        "Value";
        title="Annual Generation by Zone: $label",
        ytitle="TWh",
    )
    save_plot_outputs(zonal_generation_fig, joinpath(paths.plots_path, "generation_by_zone"); formats=formats)

    if nrow(curtail_by_tech) > 0
        curtailment_fig = build_simple_bar_figure(
            curtail_by_tech.Technology,
            curtail_by_tech.Curtailment_TWh;
            title="VRE Curtailment by Technology: $label",
            ytitle="TWh",
            colors=[default_plot_color(string(t)) for t in curtail_by_tech.Technology],
        )
        save_plot_outputs(curtailment_fig, joinpath(paths.plots_path, "curtailment_by_technology"); formats=formats)
    end

    cost_fig = plot(
        bar(
            x=cost_split.Category,
            y=cost_split.Value,
            marker_color=["#6f8fb3", "#4c6b87", "#c97b63"],
        ),
        single_panel_layout(title="System Cost Split: $label", ytitle="Billion USD", showlegend=false),
    )
    save_plot_outputs(cost_fig, joinpath(paths.plots_path, "system_cost_split"); formats=formats)

    println("Wrote generation plots to $(paths.plots_path)")
    return paths.plots_path
end

if abspath(PROGRAM_FILE) == @__FILE__
    isempty(ARGS) && error("Usage: julia --project=. tools/plotting/plot_output_generation.jl <case_path> [png|html|svg,...]")
    formats = length(ARGS) >= 2 ? split(ARGS[2], ",") : String["png"]
    build_generation_plots(ARGS[1]; formats=formats)
end
