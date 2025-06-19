"""
# PlotGenerator.jl - Unified Plotting System
# 
# This module provides standardized plotting capabilities for HOPE model results
# using basic CSV output for now (can be extended with plotting libraries later).
"""

module PlotGenerator

using DataFrames
using CSV
using Dates

# Conditional plotting imports
const HAS_PLOTLYJS = try
    using PlotlyJS
    using Colors
    true
catch
    false
end

"""
Plot generator structure for creating standardized visualizations
"""
struct HOPEPlotGenerator
    output_path::String
    model_mode::String
    config::Dict
    
    function HOPEPlotGenerator(output_path::String, model_mode::String, config::Dict)
        # Create plots subdirectory
        plot_path = joinpath(output_path, "plots")
        mkpath(plot_path)
        new(plot_path, model_mode, config)
    end
end

"""
Generate all standard plots for the model results
"""
function generate_all_plots!(generator::HOPEPlotGenerator, results_path::String)
    println("📊 Generating plots in: $(generator.output_path)")
    
    if !HAS_PLOTLYJS
        println("⚠️  PlotlyJS not available, creating plot data files instead")
        create_plot_data_files!(generator, results_path)
        return
    end
    
    try
        if generator.model_mode == "GTEP"
            generate_gtep_plots!(generator, results_path)
        elseif generator.model_mode == "PCM"
            generate_pcm_plots!(generator, results_path)
        elseif generator.model_mode == "HOLISTIC"
            generate_holistic_plots!(generator, results_path)
        end
        
        println("✅ All plots generated successfully")
    catch e
        println("⚠️  Warning: Some plots could not be generated: $e")
        # Fallback to data files
        create_plot_data_files!(generator, results_path)
    end
end

"""
Create plot data files when plotting libraries are not available
"""
function create_plot_data_files!(generator::HOPEPlotGenerator, results_path::String)
    println("📋 Creating plot data files...")
    
    # Investment summary
    plot_investment_summary_data!(generator, results_path)
    
    # Generation summary  
    plot_generation_summary_data!(generator, results_path)
    
    # System summary
    plot_system_summary_data!(generator, results_path)
    
    println("✅ Plot data files created")
end

"""
Generate GTEP-specific plots
"""
function generate_gtep_plots!(generator::HOPEPlotGenerator, results_path::String)
    # Investment plots
    plot_investment_decisions!(generator, results_path)
    
    # Generation mix plots
    plot_generation_mix!(generator, results_path)
    
    # Transmission utilization
    plot_transmission_flows!(generator, results_path)
    
    # Storage operation
    plot_storage_operation!(generator, results_path)
    
    # Objective breakdown
    plot_objective_breakdown!(generator, results_path)
end

"""
Generate PCM-specific plots
"""
function generate_pcm_plots!(generator::HOPEPlotGenerator, results_path::String)
    # Hourly generation
    plot_hourly_generation!(generator, results_path)
    
    # Load following
    plot_load_following!(generator, results_path)
    
    # Storage cycling
    plot_storage_cycling!(generator, results_path)
    
    # Transmission congestion
    plot_transmission_congestion!(generator, results_path)
    
    # Unit commitment (if applicable)
    if isfile(joinpath(results_path, "unit_commitment.csv"))
        plot_unit_commitment!(generator, results_path)
    end
end

"""
Generate holistic model plots
"""
function generate_holistic_plots!(generator::HOPEPlotGenerator, results_path::String)
    generate_gtep_plots!(generator, results_path)
    generate_pcm_plots!(generator, results_path)
end

"""
Plot investment decisions (GTEP)
"""
function plot_investment_decisions!(generator::HOPEPlotGenerator, results_path::String)
    # Generator investments
    gen_file = joinpath(results_path, "investment_generators.csv")
    if isfile(gen_file)
        gen_df = CSV.read(gen_file, DataFrame)
        
        if nrow(gen_df) > 0
            # Investment by technology
            tech_capacity = combine(groupby(gen_df, :Technology), :Capacity_MW => sum => :Total_Capacity)
            
            p1 = plot(
                tech_capacity,
                x=:Technology,
                y=:Total_Capacity,
                kind="bar",
                Layout(
                    title="Generator Investment by Technology",
                    xaxis_title="Technology",
                    yaxis_title="Capacity (MW)",
                    showlegend=false
                )
            )
            
            savefig(p1, joinpath(generator.output_path, "investment_generators_by_tech.html"))
            
            # Investment by zone
            zone_capacity = combine(groupby(gen_df, :Zone), :Capacity_MW => sum => :Total_Capacity)
            
            p2 = plot(
                zone_capacity,
                x=:Zone,
                y=:Total_Capacity,
                kind="bar",
                Layout(
                    title="Generator Investment by Zone",
                    xaxis_title="Zone",
                    yaxis_title="Capacity (MW)",
                    showlegend=false
                )
            )
            
            savefig(p2, joinpath(generator.output_path, "investment_generators_by_zone.html"))
        end
    end
    
    # Transmission investments
    line_file = joinpath(results_path, "investment_transmission.csv")
    if isfile(line_file)
        line_df = CSV.read(line_file, DataFrame)
        
        if nrow(line_df) > 0
            p3 = plot(
                line_df,
                x=:Line,
                y=:Capacity_MW,
                kind="bar",
                Layout(
                    title="Transmission Line Investments",
                    xaxis_title="Transmission Line",
                    yaxis_title="Capacity (MW)",
                    showlegend=false
                )
            )
            
            savefig(p3, joinpath(generator.output_path, "investment_transmission.html"))
        end
    end
    
    # Storage investments
    storage_file = joinpath(results_path, "investment_storage.csv")
    if isfile(storage_file)
        storage_df = CSV.read(storage_file, DataFrame)
        
        if nrow(storage_df) > 0
            # Energy capacity
            p4 = plot(
                storage_df,
                x=:Storage,
                y=:Energy_Capacity_MWh,
                kind="bar",
                Layout(
                    title="Storage Energy Capacity Investments",
                    xaxis_title="Storage Resource",
                    yaxis_title="Energy Capacity (MWh)",
                    showlegend=false
                )
            )
            
            savefig(p4, joinpath(generator.output_path, "investment_storage_energy.html"))
            
            # Power capacity
            p5 = plot(
                storage_df,
                x=:Storage,
                y=:Power_Capacity_MW,
                kind="bar",
                Layout(
                    title="Storage Power Capacity Investments",
                    xaxis_title="Storage Resource",
                    yaxis_title="Power Capacity (MW)",
                    showlegend=false
                )
            )
            
            savefig(p5, joinpath(generator.output_path, "investment_storage_power.html"))
        end
    end
end

"""
Plot generation mix
"""
function plot_generation_mix!(generator::HOPEPlotGenerator, results_path::String)
    gen_file = joinpath(results_path, "power_hourly.csv")
    if isfile(gen_file)
        gen_df = CSV.read(gen_file, DataFrame)
        
        if nrow(gen_df) > 0
            # Generation by technology
            tech_gen = combine(groupby(gen_df, :Technology), :Generation_MW => sum => :Total_Generation)
            
            p1 = plot(
                tech_gen,
                x=:Technology,
                y=:Total_Generation,
                kind="bar",
                Layout(
                    title="Total Generation by Technology",
                    xaxis_title="Technology",
                    yaxis_title="Generation (MWh)",
                    showlegend=false
                )
            )
            
            savefig(p1, joinpath(generator.output_path, "generation_by_technology.html"))
            
            # Pie chart for technology mix
            p2 = plot(
                tech_gen,
                labels=:Technology,
                values=:Total_Generation,
                kind="pie",
                Layout(title="Generation Mix by Technology")
            )
            
            savefig(p2, joinpath(generator.output_path, "generation_mix_pie.html"))
            
            # Generation by zone
            zone_gen = combine(groupby(gen_df, :Zone), :Generation_MW => sum => :Total_Generation)
            
            p3 = plot(
                zone_gen,
                x=:Zone,
                y=:Total_Generation,
                kind="bar",
                Layout(
                    title="Total Generation by Zone",
                    xaxis_title="Zone",
                    yaxis_title="Generation (MWh)",
                    showlegend=false
                )
            )
            
            savefig(p3, joinpath(generator.output_path, "generation_by_zone.html"))
        end
    end
end

"""
Plot hourly generation time series (PCM)
"""
function plot_hourly_generation!(generator::HOPEPlotGenerator, results_path::String)
    gen_file = joinpath(results_path, "power_hourly.csv")
    if isfile(gen_file)
        gen_df = CSV.read(gen_file, DataFrame)
        
        if nrow(gen_df) > 0 && :Hour in names(gen_df)
            # Stack plot by technology over time
            tech_hourly = combine(
                groupby(gen_df, [:Hour, :Technology]), 
                :Generation_MW => sum => :Generation
            )
            
            technologies = unique(tech_hourly.Technology)
            colors = distinguishable_colors(length(technologies))
            
            traces = []
            for (i, tech) in enumerate(technologies)
                tech_data = filter(row -> row.Technology == tech, tech_hourly)
                sort!(tech_data, :Hour)
                
                push!(traces, 
                    scatter(
                        x=tech_data.Hour,
                        y=tech_data.Generation,
                        mode="lines",
                        stackgroup="one",
                        name=tech,
                        line=attr(color=hex(colors[i]))
                    )
                )
            end
            
            layout = Layout(
                title="Hourly Generation by Technology",
                xaxis_title="Hour",
                yaxis_title="Generation (MW)",
                hovermode="x unified"
            )
            
            p1 = plot(traces, layout)
            savefig(p1, joinpath(generator.output_path, "hourly_generation_stack.html"))
            
            # Sample week view (first 168 hours)
            if maximum(tech_hourly.Hour) >= 168
                week_data = filter(row -> row.Hour <= 168, tech_hourly)
                
                week_traces = []
                for (i, tech) in enumerate(technologies)
                    tech_week = filter(row -> row.Technology == tech, week_data)
                    sort!(tech_week, :Hour)
                    
                    push!(week_traces,
                        scatter(
                            x=tech_week.Hour,
                            y=tech_week.Generation,
                            mode="lines",
                            stackgroup="one",
                            name=tech,
                            line=attr(color=hex(colors[i]))
                        )
                    )
                end
                
                week_layout = Layout(
                    title="First Week Generation by Technology",
                    xaxis_title="Hour",
                    yaxis_title="Generation (MW)",
                    hovermode="x unified"
                )
                
                p2 = plot(week_traces, week_layout)
                savefig(p2, joinpath(generator.output_path, "weekly_generation_stack.html"))
            end
        end
    end
end

"""
Plot transmission flows
"""
function plot_transmission_flows!(generator::HOPEPlotGenerator, results_path::String)
    flow_file = joinpath(results_path, "power_flow.csv")
    if isfile(flow_file)
        flow_df = CSV.read(flow_file, DataFrame)
        
        if nrow(flow_df) > 0
            # Flow utilization by line
            line_flows = combine(groupby(flow_df, :Line), 
                :Flow_MW => (x -> sum(abs.(x))) => :Total_Flow)
            sort!(line_flows, :Total_Flow, rev=true)
            
            p1 = plot(
                line_flows,
                x=:Line,
                y=:Total_Flow,
                kind="bar",
                Layout(
                    title="Transmission Line Utilization",
                    xaxis_title="Transmission Line",
                    yaxis_title="Total Flow (MWh)",
                    showlegend=false
                )
            )
            
            savefig(p1, joinpath(generator.output_path, "transmission_utilization.html"))
        end
    end
end

"""
Plot storage operation
"""
function plot_storage_operation!(generator::HOPEPlotGenerator, results_path::String)
    # Storage SOC
    soc_file = joinpath(results_path, "es_power_soc.csv")
    if isfile(soc_file)
        soc_df = CSV.read(soc_file, DataFrame)
        
        if nrow(soc_df) > 0 && :Hour in names(soc_df)
            # SOC over time for each storage resource
            storage_units = unique(soc_df.Storage)
            colors = distinguishable_colors(length(storage_units))
            
            traces = []
            for (i, storage) in enumerate(storage_units)
                storage_data = filter(row -> row.Storage == storage, soc_df)
                sort!(storage_data, :Hour)
                
                push!(traces,
                    scatter(
                        x=storage_data.Hour,
                        y=storage_data.SOC_MWh,
                        mode="lines",
                        name=storage,
                        line=attr(color=hex(colors[i]))
                    )
                )
            end
            
            layout = Layout(
                title="Storage State of Charge Over Time",
                xaxis_title="Hour",
                yaxis_title="SOC (MWh)"
            )
            
            p1 = plot(traces, layout)
            savefig(p1, joinpath(generator.output_path, "storage_soc.html"))
        end
    end
    
    # Storage charge/discharge
    charge_file = joinpath(results_path, "es_power_charge.csv")
    discharge_file = joinpath(results_path, "es_power_discharge.csv")
    
    if isfile(charge_file) && isfile(discharge_file)
        charge_df = CSV.read(charge_file, DataFrame)
        discharge_df = CSV.read(discharge_file, DataFrame)
        
        if nrow(charge_df) > 0 && nrow(discharge_df) > 0 && :Hour in names(charge_df)
            # Combined charge/discharge plot for first storage unit
            if !isempty(charge_df.Storage)
                first_storage = first(charge_df.Storage)
                
                storage_charge = filter(row -> row.Storage == first_storage, charge_df)
                storage_discharge = filter(row -> row.Storage == first_storage, discharge_df)
                
                sort!(storage_charge, :Hour)
                sort!(storage_discharge, :Hour)
                
                # Make discharge negative for visualization
                storage_discharge.Discharge_MW = -storage_discharge.Discharge_MW
                
                p2 = plot([
                    scatter(
                        x=storage_charge.Hour,
                        y=storage_charge.Charge_MW,
                        mode="lines",
                        name="Charge",
                        line=attr(color="blue")
                    ),
                    scatter(
                        x=storage_discharge.Hour,
                        y=storage_discharge.Discharge_MW,
                        mode="lines",
                        name="Discharge",
                        line=attr(color="red")
                    )
                ], Layout(
                    title="Storage Charge/Discharge - $first_storage",
                    xaxis_title="Hour",
                    yaxis_title="Power (MW)",
                    hovermode="x unified"
                ))
                
                savefig(p2, joinpath(generator.output_path, "storage_charge_discharge.html"))
            end
        end
    end
end

"""
Plot unit commitment results
"""
function plot_unit_commitment!(generator::HOPEPlotGenerator, results_path::String)
    uc_file = joinpath(results_path, "unit_commitment.csv")
    if isfile(uc_file)
        uc_df = CSV.read(uc_file, DataFrame)
        
        if nrow(uc_df) > 0
            # Unit commitment status heatmap
            uc_pivot = unstack(uc_df, :Hour, :Generator, :Online)
            
            # Create heatmap
            p1 = plot(
                heatmap(
                    z=Matrix(uc_pivot[:, 2:end]),
                    x=names(uc_pivot)[2:end],
                    y=uc_pivot.Hour,
                    colorscale="RdYlBu"
                ),
                Layout(
                    title="Unit Commitment Status",
                    xaxis_title="Generator",
                    yaxis_title="Hour"
                )
            )
            
            savefig(p1, joinpath(generator.output_path, "unit_commitment_heatmap.html"))
        end
    end
end

"""
Plot objective breakdown
"""
function plot_objective_breakdown!(generator::HOPEPlotGenerator, results_path::String)
    obj_file = joinpath(results_path, "objective_breakdown.csv")
    if isfile(obj_file)
        obj_df = CSV.read(obj_file, DataFrame)
        
        if nrow(obj_df) > 0
            # Filter out total objective for component breakdown
            components = filter(row -> row.Component != "Total Objective", obj_df)
            
            if nrow(components) > 0
                p1 = plot(
                    components,
                    x=:Component,
                    y=:Value,
                    kind="bar",
                    Layout(
                        title="Objective Function Components",
                        xaxis_title="Cost Component",
                        yaxis_title="Cost (USD)",
                        showlegend=false
                    )
                )
                
                savefig(p1, joinpath(generator.output_path, "objective_breakdown.html"))
                
                # Pie chart
                p2 = plot(
                    components,
                    labels=:Component,
                    values=:Value,
                    kind="pie",
                    Layout(title="Cost Component Breakdown")
                )
                
                savefig(p2, joinpath(generator.output_path, "objective_breakdown_pie.html"))
            end
        end
    end
end

"""
Plot load following analysis (PCM)
"""
function plot_load_following!(generator::HOPEPlotGenerator, results_path::String)
    gen_file = joinpath(results_path, "power_hourly.csv")
    
    if isfile(gen_file)
        gen_df = CSV.read(gen_file, DataFrame)
        
        if nrow(gen_df) > 0 && :Hour in names(gen_df)
            # Calculate total generation by hour
            hourly_gen = combine(groupby(gen_df, :Hour), :Generation_MW => sum => :Total_Generation)
            sort!(hourly_gen, :Hour)
            
            # Sample first week for detailed view
            if maximum(hourly_gen.Hour) >= 168
                week_gen = filter(row -> row.Hour <= 168, hourly_gen)
                
                p1 = plot(
                    week_gen,
                    x=:Hour,
                    y=:Total_Generation,
                    kind="scatter",
                    mode="lines",
                    Layout(
                        title="Total Generation - First Week",
                        xaxis_title="Hour",
                        yaxis_title="Generation (MW)"
                    )
                )
                
                savefig(p1, joinpath(generator.output_path, "load_following_week.html"))
            end
        end
    end
end

"""
Plot transmission congestion analysis
"""
function plot_transmission_congestion!(generator::HOPEPlotGenerator, results_path::String)
    flow_file = joinpath(results_path, "power_flow.csv")
    if isfile(flow_file)
        flow_df = CSV.read(flow_file, DataFrame)
        
        if nrow(flow_df) > 0 && :Hour in names(flow_df)
            # Flow utilization over time for top congested lines
            line_util = combine(groupby(flow_df, :Line), 
                :Flow_MW => (x -> sum(abs.(x))) => :Total_Utilization)
            sort!(line_util, :Total_Utilization, rev=true)
            
            # Plot top 5 most utilized lines over time
            top_lines = first(line_util, 5).Line
            
            if !isempty(top_lines)
                colors = distinguishable_colors(length(top_lines))
                traces = []
                
                for (i, line) in enumerate(top_lines)
                    line_data = filter(row -> row.Line == line, flow_df)
                    sort!(line_data, :Hour)
                    
                    push!(traces,
                        scatter(
                            x=line_data.Hour,
                            y=abs.(line_data.Flow_MW),
                            mode="lines",
                            name=line,
                            line=attr(color=hex(colors[i]))
                        )
                    )
                end
                
                layout = Layout(
                    title="Transmission Line Utilization (Top 5 Lines)",
                    xaxis_title="Hour",
                    yaxis_title="Flow (MW)"
                )
                
                p1 = plot(traces, layout)
                savefig(p1, joinpath(generator.output_path, "transmission_congestion.html"))
            end
        end
    end
end

"""
Plot storage cycling analysis
"""
function plot_storage_cycling!(generator::HOPEPlotGenerator, results_path::String)
    charge_file = joinpath(results_path, "es_power_charge.csv")
    discharge_file = joinpath(results_path, "es_power_discharge.csv")
    
    if isfile(charge_file) && isfile(discharge_file)
        charge_df = CSV.read(charge_file, DataFrame)
        discharge_df = CSV.read(discharge_file, DataFrame)
        
        if nrow(charge_df) > 0 && nrow(discharge_df) > 0
            # Calculate cycling metrics by storage unit
            storage_cycling = []
            
            for storage in unique(vcat(charge_df.Storage, discharge_df.Storage))
                storage_charge = filter(row -> row.Storage == storage, charge_df)
                storage_discharge = filter(row -> row.Storage == storage, discharge_df)
                
                total_charge = sum(storage_charge.Charge_MW)
                total_discharge = sum(storage_discharge.Discharge_MW)
                cycles = min(total_charge, total_discharge)
                
                push!(storage_cycling, (
                    Storage = storage,
                    Total_Charge = total_charge,
                    Total_Discharge = total_discharge,
                    Equivalent_Cycles = cycles
                ))
            end
            
            if !isempty(storage_cycling)
                cycling_df = DataFrame(storage_cycling)
                
                p1 = plot(
                    cycling_df,
                    x=:Storage,
                    y=:Equivalent_Cycles,
                    kind="bar",
                    Layout(
                        title="Storage Cycling Analysis",
                        xaxis_title="Storage Unit",
                        yaxis_title="Equivalent Full Cycles",
                        showlegend=false
                    )
                )
                
                savefig(p1, joinpath(generator.output_path, "storage_cycling.html"))
            end
        end    end
end

"""
Create investment summary data file
"""
function plot_investment_summary_data!(generator::HOPEPlotGenerator, results_path::String)
    summary_data = []
    
    # Check for investment files
    gen_file = joinpath(results_path, "investment_generators.csv")
    if isfile(gen_file)
        gen_df = CSV.read(gen_file, DataFrame)
        if nrow(gen_df) > 0
            tech_summary = combine(groupby(gen_df, :Technology), :Capacity_MW => sum => :Total_MW)
            for row in eachrow(tech_summary)
                push!(summary_data, ("Generator Investment", row.Technology, row.Total_MW))
            end
        end
    end
    
    line_file = joinpath(results_path, "investment_transmission.csv")
    if isfile(line_file)
        line_df = CSV.read(line_file, DataFrame)
        if nrow(line_df) > 0
            total_line_capacity = sum(line_df.Capacity_MW)
            push!(summary_data, ("Transmission Investment", "Total", total_line_capacity))
        end
    end
    
    storage_file = joinpath(results_path, "investment_storage.csv")
    if isfile(storage_file)
        storage_df = CSV.read(storage_file, DataFrame)
        if nrow(storage_df) > 0
            total_storage_energy = sum(storage_df.Energy_Capacity_MWh)
            total_storage_power = sum(storage_df.Power_Capacity_MW)
            push!(summary_data, ("Storage Investment", "Energy (MWh)", total_storage_energy))
            push!(summary_data, ("Storage Investment", "Power (MW)", total_storage_power))
        end
    end
    
    if !isempty(summary_data)
        summary_df = DataFrame(
            Category = [x[1] for x in summary_data],
            Type = [x[2] for x in summary_data],
            Value = [x[3] for x in summary_data]
        )
        CSV.write(joinpath(generator.output_path, "investment_summary_data.csv"), summary_df)
    end
end

"""
Create generation summary data file
"""
function plot_generation_summary_data!(generator::HOPEPlotGenerator, results_path::String)
    gen_file = joinpath(results_path, "power_hourly.csv")
    if isfile(gen_file)
        gen_df = CSV.read(gen_file, DataFrame)
        if nrow(gen_df) > 0
            # Technology summary
            if hasproperty(gen_df, :Technology)
                tech_summary = combine(groupby(gen_df, :Technology), :Generation_MW => sum => :Total_MWh)
                CSV.write(joinpath(generator.output_path, "generation_by_technology_data.csv"), tech_summary)
            end
            
            # Zone summary
            if hasproperty(gen_df, :Zone)
                zone_summary = combine(groupby(gen_df, :Zone), :Generation_MW => sum => :Total_MWh)
                CSV.write(joinpath(generator.output_path, "generation_by_zone_data.csv"), zone_summary)
            end
        end
    end
end

"""
Create system summary data file
"""
function plot_system_summary_data!(generator::HOPEPlotGenerator, results_path::String)
    system_data = []
    
    # Objective breakdown
    obj_file = joinpath(results_path, "objective_breakdown.csv")
    if isfile(obj_file)
        obj_df = CSV.read(obj_file, DataFrame)
        for row in eachrow(obj_df)
            push!(system_data, ("Objective", row.Component, row.Value))
        end
    end
    
    # Model summary
    model_file = joinpath(results_path, "model_summary.csv")
    if isfile(model_file)
        model_df = CSV.read(model_file, DataFrame)
        for row in eachrow(model_df)
            push!(system_data, ("Model", row.Metric, row.Value))
        end
    end
    
    if !isempty(system_data)
        system_df = DataFrame(
            Category = [x[1] for x in system_data],
            Metric = [x[2] for x in system_data],
            Value = [x[3] for x in system_data]
        )
        CSV.write(joinpath(generator.output_path, "system_summary_data.csv"), system_df)
    end
end

# Export main functions and types
export HOPEPlotGenerator
export generate_all_plots!

end # module PlotGenerator
