function mkdir_overwrite(path::AbstractString)
    if isdir(path)
        rm(path; force=true, recursive=true)
        println("'output' folder exists, will be overwritten now!")
    end
    mkdir(path)
end

function write_output(outpath::AbstractString,config_set::Dict, input_data::Dict, model::Model)
	mkdir_overwrite(outpath)
    model_mode = config_set["model_mode"]
    println("HOPE model ("*model_mode*" mode) is successfully solved!")
    if model_mode == "GTEP"
        ##read input for print	
        Gendata = input_data["Gendata"]
        Estoragedata = input_data["Estoragedata"]
        Estoragedata_candidate = input_data["Estoragedata_candidate"]
        Linedata_candidate = input_data["Linedata_candidate"]
        Gendata_candidate = input_data["Gendata_candidate"]

        #Calculate number of elements of input data
        #Num_bus=size(Busdata,1)
        #Num_load=count(!iszero, Busdata[:,3])
        #Num_Eline=size(Branchdata,1)
        #Num_zone=length(Busdata[:,"Zone_id"])
        Num_sto=size(Estoragedata,1)
        Num_Csto=size(Estoragedata_candidate,1)
        Num_Cgen=size(Gendata_candidate,1)
        #Num_Cline=size(Linedata_candidate,1)

        #Time period
        T=[t for t=1:length(config_set["time_periods"])]		#Set of time periods (e.g., representative days of seasons), index t
        H_t=[collect(1:24) for t in T]                          #Set of hours in time period (day) t, index h, subset of H
        HD = [h for h in 1:24]
        ##Generator-----------------------------------------------------------------------------------------------------------
        Num_gen=size(Gendata,1)
        G=[g for g=1:Num_gen+Num_Cgen]
        G_exist=[g for g=1:Num_gen]
        G_new=[g for g=Num_gen+1:Num_gen+Num_Cgen]
        #Power OutputDF
        P_gen_df = DataFrame(
            Technology = vcat(Gendata[:,"Type"],Gendata_candidate[:,"Type"]),
            Zone = vcat(Gendata[:,"Zone"],Gendata_candidate[:,"Zone"]),
            EC_Category = [repeat(["Existing"],Num_gen);repeat(["Candidate"],Num_Cgen)],
            New_Build = Array{Union{Missing,Bool}}(undef, size(G)[1]),
            AnnSum = Array{Union{Missing,Float64}}(undef, size(G)[1])  #Annual generation output
        )
        P_gen_df.AnnSum .= [sum(value.(model[:p][g,t,h]) for t in T for h in H_t[t] ) for g in G]
        New_built_idx = map(x -> x + Num_gen, [i for (i, v) in enumerate(value.(model[:x])) if v > 0])
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
            EC_Category = [repeat(["Existing"],Num_gen);repeat(["Candidate"],Num_Cgen)],
            New_Build = Array{Union{Missing,Bool}}(undef, size(G)[1]),
            Capacity = vcat(Gendata[:,"Pmax (MW)"],Gendata_candidate[:,"Pmax (MW)"])
        )
        C_gen_df[!,:New_Build] .= 0
        C_gen_df[New_built_idx,:New_Build] .= 1
        rename!(C_gen_df, :Capacity => Symbol("Capacity (MW)"))

        CSV.write(joinpath(outpath, "capacity.csv"), C_gen_df, writeheader=true)
        ##Transmission line-----------------------------------------------------------------------------------------------------------
        
        
        ##Storage---------------------------------------------------------------------------------------------------------------------
        S=[s for s=1:Num_sto+Num_Csto]							        #Set of storage units, index s
        S_exist=[s for s=1:Num_sto]										#Set of existing storage units, subset of S  
        S_new=[s for s=Num_sto+1:Num_sto+Num_Csto]						#Set of candidate storage units, subset of S  

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
            New_Build = Array{Union{Missing,Bool}}(undef, size(S)[1]),            EnergyCapacity = vcat(Estoragedata[:,"Capacity (MWh)"],Estoragedata_candidate[:,"Capacity (MWh)"]),
            Capacity = vcat(Estoragedata[:,"Max Power (MW)"],Estoragedata_candidate[:,"Max Power (MW)"])
        )
        C_es_df[!,:New_Build] .= 0
        C_es_df[New_built_idx,:New_Build] .= 1
        rename!(C_es_df, :Capacity => Symbol("Capacity (MW)"))
        rename!(C_es_df, :EnergyCapacity => Symbol("EnergyCapacity (MWh)"))
        
        CSV.write(joinpath(outpath, "es_capacity.csv"), C_es_df, writeheader=true)
    elseif model_mode == "PCM" 
        Gendata = input_data["Gendata"]
        Estoragedata = input_data["Estoragedata"]

        
        #Calculate number of elements of input data
        #Num_bus=size(Busdata,1);
        Num_gen=size(Gendata,1);
        #Num_load=count(!iszero, Busdata[:,3]);
        #Num_Eline=size(Branchdata,1);
        #Num_zone=length(Busdata[:,"Zone_id"]);
        Num_sto=size(Estoragedata,1);
        G=[g for g=1:Num_gen]
        S=[s for s=1:Num_sto]
        H=[h for h=1:8760]

        #Power OutputDF
        P_gen_df = DataFrame(
            Technology = vcat(Gendata[:,"Type"]),
            Zone = vcat(Gendata[:,"Zone"]),
            EC_Category = repeat(["Existing"],Num_gen),
            New_Build = Array{Union{Missing,Bool}}(undef, Num_gen),
            AnnSum = Array{Union{Missing,Float64}}(undef, Num_gen)  #Annual generation output
        )
        P_gen_df.AnnSum .= [sum(value.(model[:p][g,h]) for h in H) for g in G]
        #New_built_idx = map(x -> x + Num_gen, [i for (i, v) in enumerate(value.(model[:x])) if v > 0])
        P_gen_df[!,:New_Build] .= 0
        #P_gen_df[New_built_idx,:New_Build] .= 1
        #Retreive power data from solved model
        power = value.(model[:p])
        power_h = hcat([Array(power[:,h]) for h in H]...)
        power_h_df = DataFrame(power_h, [Symbol("h$h") for h in H])
        P_gen_df = hcat(P_gen_df, power_h_df )
        
        CSV.write(joinpath(outpath, "power_hourly.csv"), P_gen_df, writeheader=true)
        
        ##Transmission line-----------------------------------------------------------------------------------------------------------
        
        
        ##Storage---------------------------------------------------------------------------------------------------------------------
        
        P_es_df = DataFrame(
            Technology = vcat(Estoragedata[:,"Type"]),
            Zone = vcat(Estoragedata[:,"Zone"]),
            EC_Category = repeat(["Existing"],Num_sto),
            New_Build = Array{Union{Missing,Bool}}(undef, Num_sto),
            ChAnnSum = Array{Union{Missing,Float64}}(undef, Num_sto),     #Annual charge
            DisAnnSum = Array{Union{Missing,Float64}}(undef, Num_sto),    #Annual discharge
        )
        P_es_df.ChAnnSum .= [sum(value.(model[:c][s,h])  for h in H ) for s in S]
        P_es_df.DisAnnSum .= [sum(value.(model[:dc][s,h]) for h in H) for s in S]
        
        #New_built_idx = map(x -> x + Num_sto, [i for (i, v) in enumerate(value.(model[:z])) if v > 0])
        P_es_df[!,:New_Build] .= 0
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
	
    end
	println("Write solved results in the folder 'output' DONE!")
end