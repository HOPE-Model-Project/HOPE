"""
# OutputWriter.jl - Unified Output Generation System
# 
# This module provides a unified framework for writing model outputs
# to various formats (CSV, Excel, HDF5) with standardized structure.
"""

module OutputWriter

using JuMP
using DataFrames
using CSV
using XLSX
using Dates

"""
Output writer structure for managing result export
"""
mutable struct HOPEOutputWriter
    output_path::String
    model_mode::String
    timestamp::String
    config::Dict
    
    function HOPEOutputWriter(output_path::String, model_mode::String, config::Dict)
        # Create timestamped output directory
        timestamp = Dates.format(now(), "yyyy-mm-dd_HH-MM-SS")
        full_output_path = joinpath(output_path, "$(model_mode)_$(timestamp)")
        mkpath(full_output_path)
        
        new(full_output_path, model_mode, timestamp, config)
    end
end

"""
Main output writing function
"""
function write_results!(
    writer::HOPEOutputWriter,
    builder,
    solve_info::Dict
)
    println("📝 Writing results to: $(writer.output_path)")
    
    # Write solve information
    write_solve_info!(writer, solve_info)
    
    # Write model variables based on mode
    if writer.model_mode == "GTEP"
        write_gtep_results!(writer, builder)
    elseif writer.model_mode == "PCM"
        write_pcm_results!(writer, builder)
    elseif writer.model_mode == "HOLISTIC"
        write_holistic_results!(writer, builder)
    end
    
    # Write objective value breakdown
    write_objective_breakdown!(writer, builder)
    
    # Write model summary
    write_model_summary!(writer, builder)
    
    println("✅ All results written successfully")
end

"""
Write solve information to a summary file
"""
function write_solve_info!(writer::HOPEOutputWriter, solve_info::Dict)
    solve_df = DataFrame(
        Metric = ["Solve Status", "Objective Value", "Solve Time (s)", "Optimizer", "Gap (%)"],
        Value = [
            solve_info["status"],
            get(solve_info, "objective_value", "N/A"),
            get(solve_info, "solve_time", "N/A"),
            get(solve_info, "optimizer", "N/A"),
            get(solve_info, "gap", "N/A")
        ]
    )
    
    CSV.write(joinpath(writer.output_path, "solve_summary.csv"), solve_df)
end

"""
Write GTEP model results
"""
function write_gtep_results!(writer::HOPEOutputWriter, builder)
    model = builder.model
    input_data = builder.input_data
    time_indices = get_time_indices(builder.time_manager)
    
    T = time_indices[:T]
    H_T = time_indices[:H_T]
    
    # Investment decisions
    if haskey(builder.variables, :x)
        inv_gen_data = []
        for g in input_data["G_new"]
            if value(model[:x][g]) > 1e-6
                push!(inv_gen_data, (
                    Generator = g,
                    Investment = value(model[:x][g]),
                    Capacity_MW = value(model[:x][g]) * input_data["Gendata_candidate"][g, Symbol("Pmax (MW)")],
                    Technology = input_data["Gendata_candidate"][g, Symbol("Fuel")],
                    Zone = input_data["Gendata_candidate"][g, Symbol("Zone")]
                ))
            end
        end
        
        if !isempty(inv_gen_data)
            inv_gen_df = DataFrame(inv_gen_data)
            CSV.write(joinpath(writer.output_path, "investment_generators.csv"), inv_gen_df)
        end
    end
    
    # Transmission investments
    if haskey(builder.variables, :y)
        inv_line_data = []
        for l in input_data["L_new"]
            if value(model[:y][l]) > 1e-6
                push!(inv_line_data, (
                    Line = l,
                    Investment = value(model[:y][l]),
                    Capacity_MW = value(model[:y][l]) * input_data["Linedata_candidate"][l, Symbol("Pmax (MW)")],
                    From_Zone = input_data["Linedata_candidate"][l, Symbol("From")],
                    To_Zone = input_data["Linedata_candidate"][l, Symbol("To")]
                ))
            end
        end
        
        if !isempty(inv_line_data)
            inv_line_df = DataFrame(inv_line_data)
            CSV.write(joinpath(writer.output_path, "investment_transmission.csv"), inv_line_df)
        end
    end
    
    # Storage investments
    if haskey(builder.variables, :z)
        inv_storage_data = []
        for s in input_data["S_new"]
            if value(model[:z][s]) > 1e-6
                push!(inv_storage_data, (
                    Storage = s,
                    Investment = value(model[:z][s]),
                    Energy_Capacity_MWh = value(model[:z][s]) * input_data["Storagedata_candidate"][s, Symbol("Capacity (MWh)")],
                    Power_Capacity_MW = value(model[:z][s]) * input_data["Storagedata_candidate"][s, Symbol("Pmax (MW)")],
                    Zone = input_data["Storagedata_candidate"][s, Symbol("Zone")]
                ))
            end
        end
        
        if !isempty(inv_storage_data)
            inv_storage_df = DataFrame(inv_storage_data)
            CSV.write(joinpath(writer.output_path, "investment_storage.csv"), inv_storage_df)
        end
    end
    
    # Generation by time period
    write_generation_time_series!(writer, builder, "GTEP")
    
    # Transmission flows
    write_transmission_flows!(writer, builder, "GTEP")
    
    # Storage operation
    write_storage_operation!(writer, builder, "GTEP")
end

"""
Write PCM model results
"""
function write_pcm_results!(writer::HOPEOutputWriter, builder)
    model = builder.model
    input_data = builder.input_data
    
    # Hourly generation
    write_generation_time_series!(writer, builder, "PCM")
    
    # Hourly transmission flows
    write_transmission_flows!(writer, builder, "PCM")
    
    # Storage operation
    write_storage_operation!(writer, builder, "PCM")
    
    # Unit commitment results (if applicable)
    if haskey(builder.variables, :u)
        write_unit_commitment_results!(writer, builder)
    end
    
    # Demand response (if applicable)
    if haskey(builder.variables, :dr)
        write_demand_response_results!(writer, builder)
    end
end

"""
Write holistic model results
"""
function write_holistic_results!(writer::HOPEOutputWriter, builder)
    # Write both GTEP and PCM style outputs
    write_gtep_results!(writer, builder)
    write_pcm_results!(writer, builder)
end

"""
Write generation time series data
"""
function write_generation_time_series!(writer::HOPEOutputWriter, builder, mode::String)
    model = builder.model
    input_data = builder.input_data
    
    if mode == "GTEP"
        time_indices = get_time_indices(builder.time_manager)
        T = time_indices[:T]
        H_T = time_indices[:H_T]
        
        gen_data = []
        for g in union(input_data["G"], input_data["G_new"])
            for t in T
                for h in H_T[t]
                    if value(model[:p][g,t,h]) > 1e-6
                        push!(gen_data, (
                            Generator = g,
                            Period = t,
                            Hour = h,
                            Generation_MW = value(model[:p][g,t,h]),
                            Technology = get(input_data["Gendata"], g, get(input_data["Gendata_candidate"], g, Dict()))[:Fuel],
                            Zone = get(input_data["Gendata"], g, get(input_data["Gendata_candidate"], g, Dict()))[:Zone]
                        ))
                    end
                end
            end
        end
        
    elseif mode == "PCM"
        H = input_data["H"]
        
        gen_data = []
        for g in input_data["G"]
            for h in H
                if value(model[:p][g,h]) > 1e-6
                    push!(gen_data, (
                        Generator = g,
                        Hour = h,
                        Generation_MW = value(model[:p][g,h]),
                        Technology = input_data["Gendata"][g, Symbol("Fuel")],
                        Zone = input_data["Gendata"][g, Symbol("Zone")]
                    ))
                end
            end
        end
    end
    
    if !isempty(gen_data)
        gen_df = DataFrame(gen_data)
        CSV.write(joinpath(writer.output_path, "power_hourly.csv"), gen_df)
    end
end

"""
Write transmission flow data
"""
function write_transmission_flows!(writer::HOPEOutputWriter, builder, mode::String)
    model = builder.model
    input_data = builder.input_data
    
    if mode == "GTEP"
        time_indices = get_time_indices(builder.time_manager)
        T = time_indices[:T]
        H_T = time_indices[:H_T]
        
        flow_data = []
        for l in union(input_data["L"], input_data["L_new"])
            for t in T
                for h in H_T[t]
                    flow_val = value(model[:f][l,t,h])
                    if abs(flow_val) > 1e-6
                        line_info = get(input_data["Linedata"], l, get(input_data["Linedata_candidate"], l, Dict()))
                        push!(flow_data, (
                            Line = l,
                            Period = t,
                            Hour = h,
                            Flow_MW = flow_val,
                            From_Zone = line_info[Symbol("From")],
                            To_Zone = line_info[Symbol("To")]
                        ))
                    end
                end
            end
        end
        
    elseif mode == "PCM"
        H = input_data["H"]
        
        flow_data = []
        for l in input_data["L"]
            for h in H
                flow_val = value(model[:f][l,h])
                if abs(flow_val) > 1e-6
                    push!(flow_data, (
                        Line = l,
                        Hour = h,
                        Flow_MW = flow_val,
                        From_Zone = input_data["Linedata"][l, Symbol("From")],
                        To_Zone = input_data["Linedata"][l, Symbol("To")]
                    ))
                end
            end
        end
    end
    
    if !isempty(flow_data)
        flow_df = DataFrame(flow_data)
        CSV.write(joinpath(writer.output_path, "power_flow.csv"), flow_data)
    end
end

"""
Write storage operation data
"""
function write_storage_operation!(writer::HOPEOutputWriter, builder, mode::String)
    model = builder.model
    input_data = builder.input_data
    
    if mode == "GTEP"
        time_indices = get_time_indices(builder.time_manager)
        T = time_indices[:T]
        H_T = time_indices[:H_T]
        
        # Storage charge
        charge_data = []
        discharge_data = []
        soc_data = []
        
        for s in union(input_data["S"], input_data["S_new"])
            for t in T
                for h in H_T[t]
                    charge_val = value(model[:c][s,t,h])
                    discharge_val = value(model[:dc][s,t,h])
                    soc_val = value(model[:soc][s,t,h])
                    
                    storage_info = get(input_data["Storagedata"], s, get(input_data["Storagedata_candidate"], s, Dict()))
                    
                    if charge_val > 1e-6
                        push!(charge_data, (
                            Storage = s,
                            Period = t,
                            Hour = h,
                            Charge_MW = charge_val,
                            Zone = storage_info[Symbol("Zone")]
                        ))
                    end
                    
                    if discharge_val > 1e-6
                        push!(discharge_data, (
                            Storage = s,
                            Period = t,
                            Hour = h,
                            Discharge_MW = discharge_val,
                            Zone = storage_info[Symbol("Zone")]
                        ))
                    end
                    
                    if soc_val > 1e-6
                        push!(soc_data, (
                            Storage = s,
                            Period = t,
                            Hour = h,
                            SOC_MWh = soc_val,
                            Zone = storage_info[Symbol("Zone")]
                        ))
                    end
                end
            end
        end
        
    elseif mode == "PCM"
        H = input_data["H"]
        
        charge_data = []
        discharge_data = []
        soc_data = []
        
        for s in input_data["S"]
            for h in H
                charge_val = value(model[:c][s,h])
                discharge_val = value(model[:dc][s,h])
                soc_val = value(model[:soc][s,h])
                
                if charge_val > 1e-6
                    push!(charge_data, (
                        Storage = s,
                        Hour = h,
                        Charge_MW = charge_val,
                        Zone = input_data["Storagedata"][s, Symbol("Zone")]
                    ))
                end
                
                if discharge_val > 1e-6
                    push!(discharge_data, (
                        Storage = s,
                        Hour = h,
                        Discharge_MW = discharge_val,
                        Zone = input_data["Storagedata"][s, Symbol("Zone")]
                    ))
                end
                
                if soc_val > 1e-6
                    push!(soc_data, (
                        Storage = s,
                        Hour = h,
                        SOC_MWh = soc_val,
                        Zone = input_data["Storagedata"][s, Symbol("Zone")]
                    ))
                end
            end
        end
    end
    
    # Write storage files
    if !isempty(charge_data)
        CSV.write(joinpath(writer.output_path, "es_power_charge.csv"), DataFrame(charge_data))
    end
    if !isempty(discharge_data)
        CSV.write(joinpath(writer.output_path, "es_power_discharge.csv"), DataFrame(discharge_data))
    end
    if !isempty(soc_data)
        CSV.write(joinpath(writer.output_path, "es_power_soc.csv"), DataFrame(soc_data))
    end
end

"""
Write unit commitment results (for PCM with UC)
"""
function write_unit_commitment_results!(writer::HOPEOutputWriter, builder)
    model = builder.model
    input_data = builder.input_data
    H = input_data["H"]
    
    uc_data = []
    for g in input_data["G_UC"]
        for h in H
            push!(uc_data, (
                Generator = g,
                Hour = h,
                Online = value(model[:u][g,h]),
                Startup = value(model[:v][g,h]),
                Shutdown = value(model[:w][g,h]),
                Min_Power_MW = value(model[:pmin][g,h]),
                Technology = input_data["Gendata"][g, Symbol("Fuel")]
            ))
        end
    end
    
    if !isempty(uc_data)
        uc_df = DataFrame(uc_data)
        CSV.write(joinpath(writer.output_path, "unit_commitment.csv"), uc_df)
    end
end

"""
Write demand response results
"""
function write_demand_response_results!(writer::HOPEOutputWriter, builder)
    model = builder.model
    input_data = builder.input_data
    
    if haskey(input_data, "H")
        H = input_data["H"]
        
        dr_data = []
        for d in input_data["D"]
            for h in H
                push!(dr_data, (
                    DR_Resource = d,
                    Hour = h,
                    Response = value(model[:dr][d,h]),
                    Up_Reserve = value(model[:dr_UP][d,h]),
                    Down_Reserve = value(model[:dr_DN][d,h])
                ))
            end
        end
        
        if !isempty(dr_data)
            dr_df = DataFrame(dr_data)
            CSV.write(joinpath(writer.output_path, "demand_response.csv"), dr_df)
        end
    end
end

"""
Write objective value breakdown
"""
function write_objective_breakdown!(writer::HOPEOutputWriter, builder)
    obj_data = []
    
    # Get objective components
    if haskey(builder.expressions, :INVCost)
        push!(obj_data, ("Investment Cost", value(builder.expressions[:INVCost])))
    end
    
    if haskey(builder.expressions, :OPCost)
        push!(obj_data, ("Operation Cost", value(builder.expressions[:OPCost])))
    end
    
    if haskey(builder.expressions, :STCost)
        push!(obj_data, ("Startup Cost", value(builder.expressions[:STCost])))
    end
    
    if haskey(builder.expressions, :PenaltyCost)
        push!(obj_data, ("Penalty Cost", value(builder.expressions[:PenaltyCost])))
    end
    
    push!(obj_data, ("Total Objective", objective_value(builder.model)))
    
    obj_df = DataFrame(Component = first.(obj_data), Value = last.(obj_data))
    CSV.write(joinpath(writer.output_path, "objective_breakdown.csv"), obj_df)
end

"""
Write model summary and statistics
"""
function write_model_summary!(writer::HOPEOutputWriter, builder)
    report = get_model_report(builder)
    
    summary_data = [
        ("Model Mode", report["model_mode"]),
        ("Number of Variables", report["num_variables"]),
        ("Number of Constraints", report["num_constraints"]),
        ("Time Structure", report["time_structure"]),
        ("Generation Timestamp", writer.timestamp)
    ]
    
    summary_df = DataFrame(Metric = first.(summary_data), Value = last.(summary_data))
    CSV.write(joinpath(writer.output_path, "model_summary.csv"), summary_df)
    
    # Write constraint report as separate file
    if haskey(report, "constraint_report")
        constraint_df = DataFrame(
            Constraint_Type = collect(keys(report["constraint_report"])),
            Count = collect(values(report["constraint_report"]))
        )
        CSV.write(joinpath(writer.output_path, "constraint_summary.csv"), constraint_df)
    end
end

# Export main functions and types
export HOPEOutputWriter
export write_results!

end # module OutputWriter
