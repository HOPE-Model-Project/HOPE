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
		Gencostdata = input_data["Gencostdata"]
		#reservedata=
		#time series
		Winddata = input_data["Winddata"]
		Solardata = input_data["Solardata"]
		Loaddata = input_data["Loaddata"]
		NIdata = input_data["NIdata"]
		#candidate
		Estoragedata_candidate = input_data["Estoragedata_candidate"]
		Linedata_candidate = input_data["Linedata_candidate"]
		Gendata_candidate = input_data["Gendata_candidate"]
		#policies
		CBPdata = input_data["CBPdata"]
		CBP_state_data = combine(groupby(CBPdata, :State), Symbol("Allowance (tons)") => sum)
		#rpspolicydata=
		RPSdata = input_data["RPSdata"]
		#penalty_cost, investment budgets, planning reserve margins etc. single parameters
		SinglePardata = input_data["Singlepar"]

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
		Ordered_zone_nm = [Idx_zone_dict[i] for i=1:Num_zone]

		#representative day clustering
		if config_set["representative_day!"]==1
			time_periods = config_set["time_periods"]
			#get representative time seires
			Load_rep = get_representative_ts(Loaddata,time_periods,Ordered_zone_nm)[1]
			Wind_rep = get_representative_ts(Winddata,time_periods,Ordered_zone_nm)[1]
			Solar_rep = get_representative_ts(Solardata,time_periods,Ordered_zone_nm)[1]
		else
			Load_rep = Loaddata
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
		#G_F_E=findall(x -> x in ["Coal", "Oil", "NGCT", "NuC", "MSW", "Bio", "Landfill_NG", "NGCC"], Gendata[:,"Type"])
		#G_F_C=findall(x -> x in ["Coal", "Oil", "NGCT", "NuC", "MSW", "Bio", "Landfill_NG", "NGCC"], Gendata_candidate[:,"Type"]).+Num_gen	
		G_F_E=findall(x -> x in [1], Gendata[:,"Flag_thermal"])
		G_F_C=findall(x -> x in [1], Gendata_candidate[:,"Flag_thermal"]).+Num_gen	
		G_MR_E=findall(x -> x in [1], Gendata[:,"Flag_mustrun"])
		G_MR_C=findall(x -> x in [1], Gendata_candidate[:,"Flag_mustrun"]).+Num_gen	
		G_F=[G_F_E;G_F_C]												#Set of dispatchable generators, subsets of G
		G_MR = [G_MR_E;G_MR_C]
		G_RPS_E = findall(x -> x in ["Hydro", "MSW", "Bio", "Landfill_NG","Nuc", "WindOn","WindOff","SolarPV"], Gendata[:,"Type"])
		G_RPS_C = findall(x -> x in ["Hydro", "MSW", "Bio", "Landfill_NG","Nuc","WindOn","WindOff","SolarPV"], Gendata_candidate[:,"Type"]).+Num_gen
		G_RPS = [G_RPS_E;G_RPS_C]										#Set of generation units providing RPS credits, index g, subset of G  
		G_exist=[g for g=1:Num_gen]										#Set of existing generation units, index g, subset of G  
		G_RET=findall(x -> x in [1], Gendata[:,"Flag_RET"])			#Set of existing generation units availiabile for retirement, index g, subset of G 
		G_new=[g for g=Num_gen+1:Num_gen+Num_Cgen]						#Set of candidate generation units, index g, subset of G 
		G_i=[[findall(Gendata[:,"Zone"].==Idx_zone_dict[i]);(findall(Gendata_candidate[:,"Zone"].==Idx_zone_dict[i]).+Num_gen)] for i in I]						#Set of generating units connected to zone i, subset of G  
		HD = [h for h in 1:24]
		if config_set["representative_day!"]==1														#Set of hours in one day, index h, subset of H
			H_t=[collect(1:24) for t in T]									#Set of hours in time period (day) t, index h, subset of H
			H_T = collect(unique(reduce(vcat,H_t)))							#Set of unique hours in time period, index h, subset of H
		else
			H_t=[collect(1:8760) for t in [1]]									#Set of hours in time period (day) t, index h, subset of H
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
		WER_w=Dict(zip(unique(RPSdata[:, :From_state]),[RPSdata[findall(RPSdata[:,"From_state"].==i),"To_state"] for i in unique(RPSdata[:, :From_state])]))		#Set of states that state w can export renewable credits to (excludes w itself), subset of W
		[WER_w[w] = [] for w in unique(RPSdata[:, :From_state]) if [w] == WER_w[w]]
		WIR_w=Dict(zip(unique(RPSdata[:, :From_state]), unique(push!(RPSdata[findall(RPSdata[:,"From_state"].==i),"To_state"], i)) for i in unique(RPSdata[:, :From_state]))) #Set of states that state w can import renewable credits from (includes w itself), subset of W

		G_L = Dict(zip([l for l in L], [G_i[i] for l in L for i in IL_l[l]]))			#Set of generation units that linked to line l, index g, subset of G

		#Parameters--------------------------------------------
		ALW = Dict((row["Time Period"], row["State"]) => row["Allowance (tons)"] for row in eachrow(CBPdata))#(t,w)														#Total carbon allowance in time period t in state w, ton
		#AFRES=Dict([(g, h, i) => Solardata[:,Idx_zone_dict[i]][h] for g in G_PV for h in H for i in I])#(g,h,i)												#Availability factor of renewable energy source g in hour h in zone i, g∈G^PV∪G^W 
		#AFREW=Dict([(g, h, i) => Winddata[:,Idx_zone_dict[i]][h] for g in G_W for h in H for i in I])#(g,h,i)													#Availability factor of renewable energy source g in hour h in zone i, g∈G^PV∪G^W 
		#AFRES_tg = Dict([(t,g) => Dict([(h, i) => Solar_rep[t][:,Idx_zone_dict[i]][h] for h in H[t] for i in I]) for t in T for g in G_PV])
		#AFREW_tg = Dict([(t,g) => Dict([(h, i) => Wind_rep[t][:,Idx_zone_dict[i]][h] for h in H[t] for i in I]) for t in T for g in G_W])
		#AFRE_tg = merge(+, AFRES_tg, AFREW_tg)
		BM = SinglePardata[1,"BigM"];														#big M penalty
		CC_g = [Gendata[:,"CC"];Gendata_candidate[:,"CC"]]#g       		#Capacity credit of generating units, unitless
		CC_s = [Storagedata[:,"CC"];Estoragedata_candidate[:,"CC"]]#s   #Capacity credit of storage units, unitless
		#CP=29#g $/ton													#Carbon price of generation g〖∈G〗^F, M$/t (∑_(g∈G^F,t∈T)〖〖CP〗_g  .N_t.∑_(h∈H_t)p_(g,h) 〗)
		EF=[Gendata[:,"EF"];Gendata_candidate[:,"EF"]]#g				#Carbon emission factor of generator g, t/MWh
		ELMT=Dict(zip(CBP_state_data[!,"State"],CBP_state_data[!,"Allowance (tons)_sum"]))#w							#Carbon emission limits at state w, t
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
		P_t = Load_rep
		PK=Zonedata[:,"Demand (MW)"]#i						#Peak power demand, MW
		PT_rps=SinglePardata[1, "PT_RPS"]											#RPS volitation penalty, $/MWh
		PT_emis=SinglePardata[1, "PT_emis"]										#Carbon emission volitation penalty, $/t
		P_min=[Gendata[:,"Pmin (MW)"];Gendata_candidate[:,"Pmin (MW)"]]#g						#Minimum power generation of unit g, MW
		P_max=[Gendata[:,"Pmax (MW)"];Gendata_candidate[:,"Pmax (MW)"]]#g						#Maximum power generation of unit g, MW
		RPS=Dict(zip(RPSdata[:,:From_state],RPSdata[:,:RPS]))	#w									#Renewable portfolio standard in state w,  unitless
		RM=SinglePardata[1,"planning _reserve_margin"]#												#Planning reserve margin, unitless
		SECAP=[Storagedata[:,"Capacity (MWh)"];Estoragedata_candidate[:,"Capacity (MWh)"]]#s		#Maximum energy capacity of storage unit s, MWh
		SCAP=[Storagedata[:,"Max Power (MW)"];Estoragedata_candidate[:,"Max Power (MW)"]]#s		#Maximum capacity of storage unit s, MWh
		SC=[Storagedata[:,"Charging Rate"]; Estoragedata_candidate[:, "Charging Rate"]]#s									#The maximum rates of charging, unitless
		SD=[Storagedata[:,"Discharging Rate"]; Estoragedata_candidate[:, "Discharging Rate"]]#s									#The maximum rates of discharging, unitless
		VCG=[Gencostdata;Gendata_candidate[:,Symbol("Cost (\$/MWh)")]]#g						#Variable cost of generation unit g, $/MWh
		VCS=[Storagedata[:,Symbol("Cost (\$/MWh)")];Estoragedata_candidate[:,Symbol("Cost (\$/MWh)")]]#s						#Variable (degradation) cost of storage unit s, $/MWh
		VOLL=SinglePardata[1, "VOLL"]#d										#Value of loss of load d, $/MWh
		e_ch=[Storagedata[:,"Charging efficiency"];Estoragedata_candidate[:,"Charging efficiency"]]#s				#Charging efficiency of storage unit s, unitless
		e_dis=[Storagedata[:,"Discharging efficiency"];Estoragedata_candidate[:,"Discharging efficiency"]]#s			#Discharging efficiency of storage unit s, unitless
			
		#for multiple time period, we need to use following TS parameters
		if config_set["representative_day!"]==1
			N=get_representative_ts(Loaddata,time_periods,Ordered_zone_nm)[2]#t	  #Number of time periods (days) represented by time period (day) t per year, ∑_(t∈T)▒〖N_t.|H_t |〗= 8760
			NI_t = Dict([t => Dict([(h,i) =>-Load_rep[t][!,"NI"][h]*(Zonedata[:,"Demand (MW)"][i]/sum(Zonedata[:,"Demand (MW)"])) for i in I for h in H_t[t]]) for t in T]) #tih
			P_t = Load_rep #thi
			AFRES_tg = Dict([(t,g) => Dict([(h, i) => Solar_rep[t][:,Idx_zone_dict[i]][h] for i in I for h in H_t[t] ]) for t in T for g in G_PV])
			AFREW_tg = Dict([(t,g) => Dict([(h, i) => Wind_rep[t][:,Idx_zone_dict[i]][h] for h in H_t[t] for i in I]) for t in T for g in G_W])
			AFRE_tg = merge(+, AFRES_tg, AFREW_tg)#[t,g][h,i]
		else
			N=[1]
			NI_t = Dict(1=> NI)
			P_t = Dict(1 => Loaddata[:,4:3+Num_zone])
			AFRES_tg = Dict([(t,g) => Dict([(h, i) => Solardata[:,4:end][:,Idx_zone_dict[i]][h] for i in I for h in H]) for t in T for g in G_PV])
			AFREW_tg = Dict([(t,g) => Dict([(h, i) => Winddata[:,4:end][:,Idx_zone_dict[i]][h] for h in H for i in I]) for t in T for g in G_W])
			AFRE_tg = merge(+, AFRES_tg, AFREW_tg)#[t,g][h,i]
		end
		unit_converter = 10^6

		#Relax of integer variable:
		inv_dcs_bin = config_set["inv_dcs_bin"]

		model=Model(OPTIMIZER)
		#Variables---------------------------------------------
		@variable(model, a[G,T]>=0) 							#Bidding carbon allowance of unit g in time period t, ton
		@variable(model, b[G,T]>=0) 							#Banking of allowance of g in time period t, ton
		@variable(model, f[L,T,H_T])							#Active power in transmission corridor/line l in h from resrource g, MW
		@variable(model, em_emis[W]>=0)							#Carbon emission violated emission limit in state  w, ton
		@variable(model, p[G,T,H_T]>=0)							#Active power generation of unit g in hour h, MW
		@variable(model, pw[G,W]>=0)							#Total renewable generation of unit g in state w, MWh
		@variable(model, p_LS[D,T,H_T]>=0)						#Load shedding of demand d in hour h, MW
		@variable(model, pt_rps[W]>=0)							#Amount of active power violated RPS policy in state w, MW
		@variable(model, pwi[G,W,W_prime]>=0)					#State w imported renewable credits from state w' annually, MWh	
		if inv_dcs_bin == 1
			@variable(model, x[G_new], Bin)							#Decision variable for candidate generator g, binary
			@variable(model, y[L_new], Bin)							#Decision variable for candidate line l, binary
			@variable(model, z[S_new], Bin)							#Decision variable for candidate storage s, binary
			@variable(model, x_RET[G_RET], Bin)						#Decision variable for generator g eligible for retirement, binary
		elseif inv_dcs_bin == 0
			@variable(model, 0 <= x[G_new] <= 1)					#Decision variable for candidate generator g, relax to scale 0-1
			@variable(model, 0 <= y[L_new] <= 1)					#Decision variable for candidate line l, relax to scale 0-1
			@variable(model, 0 <= z[S_new] <= 1)					#Decision variable for candidate storage s, relax to scale 0-1
			@variable(model, 0 <=x_RET[G_RET]<= 1)					#Decision variable for generator g eligible for retirement, relax to scale 0-1
		end
		@variable(model, soc[S,T,H_T]>=0)							#State of charge level of storage s in hour h, MWh
		@variable(model, c[S,T,H_T]>=0)							#Charging power of storage s from grid in hour h, MW
		@variable(model, dc[S,T,H_T]>=0)							#Discharging power of storage s into grid in hour h, MW
		#@variable(model, slack_pos[T,H_T,I]>=0)					#Slack varbale for debuging
		#@variable(model, slack_neg[T,H_T,I]>=0)					#Slack varbale for debuging
		#unregister(model, :p)

		#Temporaty constraint for debugging
		#@constraint(model, [g in G_new], x[g]==0);
		#@constraint(model, [l in L_new], y[l]==0);
		#@constraint(model, [s in S_new], z[s]==0);

		#Constraints--------------------------------------------
		#(2) Generator investment budget:∑_(g∈G^+) INV_g ∙x_g ≤IBG
		IBG_con = @constraint(model,  [g in G_new], INV_g[g]*x[g] <=IBG, base_name = "IBG_con")

		#(3) Transmission line investment budget:∑_(l∈L^+) INV_l ∙x_l ≤IBL
		IBL_con = @constraint(model,  [l in L_new], unit_converter*INV_l[l]*y[l] <=IBL, base_name = "IBL_con")

		#(4) Storages investment budget:∑_(s∈S^+) INV_s ∙x_s ≤IBS
		IBS_con = @constraint(model,  [s in S_new], INV_s[s]*z[s] <=IBS, base_name = "IBS_con")

		#(5) Power balance: power generation from generators + power generation from storages + power transmissed + net import = Load demand - Loadshedding	
		PB_con = @constraint(model, [i in I, t in T, h in H_t[t]], sum(p[g,t,h] for g in G_i[i]) 
			+ sum(dc[s,t,h] - c[s,t,h] for s in S_i[i])
			- sum(f[l,t,h] for l in LS_i[i])#LS
			+ sum(f[l,t,h] for l in LR_i[i])#LR
			+ NI_t[t][h,i]
			#+ slack_pos[t,h,i]-slack_neg[t,h,i]
			== sum(P_t[t][h,i]*PK[i] - p_LS[d,t,h] for d in D_i[i]),base_name = "PB_con")
		
		#(6) Transissim power flow limit for existing lines	
		TLe_con = @constraint(model, [l in L_exist,t in T,h in H_t[t]], -F_max[l] <= f[l,t,h] <= F_max[l],base_name = "TLe_con")

		#(7) Transissim power flow limit for new lines
		TLn_LB_con = @constraint(model, [l in L_new,t in T,h in H_t[t]], -F_max[l] * y[l] <= f[l,t,h],base_name = "TLn_LB_con")
		TLn_UB_con = @constraint(model, [l in L_new,t in T,h in H_t[t]],  f[l,t,h] <= F_max[l]* y[l],base_name = "TLn_UB_con")
		
		#(8) Maximum capacity limits for existing power generator
		CLe_con = @constraint(model, [g in setdiff(G_exist, G_RET),t in T, h in H_t[t]], P_min[g] <= p[g,t,h] <=P_max[g],base_name = "CLe_con")
		CLe_RET_LB_con = @constraint(model, [g in G_RET,t in T, h in H_t[t]], P_min[g] - P_min[g]*x_RET[g] <= p[g,t,h], base_name = "CLe_RET_LB_con")
		CLe_RET_UP_con = @constraint(model, [g in G_RET,t in T, h in H_t[t]],  p[g,t,h] <= P_max[g]- P_max[g]*x_RET[g], base_name = "CLe_RET_UP_con")
		CLe_MR_con =  @constraint(model, [g in intersect(G_exist,G_MR),t in T, h in H_t[t]],  p[g,t,h] == P_max[g], base_name = "CLe_MR_con")
		#(9) Maximum capacity limits for new power generator
		CLn_LB_con = @constraint(model, [g in G_new,t in T,h in H_t[t]], P_min[g]*x[g] <= p[g,t,h],base_name = "CLn_LB_con")
		CLn_UB_con = @constraint(model, [g in G_new,t in T,h in H_t[t]],  p[g,t,h] <=P_max[g]*x[g],base_name = "CLn_UB_con")
		CLn_MR_con =  @constraint(model, [g in intersect(G_new,G_MR),t in T, h in H_t[t]],  p[g,t,h] == P_max[g]*x[g], base_name = "CLn_MR_con")
		#(10) Load shedding limit	
		LS_con = @constraint(model, [i in I, d in D_i[i], t in T, h in H[t]], 0 <= p_LS[d,t,h]<= P_t[t][h,i]*PK[i],base_name = "LS_con")
		
		##############
		##Renewbales##
		##############
		#(11) Renewables generation availability for the existing plants: p_(g,h)≤AFRE_(g,h)∙P_g^max; ∀h∈H_t,g∈G^E∩(G^PV∪G^W)  
		ReAe_con=@constraint(model, [i in I, g in intersect(G_exist,G_i[i],union(G_PV,G_W)), t in T, h in H_t[t]], p[g,t,h] <= AFRE_tg[t,g][h,i]*P_max[g],base_name = "ReAe_con")
		ReAe_MR_con=@constraint(model, [i in I, g in intersect(intersect(G_exist,G_MR),G_i[i],union(G_PV,G_W)), t in T, h in H_t[t]], p[g,t,h] == AFRE_tg[t,g][h,i]*P_max[g],base_name = "ReAe_MR_con")


		#(12) Renewables generation availability for new installed plants: p_(g,h)≤AFRE_(g,h)∙P_g^max ∙x_g; ∀h∈H_t,g∈G^+∩(G^PV∪G^W)  
		ReAn_con=@constraint(model, [i in I, g in intersect(G_new,G_i[i],union(G_PV,G_W)), t in T, h in H_t[t]], p[g,t,h]<= x[g]*AFRE_tg[t,g][h,i]*P_max[g],base_name = "ReAn_con")
		ReAn_MR_con=@constraint(model, [i in I, g in intersect(intersect(G_new,G_MR),G_i[i],union(G_PV,G_W)), t in T, h in H_t[t]], p[g,t,h] == x[g]*AFRE_tg[t,g][h,i]*P_max[g],base_name = "ReAn_MR_con")

		##############
		###Storages###
		##############
		#(13) Storage charging rate limit for existing units
		ChLe_con=@constraint(model, [t in T, h in H_t[t], s in S_exist], c[s,t,h]/SC[s] <= SCAP[s],base_name = "ChLe_con")
		
		#(14) Storage discharging rate limit for existing units
		DChLe_con=@constraint(model, [t in T, h in H_t[t],  s in S_exist], dc[s,t,h]/SD[s] <= SCAP[s],base_name = "DChLe_con")
		
		#(15) Storage charging rate limit for new installed units
		ChLn_con=@constraint(model, [t in T, h in H_t[t], s in S_new], c[s,t,h]/SC[s] <= z[s]*SCAP[s],base_name = "ChLn_con")
		
		#(16) Storage discharging rate limit for new installed units
		DChLn_con=@constraint(model, [t in T, h in H_t[t] , s in S_new], dc[s,t,h]/SD[s] <= z[s]*SCAP[s],base_name = "DChLn_con")
		
		#(17) State of charge limit for existing units: 0≤ soc_(s,h) ≤ SCAP_s;   ∀h∈H_t,t∈T,s∈ S^E
		SoCLe_con=@constraint(model, [t in T, h in H_t[t], s in S_exist], 0 <= soc[s,t,h] <= SECAP[s], base_name = "SoCLe_con")
		
		#(18) State of charge limit for new installed units
		SoCLn_ub_con= @constraint(model, [t in T, h in H_t[t],  s in S_new],  soc[s,t,h] <= z[s]*SECAP[s],base_name = "SoCLn_ub_con")
		SoCLn_lb_con= @constraint(model, [t in T, h in H_t[t],  s in S_new],  0 <= soc[s,t,h], base_name = "SoCLn_lb_con")
		#Stroage investment lower bound
		S_lb_con = @constraint(model, [w in ["MD"]], sum(sum(z[s]*SCAP[s] for s in S_new_i[i]) for i in I_w[w])>= 3000, base_name="S_lb_con")

		#(19) Storage operation constraints
		SoC_con=@constraint(model, [t in T, h in setdiff(H_t[t], [1]),s in S], soc[s,t,h] == soc[s,t,h-1] + e_ch[s]*c[s,t,h] - dc[s,t,h]/e_dis[s],base_name = "SoC_con")
		
		#(20) Daily 50% of storage level balancing for existing units
		SDBe_st_con=@constraint(model, [t in T, s in S_exist], soc[s,t,1] == soc[s,t,end],base_name = "SDBe_st_con")
		SDBe_ed_con=@constraint(model, [t in T, s in S_exist], soc[s,t,end] == 0.5 * SECAP[s],base_name = "SDBe_ed_con")
		
		#(21) Daily 50% of storage level balancing for new units
		SDBn_st_con=@constraint(model, [t in T, s in S_new], soc[s,t,1] == soc[s,t,end],base_name = "SDBn_st_con" )
		SDBn_ed_con=@constraint(model, [t in T, s in S_new], soc[s,t,end] == 0.5 * z[s]*SECAP[s],base_name = "SDBn_ed_con")
		
		
		##############
		#Planning Rsv#
		##############
		#(22) Resource adequacy
		RA_con = @constraint(model, sum(CC_g[g]*P_max[g] for g in G_exist)+ sum(CC_g[g]*P_max[g]*x[g] for g in G_new)
								+sum(CC_s[s]*SCAP[s] for s in S_exist)+sum(CC_s[s]*SCAP[s]*z[s] for s in S_new)
								>= (1+RM)*sum(PK[i] for i in I_w["MD"]), base_name = "RA_con")

		##############
		##RPSPolicies##
		##############
		#(23) RPS, state level total Defining
		RPS_pw_con = @constraint(model, [w in W, g in intersect(union([G_i[i] for i in I_w[w]]...),G_RPS)],
							pw[g,w] == sum(N[t]*sum(p[g,t,h] for h in H_t[t]) for t in T), base_name = "RPS_pw_con")

		
		#(24) State renewable credits export limitation 
		RPS_expt_con = @constraint(model, [w in W, g in intersect(union([G_i[i] for i in I_w[w]]...),G_RPS) ], pw[g,w] >= sum(pwi[g,w_prime,w] for w_prime in WER_w[w]), base_name = "RPS_expt_con")
		
		#(25) State renewable credits import limitation 
		RPS_impt_con = @constraint(model, [w in W, w_prime in WIR_w[w],g in intersect(union([G_i[i] for i in I_w[w_prime]]...),G_RPS)], pw[g,w_prime] >= pwi[g,w,w_prime], base_name = "RPS_impt_con")

		#(26) Renewable credits trading meets state RPS requirements
		RPS_con = @constraint(model, [w in W], sum(pwi[g,w,w_prime]  for w_prime in WIR_w[w] for g in intersect(union([G_i[i] for i in I_w[w_prime]]...),G_RPS))
									- sum(pwi[g,w_prime,w] for w_prime in WER_w[w] for g in intersect(union([G_i[i] for i in I_w[w]]...),G_RPS))
									+ pt_rps[w] 
									>= sum(N[t]*sum(sum(P_t[t][h,i]*PK[i]*RPS[w] for d in D_i[i]) for i in I_w[w] for h in H_t[t]) for t in T), base_name = "RPS_con") 
		# RPS_con_selfmeet = @constraint(model, [w in setdiff(W,W_RPS)], sum(N[t]*sum(p[g,t,h] for g in intersect(union([G_i[i] for i in I_w[w]]...),G_RPS) for h in H_t[t]) for t in T) + pt_rps[w] >= sum(N[t]*sum(sum(P_t[t][h,i]*PK[i]*RPS[w] for d in D_i[i]) for i in I_w[w] for h in H_t[t]) for t in T), base_name = "RPS_con_selfmeet")
		
		###############
		#CarbonPolicies#				
		###############
		#(27) State carbon emission limit
		CL_con = @constraint(model, [w in W], sum(sum(N[t]*sum(EF[g]*p[g,t,h] for g in intersect(G_F,G_i[i]) for h in H[t]) for t in T) for i in I_w[w])<=ELMT[w], base_name = "CL_con")


		##Cap & Trade##
		#(28) State carbon allowance cap
		#SCAL_con = @constraint(model, [w in W, t in T], sum(a[g,t] for g in intersect(union([G_i[i] for i in I_w[w]]...), G_F)) - em_emis[w] <= ALW[t,w],base_name = "SCAL_con")

		#(29) Balance between allowances and write_emissions
		#BAL_con = @constraint(model, [w in W, g in intersect(union([G_i[i] for i in I_w[w]]...), G_F), t in setdiff(T,[1])], N[t]*sum(EF[g]*p[g,t,h] for h in H_t[t]) == a[g,t]+b[g,t-1]-b[g,t],base_name = "BAL_con")

		#(30) No cross-year banking
		#NCrY_in_con = @constraint(model, [g in G_F], b[g,1] == b[g,end],base_name="NCrY_in_con")
		#NCrY_end_con = @constraint(model, [g in G_F], b[g,end] == 0, base_name="NCrY_end_con")


		#Objective function and solve--------------------------
		#Investment cost of generator, lines, and storages
		@expression(model, INVCost, sum(INV_g[g]*x[g]*P_max[g] for g in G_new)+sum(unit_converter*INV_l[l]*y[l]*F_max[l] for l in L_new)+sum(INV_s[s]*z[s]*SECAP[s] for s in S_new))			
		

		#Operation cost of generator and storages
		@expression(model, OPCost, sum(VCG[g]*N[t]*sum(p[g,t,h] for h in H_t[t]) for g in G for t in T)
					+ sum(VCS[s]*N[t]*sum(c[s,t,h]+dc[s,t,h] for h in H_t[t]) for s in S for t in T)
					)	

		#Loss of load penalty
		@expression(model, LoadShedding, sum(VOLL*N[t]*sum(p_LS[d,t,h] for h in H_t[t]) for d in D for t in T))

		#RPS volitation penalty
		@expression(model, RPSPenalty, PT_rps*sum(pt_rps[w] for w in W))

		#Carbon cap volitation penalty
		@expression(model, CarbonCapPenalty, PT_emis*sum(em_emis[w] for w in W))
		@expression(model, CarbonEmission[w in W], sum(N[t]*EF[g]*p[g,t,h] for g in intersect(union([G_i[i] for i in I_w[w]]...), G_F) for t in T for h in H_t[t] ))
		#Slack variable penalty
		#@expression(model, SlackPenalty, sum(BM * N[t]*sum(slack_pos[t,h,i]+slack_neg[t,h,i] for h in H_t[t] for i in I) for t in T))

		#Minmize objective fuction: INVCost + OPCost + RPSPenalty + CarbonCapPenalty + SlackPenalty
		@objective(model,Min,INVCost + OPCost + LoadShedding + RPSPenalty + CarbonCapPenalty)#+ SlackPenalty

		return model
	end
end 
