include(joinpath(@__DIR__, "plotting_common.jl"))

function build_capacity_plots(case_arg::AbstractString; formats::Vector{String}=String["png"])
    paths = resolve_case_paths(case_arg)
    ensure_plots_path(paths.plots_path)

    capacity_df = load_output_csv(paths.output_path, "capacity.csv")
    final_cap = aggregate_by_technology(capacity_df, "Capacity_FIN (MW)")
    final_cap[!, :Capacity_GW] = gw.(final_cap[!, Symbol("Capacity_FIN (MW)")])
    final_cap = final_cap[final_cap.Capacity_GW .> 1e-6, :]

    new_build_df = filter(row -> to_float_plot(row.New_Build, 0.0) > 0.0, capacity_df)
    new_cap = if nrow(new_build_df) == 0
        DataFrame(Technology=String[], Capacity_GW=Float64[])
    else
        tmp = aggregate_by_technology(new_build_df, "Capacity_FIN (MW)")
        tmp[!, :Capacity_GW] = gw.(tmp[!, Symbol("Capacity_FIN (MW)")])
        tmp[tmp.Capacity_GW .> 1e-6, [:Technology, :Capacity_GW]]
    end

    final_zone = aggregate_by_zone_technology(capacity_df, "Capacity_FIN (MW)")
    final_zone[!, :Capacity_GW] = gw.(final_zone[!, Symbol("Capacity_FIN (MW)")])
    final_zone = final_zone[final_zone.Capacity_GW .> 1e-6, [:Zone, :Technology, :Capacity_GW]]

    new_zone = if nrow(new_build_df) == 0
        DataFrame(Zone=String[], Technology=String[], Capacity_GW=Float64[])
    else
        tmp = aggregate_by_zone_technology(new_build_df, "Capacity_FIN (MW)")
        tmp[!, :Capacity_GW] = gw.(tmp[!, Symbol("Capacity_FIN (MW)")])
        tmp[tmp.Capacity_GW .> 1e-6, [:Zone, :Technology, :Capacity_GW]]
    end

    storage_power = DataFrame(Zone=String[], Technology=String[], Value_GW=Float64[])
    storage_energy = DataFrame(Zone=String[], Technology=String[], Value_GWh=Float64[])
    es_path = joinpath(paths.output_path, "es_capacity.csv")
    if isfile(es_path)
        es_df = CSV.read(es_path, DataFrame)
        if nrow(es_df) > 0
            es_names = string.(names(es_df))
            power_col = "Capacity (MW)" in es_names ? "Capacity (MW)" : "Capacity"
            energy_col = "EnergyCapacity (MWh)" in es_names ? "EnergyCapacity (MWh)" : ("Capacity (MWh)" in es_names ? "Capacity (MWh)" : "")

            power_group = aggregate_by_zone_technology(es_df, power_col)
            power_group[!, :Value_GW] = gw.(power_group[!, Symbol(power_col)])
            storage_power = power_group[power_group.Value_GW .> 1e-6, [:Zone, :Technology, :Value_GW]]

            if !isempty(energy_col)
                energy_group = aggregate_by_zone_technology(es_df, energy_col)
                energy_group[!, :Value_GWh] = energy_group[!, Symbol(energy_col)] ./ 1000.0
                storage_energy = energy_group[energy_group.Value_GWh .> 1e-6, [:Zone, :Technology, :Value_GWh]]
            end
        end
    end

    label = case_label_from_path(paths.case_path)

    final_fig = build_simple_bar_figure(
        final_cap.Technology,
        final_cap.Capacity_GW;
        title="Installed Capacity by Technology: $label",
        ytitle="GW",
        colors=[default_plot_color(string(t)) for t in final_cap.Technology],
    )
    save_plot_outputs(final_fig, joinpath(paths.plots_path, "capacity_by_technology"); formats=formats)

    new_fig = build_simple_bar_figure(
        new_cap.Technology,
        new_cap.Capacity_GW;
        title="New Capacity Build by Technology: $label",
        ytitle="GW",
        colors=[default_plot_color(string(t)) for t in new_cap.Technology],
    )
    save_plot_outputs(new_fig, joinpath(paths.plots_path, "new_capacity_by_technology"); formats=formats)

    final_zone_fig = build_stacked_zone_figure(
        rename(final_zone, :Capacity_GW => :Value),
        "Value";
        title="Installed Capacity by Zone: $label",
        ytitle="GW",
    )
    save_plot_outputs(final_zone_fig, joinpath(paths.plots_path, "capacity_by_zone"); formats=formats)

    new_zone_fig = build_stacked_zone_figure(
        rename(new_zone, :Capacity_GW => :Value),
        "Value";
        title="New Capacity Build by Zone: $label",
        ytitle="GW",
    )
    save_plot_outputs(new_zone_fig, joinpath(paths.plots_path, "new_capacity_by_zone"); formats=formats)

    if nrow(storage_power) > 0
        storage_power_fig = build_stacked_zone_figure(
            rename(storage_power, :Value_GW => :Value),
            "Value";
            title="Storage Power by Zone: $label",
            ytitle="GW",
        )
        save_plot_outputs(storage_power_fig, joinpath(paths.plots_path, "storage_power_by_zone"); formats=formats)
    end

    if nrow(storage_energy) > 0
        storage_energy_fig = build_stacked_zone_figure(
            rename(storage_energy, :Value_GWh => :Value),
            "Value";
            title="Storage Energy by Zone: $label",
            ytitle="GWh",
        )
        save_plot_outputs(storage_energy_fig, joinpath(paths.plots_path, "storage_energy_by_zone"); formats=formats)
    end

    println("Wrote capacity plots to $(paths.plots_path)")
    return paths.plots_path
end

if abspath(PROGRAM_FILE) == @__FILE__
    isempty(ARGS) && error("Usage: julia --project=. tools/plotting/plot_output_capacity.jl <case_path> [png|html|svg,...]")
    formats = length(ARGS) >= 2 ? split(ARGS[2], ",") : String["png"]
    build_capacity_plots(ARGS[1]; formats=formats)
end
