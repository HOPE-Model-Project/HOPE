function get_representative_ts(df, time_periods, ordered_zone, k=1)
    #k = 1# Cluster the time series data to find a representative day
    # Function to filter rows based on the season's start and end dates
    filter_time_period(time_period, row) = (row.Month == time_period[1] && row.Day >= time_period[2]) || (row.Month == time_period[3] && row.Day <= time_period[4]) || (row.Month > time_period[1] && row.Month < time_period[3])|| ( time_period[1]>time_period[3] && row.Month < time_period[3])
    # Initialize a dictionary to store the representative days and number of days for each season  
    rep_dat_dict=Dict()
    ndays_dict=Dict()
	
    # Loop over the seasons/time periods
    for (tp, dates) in time_periods
        local tp_df, n_days ,representative_day_df
		#check if tuple is saved as string
		if isa(dates, String)
			dates = eval(Meta.parse(dates))
		end 
        # Filter the DataFrame for the current season/time periods
        tp_df = filter(row -> filter_time_period(dates, row), df)
		n_days = Int(size(tp_df,1)/24)
        representative_day_df = DataFrame()
        # Extract the time series data for the current season/time periods
        for nm in names(tp_df)[4:end]
            local col_mtx,clustering_result
            col_mtx = reshape(tp_df[!, nm], (24, n_days))
			col_mtx = parse.(Float64,string.(col_mtx))
            # Number of clusters (set to 1 for representative day)
            clustering_result = kmeans(col_mtx, k)
            # Store the representative day for the current season in the df
            representative_day_df[!,nm] = clustering_result.centers'[1, :]
        end
		
		if ["NI"] ⊆ names(df)	
			representative_day_df_ordered= select(representative_day_df, [ordered_zone;"NI"]) # use for load ts with NI
		else
			representative_day_df_ordered= select(representative_day_df, ordered_zone)	# use for renewable ts without NI
		end
		representative_day_df.Hour = 1:24
        rep_dat_dict[tp]=representative_day_df_ordered
		ndays_dict[tp]=n_days
    end
    return (rep_dat_dict,ndays_dict)
end


function create_GTEP_model(config_set::Dict,input_data::Dict,OPTIMIZER::MOI.OptimizerWithAttributes)
	model_mode = config_set["model_mode"]
	if model_mode == "PCM"
		return "ModeError: Please use function 'create_PCM_model' or set model mode to be 'GTEP'!" 
	elseif model_mode == "GTEP" 
		#network
		Zonedata = input_data["Zonedata"]
		Linedata = input_data["Linedata"]
		#technology
		Gendata = input_data["Gendata"]
		Storagedata = input_data["Storagedata"]
		Gencostdata = input_data["Gendata"][:,Symbol("Cost (\$/MWh)")]
		#reservedata=
		#time series
		AFdata = input_data["AFdata"] #Generator-level hourly availability factors
		Loaddata = input_data["Loaddata"]
		NIdata = input_data["NIdata"]
		#candidate
		Estoragedata_candidate = input_data["Estoragedata_candidate"]
		Linedata_candidate = input_data["Linedata_candidate"]
		Gendata_candidate = input_data["Gendata_candidate"]
		# Availability factor defaults (backward compatible):
		# if AF is omitted, assume AF = 1.0.
		if !("AF" in names(Gendata))
			Gendata[!, "AF"] = fill(1.0, nrow(Gendata))
		end
		if !("AF" in names(Gendata_candidate))
			Gendata_candidate[!, "AF"] = fill(1.0, nrow(Gendata_candidate))
		end
		#policies
		CBPdata = input_data["CBPdata"]
		CBP_state_data = combine(groupby(CBPdata, :State), Symbol("Allowance (tons)") => sum)
		#rpspolicydata=
		RPSdata = input_data["RPSdata"]
		#penalty_cost, investment budgets, planning reserve margins etc. single parameters
		SinglePardata = input_data["Singlepar"]
		# Carbon policy switch:
		# 0 = no carbon policy
		# 1 = Option A (state emission cap with slack penalty)
		# 2 = Option B (cap-and-trade style allowance + slack penalty)
		carbon_policy_raw = get(config_set, "carbon_policy", 1)
		carbon_policy = carbon_policy_raw isa Integer ? Int(carbon_policy_raw) : parse(Int, string(carbon_policy_raw))
		if !(carbon_policy in [0, 1, 2])
			throw(ArgumentError("Invalid carbon_policy=$(carbon_policy). Expected 0, 1, or 2."))
		end
		# Clean energy policy switch:
		# 0 = turn RPS off
		# 1 = turn RPS on
		clean_energy_policy_raw = get(config_set, "clean_energy_policy", 1)
		clean_energy_policy = clean_energy_policy_raw isa Integer ? Int(clean_energy_policy_raw) : parse(Int, string(clean_energy_policy_raw))
		if !(clean_energy_policy in [0, 1])
			throw(ArgumentError("Invalid clean_energy_policy=$(clean_energy_policy). Expected 0 or 1."))
		end
		# Planning reserve mode switch:
		# 0 = off
		# 1 = system-level planning reserve
		# 2 = zonal-level planning reserve
		planning_reserve_mode_raw = get(config_set, "planning_reserve_mode", 1)
		planning_reserve_mode = planning_reserve_mode_raw isa Integer ? Int(planning_reserve_mode_raw) : parse(Int, string(planning_reserve_mode_raw))
		if !(planning_reserve_mode in [0, 1, 2])
			throw(ArgumentError("Invalid planning_reserve_mode=$(planning_reserve_mode). Expected 0, 1, or 2."))
		end
		flexible_demand_raw = get(config_set, "flexible_demand", 0)
		flexible_demand = flexible_demand_raw isa Integer ? Int(flexible_demand_raw) : parse(Int, string(flexible_demand_raw))
		if !(flexible_demand in [0, 1])
			throw(ArgumentError("Invalid flexible_demand=$(flexible_demand). Expected 0 or 1."))
		end

		#Calculate number of elements of input data
		Num_bus=size(Zonedata,1)
		Num_gen=size(Gendata,1)
		Num_load=size(Zonedata,1) #to revise, consider nodal
		Num_Eline=size(Linedata,1)
		Num_zone=length(Zonedata[:,"Zone_id"])
		Num_sto=size(Storagedata,1)
		Num_Csto=size(Estoragedata_candidate,1)
		Num_Cgen=size(Gendata_candidate,1)
		Num_Cline=size(Linedata_candidate,1)

		#Index-Zone Mapping dict
		Idx_zone_dict = Dict(zip([i for i=1:Num_zone],Zonedata[:,"Zone_id"]))
		Zone_idx_dict = Dict(zip(Zonedata[:,"Zone_id"],[i for i=1:Num_zone]))
		#Ordered zone
		Ordered_zone_nm =[Idx_zone_dict[i] for i=1:Num_zone]
		#Ordered generator labels for generator-level availability input
		Ordered_gen_nm = ["G$(g)" for g in 1:(Num_gen+Num_Cgen)]
		required_af_time_cols = ["Month", "Day", "Period"]
		missing_af_time_cols = setdiff(required_af_time_cols, names(AFdata))
		if !isempty(missing_af_time_cols)
			throw(ArgumentError("Missing required time columns in generator availability input: $(collect(missing_af_time_cols)). Expected at least Month, Day, Period."))
		end
		AF_g_static_prefill = [Float64(coalesce(v, 1.0)) for v in [Gendata[:,"AF"];Gendata_candidate[:,"AF"]]]
		AF_fill_map = Dict(zip(Ordered_gen_nm, AF_g_static_prefill))
		# Allow sparse AF columns: missing generator columns fallback to static AF (default 1.0).
		provided_af_cols = Set(String.(intersect(names(AFdata), Ordered_gen_nm)))
		missing_gen_af_cols = setdiff(Ordered_gen_nm, names(AFdata))
		if !isempty(missing_gen_af_cols)
			for col in missing_gen_af_cols
				AFdata[!, col] = fill(AF_fill_map[col], nrow(AFdata))
			end
			println("Info: $(length(missing_gen_af_cols)) generators are missing hourly AF columns; static AF fallback will be used.")
		end
		AFdata = select(AFdata, vcat(required_af_time_cols, Ordered_gen_nm))
		
		#DR related
		DR_CC = ones(Float64, Num_load)
		DR_shift_eff = fill(1.0, Num_load)        # default demand shifting efficiency
		DR_max_defer_hours = fill(24.0, Num_load) # default max defer window (hours)
		if flexible_demand == 1
			DRdata = input_data["DRdata"]
			DRtsdata = input_data["DRtsdata"]
			#[findall(row -> row.Zone == Idx_zone_dict[i], eachrow(DRdata))[1] for i=1:Num_zone] #reorder 
			DRC_d = [DRdata[idx, "Cost (\$/MW)"] for idx in [findall(row -> row.Zone == Idx_zone_dict[i], eachrow(DRdata))[1] for i=1:Num_zone]]
			DR_MAX = [DRdata[idx, "Max Power (MW)"] for idx in [findall(row -> row.Zone == Idx_zone_dict[i], eachrow(DRdata))[1] for i=1:Num_zone]]
			if "CC" in names(DRdata)
				DR_CC .= [Float64(DRdata[idx, "CC"]) for idx in [findall(row -> row.Zone == Idx_zone_dict[i], eachrow(DRdata))[1] for i=1:Num_zone]]
			end
			if "Shift_Efficiency" in names(DRdata)
				DR_shift_eff .= [Float64(DRdata[idx, "Shift_Efficiency"]) for idx in [findall(row -> row.Zone == Idx_zone_dict[i], eachrow(DRdata))[1] for i=1:Num_zone]]
			elseif "Payback_Efficiency" in names(DRdata)
				# backward compatibility
				DR_shift_eff .= [Float64(DRdata[idx, "Payback_Efficiency"]) for idx in [findall(row -> row.Zone == Idx_zone_dict[i], eachrow(DRdata))[1] for i=1:Num_zone]]
			end
			if "Max_Defer_Hours" in names(DRdata)
				DR_max_defer_hours .= [Float64(DRdata[idx, "Max_Defer_Hours"]) for idx in [findall(row -> row.Zone == Idx_zone_dict[i], eachrow(DRdata))[1] for i=1:Num_zone]]
			elseif "Backlog_Multiplier" in names(DRdata)
				# backward compatibility
				DR_max_defer_hours .= [Float64(DRdata[idx, "Backlog_Multiplier"]) for idx in [findall(row -> row.Zone == Idx_zone_dict[i], eachrow(DRdata))[1] for i=1:Num_zone]]
			end
		end
		
		#representative day clustering
		if config_set["representative_day!"]==1
			time_periods = config_set["time_periods"]
			#get representative time seires
			Load_rep = get_representative_ts(Loaddata,time_periods,Ordered_zone_nm)[1]
			AF_rep = get_representative_ts(AFdata,time_periods,Ordered_gen_nm)[1]
			if flexible_demand == 1
				DR_rep = get_representative_ts(DRtsdata,time_periods,Ordered_zone_nm)[1]
			end
		else
			Load_rep = Loaddata
			if flexible_demand == 1
				DR_rep = DRtsdata
			end
		end

		#Sets--------------------------------------------------
		D=[d for d=1:Num_load] 									#Set of demand, index d
		G=[g for g=1:Num_gen+Num_Cgen]							#Set of all types of generating units, index g
		K=unique(Gendata[:,"Type"]) 							#Set of technology types, index k
		H=[h for h=1:8760]										#Set of hours, index h
		if config_set["representative_day!"]==1
			T=[t for t=1:length(config_set["time_periods"])]		#Set of time periods (e.g., representative days of seasons), index t
		else
			T=[1]
		end
		S=[s for s=1:Num_sto+Num_Csto]							#Set of storage units, index s
		I=[i for i=1:Num_zone]									#Set of zones, index i
		J=I														#Set of zones, index j
		L=[l for l=1:Num_Eline+Num_Cline]						#Set of transmission corridors, index l
		W=unique(Zonedata[:,"State"])							#Set of states, index w/w’
		W_prime = W												#Set of states, index w/w’
		# W_RPS=unique(vcat(RPSdata[:, "From_state"],RPSdata[:, "To_state"]))    #Set of states participate in RPS trading, not needed

		#SubSets------------------------------------------------
		D_i=[[d] for d in D]											#Set of demand connected to zone i, a subset of D
		G_PV_E=findall(Gendata[:,"Type"].=="SolarPV")					#Set of existingsolar, subsets of G
		G_PV_C=findall(Gendata_candidate[:,"Type"].=="SolarPV").+Num_gen#Set of candidate solar, subsets of G
		G_PV=[G_PV_E;G_PV_C]											#Set of all solar, subsets of G
		G_W_E=findall(x -> x in ["WindOn","WindOff"], Gendata[:,"Type"])#Set of existing wind, subsets of G
		G_W_C=findall(x -> x in ["WindOn","WindOff"], Gendata_candidate[:,"Type"]).+Num_gen#Set of candidate wind, subsets of G
		G_W=[G_W_E;G_W_C]                                               #Set of all wind, subsets of G
		G_VRE_E = [G_PV_E;G_W_E]
        G_VRE_C = [G_PV_C;G_W_C]
        G_VRE = [G_VRE_E;G_VRE_C]
		#G_F_E=findall(x -> x in ["Coal", "Oil", "NGCT", "NuC", "MSW", "Bio", "Landfill_NG", "NGCC"], Gendata[:,"Type"])
		#G_F_C=findall(x -> x in ["Coal", "Oil", "NGCT", "NuC", "MSW", "Bio", "Landfill_NG", "NGCC"], Gendata_candidate[:,"Type"]).+Num_gen	
		G_F_E=findall(x -> x in [1], Gendata[:,"Flag_thermal"])
		G_F_C=findall(x -> x in [1], Gendata_candidate[:,"Flag_thermal"]).+Num_gen	
		G_MR_E=findall(x -> x in [1], Gendata[:,"Flag_mustrun"])
		G_MR_C=findall(x -> x in [1], Gendata_candidate[:,"Flag_mustrun"]).+Num_gen	
		G_F=[G_F_E;G_F_C]												#Set of dispatchable generators, subsets of G
		G_MR = [G_MR_E;G_MR_C]
		if !("Flag_RPS" in names(Gendata)) || !("Flag_RPS" in names(Gendata_candidate))
			throw(ArgumentError("Missing required column 'Flag_RPS' in gendata/gendata_candidate for RPS eligibility."))
		end
		# legacy type-based reference:
		# G_RPS_E = findall(x -> x in ["Hydro", "MSW", "Bio", "Landfill_NG", "Nuc", "NuC", "WindOn", "WindOff", "SolarPV"], Gendata[:,"Type"])
		# G_RPS_C = findall(x -> x in ["Hydro", "MSW", "Bio", "Landfill_NG", "Nuc", "NuC", "WindOn", "WindOff", "SolarPV"], Gendata_candidate[:,"Type"]).+Num_gen
		G_RPS_E=findall(x -> x in [1], Gendata[:,"Flag_RPS"])
		G_RPS_C=findall(x -> x in [1], Gendata_candidate[:,"Flag_RPS"]).+Num_gen
		G_RPS = [G_RPS_E;G_RPS_C]										#Set of generation units providing RPS credits, index g, subset of G
		missing_vre_in_rps = setdiff(G_VRE, G_RPS)
		if !isempty(missing_vre_in_rps)
			println("Warning: enforcing G_VRE ⊆ G_RPS by adding $(length(missing_vre_in_rps)) VRE units into G_RPS.")
			G_RPS = sort(unique(vcat(G_RPS, missing_vre_in_rps)))
		end
		missing_rps_profile_cols = [Ordered_gen_nm[g] for g in G_RPS if !(Ordered_gen_nm[g] in provided_af_cols)]
		if !isempty(missing_rps_profile_cols)
			println("Warning: AF timeseries missing for $(length(missing_rps_profile_cols)) RPS/VRE generators; static AF fallback will be used.")
		end
		G_exist=[g for g=1:Num_gen]										#Set of existing generation units, index g, subset of G  
		G_RET_raw=findall(x -> x in [1], Gendata[:,"Flag_RET"])			#Set of existing generation units marked as retirement-eligible, index g, subset of G
		G_RET_conflict = intersect(G_RET_raw, G_MR_E)
		if !isempty(G_RET_conflict)
			println("Warning: removing $(length(G_RET_conflict)) must-run generators from retirement set (MR units cannot be retired).")
		end
		G_RET=setdiff(G_RET_raw, G_MR_E)								#Set of existing generation units available for retirement, excluding must-run units
		G_new=[g for g=Num_gen+1:Num_gen+Num_Cgen]						#Set of candidate generation units, index g, subset of G 
		G_i=[[findall(Gendata[:,"Zone"].==Idx_zone_dict[i]);(findall(Gendata_candidate[:,"Zone"].==Idx_zone_dict[i]).+Num_gen)] for i in I]						#Set of generating units connected to zone i, subset of G  
		HD = [h for h in 1:24]
		H_D = [h for h in 0:24:8760]
		if config_set["representative_day!"]==1								#Set of hours in one day, index h, subset of H
			H_t=[collect(1+24*(t-1):24+24*(t-1)) for t in T]				#Set of hours in time period (day) t, index h, subset of H
			H_T = collect(unique(reduce(vcat,H_t)))							#Set of unique hours in time period, index h, subset of H
		else
			H_t=[collect(1:8760) for t in [1]]								#Set of hours in time period (day) t, index h, subset of H
			H_T = collect(unique(reduce(vcat,H_t)))							#Set of unique hours in time period, index h, subset of H
		end
	
		S_exist=[s for s=1:Num_sto]										#Set of existing storage units, subset of S  
		S_new=[s for s=Num_sto+1:Num_sto+Num_Csto]						#Set of candidate storage units, subset of S  
		S_i=[[findall(Storagedata[:,"Zone"].==Idx_zone_dict[i]);(findall(Estoragedata_candidate[:,"Zone"].==Idx_zone_dict[i]).+Num_sto)] for i in I]				#Set of storage units connected to zone i, subset of S  
		S_new_i=[(findall(Estoragedata_candidate[:,"Zone"].==Idx_zone_dict[i]).+Num_sto) for i in I]				#Set of storage units connected to zone i, subset of S  
		L_exist=[l for l=1:Num_Eline]									#Set of existing transmission corridors
		L_new=[l for l=Num_Eline+1:Num_Eline+Num_Cline]					#Set of candidate transmission corridors
		LS_i=[[findall(Linedata[:,"From_zone"].==Idx_zone_dict[i]);(findall(Linedata_candidate[:,"From_zone"].==Idx_zone_dict[i]).+Num_Eline)] for i in I]	#Set of sending transmission corridors of zone i, subset of L
		LR_i=[[findall(Linedata[:,"To_zone"].==Idx_zone_dict[i]);(findall(Linedata_candidate[:,"To_zone"].==Idx_zone_dict[i]).+Num_Eline)] for i in I]		#Set of receiving transmission corridors of zone i， subset of L
		IL_l = Dict(zip(L,[[i,j] for i in map(x -> Zone_idx_dict[x],Linedata[:,"From_zone"]) for j in map(x -> Zone_idx_dict[x],Linedata[:,"To_zone"])]))
		I_w=Dict(zip(W, [findall(Zonedata[:,"State"].== w) for w in W]))	#Set of zones in state w, subset of I
		WER_w = Dict{Any,Vector{Any}}() #Set of states that state w can export renewable credits to (excludes w itself), subset of W
		WIR_w = Dict{Any,Vector{Any}}() #Set of states that state w can import renewable credits from (excludes w itself), subset of W
		for w in W
			export_targets = unique(RPSdata[RPSdata[:, "From_state"] .== w, "To_state"])
			import_sources = unique(RPSdata[RPSdata[:, "To_state"] .== w, "From_state"])
			WER_w[w] = collect(setdiff(export_targets, [w]))
			WIR_w[w] = collect(setdiff(import_sources, [w]))
		end

		G_L = Dict(zip([l for l in L], [G_i[i] for l in L for i in IL_l[l]]))			#Set of generation units that linked to line l, index g, subset of G

		#Parameters--------------------------------------------
		ALW = Dict((row["Time Period"], row["State"]) => row["Allowance (tons)"] for row in eachrow(CBPdata))#(t,w)														#Total carbon allowance in time period t in state w, ton
		# Hourly generator availability AF_{g,h} (generator-level time series; fallback to static AF).
		BM = SinglePardata[1,"BigM"];														#big M penalty
		CC_g = [Gendata[:,"CC"];Gendata_candidate[:,"CC"]]#g       		#Capacity credit of generating units, unitless
		CC_s = [Storagedata[:,"CC"];Estoragedata_candidate[:,"CC"]]#s   #Capacity credit of storage units, unitless
		AF_g_static = [Float64(coalesce(v, 1.0)) for v in [Gendata[:,"AF"];Gendata_candidate[:,"AF"]]] #Fallback static availability factor (non-VRE)
		#CP=29#g $/ton													#Carbon price of generation g〖∈G〗^F, M$/t (∑_(g∈G^F,t∈T)〖〖CP〗_g  .N_t.∑_(h∈H_t)p_(g,h) 〗)
		EF=[Gendata[:,"EF"];Gendata_candidate[:,"EF"]]#g				#Carbon emission factor of generator g, t/MWh
		ELMT=Dict(zip(CBP_state_data[!,"State"],CBP_state_data[!,"Allowance (tons)_sum"]))#w							#Carbon emission limits at state w, t
		ALW_state = Dict(zip(CBP_state_data[!,"State"],CBP_state_data[!,"Allowance (tons)_sum"])) #w				#Total annual carbon allowances by state
		F_max=[Linedata[!,"Capacity (MW)"];Linedata_candidate[!,"Capacity (MW)"]]#l			#Maximum capacity of transmission corridor/line l, MW
		INV_g=Dict(zip(G_new,Gendata_candidate[:,Symbol("Cost (\$/MW/yr)")])) #g						#Investment cost of candidate generator g, M$
		INV_l=Dict(zip(L_new,Linedata_candidate[:,Symbol("Cost (M\$)")]))#l						#Investment cost of transmission line l, M$
		INV_s=Dict(zip(S_new,Estoragedata_candidate[:,Symbol("Cost (\$/MW/yr)")])) #s				#Investment cost of storage unit s, M$
		IBG=SinglePardata[1, "Inv_bugt_gen"]														#Total investment budget for generators
		IBL=SinglePardata[1, "Inv_bugt_line"]														#Total investment budget for transmission lines
		IBS=SinglePardata[1, "Inv_bugt_storage"]													#Total investment budget for storages

		NI=Dict([(h,i) =>NIdata[h]*(Zonedata[:,"Demand (MW)"][i]/sum(Zonedata[:,"Demand (MW)"])) for i in I for h in H])#IH	#Net imports in zone i in h, MWh
		#NI_t = Dict([t => Dict([(i,h) =>Load_rep[t][!,"NI"][h]*(Zonedata[:,"Demand (MW)"][i]/sum(Zonedata[:,"Demand (MW)"])) for i in I for h in H_t[t]]) for t in T]) #tih
		#P=Dict([(d,h) => Loaddata[:,Idx_zone_dict[d]][h] for d in D for h in H])#d,h			#Active power demand of d in hour h, MW
		PK=Zonedata[:,"Demand (MW)"]#d												#Zone reference demand (used with per-unit load profile), MW
		PT_rps=SinglePardata[1, "PT_RPS"]											#RPS volitation penalty, $/MWh
		PT_emis=SinglePardata[1, "PT_emis"]											#Carbon emission volitation penalty, $/t
		P_min=[Gendata[:,"Pmin (MW)"];Gendata_candidate[:,"Pmin (MW)"]]#g						#Minimum power generation of unit g, MW
		P_max=[Gendata[:,"Pmax (MW)"];Gendata_candidate[:,"Pmax (MW)"]]#g						#Maximum power generation of unit g, MW
		RPS=Dict(zip(RPSdata[:,:From_state],RPSdata[:,:RPS]))	#w									#Renewable portfolio standard in state w,  unitless
		PRM=SinglePardata[1,"planning _reserve_margin"]#												#System-level planning reserve margin, unitless
		if !("Zonal PRM" in names(Zonedata))
			PRM_i = Dict(i => PRM for i in I) # fallback: zonal PRM defaults to system PRM
		else
			PRM_i = Dict(i => Float64(Zonedata[i, "Zonal PRM"]) for i in I)
		end
		SECAP=[Storagedata[:,"Capacity (MWh)"];Estoragedata_candidate[:,"Capacity (MWh)"]]#s		#Maximum energy capacity of storage unit s, MWh
		SCAP=[Storagedata[:,"Max Power (MW)"];Estoragedata_candidate[:,"Max Power (MW)"]]#s		#Maximum capacity of storage unit s, MWh
		SC=[Storagedata[:,"Charging Rate"]; Estoragedata_candidate[:, "Charging Rate"]]#s									#The maximum rates of charging, unitless
		SD=[Storagedata[:,"Discharging Rate"]; Estoragedata_candidate[:, "Discharging Rate"]]#s									#The maximum rates of discharging, unitless
		VCG=[Gencostdata;Gendata_candidate[:,Symbol("Cost (\$/MWh)")]]#g						#Variable cost of generation unit g, $/MWh
		VCS=[Storagedata[:,Symbol("Cost (\$/MWh)")];Estoragedata_candidate[:,Symbol("Cost (\$/MWh)")]]#s						#Variable (degradation) cost of storage unit s, $/MWh
		VOLL=SinglePardata[1, "VOLL"]#d										#Value of loss of load d, $/MWh
		e_ch=[Storagedata[:,"Charging efficiency"];Estoragedata_candidate[:,"Charging efficiency"]]#s				#Charging efficiency of storage unit s, unitless
		e_dis=[Storagedata[:,"Discharging efficiency"];Estoragedata_candidate[:,"Discharging efficiency"]]#s			#Discharging efficiency of storage unit s, unitless
		# Storage duration subsets (hours = energy capacity / power capacity):
		# S_SD: short-duration storage, representative-day 50% anchoring.
		# S_LD: long-duration storage, representative-day inter-period SOC linkage.
		storage_ld_duration_hours_raw = get(config_set, "storage_ld_duration_hours", 12.0)
		storage_ld_duration_hours = storage_ld_duration_hours_raw isa Number ? Float64(storage_ld_duration_hours_raw) : parse(Float64, string(storage_ld_duration_hours_raw))
		if storage_ld_duration_hours < 0
			throw(ArgumentError("Invalid storage_ld_duration_hours=$(storage_ld_duration_hours). Expected non-negative value in hours."))
		end
		StorageDurationHours = Dict(s => (SCAP[s] > 0 ? SECAP[s] / SCAP[s] : 0.0) for s in S)
		S_LD = [s for s in S if StorageDurationHours[s] >= storage_ld_duration_hours]
		S_SD = setdiff(S, S_LD)
		S_SD_exist = intersect(S_SD, S_exist)
		S_SD_new = intersect(S_SD, S_new)
		S_LD_exist = intersect(S_LD, S_exist)
		S_LD_new = intersect(S_LD, S_new)
			
		#for multiple time period, we need to use following TS parameters
		if config_set["representative_day!"]==1
			N=get_representative_ts(Loaddata,time_periods,Ordered_zone_nm)[2]#t	  #Number of time periods (days) represented by time period (day) t per year, ∑_(t∈T)▒〖N_t.|H_t |〗= 8760
			#NI_t = Dict([t => Dict([(h,i) =>-Load_rep[t][!,"NI"][h]*(Zonedata[:,"Demand (MW)"][i]/sum(Zonedata[:,"Demand (MW)"])) for i in I for h in H_t[t]]) for t in T]) #tih
			NI_hi = Dict([(h,i) => -Load_rep[t][!,"NI"][h- 24*(t-1)]*(Zonedata[:,"Demand (MW)"][i]/sum(Zonedata[:,"Demand (MW)"])) for i in I for t in T for h in H_t[t]])
			#P_t = Load_rep #thd P_t[t][h,d]*PK[d] for d in D_i[i]
			P_hd = Dict([(h,d) => Load_rep[t][h-24*(t-1),d] for i in I for d in D_i[i] for t in T for h in H_t[t]])
			if flexible_demand == 1
				#DR_t = DR_rep
				DR_hd = Dict([(h,d) => DR_rep[t][h-24*(t-1),d] for i in I for d in D_i[i] for t in T for h in H_t[t]])
			end
			AF_gh = Dict{Tuple{Int,Int},Float64}()
			for t in T, g in G, h in H_t[t]
				v = AF_rep[t][h-24*(t-1), Ordered_gen_nm[g]]
				AF_gh[(g,h)] = ismissing(v) ? AF_g_static[g] : Float64(v)
			end
		else
			N=[1]
			#NI_t = Dict(1=> NI)
			NI_hi = NI
			#P_t = Dict(1 => Loaddata[:,4:3+Num_zone])
			P_hd = Loaddata[:,4:3+Num_zone]
			if flexible_demand == 1
				#DR_t = Dict(1 => DRtsdata[:,4:3+Num_zone])
				DR_hd = DRtsdata[:,4:3+Num_zone]
			end
			AF_gh = Dict{Tuple{Int,Int},Float64}()
			for t in T, g in G, h in H_t[t]
				v = AFdata[h, Ordered_gen_nm[g]]
				AF_gh[(g,h)] = ismissing(v) ? AF_g_static[g] : Float64(v)
			end
		end
		if flexible_demand == 1
			DR_DF_max = Dict((h, d) => DR_hd[h, d] * DR_MAX[d] for d in D for h in H_T)
			DR_PB_max = Dict((h, d) => DR_hd[h, d] * DR_MAX[d] for d in D for h in H_T)
			DR_DF_peak = Dict(d => maximum(DR_DF_max[h, d] for h in H_T) for d in D)
		end
		# Peak demand definitions used in planning reserve constraints
		PK_i = Dict(i => maximum(sum(P_hd[h,d]*PK[d] for d in D_i[i]) for h in H_T) for i in I)
		PK_system = maximum(sum(sum(P_hd[h,d]*PK[d] for d in D_i[i]) for i in I) for h in H_T)
		unit_converter = 10^6

		#Relax of integer variable:
		inv_dcs_bin = config_set["inv_dcs_bin"]

		model=Model(OPTIMIZER)
		#Variables---------------------------------------------
		if carbon_policy == 2
			@variable(model, a[G]>=0) 							#Bidding carbon allowance of unit g, ton
		end
		@variable(model, f[L,H_T])							#Active power in transmission corridor/line l in h from resrource g, MW
		@variable(model, em_emis[W]>=0)							#Carbon emission violated emission limit in state  w, ton
		@variable(model, p[G,H_T]>=0)							#Active power generation of unit g in hour h, MW
		@variable(model, pw[G,W]>=0)							#Total renewable generation of unit g in state w, MWh
		@variable(model, p_LS[I,H_T]>=0)						#Load shedding of demand d in hour h, MW
		@variable(model, pt_rps[W]>=0)							#Amount of active power violated RPS policy in state w, MW
		@variable(model, pwi[G,W,W_prime]>=0)					#Renewable credits transferred from state w to state w' annually, MWh
		if inv_dcs_bin == 1
			@variable(model, x[G_new], Bin)							#Decision variable for candidate generator g, binary
			@variable(model, y[L_new], Bin)							#Decision variable for candidate line l, binary
			@variable(model, z[S_new], Bin)							#Decision variable for candidate storage s, binary
			@variable(model, x_RET[G_RET], Bin)						#Decision variable for generator g eligible for retirement, binary
		elseif inv_dcs_bin == 0
			@variable(model, 0 <= x[G_new] <= 1)					#Decision variable for candidate generator g, relax to scale 0-1
			@variable(model, 0 <= y[L_new] <= 1)					#Decision variable for candidate line l, relax to scale 0-1
			@variable(model, 0 <= z[S_new] <= 1)					#Decision variable for candidate storage s, relax to scale 0-1
			@variable(model, 0 <= x_RET[G_RET] <= 1)				#Decision variable for generator g eligible for retirement, relax to scale 0-1
		end
		if flexible_demand == 1
			@variable(model, dr_DF[D,H_T]>=0)						#Deferred demand (load shifted out), MW
			@variable(model, dr_PB[D,H_T]>=0)						#Payback demand (load shifted back), MW
			@variable(model, b_DR[D,H_T]>=0)						#Backlog state variable, MWh
		end
		@variable(model, soc[S,H_T]>=0)							#State of charge level of storage s in hour h, MWh
		@variable(model, c[S,H_T]>=0)							#Charging power of storage s from grid in hour h, MW
		@variable(model, dc[S,H_T]>=0)							#Discharging power of storage s into grid in hour h, MW
		#@variable(model, slack_pos[T,H_T,I]>=0)					#Slack varbale for debuging
		#@variable(model, slack_neg[T,H_T,I]>=0)					#Slack varbale for debuging
		#unregister(model, :p)

		#Temporaty constraint for debugging
		#@constraint(model, [g in G_new], x[g]==0);
		#@constraint(model, [l in L_new], y[l]==0);
		#@constraint(model, [s in S_new], z[s]==0);

		#Constraints--------------------------------------------
		#(2) Generator investment budget:∑_(g∈G^+) INV_g ∙x_g ≤IBG
		IBG_con = @constraint(model, sum(INV_g[g]*x[g]*P_max[g] for g in G_new) <= IBG, base_name = "IBG_con")

		#(3) Transmission line investment budget:∑_(l∈L^+) INV_l ∙x_l ≤IBL
		IBL_con = @constraint(model, sum(unit_converter*INV_l[l]*y[l] for l in L_new) <= IBL, base_name = "IBL_con")

		#(4) Storages investment budget:∑_(s∈S^+) INV_s ∙x_s ≤IBS
		IBS_con = @constraint(model, sum(INV_s[s]*z[s]*SCAP[s] for s in S_new) <= IBS, base_name = "IBS_con")

		#(5) Power balance: power generation from generators + power generation from storages + power transmissed + net import = Load demand - Loadshedding	
		if flexible_demand != 0
			@expression(model, DR_OPT[i in I, t in T, h in H_t[t]], sum(dr_PB[d,h] - dr_DF[d,h] for d in D_i[i]))
		else
			@expression(model, DR_OPT[i in I, t in T, h in H_t[t]], 0)
		end
		@constraint(model, PB_con[i in I, t in T, h in H_t[t]], sum(p[g,h] for g in G_i[i]) 
			+ sum(dc[s,h] - c[s,h] for s in S_i[i])
			- sum(f[l,h] for l in LS_i[i])#LS
			+ sum(f[l,h] for l in LR_i[i])#LR
			#+ NI_t[t][h,i]
			+ NI_hi[h,i] #net import
			#+ slack_pos[t,h,i]-slack_neg[t,h,i]
			== sum(P_hd[h,d]*PK[d] for d in D_i[i]) + DR_OPT[i,t,h] - p_LS[i,h],base_name = "PB_con")
		
		#(6) Transissim power flow limit for existing lines	
		TLe_con = @constraint(model, [l in L_exist,t in T,h in H_t[t]], -F_max[l] <= f[l,h] <= F_max[l],base_name = "TLe_con")

		#(7) Transissim power flow limit for new lines
		TLn_LB_con = @constraint(model, [l in L_new,t in T,h in H_t[t]], -F_max[l] * y[l] <= f[l,h],base_name = "TLn_LB_con")
		TLn_UB_con = @constraint(model, [l in L_new,t in T,h in H_t[t]],  f[l,h] <= F_max[l]* y[l],base_name = "TLn_UB_con")

		#(8) Maximum capacity limits for existing power generator
		CLe_con = @constraint(model, [g in setdiff(G_exist, G_RET),t in T, h in H_t[t]], P_min[g] <= p[g,h] <=P_max[g]*AF_gh[g,h],base_name = "CLe_con")
		CLe_RET_LB_con = @constraint(model, [g in G_RET,t in T, h in H_t[t]], P_min[g] - P_min[g]*x_RET[g] <= p[g,h], base_name = "CLe_RET_LB_con")
		CLe_RET_UP_con = @constraint(model, [g in G_RET,t in T, h in H_t[t]],  p[g,h] <= AF_gh[g,h]*P_max[g]- AF_gh[g,h]*P_max[g]*x_RET[g], base_name = "CLe_RET_UP_con")
		CLe_MR_con =  @constraint(model, [g in intersect(G_exist,G_MR),t in T, h in H_t[t]],  p[g,h] == P_max[g]*AF_gh[g,h], base_name = "CLe_MR_con")
	
		#(9) Maximum capacity limits for new power generator
		CLn_LB_con = @constraint(model, [g in G_new,t in T,h in H_t[t]], P_min[g]*x[g] <= p[g,h], base_name = "CLn_LB_con")
		CLn_UB_con = @constraint(model, [g in G_new,t in T,h in H_t[t]],  p[g,h] <=P_max[g]*x[g]*AF_gh[g,h],base_name = "CLn_UB_con")
		CLn_MR_con =  @constraint(model, [g in intersect(G_new,G_MR),t in T, h in H_t[t]],  p[g,h] == P_max[g]*x[g]*AF_gh[g,h], base_name = "CLn_MR_con")
		#(10) Load shedding limit	
		LS_con = @constraint(model, [i in I, t in T, h in H_t[t]], 0 <= p_LS[i,h]<= sum(P_hd[h,d]*PK[d] for d in D_i[i]),base_name = "LS_con")
	
		##############
		##Renewbales##
		##############
		#(11) Renewables/RPS-eligible generation availability for existing plants
		ReAe_con=@constraint(model, [g in intersect(G_exist,G_RPS), t in T, h in H_t[t]], p[g,h] <= AF_gh[g,h]*P_max[g],base_name = "ReAe_con")
		ReAe_MR_con=@constraint(model, [g in intersect(intersect(G_exist,G_MR),G_RPS), t in T, h in H_t[t]], p[g,h] == AF_gh[g,h]*P_max[g],base_name = "ReAe_MR_con")
		@expression(model, RenewableCurtailExist[g in intersect(G_exist,G_RPS), t in T, h in H_t[t]], AF_gh[g,h]*P_max[g]-p[g,h])
		
		#(12) Renewables/RPS-eligible generation availability for new installed plants
		ReAn_con=@constraint(model, [g in intersect(G_new,G_RPS), t in T, h in H_t[t]], p[g,h]<= x[g]*AF_gh[g,h]*P_max[g],base_name = "ReAn_con")
		ReAn_MR_con=@constraint(model, [g in intersect(intersect(G_new,G_MR),G_RPS), t in T, h in H_t[t]], p[g,h] == x[g]*AF_gh[g,h]*P_max[g],base_name = "ReAn_MR_con")
		@expression(model, RenewableCurtailNew[g in intersect(G_new,G_RPS), t in T, h in H_t[t]], AF_gh[g,h]*P_max[g]-p[g,h])
		
		##############
		###Storages###
		##############
		#(13) Storage charging rate limit for existing units
		ChLe_con=@constraint(model, [t in T, h in H_t[t], s in S_exist], c[s,h]/SC[s] <= SCAP[s],base_name = "ChLe_con")
		
		#(14) Storage discharging rate limit for existing units
		DChLe_con=@constraint(model, [t in T, h in H_t[t],  s in S_exist], c[s,h]/SC[s] + dc[s,h]/SD[s] <= SCAP[s],base_name = "DChLe_con")
		
		#(15) Storage charging rate limit for new installed units
		ChLn_con=@constraint(model, [t in T, h in H_t[t], s in S_new], c[s,h]/SC[s] <= z[s]*SCAP[s],base_name = "ChLn_con")
		
		#(16) Storage discharging rate limit for new installed units
		DChLn_con=@constraint(model, [t in T, h in H_t[t] , s in S_new], c[s,h]/SC[s]+ dc[s,h]/SD[s] <= z[s]*SCAP[s],base_name = "DChLn_con")
		
		#(17) State of charge limit for existing units: 0≤ soc_(s,h) ≤ SCAP_s;   ∀h∈H_t,t∈T,s∈ S^E
		SoCLe_con=@constraint(model, [t in T, h in H_t[t], s in S_exist], 0 <= soc[s,h] <= SECAP[s], base_name = "SoCLe_con")
		
		#(18) State of charge limit for new installed units
		SoCLn_ub_con= @constraint(model, [t in T, h in H_t[t],  s in S_new],  soc[s,h] <= z[s]*SECAP[s],base_name = "SoCLn_ub_con")
		SoCLn_lb_con= @constraint(model, [t in T, h in H_t[t],  s in S_new],  0 <= soc[s,h], base_name = "SoCLn_lb_con")
		#Stroage investment lower bound for MD
		#S_lb_con = @constraint(model, [w in ["MD"]], sum(sum(z[s]*SCAP[s] for s in S_new_i[i]) for i in I_w[w])>= 3000, base_name="S_lb_con")

		#(19) Storage operation constraints
		SoC_con=@constraint(model, [t in T, h in setdiff(H_t[t], [H_t[t][1]]),s in S], soc[s,h] == soc[s,h-1] + e_ch[s]*c[s,h] - dc[s,h]/e_dis[s],base_name = "SoC_con")
		
		#(20)-(21) Storage boundary conditions
		if T == [1]
			# Full-year mode: all storage uses cyclic SOC with first-hour wrap.
			SDBe_st_con=@constraint(model, [t in T,s in S_exist, h in [8760]], soc[s,1] == soc[s,end] + e_ch[s]*c[s,1] - dc[s,1]/e_dis[s],base_name = "SDBe_st_con")
			SDBn_st_con=@constraint(model, [t in T,s in S_new,h in [8760]], soc[s,1] == soc[s,end] + e_ch[s]*c[s,1] - dc[s,1]/e_dis[s],base_name = "SDBn_st_con")
		else
			# Representative-day mode:
			# - Short-duration storage (S_SD): daily cyclic SOC + 50% end anchor.
			# - Long-duration storage (S_LD): inter-period SOC linkage (no daily 50% anchor).
			SDBe_st_con=@constraint(model, [t in T, s in S_SD_exist], soc[s,H_t[t][1]] == soc[s,H_t[t][end]] + e_ch[s]*c[s,H_t[t][1]] - dc[s,H_t[t][1]]/e_dis[s],base_name = "SDBe_st_con")
			SDBe_ed_con=@constraint(model, [t in T, s in S_SD_exist], soc[s,H_t[t][end]] == 0.5 * SECAP[s],base_name = "SDBe_ed_con")
			SDBn_st_con=@constraint(model, [t in T, s in S_SD_new], soc[s,H_t[t][1]] == soc[s,H_t[t][end]] + e_ch[s]*c[s,H_t[t][1]] - dc[s,H_t[t][1]]/e_dis[s],base_name = "SDBn_st_con" )
			SDBn_ed_con=@constraint(model, [t in T, s in S_SD_new], soc[s,H_t[t][end]] == 0.5 * z[s]*SECAP[s],base_name = "SDBn_ed_con")
			T_first = T[1]
			T_last = T[end]
			T_follow = length(T) > 1 ? T[2:end] : Int[]
			SDBe_ld_wrap_con=@constraint(model, [s in S_LD_exist], soc[s,H_t[T_first][1]] == soc[s,H_t[T_last][end]] + e_ch[s]*c[s,H_t[T_first][1]] - dc[s,H_t[T_first][1]]/e_dis[s], base_name = "SDBe_ld_wrap_con")
			SDBe_ld_link_con=@constraint(model, [t in T_follow, s in S_LD_exist], soc[s,H_t[t][1]] == soc[s,H_t[t-1][end]] + e_ch[s]*c[s,H_t[t][1]] - dc[s,H_t[t][1]]/e_dis[s], base_name = "SDBe_ld_link_con")
			SDBn_ld_wrap_con=@constraint(model, [s in S_LD_new], soc[s,H_t[T_first][1]] == soc[s,H_t[T_last][end]] + e_ch[s]*c[s,H_t[T_first][1]] - dc[s,H_t[T_first][1]]/e_dis[s], base_name = "SDBn_ld_wrap_con")
			SDBn_ld_link_con=@constraint(model, [t in T_follow, s in S_LD_new], soc[s,H_t[t][1]] == soc[s,H_t[t-1][end]] + e_ch[s]*c[s,H_t[t][1]] - dc[s,H_t[t][1]]/e_dis[s], base_name = "SDBn_ld_link_con")
		end

		
		
		##############
		#Planning Rsv#
		##############
		#(22) Resource adequacy
		# planning_reserve_mode:
		# 0 -> disable planning reserve constraints
		# 1 -> enforce one system-level reserve adequacy constraint
		# 2 -> enforce zonal reserve adequacy constraints
		if flexible_demand == 1
			@expression(model, DR_RA_i[i in I], sum(DR_CC[d] * DR_DF_peak[d] for d in D_i[i]))
		else
			@expression(model, DR_RA_i[i in I], 0)
		end
		@expression(model, DR_RA_system, sum(DR_RA_i[i] for i in I))
		if planning_reserve_mode == 1
			RA_con = @constraint(model, sum(CC_g[g]*P_max[g] for g in G_exist)+ sum(CC_g[g]*P_max[g]*x[g] for g in G_new)
									+sum(CC_s[s]*SCAP[s] for s in S_exist)+sum(CC_s[s]*SCAP[s]*z[s] for s in S_new)
									+DR_RA_system
									>= (1+PRM)*PK_system, base_name = "RA_con")
		elseif planning_reserve_mode == 2
			RA_zone_con = @constraint(model, [i in I],
									sum(CC_g[g]*P_max[g] for g in intersect(G_exist, G_i[i]))
									+ sum(CC_g[g]*P_max[g]*x[g] for g in intersect(G_new, G_i[i]))
									+ sum(CC_s[s]*SCAP[s] for s in intersect(S_exist, S_i[i]))
									+ sum(CC_s[s]*SCAP[s]*z[s] for s in intersect(S_new, S_i[i]))
									+ DR_RA_i[i]
									>= (1+PRM_i[i])*PK_i[i], base_name = "RA_zone_con")
		else
			println("Planning reserve constraints are disabled (planning_reserve_mode = 0).")
		end
		##############
		##RPSPolicies##
		##############
		if clean_energy_policy == 1
			#(23) RPS, state level total Defining
			RPS_pw_con = @constraint(model, [w in W, g in intersect(union([G_i[i] for i in I_w[w]]...),G_RPS)],
								pw[g,w] == sum(N[t]*sum(p[g,h] for h in H_t[t]) for t in T), base_name = "RPS_pw_con")

			
			#(24) State renewable credits export limitation 
			RPS_expt_con = @constraint(model, [w in W, g in intersect(union([G_i[i] for i in I_w[w]]...),G_RPS) ], pw[g,w] >= sum(pwi[g,w,w_prime] for w_prime in WER_w[w]), base_name = "RPS_expt_con")
			
			#(25) State renewable credits import limitation 
			RPS_impt_con = @constraint(model, [w in W, w_prime in WIR_w[w],g in intersect(union([G_i[i] for i in I_w[w_prime]]...),G_RPS)], pw[g,w_prime] >= pwi[g,w_prime,w], base_name = "RPS_impt_con")

			#(26) Renewable credits trading meets state RPS requirements
			RPS_con = @constraint(model, [w in W], sum(pw[g,w] for g in intersect(union([G_i[i] for i in I_w[w]]...),G_RPS))
										+ sum(pwi[g,w_prime,w] for w_prime in WIR_w[w] for g in intersect(union([G_i[i] for i in I_w[w_prime]]...),G_RPS))
										- sum(pwi[g,w,w_prime] for w_prime in WER_w[w] for g in intersect(union([G_i[i] for i in I_w[w]]...),G_RPS))
										+ pt_rps[w] 
										>= sum(N[t]*sum(sum(P_hd[h,d]*PK[d]*RPS[w] for d in D_i[i]) for i in I_w[w] for h in H_t[t]) for t in T), base_name = "RPS_con") 
			# RPS_con_selfmeet = @constraint(model, [w in setdiff(W,W_RPS)], sum(N[t]*sum(p[g,t,h] for g in intersect(union([G_i[i] for i in I_w[w]]...),G_RPS) for h in H_t[t]) for t in T) + pt_rps[w] >= sum(N[t]*sum(sum(P_t[t][h,i]*PK[i]*RPS[w] for d in D_i[i]) for i in I_w[w] for h in H_t[t]) for t in T), base_name = "RPS_con_selfmeet")
		else
			RPS_off_con = @constraint(model, [w in W], pt_rps[w] == 0, base_name = "RPS_off_con")
		end
		
		###############
		#CarbonPolicies#				
		###############
		@expression(model, StateCarbonEmission[w in W], sum(sum(N[t]*sum(EF[g]*p[g,h] for g in intersect(G_F,G_i[i]) for h in H_t[t]) for t in T) for i in I_w[w]))
		if carbon_policy == 2
			#(28B) State carbon allowance cap
			SCAL_con = @constraint(model, [w in W], sum(a[g] for g in intersect(union([G_i[i] for i in I_w[w]]...), G_F)) <= get(ALW_state, w, 0.0), base_name = "SCAL_con")
			#(29B) Balance between allowances and annual emissions
			BAL_con = @constraint(model, [w in W], StateCarbonEmission[w] <= sum(a[g] for g in intersect(union([G_i[i] for i in I_w[w]]...), G_F)) + em_emis[w], base_name = "BAL_con")
		elseif carbon_policy == 1
			#(28A) State carbon emission limit with penalty slack
			CL_con = @constraint(model, [w in W], StateCarbonEmission[w] <= ELMT[w] + em_emis[w], base_name = "CL_con")
		else
			NoCarbon_con = @constraint(model, [w in W], em_emis[w] == 0, base_name = "NoCarbon_con")
		end

		if flexible_demand == 1
			#Demand response (load shifting), backlog dynamics
			DR_backlog_con = @constraint(model, [d in D, t in T, h in setdiff(H_t[t], [H_t[t][1]])],
				b_DR[d,h] == b_DR[d,h-1] + dr_DF[d,h] - DR_shift_eff[d] * dr_PB[d,h], base_name="DR_backlog_con")
			DR_backlog_start_con = @constraint(model, [d in D, t in T], b_DR[d,H_t[t][1]] == 0, base_name="DR_backlog_start_con")
			DR_backlog_end_con = @constraint(model, [d in D, t in T], b_DR[d,H_t[t][end]] == 0, base_name="DR_backlog_end_con")
			DR_df_con = @constraint(model, [d in D, t in T, h in H_t[t]], dr_DF[d,h] <= DR_DF_max[h,d], base_name="DR_df_con")
			DR_pb_con = @constraint(model, [d in D, t in T, h in H_t[t]], dr_PB[d,h] <= DR_PB_max[h,d], base_name="DR_pb_con")
			DR_backlog_cap_con = @constraint(model, [d in D, h in H_T], b_DR[d,h] <= DR_max_defer_hours[d] * DR_DF_peak[d], base_name="DR_backlog_cap_con")
		end
		#Objective function and solve--------------------------
		#Investment cost of generator, lines, and storages
		@expression(model, INVCost, sum(INV_g[g]*x[g]*P_max[g] for g in G_new)+sum(unit_converter*INV_l[l]*y[l] for l in L_new)+sum(INV_s[s]*z[s]*SCAP[s] for s in S_new))			
		@expression(model, INVCost_gen, sum(INV_g[g]*x[g]*P_max[g] for g in G_new))
		@expression(model, INVCost_line, sum(unit_converter*INV_l[l]*y[l] for l in L_new))
		@expression(model, INVCost_storage, sum(INV_s[s]*z[s]*SCAP[s] for s in S_new))

		#Operation cost of generator and storages
		@expression(model, OPCost, sum(VCG[g]*N[t]*sum(p[g,h] for h in H_t[t]) for g in G for t in T)
					+ sum(VCS[s]*N[t]*sum(c[s,h]+dc[s,h] for h in H_t[t]) for s in S for t in T)
					)	
		#Loss of load penalty
		@expression(model, LoadShedding, sum(VOLL*N[t]*sum(p_LS[i,h] for h in H_t[t]) for i in I for t in T))

		#RPS volitation penalty
		if clean_energy_policy == 1
			@expression(model, RPSPenalty, PT_rps*sum(pt_rps[w] for w in W))
		else
			@expression(model, RPSPenalty, 0)
		end
		#VRE curtailments
		VRE_CT = @expression(model, [g in G_VRE, t in T, h in H_t[t]], AF_gh[g,h]*P_max[g] - p[g,h])			
		
		#Carbon cap volitation penalty
		if carbon_policy == 0
			@expression(model, CarbonCapPenalty, 0)
		else
			@expression(model, CarbonCapPenalty, PT_emis*sum(em_emis[w] for w in W))
		end
		@expression(model, CarbonEmission[w in W], sum(N[t]*EF[g]*p[g,h] for g in intersect(union([G_i[i] for i in I_w[w]]...), G_F) for t in T for h in H_t[t] ))
		#Slack variable penalty
		#@expression(model, SlackPenalty, sum(BM * N[t]*sum(slack_pos[t,h,i]+slack_neg[t,h,i] for h in H_t[t] for i in I) for t in T))

		#Minmize objective fuction: INVCost + OPCost + RPSPenalty + CarbonCapPenalty + SlackPenalty
		if flexible_demand != 0
			@expression(model,DR_OPcost,sum(N[t]*sum(DRC_d[d]*(dr_DF[d,h]+dr_PB[d,h]) for h in H_t[t] for d in D) for t in T))
		else
			@expression(model,DR_OPcost,0)		
		end
		@objective(model,Min,INVCost + OPCost +DR_OPcost + LoadShedding + RPSPenalty + CarbonCapPenalty)#+ SlackPenalty
		return model
	end
end 
