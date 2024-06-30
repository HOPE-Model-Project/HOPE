function mkdir_overwrite(path::AbstractString)
    if isdir(path)
        rm(path; force=true, recursive=true)
        println() 
        println("'output' folder exists, will be overwritten!")
    end
    mkdir(path)
end

function write_output(outpath::AbstractString,config_set::Dict, input_data::Dict, model::Model)
	mkdir_overwrite(outpath)
    model_mode = config_set["model_mode"]
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
        W=unique(Zonedata[:,"State"])
        #lines
        L=[l for l=1:Num_Eline+Num_Cline]						#Set of transmission corridors, index l
        L_exist=[l for l=1:Num_Eline]									#Set of existing transmission corridors
		L_new=[l for l=Num_Eline+1:Num_Eline+Num_Cline]					#Set of candidate transmission corridors
        #Time period
        T=[t for t=1:length(config_set["time_periods"])]		#Set of time periods (e.g., representative days of seasons), index t
		if config_set["representative_day!"]==1														#Set of hours in one day, index h, subset of H
			H_t=[collect(1:24) for t in T]									#Set of hours in time period (day) t, index h, subset of H
			H_T = collect(unique(reduce(vcat,H_t)))							#Set of unique hours in time period, index h, subset of H
		else
			H_t=[collect(1:8760) for t in [1]]									#Set of hours in time period (day) t, index h, subset of H
			H_T = collect(unique(reduce(vcat,H_t)))							#Set of unique hours in time period, index h, subset of H
		end
        I=[i for i=1:Num_zone]
        I_w=Dict(zip(W, [findall(Zonedata[:,"State"].== w) for w in W])) #Set of zones in state w, subset of I
        HD = [h for h in 1:24]
        #Sets
        G=[g for g=1:Num_Egen+Num_Cgen]
        G_exist=[g for g=1:Num_Egen]
        G_new=[g for g=Num_Egen+1:Num_Egen+Num_Cgen]
        G_RET=findall(x -> x in [1], Gendata[:,"Flag_RET"])
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
		if config_set["representative_day!"]==1
			time_periods = config_set["time_periods"]
            N=get_representative_ts(Loaddata,time_periods,Ordered_zone_nm)[2]
        else
            N=[1]
            T=[1]
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
        P_gen_df.AnnSum .= [sum(value.(model[:p][g,t,h]) for t in T for h in H_t[t] ) for g in G]
        New_built_idx = map(x -> x + Num_Egen, [i for (i, v) in enumerate(value.(model[:x])) if v > 0])
        #print(New_built_idx)
        #New_built_idx = map(x -> G_new[x], [i for (i, v) in enumerate(value.(model[:x])) if v > 0])
        P_gen_df[!,:New_Build] .= 0
        P_gen_df[New_built_idx,:New_Build] .= 1
        #Retreive power data from solved model
        power = value.(model[:p])
        power_t_h = hcat([Array(power[:,t,h]) for t in T for h in H_t[t]]...)
        #print(power_t_h)
        power_t_h_df = DataFrame(power_t_h, [Symbol("t$t"*"h$h") for t in T for h in H_t[t]])
        P_gen_df = hcat(P_gen_df, power_t_h_df )
        
        CSV.write(joinpath(outpath, "power.csv"), P_gen_df, writeheader=true)
        
        ##Power price
        # Obtain hourly power price, utilize power balance constraint's shadow price
        if config_set["solver"] == "cbc"
            P_price_df = DataFrame()
            println("Cbc solver does not support for calaculating electricity price")
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
        #power_VRE_max_t_h = hct([Array(AFRE_tg[t,g][h,i]*P_max[g]) for t in T for h in H_t[t]]...)
        #power_VRE_ctl_t_h =  hcat([Array(power[G_VRE,t,h]) for t in T for h in H_t[t]]...)

        ##Load shedding
        P_ls_df = DataFrame(
          load_area = vcat(Zonedata[:, "Zone_id"]), 
          AnnTol =  Array{Union{Missing,Float64}}(undef, Num_load)
        )
        P_ls_df.AnnTol .= [sum(value.(model[:p_LS][d,t,h]) for t in T for h in H_t[t]) for d in D]
        power_ls = value.(model[:p_LS])
        power_ls_t_h = hcat([Array(power_ls[:,t,h]) for t in T for h in H_t[t]]...)
        power_ls_t_h_df = DataFrame(power_ls_t_h, [Symbol("t$t"*"h$h") for t in T for h in H_t[t]])
        P_ls_df = hcat(P_ls_df, power_ls_t_h_df)

        CSV.write(joinpath(outpath, "power_loadshedding.csv"), P_ls_df, writeheader=true)
        
        ##Renewable curtailments
        P_ct_df = DataFrame(
            Technology = vcat(Gendata[[g for g in intersect(G_exist,union(G_PV,G_W))],"Type"],Gendata_candidate[[g for g in intersect(G_new,union(G_PV,G_W))] .- Num_Egen,"Type"]),
            Zone = vcat(Gendata[[g for g in intersect(G_exist,union(G_PV,G_W))],"Zone"],Gendata_candidate[[g for g in intersect(G_new,union(G_PV,G_W))] .- Num_Egen,"Zone"]),
            EC_Category = [repeat(["Existing"],size([g for g in intersect(G_exist,union(G_PV,G_W))])[1]);repeat(["Candidate"],size([g for g in intersect(G_new,union(G_PV,G_W))])[1])], # existing capacity
            New_Build = Array{Union{Missing,Bool}}(undef, size([g for g in intersect(G_exist,union(G_PV,G_W))])[1]+size([g for g in intersect(G_new,union(G_PV,G_W))])[1]),
            AnnSum = Array{Union{Missing,Float64}}(undef, size([g for g in intersect(G_exist,union(G_PV,G_W))])[1]+size([g for g in intersect(G_new,union(G_PV,G_W))])[1])  #Annual generation output
        )
        P_ct_df.AnnSum .= [[sum(value.(model[:RenewableCurtailExist][Zone_idx_dict[Gendata[g,"Zone"]],g,t,h]) for t in T for h in H_t[t];init=0) for g in intersect(G_exist,union(G_PV,G_W))];[sum(value.(model[:RenewableCurtailNew][Zone_idx_dict[Gendata_candidate[g - Num_Egen,"Zone"]],g,t,h]) for t in T for h in H_t[t];init=0) for g in intersect(G_new,union(G_PV,G_W))]]
        New_built_vre_idx = intersect(New_built_idx,G_VRE_C)
        New_built_matched_vre_idx = findall(x->x in New_built_vre_idx, [[g for g in intersect(G_exist,union(G_PV,G_W))];[g for g in intersect(G_new,union(G_PV,G_W))]])

        #print(New_built_idx)
        #New_built_idx = map(x -> G_new[x], [i for (i, v) in enumerate(value.(model[:x])) if v > 0])
        P_ct_df[!,:New_Build] .= 0
        P_ct_df[New_built_matched_vre_idx ,:New_Build] .= 1
        #Retreive power data from solved model
        power_e = value.(model[:RenewableCurtailExist])
        power_n = value.(model[:RenewableCurtailNew])
        power_h =[[[power_e[Zone_idx_dict[Gendata[g,"Zone"]],g,t,h] for t in T for h in H_t[t]] for g in intersect(G_exist,union(G_PV,G_W))];[[power_n[Zone_idx_dict[Gendata_candidate[g - Num_Egen,"Zone"]],g,t,h] for t in T for h in H_t[t]] for g in intersect(G_new,union(G_PV,G_W))]]
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
        P_flow_df.AnnSum .= [sum(value.(model[:f][l,t,h]) for t in T for h in H_t[t] ) for l in L]
        
        New_built_line_idx = map(x -> x + Num_Eline, [i for (i, v) in enumerate(value.(model[:y])) if v > 0])
        P_flow_df[!,"New_Build"] .= 0
        P_flow_df[New_built_line_idx,:New_Build] .=1
        
        #Retreive power data from solved model
        flow = value.(model[:f])
        flow_t_h = hcat([Array(flow[:,t,h]) for t in T for h in H_t[t]]...)
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
        P_es_c_df.ChAnnSum .= [sum(value.(model[:c][s,t,h]) for t in T for h in H_t[t] ) for s in S]
        
        New_built_idx = map(x -> x + Num_sto, [i for (i, v) in enumerate(value.(model[:z])) if v > 0])
        P_es_c_df[!,:New_Build] .= 0
        P_es_c_df[New_built_idx,:New_Build] .= 1
        #Retreive power data from solved model
        power_c = value.(model[:c])

        power_c_t_h = hcat([Array(power_c[:,t,h]) for t in T for h in H_t[t]]...)
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
        P_es_dc_df.DisAnnSum .= [sum(value.(model[:dc][s,t,h]) for t in T for h in H_t[t] ) for s in S]
        
        New_built_idx = map(x -> x + Num_sto, [i for (i, v) in enumerate(value.(model[:z])) if v > 0])
        P_es_dc_df[!,:New_Build] .= 0
        P_es_dc_df[New_built_idx,:New_Build] .= 1
        #Retreive power data from solved model
        power_dc = value.(model[:dc])

        power_dc_t_h = hcat([Array(power_dc[:,t,h]) for t in T for h in H_t[t]]...)
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

        power_soc_t_h = hcat([Array(power_soc[:,t,h]) for t in T for h in H_t[t]]...)
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
            Opr_c = sum(VCG[g]*N[t]*sum(p[g,t,h] for h in H_t[t]) for g in intersect(G,G_i[i]) for t in T; init=0) + sum(VCS[s]*N[t]*sum(c[s,t,h]+dc[s,t,h] for h in H_t[t]; init=0) for s in intersect(S,S_i[i]) for t in T; init=0)
            #RPS_p =  PT_rps*sum(pt_rps[w] for w in W)
            #Cb_p = PT_emis*sum(em_emis[w] for w in W)
            Lol_p = sum(VOLL*N[t]*sum(p_LS[d,t,h] for h in H_t[t]; init=0) for d in intersect(D,D_i[i]) for t in T; init=0)
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
        Gendata = input_data["Gendata"]
        Storagedata = input_data["Storagedata"]
        Linedata = input_data["Linedata"]
        Zonedata = input_data["Zonedata"]
        Loaddata = input_data["Loaddata"]
        VOLL = input_data["Singlepar"][1,"VOLL"]
        
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
        H=[h for h=1:8760]
        L=[l for l=1:Num_Eline]						#Set of transmission corridors, index l
        I=[i for i=1:Num_zone]									#Set of zones, index i
        G_i=[findall(Gendata[:,"Zone"].==Idx_zone_dict[i]) for i in I]	
        G_PV_E=findall(Gendata[:,"Type"].=="SolarPV")					#Set of existingsolar, subsets of G
		G_PV=[G_PV_E;]											#Set of all solar, subsets of G
		G_W_E=findall(x -> x in ["WindOn","WindOff"], Gendata[:,"Type"])#Set of existing wind, subsets of G
		G_W=[G_W_E;]                                               #Set of all wind, subsets of G
        S_i=[findall(Storagedata[:,"Zone"].==Idx_zone_dict[i]) for i in I]
        S_exist=[s for s=1:Num_sto]										#Set of existing storage units, subset of S   
        LS_i=[[findall(Linedata[:,"From_zone"].==Idx_zone_dict[i])] for i in I]
  
        #zone
        Ordered_zone_nm = [Idx_zone_dict[i] for i=1:Num_zone]
        #Param
        Gencostdata = input_data["Gendata"][:,Symbol("Cost (\$/MWh)")]
        VCG=[Gencostdata;]#g						#Variable cost of generation unit g, $/MWh
		VCS=[Storagedata[:,Symbol("Cost (\$/MWh)")];]#s		
        unit_converter = 10^6

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
        P_gen_df = DataFrame(
            Technology = vcat(Gendata[:,"Type"]),
            Zone = vcat(Gendata[:,"Zone"]),
            EC_Category = repeat(["Existing"],Num_Egen), # existing capacity
            AnnSum = Array{Union{Missing,Float64}}(undef, Num_Egen)  #Annual generation output
        )
        P_gen_df.AnnSum .= [sum(value.(model[:p][g,h]) for h in H) for g in G]
        #New_built_idx = map(x -> x + Num_Egen, [i for (i, v) in enumerate(value.(model[:x])) if v > 0])
        #P_gen_df[New_built_idx,:New_Build] .= 1
        #Retreive power data from solved model
        power = value.(model[:p])
        power_h = hcat([Array(power[:,h]) for h in H]...)
        power_h_df = DataFrame(power_h, [Symbol("h$h") for h in H])
        P_gen_df = hcat(P_gen_df, power_h_df)
        
        CSV.write(joinpath(outpath, "power_hourly.csv"), P_gen_df, writeheader=true)
        
        ##Power price
        # Obtain hourly power price, utilize power balance constraint's shadow price
        if config_set["solver"] == "cbc"
            P_price_df = DataFrame()
            println("Cbc solver does not support for calaculating electricity price")
        else
            P_price_df = DataFrame(Zone = Zonedata[:,"Zone_id"]) 
            dual_matrix = dual.(model[:PB_con])
            dual_h = [[dual_matrix[i,h] for h in H] for i in I]
            #dfPrice = hcat(dfPrice, DataFrame(transpose(dual_matrix), :auto))
            dual_h = transpose(hcat(dual_h...))
            dual_h_df = DataFrame(dual_h, [Symbol("h$h")  for h in H])
            P_price_df = hcat(P_price_df,dual_h_df)
            CSV.write(joinpath(outpath, "power_price.csv"), P_price_df, writeheader=true)
        end


        ##Transmission line-----------------------------------------------------------------------------------------------------------
        #Power flow OutputDF
        P_flow_df = DataFrame(
            From_zone = vcat(Linedata[:,"From_zone"]),
            To_zone = vcat(Linedata[:,"To_zone"]),
            EC_Category = [repeat(["Existing"],Num_Eline)...],
            AnnSum = Array{Union{Missing,Float64}}(undef, Num_Eline)
        )
        P_flow_df.AnnSum .= [sum(value.(model[:f][l,h]) for h in H ) for l in L]
        
        #Retreive power data from solved model
        flow = value.(model[:f])
        flow_t_h = hcat([Array(flow[:,h]) for h in H]...)
        flow_t_h_df = DataFrame(flow_t_h, [Symbol("h$h") for h in H])
        P_flow_df = hcat(P_flow_df, flow_t_h_df )
        CSV.write(joinpath(outpath, "power_flow.csv"), P_flow_df, writeheader=true)
        
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
        Results_dict = Dict(
            "power_loadshedding" => P_ls_df,
            "power_renewable_curtailment" =>P_ct_df,
            "power_hourly" => P_gen_df,
            "power_price" => P_price_df,
            "power_flow" => P_flow_df,
            "es_power_charge" => P_es_c_df,
            "es_power_discharge" => P_es_dc_df,
            "es_power_soc" => P_es_soc_df,
            "system_cost" => Cost_df)
    end
	println("Write solved results in the folder $outpath 'output' DONE!")

    return Results_dict
end