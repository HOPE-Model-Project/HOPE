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
    println("HOPE model ("*model_mode*" mode) is successfully solved!")
    if model_mode == "GTEP"
        ##read input for print	
        Estoragedata = input_data["Estoragedata"]
        Estoragedata_candidate = input_data["Estoragedata_candidate"]
        Gendata = input_data["Gendata"]
        Gendata_candidate = input_data["Gendata_candidate"]
        Branchdata = input_data["Branchdata"]
        Busdata = input_data["Busdata"]
        Linedata_candidate = input_data["Linedata_candidate"]
        Loaddata = input_data["Loaddata"]
        VOLL = input_data["VOLL"]
        #Calculate number of elements of input data
        Num_Egen=size(Gendata,1)
        Num_bus=size(Busdata,1)
        Num_load=count(!iszero, Busdata[:,3])
        Num_Eline=size(Branchdata,1)
        Num_zone=length(Busdata[:,"Zone_id"])
        Num_sto=size(Estoragedata,1)
        Num_Csto=size(Estoragedata_candidate,1)
        Num_Cgen=size(Gendata_candidate,1)
        Num_Cline=size(Linedata_candidate,1)
        #Mapping
        #Index-Zone Mapping dict
		Idx_zone_dict = Dict(zip([i for i=1:Num_zone],Busdata[:,"Zone_id"]))
		Zone_idx_dict = Dict(zip(Busdata[:,"Zone_id"],[i for i=1:Num_zone]))
        #zone
        Ordered_zone_nm = [Idx_zone_dict[i] for i=1:Num_zone]
        D=[d for d=1:Num_load] 	
        D_i=[[d] for d in D]
        W=unique(Busdata[:,"State"])
        #lines
        L=[l for l=1:Num_Eline+Num_Cline]						#Set of transmission corridors, index l
        L_exist=[l for l=1:Num_Eline]									#Set of existing transmission corridors
		L_new=[l for l=Num_Eline+1:Num_Eline+Num_Cline]					#Set of candidate transmission corridors
        #Time period
        T=[t for t=1:length(config_set["time_periods"])]		#Set of time periods (e.g., representative days of seasons), index t
        H_t=[collect(1:24) for t in T]                          #Set of hours in time period (day) t, index h, subset of H
        I=[i for i=1:Num_zone]
        I_w=Dict(zip(W, [findall(Busdata[:,"State"].== w) for w in W])) #Set of zones in state w, subset of I
        HD = [h for h in 1:24]
        #Sets
        G=[g for g=1:Num_Egen+Num_Cgen]
        G_exist=[g for g=1:Num_Egen]
        G_new=[g for g=Num_Egen+1:Num_Egen+Num_Cgen]
        G_i=[[findall(Gendata[:,"Zone"].==Idx_zone_dict[i]);(findall(Gendata_candidate[:,"Zone"].==Idx_zone_dict[i]).+Num_Egen)] for i in I]	
        S_i=[[findall(Estoragedata[:,"Zone"].==Idx_zone_dict[i]);(findall(Estoragedata_candidate[:,"Zone"].==Idx_zone_dict[i]).+Num_sto)] for i in I]
        S_exist=[s for s=1:Num_sto]										#Set of existing storage units, subset of S  
		S_new=[s for s=Num_sto+1:Num_sto+Num_Csto]						#Set of candidate storage units, subset of S  
        LS_i=[[findall(Branchdata[:,"From_zone"].==Idx_zone_dict[i]);(findall(Linedata_candidate[:,"From_zone"].==Idx_zone_dict[i]).+Num_Eline)] for i in I]
        #Param
        INV_g=Dict(zip(G_new,Gendata_candidate[:,Symbol("Cost (M\$)")])) #g						#Investment cost of candidate generator g, M$
		INV_l=Dict(zip(L_new,Linedata_candidate[:,Symbol("Cost (M\$)")]))#l						#Investment cost of transmission line l, M$
		INV_s=Dict(zip(S_new,Estoragedata_candidate[:,Symbol("Cost (M\$)")])) #s	
        Gencostdata = input_data["Gencostdata"]
        VCG=[Gencostdata;Gendata_candidate[:,Symbol("Cost (\$/MWh)")]]#g						#Variable cost of generation unit g, $/MWh
		VCS=[Estoragedata[:,Symbol("Cost (\$/MWh)")];Estoragedata_candidate[:,Symbol("Cost (\$/MWh)")]]#s		
        unit_converter = 10^6

        		#representative day clustering
		if config_set["representative_day!"]==1
			time_periods = config_set["time_periods"]
		end
        N=get_representative_ts(Loaddata,time_periods,Ordered_zone_nm)[2]
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
        P_gen_df[!,:New_Build] .= 0
        P_gen_df[New_built_idx,:New_Build] .= 1
        #Retreive power data from solved model
        power = value.(model[:p])
        power_t_h = hcat([Array(power[:,t,h]) for t in T for h in H_t[t]]...)
        power_t_h_df = DataFrame(power_t_h, [Symbol("t$t"*"h$h") for t in T for h in H_t[t]])
        P_gen_df = hcat(P_gen_df, power_t_h_df )
        
        CSV.write(joinpath(outpath, "power.csv"), P_gen_df, writeheader=true)
        
        #Capacity OutputDF
        C_gen_df = DataFrame(
            Technology = vcat(Gendata[:,"Type"],Gendata_candidate[:,"Type"]),
            Zone = vcat(Gendata[:,"Zone"],Gendata_candidate[:,"Zone"]),
            EC_Category = [repeat(["Existing"],Num_Egen);repeat(["Candidate"],Num_Cgen)],
            New_Build = Array{Union{Missing,Bool}}(undef, size(G)[1]),
            Capacity = vcat(Gendata[:,"Pmax (MW)"],Gendata_candidate[:,"Pmax (MW)"])
        )
        C_gen_df[!,:New_Build] .= 0
        C_gen_df[New_built_idx,:New_Build] .= 1
        rename!(C_gen_df, :Capacity => Symbol("Capacity (MW)"))

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
            From_zone = vcat(Branchdata[:,"From_zone"],Linedata_candidate[:,"From_zone"]),
            To_zone = vcat(Branchdata[:,"To_zone"],Linedata_candidate[:,"To_zone"]),
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
        P_es_df = DataFrame(
            Technology = vcat(Estoragedata[:,"Type"],Estoragedata_candidate[:,"Type"]),
            Zone = vcat(Estoragedata[:,"Zone"],Estoragedata_candidate[:,"Zone"]),
            EC_Category = [repeat(["Existing"],Num_sto);repeat(["Candidate"],Num_Csto)],
            New_Build = Array{Union{Missing,Bool}}(undef, size(S)[1]),
            ChAnnSum = Array{Union{Missing,Float64}}(undef, size(S)[1]),     #Annual charge
            DisAnnSum = Array{Union{Missing,Float64}}(undef, size(S)[1]),    #Annual discharge
        )
        P_es_df.ChAnnSum .= [sum(value.(model[:c][s,t,h]) for t in T for h in H_t[t] ) for s in S]
        P_es_df.DisAnnSum .= [sum(value.(model[:dc][s,t,h]) for t in T for h in H_t[t] ) for s in S]
        
        New_built_idx = map(x -> x + Num_sto, [i for (i, v) in enumerate(value.(model[:z])) if v > 0])
        P_es_df[!,:New_Build] .= 0
        P_es_df[New_built_idx,:New_Build] .= 1
        #Retreive power data from solved model
        power_c = value.(model[:c])
        power_dc = value.(model[:dc])
        power_soc = value.(model[:soc])

        power_c_t_h = hcat([Array(power_c[:,t,h]) for t in T for h in H_t[t]]...)
        power_c_t_h_df = DataFrame(power_c_t_h, [Symbol("c_"*"t$t"*"h$h") for t in T for h in H_t[t]])

        power_dc_t_h = hcat([Array(power_dc[:,t,h]) for t in T for h in H_t[t]]...)
        power_dc_t_h_df = DataFrame(power_dc_t_h, [Symbol("dc_"*"t$t"*"h$h") for t in T for h in H_t[t]])

        power_soc_t_h = hcat([Array(power_soc[:,t,h]) for t in T for h in H_t[t]]...)
        power_soc_t_h_df = DataFrame(power_soc_t_h, [Symbol("soc_"*"t$t"*"h$h") for t in T for h in H_t[t]])

        P_es_df = hcat(P_es_df, power_c_t_h_df, power_dc_t_h_df, power_soc_t_h_df)
        CSV.write(joinpath(outpath, "es_power.csv"), P_es_df, writeheader=true)

        #Storage Capacity OutputDF
        C_es_df = DataFrame(
            Technology = vcat(Estoragedata[:,"Type"],Estoragedata_candidate[:,"Type"]),
            Zone = vcat(Estoragedata[:,"Zone"],Estoragedata_candidate[:,"Zone"]),
            EC_Category = [repeat(["Existing"],Num_sto);repeat(["Candidate"],Num_Csto)],
            New_Build = Array{Union{Missing,Bool}}(undef, size(S)[1]),            
            EnergyCapacity = vcat(Estoragedata[:,"Capacity (MWh)"],Estoragedata_candidate[:,"Capacity (MWh)"]),
            Capacity = vcat(Estoragedata[:,"Max Power (MW)"],Estoragedata_candidate[:,"Max Power (MW)"])
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
            Inv_c = sum(INV_g[g]*unit_converter*x[g] for g in intersect(G_new,G_i[i]); init=0)+sum(INV_l[l]*unit_converter*y[l] for l in intersect(L_new,LS_i[i]); init=0)+sum(INV_s[s]*unit_converter*z[s] for s in intersect(S_new,S_i[i]); init=0)
            Opr_c = sum(VCG[g]*N[t]*sum(p[g,t,h] for h in H_t[t]) for g in intersect(G,G_i[i]) for t in T; init=0) + sum(VCS[s]*N[t]*sum(c[s,t,h]+dc[s,t,h] for h in H_t[t]; init=0) for s in intersect(S,S_i[i]) for t in T; init=0)
            #RPS_p =  PT_rps*sum(pt_rps[w] for w in W)
            #Cb_p = PT_emis*sum(em_emis[w] for w in W)
            Lol_p = sum(VOLL*N[t]*sum(p_LS[d,t,h] for h in H_t[t]; init=0) for d in intersect(D,D_i[i]) for t in T; init=0)
            Tot = sum([Inv_c,Opr_c,Lol_p])
            Cost_df[i,2:end] = [Inv_c,Opr_c,Lol_p,Tot]
        end
        CSV.write(joinpath(outpath, "system_cost.csv"), Cost_df, writeheader=true)
    
    
    
    elseif model_mode == "PCM" 
        Gendata = input_data["Gendata"]
        Estoragedata = input_data["Estoragedata"]
        Branchdata = input_data["Branchdata"]
        Busdata = input_data["Busdata"]
        Loaddata = input_data["Loaddata"]
        VOLL = input_data["VOLL"]
        
        #Calculate number of elements of input data
        Num_bus=size(Busdata,1);
        Num_Egen=size(Gendata,1);
        Num_load=count(!iszero, Busdata[:,3]);
        Num_Eline=size(Branchdata,1);
        Num_zone=length(Busdata[:,"Zone_id"]);
        Num_sto=size(Estoragedata,1);
        #Mapping
        #Index-Zone Mapping dict
		Idx_zone_dict = Dict(zip([i for i=1:Num_zone],Busdata[:,"Zone_id"]))
		Zone_idx_dict = Dict(zip(Busdata[:,"Zone_id"],[i for i=1:Num_zone]))
        #Set
        D=[d for d=1:Num_load] 	
        D_i=[[d] for d in D]
        G=[g for g=1:Num_Egen]
        S=[s for s=1:Num_sto]
        H=[h for h=1:8760]
        L=[l for l=1:Num_Eline]						#Set of transmission corridors, index l
        I=[i for i=1:Num_zone]									#Set of zones, index i
        G_i=[[findall(Gendata[:,"Zone"].==Idx_zone_dict[i])] for i in I]	
        S_i=[[findall(Estoragedata[:,"Zone"].==Idx_zone_dict[i])] for i in I]
        S_exist=[s for s=1:Num_sto]										#Set of existing storage units, subset of S   
        LS_i=[[findall(Branchdata[:,"From_zone"].==Idx_zone_dict[i])] for i in I]
  
        #zone
        Ordered_zone_nm = [Idx_zone_dict[i] for i=1:Num_zone]
        #Param
        Gencostdata = input_data["Gencostdata"]
        VCG=[Gencostdata]#g						#Variable cost of generation unit g, $/MWh
		VCS=[Estoragedata[:,Symbol("Cost (\$/MWh)")]]#s		
        unit_converter = 10^6
        #Power OutputDF
        P_gen_df = DataFrame(
            Technology = vcat(Gendata[:,"Type"]),
            Zone = vcat(Gendata[:,"Zone"]),
            EC_Category = repeat(["Existing"],Num_Egen),
            AnnSum = Array{Union{Missing,Float64}}(undef, Num_Egen)  #Annual generation output
        )
        P_gen_df.AnnSum .= [sum(value.(model[:p][g,h]) for h in H) for g in G]
        #New_built_idx = map(x -> x + Num_Egen, [i for (i, v) in enumerate(value.(model[:x])) if v > 0])
        #P_gen_df[New_built_idx,:New_Build] .= 1
        #Retreive power data from solved model
        power = value.(model[:p])
        power_h = hcat([Array(power[:,h]) for h in H]...)
        power_h_df = DataFrame(power_h, [Symbol("h$h") for h in H])
        P_gen_df = hcat(P_gen_df, power_h_df )
        
        CSV.write(joinpath(outpath, "power_hourly.csv"), P_gen_df, writeheader=true)
        
        ##Transmission line-----------------------------------------------------------------------------------------------------------
        #Power flow OutputDF
        P_flow_df = DataFrame(
            From_zone = vcat(Branchdata[:,"From_zone"]),
            To_zone = vcat(Branchdata[:,"To_zone"]),
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
        
        P_es_df = DataFrame(
            Technology = vcat(Estoragedata[:,"Type"]),
            Zone = vcat(Estoragedata[:,"Zone"]),
            EC_Category = repeat(["Existing"],Num_sto),
            ChAnnSum = Array{Union{Missing,Float64}}(undef, Num_sto),     #Annual charge
            DisAnnSum = Array{Union{Missing,Float64}}(undef, Num_sto),    #Annual discharge
        )
        P_es_df.ChAnnSum .= [sum(value.(model[:c][s,h])  for h in H ) for s in S]
        P_es_df.DisAnnSum .= [sum(value.(model[:dc][s,h]) for h in H) for s in S]
        
        #New_built_idx = map(x -> x + Num_sto, [i for (i, v) in enumerate(value.(model[:z])) if v > 0])
        #P_es_df[!,:New_Build] .= 0
        #P_es_df[New_built_idx,:New_Build] .= 1
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
            Opr_c = sum(VCG[g]*sum(p[g,h] for h in H) for g in intersect(G,G_i[i]); init=0) + sum(VCS[s]*sum(c[s,h]+dc[s,h] for h in H; init=0) for s in intersect(S,S_i[i]); init=0)
            #RPS_p =  PT_rps*sum(pt_rps[w] for w in W)
            #Cb_p = PT_emis*sum(em_emis[w] for w in W)
            Lol_p = sum(VOLL*sum(p_LS[d,h] for h in H; init=0) for d in intersect(D,D_i[i]); init=0)
            Tot = sum([Opr_c,Lol_p])
            Cost_df[i,2:end] = [Opr_c,Lol_p,Tot]
        end
        CSV.write(joinpath(outpath, "system_cost.csv"), Cost_df, writeheader=true)

    end
	println("Write solved results in the folder 'output' DONE!")
end