function mkdir_overwrite(path::AbstractString)
    if isdir(path)
        println("'output' folder exists, will be overwritten!")
        
        # Try to remove with retries for Windows file locking issues
        max_retries = 3
        for attempt in 1:max_retries
            try
                rm(path; force=true, recursive=true)
                break  # Success, exit retry loop
            catch e
                if isa(e, SystemError) && attempt < max_retries
                    println("Warning: Failed to remove output directory (attempt $attempt/$max_retries): $(e.msg)")
                    println("Retrying in 1 second...")
                    sleep(1)
                    # Try to force release any file handles
                    GC.gc()
                elseif attempt == max_retries
                    println("Warning: Could not remove existing output directory after $max_retries attempts.")
                    println("This may be due to files being open in another application.")
                    println("Trying to create backup and continue...")
                    
                    # Try to create a backup directory name
                    backup_path = path * "_backup_" * string(round(Int, time()))
                    try
                        mv(path, backup_path)
                        println("Moved existing output to: $backup_path")
                    catch mv_error
                        error("Cannot remove or move existing output directory '$path'. Please close any files/applications that may be using files in this directory and try again.\nOriginal error: $e")
                    end
                end
            end
        end
    end
    
    # Create the directory
    try
        mkdir(path)
    catch e
        if isa(e, SystemError) && occursin("already exists", e.msg)
            # Directory was created between our check and mkdir call, that's fine
            println("Directory was created by another process, continuing...")
        else
            rethrow(e)
        end
    end
end

function parse_setting_int(config_set::Dict, key::String, default_value::Int)
    raw = get(config_set, key, default_value)
    return raw isa Integer ? Int(raw) : parse(Int, string(raw))
end

"""
Build nodal mapping metadata for PCM output post-processing.
Returns bus labels, bus->zone index mapping, zone->bus index lists, and bus load-share weights.
"""
function build_pcm_nodal_output_maps(input_data::Dict)
    Zonedata = input_data["Zonedata"]
    Linedata = haskey(input_data, "Branchdata") ? input_data["Branchdata"] : input_data["Linedata"]
    Busdata = haskey(input_data, "Busdata") ? input_data["Busdata"] : nothing

    Num_zone = length(Zonedata[:, "Zone_id"])
    I = [i for i in 1:Num_zone]
    Idx_zone_dict = Dict(zip([i for i in 1:Num_zone], Zonedata[:, "Zone_id"]))
    Zone_idx_dict = Dict(zip(Zonedata[:, "Zone_id"], [i for i in 1:Num_zone]))
    linedata_cols = Set(string.(names(Linedata)))
    from_zone_col = first_existing_col(linedata_cols, ["From_zone", "from_zone"])
    to_zone_col = first_existing_col(linedata_cols, ["To_zone", "to_zone"])
    from_bus_col = first_existing_col(linedata_cols, ["from_bus", "From_bus", "f_bus", "F_BUS"])
    to_bus_col = first_existing_col(linedata_cols, ["to_bus", "To_bus", "t_bus", "T_BUS"])

    linedata_local = Linedata
    if (from_zone_col === nothing || to_zone_col === nothing) && Busdata !== nothing && from_bus_col !== nothing && to_bus_col !== nothing
        bus_cols = Set(string.(names(Busdata)))
        bus_id_col = first_existing_col(bus_cols, ["Bus_id", "bus_id", "bus_i", "BUS_I", "Bus"])
        bus_zone_col = first_existing_col(bus_cols, ["Zone_id", "zone_id", "Zone", "zone"])
        if bus_id_col !== nothing && bus_zone_col !== nothing
            bus_zone_map = Dict(Busdata[r, bus_id_col] => Busdata[r, bus_zone_col] for r in 1:size(Busdata, 1))
            linedata_local = copy(Linedata)
            linedata_local[!, "From_zone"] = [haskey(bus_zone_map, Linedata[l, from_bus_col]) ? bus_zone_map[Linedata[l, from_bus_col]] : missing for l in 1:size(Linedata, 1)]
            linedata_local[!, "To_zone"] = [haskey(bus_zone_map, Linedata[l, to_bus_col]) ? bus_zone_map[Linedata[l, to_bus_col]] : missing for l in 1:size(Linedata, 1)]
            from_zone_col = "From_zone"
            to_zone_col = "To_zone"
        end
    end
    if from_bus_col === nothing || to_bus_col === nothing
        if from_zone_col === nothing || to_zone_col === nothing
            throw(ArgumentError("Unable to build nodal output mapping: missing from/to bus and from/to zone columns in linedata/branchdata."))
        end
        linedata_local = copy(linedata_local)
        linedata_local[!, "from_bus"] = [linedata_local[l, from_zone_col] for l in 1:size(linedata_local, 1)]
        linedata_local[!, "to_bus"] = [linedata_local[l, to_zone_col] for l in 1:size(linedata_local, 1)]
        from_bus_col = "from_bus"
        to_bus_col = "to_bus"
    end

    bus_labels = Any[]
    bus_to_zone_idx = Dict{Any,Int}()
    if Busdata !== nothing
        bus_cols = Set(string.(names(Busdata)))
        bus_id_col = first_existing_col(bus_cols, ["Bus_id", "bus_id", "bus_i", "BUS_I", "Bus"])
        bus_zone_col = first_existing_col(bus_cols, ["Zone_id", "zone_id", "Zone", "zone"])
        if bus_id_col !== nothing && bus_zone_col !== nothing
            bus_labels = [Busdata[r, bus_id_col] for r in 1:size(Busdata, 1)]
            for r in 1:size(Busdata, 1)
                zone_nm = Busdata[r, bus_zone_col]
                if haskey(Zone_idx_dict, zone_nm)
                    bus_to_zone_idx[Busdata[r, bus_id_col]] = Zone_idx_dict[zone_nm]
                end
            end
        end
    end
    if isempty(bus_labels)
        bus_labels = collect(unique(vcat([linedata_local[l, from_bus_col] for l in 1:size(linedata_local, 1)], [linedata_local[l, to_bus_col] for l in 1:size(linedata_local, 1)])))
    end
    for l in 1:size(linedata_local, 1)
        from_bus = linedata_local[l, from_bus_col]
        to_bus = linedata_local[l, to_bus_col]
        if from_zone_col !== nothing && haskey(Zone_idx_dict, linedata_local[l, from_zone_col])
            bus_to_zone_idx[from_bus] = Zone_idx_dict[linedata_local[l, from_zone_col]]
        end
        if to_zone_col !== nothing && haskey(Zone_idx_dict, linedata_local[l, to_zone_col])
            bus_to_zone_idx[to_bus] = Zone_idx_dict[linedata_local[l, to_zone_col]]
        end
    end
    for b in bus_labels
        if !haskey(bus_to_zone_idx, b)
            bus_to_zone_idx[b] = 1
        end
    end

    N = [n for n in 1:length(bus_labels)]
    bus_idx_dict = Dict(bus_labels[n] => n for n in N)
    bus_zone_of_n = Dict{Int,Int}(n => bus_to_zone_idx[bus_labels[n]] for n in N)
    N_i = [[n for n in N if bus_zone_of_n[n] == i] for i in I]
    bus_weight = Dict{Int,Float64}()
    for i in I
        nodes = N_i[i]
        if isempty(nodes)
            continue
        end
        for n in nodes
            bus_weight[n] = 1.0 / length(nodes)
        end
    end

    if Busdata !== nothing
        bus_cols = Set(string.(names(Busdata)))
        bus_id_col = first_existing_col(bus_cols, ["Bus_id", "bus_id", "bus_i", "BUS_I", "Bus"])
        load_share_col = first_existing_col(bus_cols, ["Load_share", "load_share", "Demand_share", "demand_share"])
        load_mw_col = first_existing_col(bus_cols, ["Demand (MW)", "Load (MW)", "Pd", "PD"])
        if bus_id_col !== nothing && (load_share_col !== nothing || load_mw_col !== nothing)
            for i in I
                nodes = N_i[i]
                if isempty(nodes)
                    continue
                end
                raw = zeros(Float64, length(nodes))
                for (k_idx, n_idx) in enumerate(nodes)
                    bid = bus_labels[n_idx]
                    row_idx = findfirst(Busdata[:, bus_id_col] .== bid)
                    if row_idx === nothing
                        raw[k_idx] = 0.0
                    else
                        raw_val = load_share_col !== nothing ? Busdata[row_idx, load_share_col] : Busdata[row_idx, load_mw_col]
                        raw[k_idx] = raw_val isa Number ? Float64(raw_val) : parse(Float64, string(raw_val))
                    end
                end
                den = sum(raw)
                if den > 0.0
                    for (k_idx, n_idx) in enumerate(nodes)
                        bus_weight[n_idx] = raw[k_idx] / den
                    end
                end
            end
        end
    end

    return (
        bus_labels = bus_labels,
        bus_idx_dict = bus_idx_dict,
        bus_zone_of_n = bus_zone_of_n,
        N_i = N_i,
        bus_weight = bus_weight,
        idx_zone_dict = Idx_zone_dict
    )
end

function write_output(outpath::AbstractString,config_set::Dict, input_data::Dict, model::Model)
	mkdir_overwrite(outpath)
    model_mode = config_set["model_mode"]
    flexible_demand_raw = get(config_set, "flexible_demand", 0)
    flexible_demand = flexible_demand_raw isa Integer ? Int(flexible_demand_raw) : parse(Int, string(flexible_demand_raw))
    summary_table_raw = get(config_set, "summary_table", get(config_set, "summary_tables", 0))
    summary_table = summary_table_raw isa Integer ? Int(summary_table_raw) : parse(Int, string(summary_table_raw))
    println() 
    println("HOPE model ($model_mode mode) is successfully solved!")
    if model_mode == "GTEP"
        ##read input for print	
        Storagedata = input_data["Storagedata"]
        Estoragedata_candidate = input_data["Estoragedata_candidate"]
        Gendata = input_data["Gendata"]
        Gendata_candidate = input_data["Gendata_candidate"]
        Linedata = input_data["Linedata"]
        Zonedata = input_data["Zonedata"]
        Linedata_candidate = input_data["Linedata_candidate"]
        Loaddata = input_data["Loaddata"]
        VOLL = input_data["Singlepar"][1,"VOLL"]
        if flexible_demand == 1
            DRdata = input_data["DRdata"]
        end
        #Calculate number of elements of input data
        Num_Egen=size(Gendata,1)
        Num_bus=size(Zonedata,1)
        Num_load=size(Zonedata,1)
        Num_Eline=size(Linedata,1)
        Num_zone=length(Zonedata[:,"Zone_id"])
        Num_sto=size(Storagedata,1)
        Num_Csto=size(Estoragedata_candidate,1)
        Num_Cgen=size(Gendata_candidate,1)
        Num_Cline=size(Linedata_candidate,1)
        #Mapping
        #Index-Zone Mapping dict
		Idx_zone_dict = Dict(zip([i for i=1:Num_zone],Zonedata[:,"Zone_id"]))
		Zone_idx_dict = Dict(zip(Zonedata[:,"Zone_id"],[i for i=1:Num_zone]))
        #zone
        Ordered_zone_nm = [Idx_zone_dict[i] for i=1:Num_zone]
        D=[d for d=1:Num_load] 	
        D_i=[[d] for d in D]
        if flexible_demand == 1
            Num_DR = size(DRdata, 1)
            R = [r for r in 1:Num_DR]
        else
            R = Int[]
        end
        W=unique(Zonedata[:,"State"])
        #lines
        L=[l for l=1:Num_Eline+Num_Cline]						#Set of transmission corridors, index l
        L_exist=[l for l=1:Num_Eline]									#Set of existing transmission corridors
		L_new=[l for l=Num_Eline+1:Num_Eline+Num_Cline]					#Set of candidate transmission corridors
        endogenous_rep_day, external_rep_day, representative_day_mode = resolve_rep_day_mode(config_set; context="write_output")
        input_T, input_H_t, input_H_T, has_custom_time_periods = build_time_period_hours(Loaddata)
        if representative_day_mode == 1
            if has_custom_time_periods && external_rep_day == 0
                throw(ArgumentError("Input timeseries defines multiple Time Periods. This is only allowed when external_rep_day = 1."))
            end
            if external_rep_day == 1
                if !haskey(input_data, "RepWeightData")
                    throw(ArgumentError("external_rep_day=1 requires rep_period_weights.csv (or sheet rep_period_weights)."))
                end
                rep_weight_df = input_data["RepWeightData"]
                if !("Time Period" in names(rep_weight_df)) || !("Weight" in names(rep_weight_df))
                    throw(ArgumentError("rep_period_weights must include columns: 'Time Period', 'Weight'."))
                end
                T = sort(unique(Int.(rep_weight_df[!, "Time Period"])))
            else
                T=[t for t=1:length(config_set["time_periods"])]		#Set of time periods (e.g., representative days of seasons), index t
            end
            H_t=[collect(1+24*(t-1):24+24*(t-1)) for t in T]			#Set of hours in time period (day) t, index h, subset of H
            H_T = collect(unique(reduce(vcat,H_t)))						#Set of unique hours in time period, index h, subset of H
        else
            H_t = input_H_t
            H_T = input_H_T
            T = input_T
        end
        I=[i for i=1:Num_zone]
        I_w=Dict(zip(W, [findall(Zonedata[:,"State"].== w) for w in W])) #Set of zones in state w, subset of I
        HD = [h for h in 1:24]
        #Sets
        G=[g for g=1:Num_Egen+Num_Cgen]
        G_exist=[g for g=1:Num_Egen]
        G_new=[g for g=Num_Egen+1:Num_Egen+Num_Cgen]
        G_MR_E=findall(x -> x in [1], Gendata[:,"Flag_mustrun"])
        G_RET_raw=findall(x -> x in [1], Gendata[:,"Flag_RET"])
        G_RET=setdiff(G_RET_raw, G_MR_E)
        G_i=[[findall(Gendata[:,"Zone"].==Idx_zone_dict[i]);(findall(Gendata_candidate[:,"Zone"].==Idx_zone_dict[i]).+Num_Egen)] for i in I]	
        G_PV_E=findall(Gendata[:,"Type"].=="SolarPV")					#Set of existingsolar, subsets of G
		G_PV_C=findall(Gendata_candidate[:,"Type"].=="SolarPV").+Num_Egen#Set of candidate solar, subsets of G
		G_PV=[G_PV_E;G_PV_C]											#Set of all solar, subsets of G
		G_W_E=findall(x -> x in ["WindOn","WindOff"], Gendata[:,"Type"])#Set of existing wind, subsets of G
        G_W_C=findall(x -> x in ["WindOn","WindOff"], Gendata_candidate[:,"Type"]).+Num_Egen#Set of candidate wind, subsets of G
		G_W=[G_W_E;G_W_C]
        G_VRE_E = [G_PV_E;G_W_E]
        G_VRE_C = [G_PV_C;G_W_C]
        G_VRE = [G_VRE_E;G_VRE_C]
        if ("Flag_RPS" in names(Gendata)) && ("Flag_RPS" in names(Gendata_candidate))
            G_RPS_E=findall(x -> x in [1], Gendata[:,"Flag_RPS"])
            G_RPS_C=findall(x -> x in [1], Gendata_candidate[:,"Flag_RPS"]).+Num_Egen
            G_RPS = sort(unique(vcat(G_RPS_E, G_RPS_C, G_VRE)))
        else
            # Backward-compatible fallback for older data
            G_RPS = G_VRE
        end
        S_i=[[findall(Storagedata[:,"Zone"].==Idx_zone_dict[i]);(findall(Estoragedata_candidate[:,"Zone"].==Idx_zone_dict[i]).+Num_sto)] for i in I]
        S=[s for s=1:Num_sto+Num_Csto]							    #Set of storage units, index s
        S_exist=[s for s=1:Num_sto]										#Set of existing storage units, subset of S  
		S_new=[s for s=Num_sto+1:Num_sto+Num_Csto]						#Set of candidate storage units, subset of S  
        LS_i=[[findall(Linedata[:,"From_zone"].==Idx_zone_dict[i]);(findall(Linedata_candidate[:,"From_zone"].==Idx_zone_dict[i]).+Num_Eline)] for i in I]
        #Param
        INV_g=Dict(zip(G_new,Gendata_candidate[:,Symbol("Cost (\$/MW/yr)")])) #g						#Investment cost of candidate generator g, M$
		INV_l=Dict(zip(L_new,Linedata_candidate[:,Symbol("Cost (M\$)")]))#l						#Investment cost of transmission line l, M$
		INV_s=Dict(zip(S_new,Estoragedata_candidate[:,Symbol("Cost (\$/MW/yr)")])) #s	
        Gencostdata = input_data["Gendata"][:,Symbol("Cost (\$/MWh)")]
        VCG=[Gencostdata;Gendata_candidate[:,Symbol("Cost (\$/MWh)")]]#g						#Variable cost of generation unit g, $/MWh
		VCS=[Storagedata[:,Symbol("Cost (\$/MWh)")];Estoragedata_candidate[:,Symbol("Cost (\$/MWh)")]]#s		
        P_max=[Gendata[:,"Pmax (MW)"];Gendata_candidate[:,"Pmax (MW)"]]#g						#Maximum power generation of unit g, MW
        SCAP=[Storagedata[:,"Max Power (MW)"];Estoragedata_candidate[:,"Max Power (MW)"]]#s		#Maximum capacity of storage unit s, MWh
        unit_converter = 10^6

        		#representative day clustering
		if representative_day_mode == 1
            if external_rep_day == 1
                rep_weight_df = input_data["RepWeightData"]
                N = Dict(Int(row["Time Period"]) => Float64(row["Weight"]) for row in eachrow(rep_weight_df))
            else
			    time_periods = config_set["time_periods"]
                N=get_representative_ts(Loaddata,time_periods,Ordered_zone_nm)[2]
            end
        else
            N = Dict{Int,Float64}(t => 1.0 for t in T)
		end
        
        ##Generator-----------------------------------------------------------------------------------------------------------
        #Investment cost of storage unit s, M$
        #Power OutputDF
        P_gen_df = DataFrame(
            Technology = vcat(Gendata[:,"Type"],Gendata_candidate[:,"Type"]),
            Zone = vcat(Gendata[:,"Zone"],Gendata_candidate[:,"Zone"]),
            EC_Category = [repeat(["Existing"],Num_Egen);repeat(["Candidate"],Num_Cgen)],
            New_Build = Array{Union{Missing,Bool}}(undef, size(G)[1]),
            AnnSum = Array{Union{Missing,Float64}}(undef, size(G)[1])  #Annual generation output
        )
        P_gen_df.AnnSum .= [sum(value.(model[:p][g,h]) for t in T for h in H_t[t] ) for g in G]
        New_built_idx = map(x -> x + Num_Egen, [i for (i, v) in enumerate(value.(model[:x])) if v > 0])
        #print(New_built_idx)
        #New_built_idx = map(x -> G_new[x], [i for (i, v) in enumerate(value.(model[:x])) if v > 0])
        P_gen_df[!,:New_Build] .= 0
        P_gen_df[New_built_idx,:New_Build] .= 1
        #Retreive power data from solved model
        power = value.(model[:p])
        power_t_h = hcat([Array(power[:,h]) for t in T for h in H_t[t]]...)
        #print(power_t_h)
        power_t_h_df = DataFrame(power_t_h, [Symbol("t$t"*"h$h") for t in T for h in H_t[t]])
        P_gen_df = hcat(P_gen_df, power_t_h_df )
        
        CSV.write(joinpath(outpath, "power.csv"), P_gen_df, writeheader=true)
        
        ##Power price
        # Obtain hourly power price, utilize power balance constraint's shadow price
        duals_available = config_set["solver"] != "cbc" && has_duals(model)
        if config_set["solver"] == "cbc"
            P_price_df = DataFrame()
            println("Cbc solver does not support for calaculating electricity price")
        elseif !duals_available
            P_price_df = DataFrame()
            println("Dual values are unavailable for GTEP power price output. For MILP runs, set write_shadow_prices=1 (and inv_dcs_bin=1) to run fixed-LP dual recovery.")
        else
            P_price_df = DataFrame(Zone = Zonedata[:,"Zone_id"]) 
            dual_matrix = dual.(model[:PB_con])
            dual_t_h = [[dual_matrix[i,t,h] for t in T for h in H_t[t]] for i in I]
            #dfPrice = hcat(dfPrice, DataFrame(transpose(dual_matrix), :auto))
            dual_t_h = transpose(hcat(dual_t_h...))
            dual_t_h_df = DataFrame(dual_t_h, [Symbol("t$t"*"h$h") for t in T for h in H_t[t]])
            P_price_df = hcat(P_price_df,dual_t_h_df)
            CSV.write(joinpath(outpath, "power_price.csv"), P_price_df, writeheader=true)
        end
        
        ##Renewable curtailments
        #P_ctl_df = DataFrame(
        #    Technology = vcat(Gendata[G_VRE_E,"Type"],Gendata_candidate[ G_VRE_C,"Type"]),
        ##    Zone = vcat(Gendata[G_VRE_E,"Zone"],Gendata_candidate[G_VRE_C,"Zone"]),
        #    EC_Category = [repeat(["Existing"],Num_Egen);repeat(["Candidate"],Num_Cgen)],
        #    New_Build = Array{Union{Missing,Bool}}(undef, size(G_VRE)[1]),
        #    AnnSum = Array{Union{Missing,Float64}}(undef, size(G_VRE)[1])
        #)
        #power = value.(model[:p])
        #power_VRE_t_h = hcat([Array(power[G_VRE,t,h]) for t in T for h in H_t[t]]...)
        #power_VRE_max_t_h = hcat([Array(AF_gh[g,h]*P_max[g]) for t in T for h in H_t[t]]...)
        #power_VRE_ctl_t_h =  hcat([Array(power[G_VRE,t,h]) for t in T for h in H_t[t]]...)

        ##Load shedding
        P_ls_df = DataFrame(
          load_area = vcat(Zonedata[:, "Zone_id"]), 
          AnnTol =  Array{Union{Missing,Float64}}(undef, Num_load)
        )
        P_ls_df.AnnTol .= [sum(value.(model[:p_LS][i,h]) for t in T for h in H_t[t]) for i in I]
        power_ls = value.(model[:p_LS])
        power_ls_t_h = hcat([Array(power_ls[:,h]) for t in T for h in H_t[t]]...)
        power_ls_t_h_df = DataFrame(power_ls_t_h, [Symbol("t$t"*"h$h") for t in T for h in H_t[t]])
        P_ls_df = hcat(P_ls_df, power_ls_t_h_df)

        CSV.write(joinpath(outpath, "power_loadshedding.csv"), P_ls_df, writeheader=true)
        
        ##Renewable curtailments
        G_vre_exist_rps = intersect(intersect(G_exist, union(G_PV, G_W)), G_RPS)
        G_vre_new_rps = intersect(intersect(G_new, union(G_PV, G_W)), G_RPS)
        P_ct_df = DataFrame(
            Technology = vcat(Gendata[[g for g in G_vre_exist_rps],"Type"],Gendata_candidate[[g for g in G_vre_new_rps] .- Num_Egen,"Type"]),
            Zone = vcat(Gendata[[g for g in G_vre_exist_rps],"Zone"],Gendata_candidate[[g for g in G_vre_new_rps] .- Num_Egen,"Zone"]),
            EC_Category = [repeat(["Existing"],size(G_vre_exist_rps)[1]);repeat(["Candidate"],size(G_vre_new_rps)[1])], # existing capacity
            New_Build = Array{Union{Missing,Bool}}(undef, size(G_vre_exist_rps)[1]+size(G_vre_new_rps)[1]),
            AnnSum = Array{Union{Missing,Float64}}(undef, size(G_vre_exist_rps)[1]+size(G_vre_new_rps)[1])  #Annual generation output
        )
        P_ct_df.AnnSum .= [[sum(value.(model[:RenewableCurtailExist][g,t,h]) for t in T for h in H_t[t];init=0) for g in G_vre_exist_rps];[sum(value.(model[:RenewableCurtailNew][g,t,h]) for t in T for h in H_t[t];init=0) for g in G_vre_new_rps]]
        New_built_vre_idx = intersect(New_built_idx,G_VRE_C)
        New_built_matched_vre_idx = findall(x->x in New_built_vre_idx, [[g for g in G_vre_exist_rps];[g for g in G_vre_new_rps]])

        #print(New_built_idx)
        #New_built_idx = map(x -> G_new[x], [i for (i, v) in enumerate(value.(model[:x])) if v > 0])
        P_ct_df[!,:New_Build] .= 0
        P_ct_df[New_built_matched_vre_idx ,:New_Build] .= 1
        #Retreive power data from solved model
        power_e = value.(model[:RenewableCurtailExist])
        power_n = value.(model[:RenewableCurtailNew])
        power_h =[[[power_e[g,t,h] for t in T for h in H_t[t]] for g in G_vre_exist_rps];[[power_n[g,t,h] for t in T for h in H_t[t]] for g in G_vre_new_rps]]
        power_h_df = DataFrame([[] for t in T for h in H_t[t]],[Symbol("t$t"*"h$h") for t in T for h in H_t[t]])
        for r in 1:size(power_h)[1]
            push!(power_h_df,power_h[r])
        end
        #power_h_df = DataFrame(power_h, [Symbol("h$h") for h in H])
        P_ct_df = hcat(P_ct_df, power_h_df )
        CSV.write(joinpath(outpath, "power_renewable_curtailment.csv"), P_ct_df , writeheader=true)
        
        #Capacity OutputDF
        C_gen_df = DataFrame(
            Technology = vcat(Gendata[:,"Type"],Gendata_candidate[:,"Type"]),
            Zone = vcat(Gendata[:,"Zone"],Gendata_candidate[:,"Zone"]),
            EC_Category = [repeat(["Existing"],Num_Egen);repeat(["Candidate"],Num_Cgen)],
            New_Build = Array{Union{Missing,Bool}}(undef, size(G)[1]),
            Capacity_IN = vcat(Gendata[:,"Pmax (MW)"],zeros(size(G_new)[1])),
            Capacity_RET = Array{Union{Missing,Float64,Int64}}(undef, size(G)[1]),
            Capacity = vcat(Gendata[:,"Pmax (MW)"],Gendata_candidate[:,"Pmax (MW)"])
        )
        C_gen_df[!,:New_Build] .= 0
        C_gen_df[New_built_idx,:New_Build] .= 1

        C_gen_df[!,:Capacity_RET] .= 0.0
        Retirement_idx = map(x -> G_RET[x], [i for (i, v) in enumerate(value.(model[:x_RET])) if v > 0])
        #Retirement_idx = map(x -> x + Num_Egen, [i for (i, v) in enumerate(value.(model[:x_RET])) if v > 0])
        #print(G_RET)
        #print(value.(model[:x_RET]))
        #print(Retirement_idx)
        if isempty(Retirement_idx)
            C_gen_df[:,:Capacity_RET] .= [0.0 for g in 1:size(G)[1]]
        else
            C_gen_df[Retirement_idx,:Capacity_RET] .= [v for (i,v) in enumerate(Gendata[G_RET,"Pmax (MW)"] .*value.(model[:x_RET]))]
        end

        C_gen_df[!,:Capacity] .=  C_gen_df[!,:Capacity] .- C_gen_df[!,:Capacity_RET]

        rename!(C_gen_df, :Capacity_IN => Symbol("Capacity_INI (MW)"))
        rename!(C_gen_df, :Capacity_RET => Symbol("Capacity_RET (MW)"))
        rename!(C_gen_df, :Capacity => Symbol("Capacity_FIN (MW)"))

        CSV.write(joinpath(outpath, "capacity.csv"), C_gen_df, writeheader=true)
        ##Transmission line-----------------------------------------------------------------------------------------------------------
        C_line_df = DataFrame(
            From_zone = Linedata_candidate[:,"From_zone"],
            To_zone = Linedata_candidate[:,"To_zone"],    
            New_Build = Array{Union{Missing,Bool}}(undef, Num_Cline),
            Capacity = Linedata_candidate[:,"Capacity (MW)"]
        )
        New_built_line_idx = map(x -> x, [i for (i, v) in enumerate(value.(model[:y])) if v > 0])
        C_line_df[!,:New_Build] .=0
        C_line_df[New_built_line_idx,:New_Build] .=1
        rename!(C_line_df, :Capacity => Symbol("Capacity (MW)"))
        CSV.write(joinpath(outpath, "line.csv"), C_line_df, writeheader=true)
        
        #Power flow OutputDF
        P_flow_df = DataFrame(
            From_zone = vcat(Linedata[:,"From_zone"],Linedata_candidate[:,"From_zone"]),
            To_zone = vcat(Linedata[:,"To_zone"],Linedata_candidate[:,"To_zone"]),
            EC_Category = [repeat(["Existing"],Num_Eline);repeat(["Candidate"],Num_Cline)],
            New_Build = Array{Union{Missing,Bool}}(undef, size(L)[1]),
            AnnSum = Array{Union{Missing,Float64}}(undef, size(L)[1])
        )
        P_flow_df.AnnSum .= [sum(value.(model[:f][l,h]) for t in T for h in H_t[t] ) for l in L]
        
        New_built_line_idx = map(x -> x + Num_Eline, [i for (i, v) in enumerate(value.(model[:y])) if v > 0])
        P_flow_df[!,"New_Build"] .= 0
        P_flow_df[New_built_line_idx,:New_Build] .=1
        
        #Retreive power data from solved model
        flow = value.(model[:f])
        flow_t_h = hcat([Array(flow[:,h]) for t in T for h in H_t[t]]...)
        flow_t_h_df = DataFrame(flow_t_h, [Symbol("t$t"*"h$h") for t in T for h in H_t[t]])
        P_flow_df = hcat(P_flow_df, flow_t_h_df )
        CSV.write(joinpath(outpath, "power_flow.csv"), P_flow_df, writeheader=true)
        

        ##Storage---------------------------------------------------------------------------------------------------------------------
        #c
        P_es_c_df = DataFrame(
            Technology = vcat(Storagedata[:,"Type"],Estoragedata_candidate[:,"Type"]),
            Zone = vcat(Storagedata[:,"Zone"],Estoragedata_candidate[:,"Zone"]),
            EC_Category = [repeat(["Existing"],Num_sto);repeat(["Candidate"],Num_Csto)],
            New_Build = Array{Union{Missing,Bool}}(undef, size(S)[1]),
            ChAnnSum = Array{Union{Missing,Float64}}(undef, size(S)[1]),     #Annual charge
        )
        P_es_c_df.ChAnnSum .= [sum(value.(model[:c][s,h]) for t in T for h in H_t[t] ) for s in S]
        
        New_built_idx = map(x -> x + Num_sto, [i for (i, v) in enumerate(value.(model[:z])) if v > 0])
        P_es_c_df[!,:New_Build] .= 0
        P_es_c_df[New_built_idx,:New_Build] .= 1
        #Retreive power data from solved model
        power_c = value.(model[:c])

        power_c_t_h = hcat([Array(power_c[:,h]) for t in T for h in H_t[t]]...)
        power_c_t_h_df = DataFrame(power_c_t_h, [Symbol("c_"*"t$t"*"h$h") for t in T for h in H_t[t]])

        P_es_c_df = hcat(P_es_c_df, power_c_t_h_df)
        CSV.write(joinpath(outpath, "es_power_charge.csv"), P_es_c_df, writeheader=true)
        #dc
        P_es_dc_df = DataFrame(
            Technology = vcat(Storagedata[:,"Type"],Estoragedata_candidate[:,"Type"]),
            Zone = vcat(Storagedata[:,"Zone"],Estoragedata_candidate[:,"Zone"]),
            EC_Category = [repeat(["Existing"],Num_sto);repeat(["Candidate"],Num_Csto)],
            New_Build = Array{Union{Missing,Bool}}(undef, size(S)[1]),
            DisAnnSum = Array{Union{Missing,Float64}}(undef, size(S)[1]),    #Annual discharge
        )
        P_es_dc_df.DisAnnSum .= [sum(value.(model[:dc][s,h]) for t in T for h in H_t[t] ) for s in S]
        
        New_built_idx = map(x -> x + Num_sto, [i for (i, v) in enumerate(value.(model[:z])) if v > 0])
        P_es_dc_df[!,:New_Build] .= 0
        P_es_dc_df[New_built_idx,:New_Build] .= 1
        #Retreive power data from solved model
        power_dc = value.(model[:dc])

        power_dc_t_h = hcat([Array(power_dc[:,h]) for t in T for h in H_t[t]]...)
        power_dc_t_h_df = DataFrame(power_dc_t_h, [Symbol("dc_"*"t$t"*"h$h") for t in T for h in H_t[t]])

        P_es_dc_df = hcat(P_es_dc_df,  power_dc_t_h_df)
        CSV.write(joinpath(outpath, "es_power_discharge.csv"), P_es_dc_df, writeheader=true)
        #soc
        P_es_soc_df = DataFrame(
            Technology = vcat(Storagedata[:,"Type"],Estoragedata_candidate[:,"Type"]),
            Zone = vcat(Storagedata[:,"Zone"],Estoragedata_candidate[:,"Zone"]),
            EC_Category = [repeat(["Existing"],Num_sto);repeat(["Candidate"],Num_Csto)],
            New_Build = Array{Union{Missing,Bool}}(undef, size(S)[1]),
        )
        
        New_built_idx = map(x -> x + Num_sto, [i for (i, v) in enumerate(value.(model[:z])) if v > 0])
        P_es_soc_df[!,:New_Build] .= 0
        P_es_soc_df[New_built_idx,:New_Build] .= 1
        #Retreive power data from solved model
        power_soc = value.(model[:soc])

        power_soc_t_h = hcat([Array(power_soc[:,h]) for t in T for h in H_t[t]]...)
        power_soc_t_h_df = DataFrame(power_soc_t_h, [Symbol("soc_"*"t$t"*"h$h") for t in T for h in H_t[t]])

        P_es_soc_df = hcat(P_es_soc_df, power_soc_t_h_df)
        CSV.write(joinpath(outpath, "es_power_soc.csv"), P_es_soc_df, writeheader=true)
        #Storage Capacity OutputDF
        C_es_df = DataFrame(
            Technology = vcat(Storagedata[:,"Type"],Estoragedata_candidate[:,"Type"]),
            Zone = vcat(Storagedata[:,"Zone"],Estoragedata_candidate[:,"Zone"]),
            EC_Category = [repeat(["Existing"],Num_sto);repeat(["Candidate"],Num_Csto)],
            New_Build = Array{Union{Missing,Bool}}(undef, size(S)[1]),            
            EnergyCapacity = vcat(Storagedata[:,"Capacity (MWh)"],Estoragedata_candidate[:,"Capacity (MWh)"]),
            Capacity = vcat(Storagedata[:,"Max Power (MW)"],Estoragedata_candidate[:,"Max Power (MW)"])
        )
        C_es_df[!,:New_Build] .= 0
        C_es_df[New_built_idx,:New_Build] .= 1
        rename!(C_es_df, :Capacity => Symbol("Capacity (MW)"))
        rename!(C_es_df, :EnergyCapacity => Symbol("EnergyCapacity (MWh)"))
        
        CSV.write(joinpath(outpath, "es_capacity.csv"), C_es_df, writeheader=true)
        ##Demand response program---------------------------------------------------------------------------------------------------------------------
        if flexible_demand == 1
            # Backlog load-shifting DR outputs
            power_df = value.(model[:dr_DF])
            power_pb = value.(model[:dr_PB])
            power_backlog = value.(model[:b_DR])
            dr_cols = [Symbol("dr_"*"t$t"*"h$h") for t in T for h in H_t[t]]

            # Net DR shift (payback minus deferred)
            dr_net_df = DataFrame(
                Resource = vcat(R),
                Zone = vcat(DRdata[:,"Zone"]),
                Technology = vcat(DRdata[:,"Type"]),
                DRAnnSum = Array{Union{Missing,Float64}}(undef, size(R)[1]),
            )
            dr_net_df.DRAnnSum .= [sum(power_pb[r,h] - power_df[r,h] for t in T for h in H_t[t]) for r in R]
            dr_net_t_h = hcat([Array(power_pb[:,h] .- power_df[:,h]) for t in T for h in H_t[t]]...)
            dr_net_df = hcat(dr_net_df, DataFrame(dr_net_t_h, dr_cols))
            CSV.write(joinpath(outpath, "dr_power.csv"), dr_net_df, writeheader=true)

            dr_pb_df = DataFrame(
                Resource = vcat(R),
                Zone = vcat(DRdata[:,"Zone"]),
                Technology = vcat(DRdata[:,"Type"]),
                DRAnnSum = Array{Union{Missing,Float64}}(undef, size(R)[1]),
            )
            dr_pb_df.DRAnnSum .= [sum(value.(model[:dr_PB][r,h]) for t in T for h in H_t[t]) for r in R]
            dr_pb_t_h = hcat([Array(power_pb[:,h]) for t in T for h in H_t[t]]...)
            dr_pb_df = hcat(dr_pb_df, DataFrame(dr_pb_t_h, dr_cols))
            CSV.write(joinpath(outpath, "dr_pb_power.csv"), dr_pb_df, writeheader=true)

            dr_df_df = DataFrame(
                Resource = vcat(R),
                Zone = vcat(DRdata[:,"Zone"]),
                Technology = vcat(DRdata[:,"Type"]),
                DRAnnSum = Array{Union{Missing,Float64}}(undef, size(R)[1]),
            )
            dr_df_df.DRAnnSum .= [sum(value.(model[:dr_DF][r,h]) for t in T for h in H_t[t]) for r in R]
            dr_df_t_h = hcat([Array(power_df[:,h]) for t in T for h in H_t[t]]...)
            dr_df_df = hcat(dr_df_df, DataFrame(dr_df_t_h, dr_cols))
            CSV.write(joinpath(outpath, "dr_df_power.csv"), dr_df_df, writeheader=true)

            dr_backlog_df = DataFrame(
                Resource = vcat(R),
                Zone = vcat(DRdata[:,"Zone"]),
                Technology = vcat(DRdata[:,"Type"]),
                DRAnnSum = Array{Union{Missing,Float64}}(undef, size(R)[1]),
            )
            dr_backlog_df.DRAnnSum .= [sum(value.(model[:b_DR][r,h]) for t in T for h in H_t[t]) for r in R]
            dr_backlog_t_h = hcat([Array(power_backlog[:,h]) for t in T for h in H_t[t]]...)
            dr_backlog_df = hcat(dr_backlog_df, DataFrame(dr_backlog_t_h, dr_cols))
            CSV.write(joinpath(outpath, "dr_backlog.csv"), dr_backlog_df, writeheader=true)
        end
        ##System Cost-----------------------------------------------------------------------------------------------------------
        Cost_df = DataFrame(
            Zone = vcat(Ordered_zone_nm),
            Inv_cost = Array{Union{Missing,Float64}}(undef, Num_zone),
            Opr_cost = Array{Union{Missing,Float64}}(undef, Num_zone),
            #RPS_plt = Array{Union{Missing,Float64}}(undef, Num_zone),
            #Carbon_plt =Array{Union{Missing,Float64}}(undef, Num_zone),
            LoL_plt = Array{Union{Missing,Float64}}(undef, Num_zone),
            Total_cost = Array{Union{Missing,Float64}}(undef, Num_zone)
        )
        
        x = value.(model[:x])
        y = value.(model[:y])
        z = value.(model[:z])
        p = value.(model[:p])
        c = value.(model[:c])
        dc = value.(model[:dc])
        p_LS = value.(model[:p_LS])
        for i in  1:Num_zone
            Inv_c = sum(INV_g[g]*x[g]*P_max[g] for g in intersect(G_new,G_i[i]); init=0)+sum(INV_l[l]*unit_converter*y[l] for l in intersect(L_new,LS_i[i]); init=0)+sum(INV_s[s]*z[s]*SCAP[s] for s in intersect(S_new,S_i[i]); init=0)
            Opr_c = sum(VCG[g]*N[t]*sum(p[g,h] for h in H_t[t]) for g in intersect(G,G_i[i]) for t in T; init=0) + sum(VCS[s]*N[t]*sum(c[s,h]+dc[s,h] for h in H_t[t]; init=0) for s in intersect(S,S_i[i]) for t in T; init=0)
            #RPS_p =  PT_rps*sum(pt_rps[w] for w in W)
            #Cb_p = PT_emis*sum(em_emis[w] for w in W)
            Lol_p = sum(VOLL*N[t]*sum(p_LS[d,h] for h in H_t[t]; init=0) for d in intersect(D,D_i[i]) for t in T; init=0)
            Tot = sum([Inv_c,Opr_c,Lol_p])
            Cost_df[i,2:end] = [Inv_c,Opr_c,Lol_p,Tot]
        end
        rename!(Cost_df, :Inv_cost => Symbol("Inv_cost (\$)"))
        rename!(Cost_df, :Opr_cost => Symbol("Opr_cost (\$)"))
        rename!(Cost_df, :LoL_plt => Symbol("LoL_plt (\$)"))
        rename!(Cost_df, :Total_cost => Symbol("Total_cost (\$)"))
        CSV.write(joinpath(outpath, "system_cost.csv"), Cost_df, writeheader=true)
        Results_dict = Dict(
            "power" => P_gen_df,
            "power_loadshedding" => P_ls_df,
            "power_renewable_curtailment" =>P_ct_df,
            "power_price" => P_price_df,
            "capacity" => C_gen_df,
            "line" => C_line_df,
            "power_flow" => P_flow_df,
            "es_power_charge" => P_es_c_df,
            "es_power_discharge" => P_es_dc_df,
            "es_power_soc" => P_es_soc_df,
            "es_capacity" => C_es_df,
            "system_cost" => Cost_df
        )
    
    elseif model_mode == "PCM" 
        network_model = parse_setting_int(config_set, "network_model", 0)
        Gendata = input_data["Gendata"]
        Storagedata = input_data["Storagedata"]
        Linedata = (network_model in [2, 3] && haskey(input_data, "Branchdata")) ? input_data["Branchdata"] : input_data["Linedata"]
        Zonedata = input_data["Zonedata"]
        Loaddata = input_data["Loaddata"]
        VOLL = input_data["Singlepar"][1,"VOLL"]
        nodal_output_map = network_model in [2, 3] ? build_pcm_nodal_output_maps(input_data) : nothing
        if flexible_demand == 1
            DRdata = input_data["DRdata"]
            Num_DR = size(DRdata, 1)
            R = [r for r in 1:Num_DR]
        else
            R = Int[]
        end
        #Calculate number of elements of input data
        Num_bus=size(Zonedata,1);
        Num_Egen=size(Gendata,1);
        Num_load=size(Zonedata,1);
        Num_Eline=size(Linedata,1);
        Num_zone=length(Zonedata[:,"Zone_id"]);
        Num_sto=size(Storagedata,1);
        #Mapping
        #Index-Zone Mapping dict
		Idx_zone_dict = Dict(zip([i for i=1:Num_zone],Zonedata[:,"Zone_id"]))
		Zone_idx_dict = Dict(zip(Zonedata[:,"Zone_id"],[i for i=1:Num_zone]))
        #Set
        D=[d for d=1:Num_load] 	
        D_i=[[d] for d in D]
        G=[g for g=1:Num_Egen]
        S=[s for s=1:Num_sto]
        H=[h for h=1:size(Loaddata,1)]
        L=[l for l=1:Num_Eline]						#Set of transmission corridors, index l
        I=[i for i=1:Num_zone]									#Set of zones, index i
        to_float_setting(v) = v isa Number ? Float64(v) : parse(Float64, string(v))
        singlepar_df = input_data["Singlepar"]
        singlepar_cols = Set(string.(names(singlepar_df)))
        theta_max_for_diag = ("theta_max" in singlepar_cols) ? to_float_setting(singlepar_df[1, "theta_max"]) : 1.0e3
        G_i=[findall(Gendata[:,"Zone"].==Idx_zone_dict[i]) for i in I]	
        G_PV_E=findall(Gendata[:,"Type"].=="SolarPV")					#Set of existingsolar, subsets of G
		G_PV=[G_PV_E;]											#Set of all solar, subsets of G
		G_W_E=findall(x -> x in ["WindOn","WindOff"], Gendata[:,"Type"])#Set of existing wind, subsets of G
		G_W=[G_W_E;]                                               #Set of all wind, subsets of G
        S_i=[findall(Storagedata[:,"Zone"].==Idx_zone_dict[i]) for i in I]
        S_exist=[s for s=1:Num_sto]										#Set of existing storage units, subset of S   
        LS_i=[Int[] for i in I]
  
        #zone
        Ordered_zone_nm = [Idx_zone_dict[i] for i=1:Num_zone]
        W = unique(Zonedata[:, "State"])
        I_w = Dict(zip(W, [findall(Zonedata[:, "State"] .== w) for w in W]))
        #Param
        Gencostdata = input_data["Gendata"][:,Symbol("Cost (\$/MWh)")]
        VCG=[Gencostdata;]#g						#Variable cost of generation unit g, $/MWh
		VCS=[Storagedata[:,Symbol("Cost (\$/MWh)")];]#s		
        unit_converter = 10^6
        linedata_cols = Set(string.(names(Linedata)))
        from_zone_col = first_existing_col(linedata_cols, ["From_zone", "from_zone"])
        to_zone_col = first_existing_col(linedata_cols, ["To_zone", "to_zone"])
        from_bus_col = first_existing_col(linedata_cols, ["from_bus", "From_bus", "f_bus", "F_BUS"])
        to_bus_col = first_existing_col(linedata_cols, ["to_bus", "To_bus", "t_bus", "T_BUS"])
        summary_outpath = joinpath(outpath, "Analysis")
        Summary_Price_Hourly_df = DataFrame(Level=String[], ID=String[], Zone=String[], State=String[], Hour=Int[], LMP=Float64[], Energy=Float64[], Congestion=Float64[], Loss=Float64[])
        Summary_Congestion_Line_Hourly_df = DataFrame(
            Line=Int[],
            From_bus=String[],
            To_bus=String[],
            From_zone=String[],
            To_zone=String[],
            Hour=Int[],
            Flow_MW=Float64[],
            Limit_MW=Float64[],
            Loading_pct=Float64[],
            ShadowPrice=Union{Missing,Float64}[],
            BindingSide=String[],
            CongestionRent=Union{Missing,Float64}[]
        )
        Summary_Congestion_Line_Annual_df = DataFrame(
            Line=Int[],
            From_bus=String[],
            To_bus=String[],
            From_zone=String[],
            To_zone=String[],
            HoursBinding=Int[],
            AvgAbsShadow=Union{Missing,Float64}[],
            MaxAbsShadow=Union{Missing,Float64}[],
            AnnCongestionRent=Float64[],
            AvgLoading_pct=Float64[],
            P95Loading_pct=Float64[]
        )
        Summary_System_Hourly_df = DataFrame(
            Hour=Int[],
            Load_MW=Float64[],
            Generation_MW=Float64[],
            StorageCharge_MW=Float64[],
            StorageDischarge_MW=Float64[],
            LoadShedding_MW=Float64[],
            Curtailment_MW=Float64[],
            AvgLMP_LoadWeighted=Union{Missing,Float64}[],
            TotalEmissions_ton=Float64[]
        )
        Summary_Congestion_Driver_Node_Hourly_df = DataFrame(
            Bus=String[],
            Zone=String[],
            State=String[],
            Hour=Int[],
            Line=Int[],
            From_bus=String[],
            To_bus=String[],
            PTDF=Float64[],
            DeltaPTDF=Float64[],
            ShadowPrice=Float64[],
            Contribution=Float64[]
        )
        if network_model == 2 && haskey(model, :theta) && theta_max_for_diag > 0.0
            theta_vals = value.(model[:theta])
            max_abs_theta = maximum(abs.(theta_vals))
            if max_abs_theta >= 0.999 * theta_max_for_diag
                println("Warning: theta_max appears binding in angle-based DCOPF (max |theta|=$(round(max_abs_theta, digits=6)), theta_max=$(theta_max_for_diag)). Consider increasing theta_max or checking angle/flow scaling.")
            end
        end

        ##Load shedding
        P_ls_df = DataFrame(
          load_area = vcat(Zonedata[:, "Zone_id"]), 
          AnnTol =  Array{Union{Missing,Float64}}(undef, Num_load)
        )
        P_ls_df.AnnTol .= [sum(value.(model[:p_LS][d,h]) for h in H) for d in D]
        power_ls = value.(model[:p_LS])
        power_ls_h = hcat([Array(power_ls[:,h]) for h in H]...)
        #print(size(power_ls_h))
        #print(power_ls_h)
        power_ls_h_df = DataFrame(power_ls_h, [Symbol("h$h") for h in H])
        P_ls_df = hcat(P_ls_df, power_ls_h_df)

        CSV.write(joinpath(outpath, "power_loadshedding.csv"), P_ls_df, writeheader=true)

        ##Renewable curtailments
        P_ct_df = DataFrame(
            Technology = vcat(Gendata[[g for g in intersect(G,union(G_PV,G_W))],"Type"]),
            Zone = vcat(Gendata[[g for g in intersect(G,union(G_PV,G_W))],"Zone"]),
            EC_Category = repeat(["Existing"],size([g for g in intersect(G,union(G_PV,G_W))])[1]), # existing capacity
            AnnSum = Array{Union{Missing,Float64}}(undef, size([g for g in intersect(G,union(G_PV,G_W))])[1])  #Annual generation output
        )
        P_ct_df.AnnSum .= [sum(value.(model[:RenewableCurtailExist][Zone_idx_dict[Gendata[g,"Zone"]],g,h]) for h in H;init=0) for g in intersect(G,union(G_PV,G_W))]
        #[sum(value.(model[:dc][s,t,h]) for t in T for h in H_t[t] ) for s in S]
        #Retreive power data from solved model
        power = value.(model[:RenewableCurtailExist])
        #print(size([[power[Zone_idx_dict[Gendata[g,"Zone"]],g,h] for h in H] for g in intersect(G,union(G_PV,G_W))]))
        power_h =[[power[Zone_idx_dict[Gendata[g,"Zone"]],g,h] for h in H] for g in intersect(G,union(G_PV,G_W))]
        power_h_df = DataFrame([[] for h in H],[Symbol("h$h") for h in H])
        for r in 1:size(power_h)[1]
            push!(power_h_df,power_h[r])
        end
        #power_h_df = DataFrame(power_h, [Symbol("h$h") for h in H])
        P_ct_df = hcat(P_ct_df, power_h_df )
        CSV.write(joinpath(outpath, "power_renewable_curtailment.csv"), P_ct_df , writeheader=true)
        
        #Power OutputDF
        if network_model in [2, 3] && nodal_output_map !== nothing
            gendata_cols_local = Set(string.(names(Gendata)))
            gen_bus_col = first_existing_col(gendata_cols_local, ["Bus_id", "bus_id", "Bus", "bus"])
            gen_bus = if gen_bus_col !== nothing
                [Gendata[g, gen_bus_col] for g in G]
            else
                [begin
                    zone_idx = Zone_idx_dict[Gendata[g, "Zone"]]
                    zone_nodes = nodal_output_map.N_i[zone_idx]
                    isempty(zone_nodes) ? missing : nodal_output_map.bus_labels[zone_nodes[1]]
                end for g in G]
            end
            P_gen_df = DataFrame(
                Technology = vcat(Gendata[:, "Type"]),
                Zone = vcat(Gendata[:, "Zone"]),
                Bus = gen_bus,
                EC_Category = repeat(["Existing"], Num_Egen), # existing capacity
                AnnSum = Array{Union{Missing,Float64}}(undef, Num_Egen)  #Annual generation output
            )
        else
            P_gen_df = DataFrame(
                Technology = vcat(Gendata[:, "Type"]),
                Zone = vcat(Gendata[:, "Zone"]),
                EC_Category = repeat(["Existing"], Num_Egen), # existing capacity
                AnnSum = Array{Union{Missing,Float64}}(undef, Num_Egen)  #Annual generation output
            )
        end
        P_gen_df.AnnSum .= [sum(value.(model[:p][g,h]) for h in H) for g in G]
        #Retreive power data from solved model
        power = value.(model[:p])
        power_h = hcat([Array(power[:,h]) for h in H]...)
        power_h_df = DataFrame(power_h, [Symbol("h$h") for h in H])
        P_gen_df = hcat(P_gen_df, power_h_df)
        
        CSV.write(joinpath(outpath, "power_hourly.csv"), P_gen_df, writeheader=true)

        #Emissions output (supports policy and post-processing checks)
        EF = [Gendata[:, "EF"];]
        E_zone_df = DataFrame(
            Zone = Zonedata[:, "Zone_id"],
            State = Zonedata[:, "State"],
            Emissions_ton = [sum(EF[g] * sum(power[g,h] for h in H; init=0) for g in G_i[i]; init=0) for i in I]
        )
        CSV.write(joinpath(outpath, "emissions_zone.csv"), E_zone_df, writeheader=true)
        E_state_df = DataFrame(
            State = W,
            Emissions_ton = [sum(E_zone_df[i, :Emissions_ton] for i in I_w[w]; init=0) for w in W]
        )
        CSV.write(joinpath(outpath, "emissions_state.csv"), E_state_df, writeheader=true)
        
        ##Power price
        # Obtain hourly power price from the active power-balance equation
        P_price_df = DataFrame()
        P_price_nodal_df = DataFrame()
        P_price_decomp_nodal_df = DataFrame()
        P_price_decomp_zonal_df = DataFrame()
        price_zone_matrix = nothing
        price_node_matrix = nothing
        duals_available = config_set["solver"] != "cbc" && has_duals(model)
        if config_set["solver"] == "cbc"
            println("Cbc solver does not support for calaculating electricity price")
        elseif !duals_available
            println("Dual values are unavailable (likely due integer UC). Skip LMP/congestion-dual outputs; set unit_commitment=2 for price analysis.")
        elseif network_model == 1 && haskey(model, :PB_con)
            dual_matrix = dual.(model[:PB_con])
            # JuMP dual sign is opposite to market LMP sign for this balance orientation.
            price_zone_matrix = -[dual_matrix[i,h] for i in I, h in H]
            dual_h_df = DataFrame(price_zone_matrix, [Symbol("h$h") for h in H])
            P_price_df = hcat(DataFrame(Zone = Zonedata[:, "Zone_id"]), dual_h_df)
            CSV.write(joinpath(outpath, "power_price.csv"), P_price_df, writeheader=true)
            ref_zone_raw = get(config_set, "reference_bus", 1)
            ref_zone_idx = resolve_reference_index(ref_zone_raw, length(I), Dict(Idx_zone_dict[i] => i for i in I), "zone")
            decomp_rows = DataFrame(Zone=String[], Hour=Int[], LMP=Float64[], Energy=Float64[], Congestion=Float64[], Loss=Float64[])
            for i in I, (h_idx, h) in enumerate(H)
                lmp = price_zone_matrix[i,h_idx]
                energy = price_zone_matrix[ref_zone_idx,h_idx]
                push!(decomp_rows, (string(Idx_zone_dict[i]), Int(h), lmp, energy, lmp - energy, 0.0))
            end
            P_price_decomp_zonal_df = decomp_rows
            CSV.write(joinpath(outpath, "power_price_decomposition_zonal.csv"), P_price_decomp_zonal_df, writeheader=true)
        elseif network_model == 2 && haskey(model, :PBNode_con) && nodal_output_map !== nothing
            N = [n for n in 1:length(nodal_output_map.bus_labels)]
            dual_matrix = dual.(model[:PBNode_con])
            price_node_matrix = -[dual_matrix[n,h] for n in N, h in H]
            nodal_h_df = DataFrame(price_node_matrix, [Symbol("h$h") for h in H])
            P_price_nodal_df = DataFrame(
                Bus = [nodal_output_map.bus_labels[n] for n in N],
                Zone = [Idx_zone_dict[nodal_output_map.bus_zone_of_n[n]] for n in N],
                State = [Zonedata[nodal_output_map.bus_zone_of_n[n], "State"] for n in N]
            )
            P_price_nodal_df = hcat(P_price_nodal_df, nodal_h_df)
            CSV.write(joinpath(outpath, "power_price_nodal.csv"), P_price_nodal_df, writeheader=true)
            price_zone_matrix = [sum(nodal_output_map.bus_weight[n] * price_node_matrix[n,h] for n in nodal_output_map.N_i[i]; init=0.0) for i in I, h in H]
            zonal_h_df = DataFrame(price_zone_matrix, [Symbol("h$h") for h in H])
            P_price_df = hcat(DataFrame(Zone = Zonedata[:, "Zone_id"]), zonal_h_df)
            CSV.write(joinpath(outpath, "power_price.csv"), P_price_df, writeheader=true)
            CSV.write(joinpath(outpath, "power_price_zonal.csv"), P_price_df, writeheader=true)
            ref_bus_raw = get(config_set, "reference_bus", 1)
            ref_bus_idx = resolve_reference_index(ref_bus_raw, length(N), nodal_output_map.bus_idx_dict, "bus")
            decomp_rows = DataFrame(Bus=Any[], Zone=String[], State=String[], Hour=Int[], LMP=Float64[], Energy=Float64[], Congestion=Float64[], Loss=Float64[])
            for n in N, (h_idx, h) in enumerate(H)
                lmp = price_node_matrix[n,h_idx]
                energy = price_node_matrix[ref_bus_idx,h_idx]
                push!(decomp_rows, (nodal_output_map.bus_labels[n], string(Idx_zone_dict[nodal_output_map.bus_zone_of_n[n]]), string(Zonedata[nodal_output_map.bus_zone_of_n[n], "State"]), Int(h), lmp, energy, lmp - energy, 0.0))
            end
            P_price_decomp_nodal_df = decomp_rows
            CSV.write(joinpath(outpath, "power_price_decomposition_nodal.csv"), P_price_decomp_nodal_df, writeheader=true)
            ref_zone_idx = nodal_output_map.bus_zone_of_n[ref_bus_idx]
            decomp_zone_rows = DataFrame(Zone=String[], Hour=Int[], LMP=Float64[], Energy=Float64[], Congestion=Float64[], Loss=Float64[])
            for i in I, (h_idx, h) in enumerate(H)
                lmp = price_zone_matrix[i,h_idx]
                energy = price_zone_matrix[ref_zone_idx,h_idx]
                push!(decomp_zone_rows, (string(Idx_zone_dict[i]), Int(h), lmp, energy, lmp - energy, 0.0))
            end
            P_price_decomp_zonal_df = decomp_zone_rows
            CSV.write(joinpath(outpath, "power_price_decomposition_zonal.csv"), P_price_decomp_zonal_df, writeheader=true)
        elseif network_model == 3 && haskey(model, :PTDFInjDef_con) && nodal_output_map !== nothing
            N = [n for n in 1:length(nodal_output_map.bus_labels)]
            dual_matrix = dual.(model[:PTDFInjDef_con])
            price_node_matrix = -[dual_matrix[n,h] for n in N, h in H]
            nodal_h_df = DataFrame(price_node_matrix, [Symbol("h$h") for h in H])
            P_price_nodal_df = DataFrame(
                Bus = [nodal_output_map.bus_labels[n] for n in N],
                Zone = [Idx_zone_dict[nodal_output_map.bus_zone_of_n[n]] for n in N],
                State = [Zonedata[nodal_output_map.bus_zone_of_n[n], "State"] for n in N]
            )
            P_price_nodal_df = hcat(P_price_nodal_df, nodal_h_df)
            CSV.write(joinpath(outpath, "power_price_nodal.csv"), P_price_nodal_df, writeheader=true)
            price_zone_matrix = [sum(nodal_output_map.bus_weight[n] * price_node_matrix[n,h] for n in nodal_output_map.N_i[i]; init=0.0) for i in I, h in H]
            zonal_h_df = DataFrame(price_zone_matrix, [Symbol("h$h") for h in H])
            P_price_df = hcat(DataFrame(Zone = Zonedata[:, "Zone_id"]), zonal_h_df)
            CSV.write(joinpath(outpath, "power_price.csv"), P_price_df, writeheader=true)
            CSV.write(joinpath(outpath, "power_price_zonal.csv"), P_price_df, writeheader=true)
            ref_bus_raw = get(config_set, "reference_bus", 1)
            ref_bus_idx = resolve_reference_index(ref_bus_raw, length(N), nodal_output_map.bus_idx_dict, "bus")
            decomp_rows = DataFrame(Bus=Any[], Zone=String[], State=String[], Hour=Int[], LMP=Float64[], Energy=Float64[], Congestion=Float64[], Loss=Float64[])
            for n in N, (h_idx, h) in enumerate(H)
                lmp = price_node_matrix[n,h_idx]
                energy = price_node_matrix[ref_bus_idx,h_idx]
                push!(decomp_rows, (nodal_output_map.bus_labels[n], string(Idx_zone_dict[nodal_output_map.bus_zone_of_n[n]]), string(Zonedata[nodal_output_map.bus_zone_of_n[n], "State"]), Int(h), lmp, energy, lmp - energy, 0.0))
            end
            P_price_decomp_nodal_df = decomp_rows
            CSV.write(joinpath(outpath, "power_price_decomposition_nodal.csv"), P_price_decomp_nodal_df, writeheader=true)
            ref_zone_idx = nodal_output_map.bus_zone_of_n[ref_bus_idx]
            decomp_zone_rows = DataFrame(Zone=String[], Hour=Int[], LMP=Float64[], Energy=Float64[], Congestion=Float64[], Loss=Float64[])
            for i in I, (h_idx, h) in enumerate(H)
                lmp = price_zone_matrix[i,h_idx]
                energy = price_zone_matrix[ref_zone_idx,h_idx]
                push!(decomp_zone_rows, (string(Idx_zone_dict[i]), Int(h), lmp, energy, lmp - energy, 0.0))
            end
            P_price_decomp_zonal_df = decomp_zone_rows
            CSV.write(joinpath(outpath, "power_price_decomposition_zonal.csv"), P_price_decomp_zonal_df, writeheader=true)
        elseif network_model == 0 && haskey(model, :SystemPB_con)
            dual_vec = dual.(model[:SystemPB_con])
            sys_price = reshape([-dual_vec[h] for h in H], 1, length(H))
            P_price_df = hcat(DataFrame(Region = ["System"]), DataFrame(sys_price, [Symbol("h$h") for h in H]))
            CSV.write(joinpath(outpath, "power_price.csv"), P_price_df, writeheader=true)
            decomp_rows = DataFrame(Region=String[], Hour=Int[], LMP=Float64[], Energy=Float64[], Congestion=Float64[], Loss=Float64[])
            for (h_idx, h) in enumerate(H)
                push!(decomp_rows, ("System", Int(h), sys_price[1,h_idx], sys_price[1,h_idx], 0.0, 0.0))
            end
            P_price_decomp_zonal_df = decomp_rows
            CSV.write(joinpath(outpath, "power_price_decomposition_zonal.csv"), P_price_decomp_zonal_df, writeheader=true)
        else
            println("No compatible power-balance duals found for configured network_model=$network_model; skipping power price output.")
        end


        ##Transmission line-----------------------------------------------------------------------------------------------------------
        #Power flow OutputDF
        if network_model in [2, 3] && from_bus_col !== nothing && to_bus_col !== nothing
            P_flow_df = DataFrame(
                From_bus = vcat(Linedata[:, from_bus_col]),
                To_bus = vcat(Linedata[:, to_bus_col]),
                EC_Category = [repeat(["Existing"], Num_Eline)...],
                AnnSum = Array{Union{Missing,Float64}}(undef, Num_Eline)
            )
            if from_zone_col !== nothing && to_zone_col !== nothing
                insertcols!(P_flow_df, 3, :From_zone => vcat(Linedata[:, from_zone_col]))
                insertcols!(P_flow_df, 4, :To_zone => vcat(Linedata[:, to_zone_col]))
            end
        else
            P_flow_df = DataFrame(
                From_zone = from_zone_col === nothing ? repeat(["Unknown"], Num_Eline) : vcat(Linedata[:, from_zone_col]),
                To_zone = to_zone_col === nothing ? repeat(["Unknown"], Num_Eline) : vcat(Linedata[:, to_zone_col]),
                EC_Category = [repeat(["Existing"], Num_Eline)...],
                AnnSum = Array{Union{Missing,Float64}}(undef, Num_Eline)
            )
        end
        P_flow_df.AnnSum .= [sum(value.(model[:f][l,h]) for h in H ) for l in L]
        
        #Retreive power data from solved model
        flow = value.(model[:f])
        flow_t_h = hcat([Array(flow[:,h]) for h in H]...)
        flow_t_h_df = DataFrame(flow_t_h, [Symbol("h$h") for h in H])
        P_flow_df = hcat(P_flow_df, flow_t_h_df )
        CSV.write(joinpath(outpath, "power_flow.csv"), P_flow_df, writeheader=true)
        
        #Congestion rent output (line-by-line)
        hourly_rent = nothing
        line_rent_df = DataFrame(
            Line = L,
            AnnCongestionRent = Array{Union{Missing,Float64}}(undef, Num_Eline)
        )
        if network_model in [2, 3] && price_node_matrix !== nothing && nodal_output_map !== nothing && from_bus_col !== nothing && to_bus_col !== nothing
            line_rent_df[!, :From_bus] = vcat(Linedata[:, from_bus_col])
            line_rent_df[!, :To_bus] = vcat(Linedata[:, to_bus_col])
            hourly_rent = Array{Float64}(undef, Num_Eline, length(H))
            for l in L
                n_from = get(nodal_output_map.bus_idx_dict, Linedata[l, from_bus_col], nothing)
                n_to = get(nodal_output_map.bus_idx_dict, Linedata[l, to_bus_col], nothing)
                for (h_idx, h) in enumerate(H)
                    if n_from === nothing || n_to === nothing
                        hourly_rent[l, h_idx] = 0.0
                    else
                        hourly_rent[l, h_idx] = (price_node_matrix[n_to, h_idx] - price_node_matrix[n_from, h_idx]) * flow[l,h]
                    end
                end
                line_rent_df[l, :AnnCongestionRent] = sum(hourly_rent[l, :])
            end
            line_rent_h_df = DataFrame(hourly_rent, [Symbol("h$h") for h in H])
            line_rent_df = hcat(line_rent_df, line_rent_h_df)
        elseif price_zone_matrix !== nothing && from_zone_col !== nothing && to_zone_col !== nothing
            line_rent_df[!, :From_zone] = vcat(Linedata[:, from_zone_col])
            line_rent_df[!, :To_zone] = vcat(Linedata[:, to_zone_col])
            hourly_rent = Array{Float64}(undef, Num_Eline, length(H))
            for l in L
                from_i = get(Zone_idx_dict, Linedata[l, from_zone_col], nothing)
                to_i = get(Zone_idx_dict, Linedata[l, to_zone_col], nothing)
                for (h_idx, h) in enumerate(H)
                    if from_i === nothing || to_i === nothing
                        hourly_rent[l, h_idx] = 0.0
                    else
                        hourly_rent[l, h_idx] = (price_zone_matrix[to_i, h_idx] - price_zone_matrix[from_i, h_idx]) * flow[l,h]
                    end
                end
                line_rent_df[l, :AnnCongestionRent] = sum(hourly_rent[l, :])
            end
            line_rent_h_df = DataFrame(hourly_rent, [Symbol("h$h") for h in H])
            line_rent_df = hcat(line_rent_df, line_rent_h_df)
        else
            line_rent_df.AnnCongestionRent .= 0.0
        end
        CSV.write(joinpath(outpath, "line_congestion_rent.csv"), line_rent_df, writeheader=true)
        shadow_h = nothing
        line_shadow_df = DataFrame()
        if duals_available && haskey(model, :TLe_con)
            dual_tle = dual.(model[:TLe_con])
            shadow_h = [dual_tle[l,h] for l in L, h in H]
            line_shadow_df = DataFrame(
                Line = L,
                AnnAbsShadowPrice = [sum(abs(shadow_h[l, h_idx]) for h_idx in 1:length(H); init=0.0) for l in L]
            )
            if network_model in [2, 3] && from_bus_col !== nothing && to_bus_col !== nothing
                line_shadow_df[!, :From_bus] = vcat(Linedata[:, from_bus_col])
                line_shadow_df[!, :To_bus] = vcat(Linedata[:, to_bus_col])
            elseif from_zone_col !== nothing && to_zone_col !== nothing
                line_shadow_df[!, :From_zone] = vcat(Linedata[:, from_zone_col])
                line_shadow_df[!, :To_zone] = vcat(Linedata[:, to_zone_col])
            end
            line_shadow_h_df = DataFrame(shadow_h, [Symbol("h$h") for h in H])
            line_shadow_df = hcat(line_shadow_df, line_shadow_h_df)
            CSV.write(joinpath(outpath, "line_shadow_price.csv"), line_shadow_df, writeheader=true)
        end
        
        ##Storage---------------------------------------------------------------------------------------------------------------------
        #=
        P_es_df = DataFrame(
            Technology = vcat(Storagedata[:,"Type"]),
            Zone = vcat(Storagedata[:,"Zone"]),
            EC_Category = repeat(["Existing"],Num_sto),
            ChAnnSum = Array{Union{Missing,Float64}}(undef, Num_sto),     #Annual charge
            DisAnnSum = Array{Union{Missing,Float64}}(undef, Num_sto),    #Annual discharge
        )
        P_es_df.ChAnnSum .= [sum(value.(model[:c][s,h])  for h in H ) for s in S]
        P_es_df.DisAnnSum .= [sum(value.(model[:dc][s,h]) for h in H) for s in S]

        #Retreive power data from solved model
        power_c = value.(model[:c])
        power_dc = value.(model[:dc])
        power_soc = value.(model[:soc])

        power_c_h = hcat([Array(power_c[:,h]) for h in H]...)
        power_c_h_df = DataFrame(power_c_h, [Symbol("c_"*"h$h") for h in H])

        power_dc_h = hcat([Array(power_dc[:,h]) for h in H]...)
        power_dc_h_df = DataFrame(power_dc_h, [Symbol("dc_"*"h$h") for h in H])

        power_soc_h = hcat([Array(power_soc[:,h]) for h in H]...)
        power_soc_h_df = DataFrame(power_soc_h, [Symbol("soc_"*"h$h") for h in H])

        P_es_df = hcat(P_es_df, power_c_h_df, power_dc_h_df, power_soc_h_df)
        CSV.write(joinpath(outpath, "es_power_hourly.csv"), P_es_df, writeheader=true)
        =#
        #c
        P_es_c_df = DataFrame(
            Technology = vcat(Storagedata[:,"Type"]),
            Zone = vcat(Storagedata[:,"Zone"]),
            EC_Category = repeat(["Existing"],Num_sto),
            ChAnnSum = Array{Union{Missing,Float64}}(undef, size(S)[1]),     #Annual charge
        )
        P_es_c_df.ChAnnSum .= [sum(value.(model[:c][s,h]) for h in H) for s in S]
    
        #Retreive power data from solved model
        power_c = value.(model[:c])

        power_c_t_h = hcat([Array(power_c[:,h]) for h in H]...)
        power_c_t_h_df = DataFrame(power_c_t_h, [Symbol("c_"*"h$h") for h in H])

        P_es_c_df = hcat(P_es_c_df, power_c_t_h_df)
        CSV.write(joinpath(outpath, "es_power_charge.csv"), P_es_c_df, writeheader=true)
        #dc
        P_es_dc_df = DataFrame(
            Technology = vcat(Storagedata[:,"Type"]),
            Zone = vcat(Storagedata[:,"Zone"]),
            EC_Category = repeat(["Existing"],Num_sto),
            DisAnnSum = Array{Union{Missing,Float64}}(undef, size(S)[1]),    #Annual discharge
        )
        P_es_dc_df.DisAnnSum .= [sum(value.(model[:dc][s,h]) for h in H) for s in S]
        
        #Retreive power data from solved model
        power_dc = value.(model[:dc])

        power_dc_t_h = hcat([Array(power_dc[:,h]) for h in H]...)
        power_dc_t_h_df = DataFrame(power_dc_t_h, [Symbol("dc_"*"h$h") for h in H])

        P_es_dc_df = hcat(P_es_dc_df,  power_dc_t_h_df)
        CSV.write(joinpath(outpath, "es_power_discharge.csv"), P_es_dc_df, writeheader=true)
        #soc
        P_es_soc_df = DataFrame(
            Technology = vcat(Storagedata[:,"Type"]),
            Zone = vcat(Storagedata[:,"Zone"]),
            EC_Category = repeat(["Existing"],Num_sto),
        )
        
        #Retreive power data from solved model
        power_soc = value.(model[:soc])

        power_soc_t_h = hcat([Array(power_soc[:,h]) for h in H]...)
        power_soc_t_h_df = DataFrame(power_soc_t_h, [Symbol("soc_"*"h$h") for h in H])

        P_es_soc_df = hcat(P_es_soc_df, power_soc_t_h_df)
        CSV.write(joinpath(outpath, "es_power_soc.csv"), P_es_soc_df, writeheader=true)
        ##Demand response program---------------------------------------------------------------------------------------------------------------------
        if flexible_demand == 1
            # Net DR shift (payback minus deferred)
            dr_df = DataFrame(
                Resource = vcat(R),
                Zone = vcat(DRdata[:,"Zone"]),    
                Technology = vcat(DRdata[:,"Type"]),
                DRAnnSum = Array{Union{Missing,Float64}}(undef, size(R)[1]),
            )
            dr_df.DRAnnSum .= [sum(value.(model[:dr_PB][r,h]) - value.(model[:dr_DF][r,h]) for h in H) for r in R]
            
            #Retreive power data from solved model
            power_dr_df = value.(model[:dr_DF])
            power_dr_pb = value.(model[:dr_PB])

            power_dr_t_h = hcat([Array(power_dr_pb[:,h] .- power_dr_df[:,h]) for h in H]...)
            power_dr_t_h_df = DataFrame(power_dr_t_h, [Symbol("dr_"*"h$h") for h in H])

            dr_df = hcat(dr_df, power_dr_t_h_df)

            CSV.write(joinpath(outpath, "dr_power.csv"), dr_df, writeheader=true)
            
            # DR payback
            dr_up_df = DataFrame(
                Resource = vcat(R),
                Zone = vcat(DRdata[:,"Zone"]),    
                Technology = vcat(DRdata[:,"Type"]),
                DRAnnSum = Array{Union{Missing,Float64}}(undef, size(R)[1]),
            )
            dr_up_df.DRAnnSum .= [sum(value.(model[:dr_PB][r,h]) for h in H) for r in R]
            
            #Retreive power data from solved model
            power_dr_up = value.(model[:dr_PB])

            power_dr_up_t_h = hcat([Array(power_dr_up[:,h]) for h in H]...)
            power_dr_up_t_h_df = DataFrame(power_dr_up_t_h, [Symbol("dr_"*"h$h") for h in H])

            dr_up_df = hcat(dr_up_df, power_dr_up_t_h_df)

            CSV.write(joinpath(outpath, "dr_pb_power.csv"), dr_up_df, writeheader=true)
            # Backward-compatible alias
            CSV.write(joinpath(outpath, "dr_up_power.csv"), dr_up_df, writeheader=true)
        
            # DR deferred
            dr_dn_df = DataFrame(
                Resource = vcat(R),
                Zone = vcat(DRdata[:,"Zone"]),    
                Technology = vcat(DRdata[:,"Type"]),
                DRAnnSum = Array{Union{Missing,Float64}}(undef, size(R)[1]),
            )
            dr_dn_df.DRAnnSum .= [sum(value.(model[:dr_DF][r,h]) for h in H) for r in R]
            
            #Retreive power data from solved model
            power_dr_dn = value.(model[:dr_DF])

            power_dr_dn_t_h = hcat([Array(power_dr_dn[:,h]) for h in H]...)
            power_dr_dn_t_h_df = DataFrame(power_dr_dn_t_h, [Symbol("dr_"*"h$h") for h in H])

            dr_dn_df = hcat(dr_dn_df, power_dr_dn_t_h_df)

            CSV.write(joinpath(outpath, "dr_df_power.csv"), dr_dn_df, writeheader=true)
            # Backward-compatible alias
            CSV.write(joinpath(outpath, "dr_dn_power.csv"), dr_dn_df, writeheader=true)

            # DR backlog
            dr_backlog_df = DataFrame(
                Resource = vcat(R),
                Zone = vcat(DRdata[:,"Zone"]),
                Technology = vcat(DRdata[:,"Type"]),
                DRAnnSum = Array{Union{Missing,Float64}}(undef, size(R)[1]),
            )
            dr_backlog_df.DRAnnSum .= [sum(value.(model[:b_DR][r,h]) for h in H) for r in R]
            power_dr_backlog = value.(model[:b_DR])
            power_dr_backlog_t_h = hcat([Array(power_dr_backlog[:,h]) for h in H]...)
            power_dr_backlog_t_h_df = DataFrame(power_dr_backlog_t_h, [Symbol("dr_"*"h$h") for h in H])
            dr_backlog_df = hcat(dr_backlog_df, power_dr_backlog_t_h_df)
            CSV.write(joinpath(outpath, "dr_backlog.csv"), dr_backlog_df, writeheader=true)
        
        end
        ##System Cost-----------------------------------------------------------------------------------------------------------
        Cost_df = DataFrame(
            Zone = vcat(Ordered_zone_nm),
            Opr_cost = Array{Union{Missing,Float64}}(undef, Num_zone),
            #RPS_plt = Array{Union{Missing,Float64}}(undef, Num_zone),
            #Carbon_plt =Array{Union{Missing,Float64}}(undef, Num_zone),
            LoL_plt = Array{Union{Missing,Float64}}(undef, Num_zone),
            Total_cost = Array{Union{Missing,Float64}}(undef, Num_zone)
        )
        p = value.(model[:p])
        c = value.(model[:c])
        dc = value.(model[:dc])
        p_LS = value.(model[:p_LS])
        for i in  1:Num_zone
            Opr_c = sum(VCG[g]*sum(p[g,h] for h in H; init=0) for g in G_i[i]; init=0) + sum(VCS[s]*sum(c[s,h]+dc[s,h] for h in H; init=0) for s in S_i[i]; init=0)
            #RPS_p =  PT_rps*sum(pt_rps[w] for w in W)
            #Cb_p = PT_emis*sum(em_emis[w] for w in W)
            Lol_p = sum(VOLL*sum(p_LS[d,h] for h in H; init=0) for d in intersect(D,D_i[i]); init=0)
            Tot = sum([Opr_c,Lol_p])
            Cost_df[i,2:end] = [Opr_c,Lol_p,Tot]
        end
        rename!(Cost_df, :Opr_cost => Symbol("Opr_cost (\$)"))
        rename!(Cost_df, :LoL_plt => Symbol("LoL_plt (\$)"))
        rename!(Cost_df, :Total_cost => Symbol("Total_cost (\$)"))
        CSV.write(joinpath(outpath, "system_cost.csv"), Cost_df, writeheader=true)

        if summary_table == 1
            mkpath(summary_outpath)
            println("Generating summary analysis tables in $summary_outpath ...")

            to_float_local(v) = v isa Number ? Float64(v) : parse(Float64, string(v))

            ## Summary_Price_Hourly -------------------------------------------------------------
            if nrow(P_price_decomp_nodal_df) > 0
                for r in eachrow(P_price_decomp_nodal_df)
                    push!(Summary_Price_Hourly_df, (
                        "Node",
                        string(r.Bus),
                        string(r.Zone),
                        string(r.State),
                        Int(r.Hour),
                        Float64(r.LMP),
                        Float64(r.Energy),
                        Float64(r.Congestion),
                        Float64(r.Loss)
                    ))
                end
            end
            if nrow(P_price_decomp_zonal_df) > 0
                if "Zone" in names(P_price_decomp_zonal_df)
                    for r in eachrow(P_price_decomp_zonal_df)
                        zone_nm = string(r.Zone)
                        state_nm = haskey(Zone_idx_dict, zone_nm) ? string(Zonedata[Zone_idx_dict[zone_nm], "State"]) : ""
                        push!(Summary_Price_Hourly_df, (
                            "Zone",
                            zone_nm,
                            zone_nm,
                            state_nm,
                            Int(r.Hour),
                            Float64(r.LMP),
                            Float64(r.Energy),
                            Float64(r.Congestion),
                            Float64(r.Loss)
                        ))
                    end
                elseif "Region" in names(P_price_decomp_zonal_df)
                    for r in eachrow(P_price_decomp_zonal_df)
                        push!(Summary_Price_Hourly_df, (
                            "System",
                            string(r.Region),
                            "",
                            "",
                            Int(r.Hour),
                            Float64(r.LMP),
                            Float64(r.Energy),
                            Float64(r.Congestion),
                            Float64(r.Loss)
                        ))
                    end
                end
            end
            if nrow(Summary_Price_Hourly_df) > 0
                CSV.write(joinpath(summary_outpath, "Summary_Price_Hourly.csv"), Summary_Price_Hourly_df, writeheader=true)
            end

            ## Summary_Congestion_Line_Hourly --------------------------------------------------
            cap_col = first_existing_col(linedata_cols, ["Capacity (MW)", "Line Capacity (MW)", "RateA", "RATE_A", "rateA"])
            line_limits = cap_col === nothing ? fill(0.0, Num_Eline) : [to_float_local(Linedata[l, cap_col]) for l in L]
            for l in L
                from_bus_val = from_bus_col === nothing ? "" : string(Linedata[l, from_bus_col])
                to_bus_val = to_bus_col === nothing ? "" : string(Linedata[l, to_bus_col])
                from_zone_val = from_zone_col === nothing ? "" : string(Linedata[l, from_zone_col])
                to_zone_val = to_zone_col === nothing ? "" : string(Linedata[l, to_zone_col])
                if (from_zone_col === nothing || to_zone_col === nothing) && nodal_output_map !== nothing && from_bus_col !== nothing && to_bus_col !== nothing
                    n_from = get(nodal_output_map.bus_idx_dict, Linedata[l, from_bus_col], nothing)
                    n_to = get(nodal_output_map.bus_idx_dict, Linedata[l, to_bus_col], nothing)
                    if n_from !== nothing
                        from_zone_val = string(Idx_zone_dict[nodal_output_map.bus_zone_of_n[n_from]])
                    end
                    if n_to !== nothing
                        to_zone_val = string(Idx_zone_dict[nodal_output_map.bus_zone_of_n[n_to]])
                    end
                end
                limit_mw = line_limits[l]
                for (h_idx, h) in enumerate(H)
                    flow_mw = Float64(flow[l, h])
                    loading_pct = limit_mw > 0 ? 100.0 * abs(flow_mw) / limit_mw : 0.0
                    tol = max(1.0e-4, 1.0e-5 * max(1.0, abs(limit_mw)))
                    binding_side = if limit_mw > 0 && abs(flow_mw - limit_mw) <= tol
                        "Upper"
                    elseif limit_mw > 0 && abs(flow_mw + limit_mw) <= tol
                        "Lower"
                    else
                        "None"
                    end
                    shadow_val = shadow_h === nothing ? missing : Float64(shadow_h[l, h_idx])
                    rent_val = hourly_rent === nothing ? missing : Float64(hourly_rent[l, h_idx])
                    push!(Summary_Congestion_Line_Hourly_df, (
                        Int(l),
                        from_bus_val,
                        to_bus_val,
                        from_zone_val,
                        to_zone_val,
                        Int(h),
                        flow_mw,
                        limit_mw,
                        loading_pct,
                        shadow_val,
                        binding_side,
                        rent_val
                    ))
                end
            end
            CSV.write(joinpath(summary_outpath, "Summary_Congestion_Line_Hourly.csv"), Summary_Congestion_Line_Hourly_df, writeheader=true)

            ## Summary_Congestion_Line_Annual --------------------------------------------------
            for l in L
                rows_l = findall(Summary_Congestion_Line_Hourly_df[!, :Line] .== l)
                if isempty(rows_l)
                    continue
                end
                from_bus_val = Summary_Congestion_Line_Hourly_df[rows_l[1], :From_bus]
                to_bus_val = Summary_Congestion_Line_Hourly_df[rows_l[1], :To_bus]
                from_zone_val = Summary_Congestion_Line_Hourly_df[rows_l[1], :From_zone]
                to_zone_val = Summary_Congestion_Line_Hourly_df[rows_l[1], :To_zone]
                loading_vals = Float64.(Summary_Congestion_Line_Hourly_df[rows_l, :Loading_pct])
                shadow_vals = collect(skipmissing(Summary_Congestion_Line_Hourly_df[rows_l, :ShadowPrice]))
                rent_vals = collect(skipmissing(Summary_Congestion_Line_Hourly_df[rows_l, :CongestionRent]))
                hours_binding = count(x -> x != "None", Summary_Congestion_Line_Hourly_df[rows_l, :BindingSide])
                avg_abs_shadow = isempty(shadow_vals) ? missing : mean(abs.(shadow_vals))
                max_abs_shadow = isempty(shadow_vals) ? missing : maximum(abs.(shadow_vals))
                ann_rent = isempty(rent_vals) ? 0.0 : sum(rent_vals)
                avg_loading = isempty(loading_vals) ? 0.0 : mean(loading_vals)
                p95_loading = isempty(loading_vals) ? 0.0 : quantile(loading_vals, 0.95)
                push!(Summary_Congestion_Line_Annual_df, (
                    Int(l),
                    string(from_bus_val),
                    string(to_bus_val),
                    string(from_zone_val),
                    string(to_zone_val),
                    Int(hours_binding),
                    avg_abs_shadow,
                    max_abs_shadow,
                    Float64(ann_rent),
                    Float64(avg_loading),
                    Float64(p95_loading)
                ))
            end
            CSV.write(joinpath(summary_outpath, "Summary_Congestion_Line_Annual.csv"), Summary_Congestion_Line_Annual_df, writeheader=true)

            ## Summary_System_Hourly -----------------------------------------------------------
            zone_load = zeros(Float64, Num_zone, length(H))
            for i in I, (h_idx, h) in enumerate(H)
                zone_nm = Ordered_zone_nm[i]
                zone_load[i, h_idx] = to_float_local(Loaddata[h, zone_nm]) * to_float_local(Zonedata[i, "Demand (MW)"])
            end
            system_load = [sum(zone_load[:, h_idx]) for h_idx in 1:length(H)]
            gen_hour = [sum(power[g, h] for g in G; init=0.0) for h in H]
            storage_charge_hour = [sum(value(model[:c][s, h]) for s in S; init=0.0) for h in H]
            storage_discharge_hour = [sum(value(model[:dc][s, h]) for s in S; init=0.0) for h in H]
            loadshed_hour = [sum(power_ls[d, h] for d in D; init=0.0) for h in H]
            ct_exist = value.(model[:RenewableCurtailExist])
            curtail_hour = [sum(ct_exist[:, :, h]; init=0.0) for h in H]
            avg_lmp_hour = Vector{Union{Missing,Float64}}(undef, length(H))
            fill!(avg_lmp_hour, missing)
            if price_node_matrix !== nothing && nodal_output_map !== nothing
                for (h_idx, _) in enumerate(H)
                    denom = system_load[h_idx]
                    if denom <= 0
                        avg_lmp_hour[h_idx] = missing
                        continue
                    end
                    num = 0.0
                    for i in I
                        zl = zone_load[i, h_idx]
                        for n in nodal_output_map.N_i[i]
                            num += nodal_output_map.bus_weight[n] * zl * price_node_matrix[n, h_idx]
                        end
                    end
                    avg_lmp_hour[h_idx] = num / denom
                end
            elseif price_zone_matrix !== nothing
                for (h_idx, _) in enumerate(H)
                    denom = system_load[h_idx]
                    if denom <= 0
                        avg_lmp_hour[h_idx] = missing
                        continue
                    end
                    num = sum(zone_load[i, h_idx] * price_zone_matrix[i, h_idx] for i in I; init=0.0)
                    avg_lmp_hour[h_idx] = num / denom
                end
            elseif nrow(P_price_df) > 0
                for (h_idx, h) in enumerate(H)
                    h_sym = Symbol("h$h")
                    if h_sym in names(P_price_df)
                        avg_lmp_hour[h_idx] = to_float_local(P_price_df[1, h_sym])
                    end
                end
            end
            EF_vec = [to_float_local(v) for v in Gendata[:, "EF"]]
            emissions_hour = [sum(EF_vec[g] * power[g, h] for g in G; init=0.0) for h in H]
            for (h_idx, h) in enumerate(H)
                push!(Summary_System_Hourly_df, (
                    Int(h),
                    Float64(system_load[h_idx]),
                    Float64(gen_hour[h_idx]),
                    Float64(storage_charge_hour[h_idx]),
                    Float64(storage_discharge_hour[h_idx]),
                    Float64(loadshed_hour[h_idx]),
                    Float64(curtail_hour[h_idx]),
                    avg_lmp_hour[h_idx],
                    Float64(emissions_hour[h_idx])
                ))
            end
            CSV.write(joinpath(summary_outpath, "Summary_System_Hourly.csv"), Summary_System_Hourly_df, writeheader=true)

            ## Summary_Congestion_Driver_Node_Hourly (nodal only) ------------------------------
            if network_model in [2, 3]
                if nodal_output_map !== nothing && shadow_h !== nothing && from_bus_col !== nothing && to_bus_col !== nothing
                    N = [n for n in 1:length(nodal_output_map.bus_labels)]
                    ptdf_matrix_summary = zeros(Float64, Num_Eline, length(N))
                    ptdf_ok = true
                    ref_bus_raw = get(config_set, "reference_bus", 1)
                    ref_bus_idx = resolve_reference_index(ref_bus_raw, length(N), nodal_output_map.bus_idx_dict, "bus")
                    ptdf_nodal_data = haskey(input_data, "PTDFNodalData") ? input_data["PTDFNodalData"] : (haskey(input_data, "PTDFdata") ? input_data["PTDFdata"] : nothing)
                    if network_model == 3 && ptdf_nodal_data !== nothing
                        ptdf_cols = Set(string.(names(ptdf_nodal_data)))
                        missing_bus_cols = [string(nodal_output_map.bus_labels[n]) for n in N if !(string(nodal_output_map.bus_labels[n]) in ptdf_cols)]
                        if isempty(missing_bus_cols) && size(ptdf_nodal_data, 1) == Num_Eline
                            for n in N
                                ptdf_matrix_summary[:, n] .= [to_float_local(v) for v in ptdf_nodal_data[:, string(nodal_output_map.bus_labels[n])]]
                            end
                        else
                            ptdf_ok = false
                            println("Skip Summary_Congestion_Driver_Node_Hourly: invalid/missing nodal PTDF input columns or row count.")
                        end
                    else
                        x_col = first_existing_col(linedata_cols, ["X", "Reactance", "x"])
                        x_vals = x_col === nothing ? fill(1.0, Num_Eline) : [to_float_local(Linedata[l, x_col]) for l in L]
                        from_idx = Vector{Int}(undef, Num_Eline)
                        to_idx = Vector{Int}(undef, Num_Eline)
                        for l in L
                            n_from = get(nodal_output_map.bus_idx_dict, Linedata[l, from_bus_col], nothing)
                            n_to = get(nodal_output_map.bus_idx_dict, Linedata[l, to_bus_col], nothing)
                            if n_from === nothing || n_to === nothing
                                ptdf_ok = false
                                break
                            end
                            from_idx[l] = n_from
                            to_idx[l] = n_to
                        end
                        if ptdf_ok
                            ptdf_matrix_summary .= compute_ptdf_from_incidence(from_idx, to_idx, x_vals, length(N), ref_bus_idx)
                        else
                            println("Skip Summary_Congestion_Driver_Node_Hourly: unable to map line endpoint buses to nodal indices.")
                        end
                    end

                    if ptdf_ok
                        for (h_idx, h) in enumerate(H)
                            for l in L
                                sh = Float64(shadow_h[l, h_idx])
                                if abs(sh) <= 1.0e-8
                                    continue
                                end
                                ref_ptdf = ptdf_matrix_summary[l, ref_bus_idx]
                                from_bus_val = string(Linedata[l, from_bus_col])
                                to_bus_val = string(Linedata[l, to_bus_col])
                                for n in N
                                    delta_ptdf = ptdf_matrix_summary[l, n] - ref_ptdf
                                    contrib = sh * delta_ptdf
                                    if abs(contrib) <= 1.0e-8
                                        continue
                                    end
                                    zone_idx_n = nodal_output_map.bus_zone_of_n[n]
                                    push!(Summary_Congestion_Driver_Node_Hourly_df, (
                                        string(nodal_output_map.bus_labels[n]),
                                        string(Idx_zone_dict[zone_idx_n]),
                                        string(Zonedata[zone_idx_n, "State"]),
                                        Int(h),
                                        Int(l),
                                        from_bus_val,
                                        to_bus_val,
                                        Float64(ptdf_matrix_summary[l, n]),
                                        Float64(delta_ptdf),
                                        Float64(sh),
                                        Float64(contrib)
                                    ))
                                end
                            end
                        end
                    end
                else
                    println("Skip Summary_Congestion_Driver_Node_Hourly: missing nodal mapping, line endpoint columns, or shadow prices.")
                end
                CSV.write(joinpath(summary_outpath, "Summary_Congestion_Driver_Node_Hourly.csv"), Summary_Congestion_Driver_Node_Hourly_df, writeheader=true)
            end
        end

        Results_dict = Dict(
            "power_loadshedding" => P_ls_df,
            "power_renewable_curtailment" =>P_ct_df,
            "power_hourly" => P_gen_df,
            "power_price" => P_price_df,
            "power_price_nodal" => P_price_nodal_df,
            "power_price_decomposition_nodal" => P_price_decomp_nodal_df,
            "power_price_decomposition_zonal" => P_price_decomp_zonal_df,
            "power_flow" => P_flow_df,
            "line_congestion_rent" => line_rent_df,
            "line_shadow_price" => line_shadow_df,
            "es_power_charge" => P_es_c_df,
            "es_power_discharge" => P_es_dc_df,
            "es_power_soc" => P_es_soc_df,
            "emissions_zone" => E_zone_df,
            "emissions_state" => E_state_df,
            "system_cost" => Cost_df,
            "Summary_Price_Hourly" => Summary_Price_Hourly_df,
            "Summary_Congestion_Line_Hourly" => Summary_Congestion_Line_Hourly_df,
            "Summary_Congestion_Line_Annual" => Summary_Congestion_Line_Annual_df,
            "Summary_System_Hourly" => Summary_System_Hourly_df,
            "Summary_Congestion_Driver_Node_Hourly" => Summary_Congestion_Driver_Node_Hourly_df)
    end
	println("Write solved results in the folder $outpath 'output' DONE!")

    return Results_dict
end
