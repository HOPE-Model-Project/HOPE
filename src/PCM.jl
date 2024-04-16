function get_TPmatched_ts(df, time_periods, ordered_zone)
    #k = 1# Cluster the time series data to find a representative day
    # Function to filter rows based on the season's start and end dates
    filter_time_period(time_period, row) = (row.Month == time_period[1] && row.Day >= time_period[2]) || (row.Month == time_period[3] && row.Day <= time_period[4]) || (row.Month > time_period[1] && row.Month < time_period[3])|| ( time_period[1]>time_period[3] && row.Month < time_period[3])
    # Initialize a dictionary to store the representative days and number of days for each season  
    rep_dat_dict=Dict()
    ndays_dict=Dict()
	
	df.Hour = [h for h in  1:8760]

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
        TPmached_df = tp_df
        # Extract the time series data for the current season/time periods

		if  ["NI"] ⊆ names(df)
			TPmacheddf_ordered= select(TPmached_df, [ordered_zone;"Hour";"NI"])
		else
			TPmacheddf_ordered= select(TPmached_df, [ordered_zone;"Hour"])
		end
        rep_dat_dict[tp]=TPmacheddf_ordered
		ndays_dict[tp]=n_days
    end
    return (rep_dat_dict,ndays_dict)
end

function unit_commitment!(config_set::Dict, input_data::Dict, model::Model)
	Gendata = input_data["Gendata"]
	Num_gen=size(Gendata,1)
	#UC sets
	G = [g for g=1:Num_gen]									#Set of all types of generating units, index g
	G_UC = findall(x -> x in [1], Gendata[:,"Flag_UC"])
	H=[h for h=1:8760]										#Set of hours, index h
	#UC parameters
	FOR_g = Dict(zip(G,Gendata[:,Symbol("FOR")]))#g			#Forced outage rate
	P_max=[Gendata[:,"Pmax (MW)"];]							#Maximum power generation of unit g, MW
	P_min=[Gendata[:,"Pmin (MW)"];]							#Maximum power generation of unit g, MW
	DT_g = Gendata[:,"Min_down_time"]					#Minimum down time
	UT_g = Gendata[:,"Min_up_time"]						#Minimum up time
	STC_g = [Gendata[:,Symbol("Start_up_cost (\$/MW)")];]	#Start up cost
	#UC variables
	if config_set["unit_commitment"] == 1
		@variable(model, pmin[G_UC,H]>=0)						#Minimum-run capacity online  generator g into grid in hour h, MW
		@variable(model, o[G_UC,H],Bin)						#Online state variable of g that is on-line in h, Bin
		@variable(model, sd[G_UC,H],Bin)						#Shut-down action for g at the beginning of h, Bin
		@variable(model, su[G_UC,H],Bin)						#Start-up action for g at the beginning of h, Bin
	elseif config_set["unit_commitment"] == 2
		@variable(model, pmin[G_UC,H]>=0)						#Minimum-run capacity online  generator g into grid in hour h, MW
		@variable(model, 0<= o[G_UC,H] <=1)					#Online state variable of g that is on-line in h, 0-1
		@variable(model, 0<= sd[G_UC,H]<=1)					#Shut-down action for g at the beginning of h, 0-1
		@variable(model, 0<= su[G_UC,H]<=1)					#Start-up action for g at the beginning of h, 0-1
	end
	#UC constraints
	#(24) Minimum run limit
	MRL_con = @constraint(model, [g in G_UC, h in H], pmin[g,h] <= (1-FOR_g[g])*P_min[g]*o[g,h],base_name = "MRL_con")
		
	#(25) State transition constraint
	STT_con = @constraint(model, [g in G_UC, h in setdiff(H, [1])], o[g,h] - o[g,h-1] == su[g,h] - sd[g,h],base_name = "STT_con")
		
	#(26) Minimum up time constraint 
	MUT_con = @constraint(model, [g in G_UC, h in  Int.(UT_g[g]+1):H[end]], sum(su[g,hr] for hr in (h-UT_g[g]+1):h) <= o[g,h],base_name = "MUT_con")
		
	#(27) Minimum down time constraint
	MDT_con = @constraint(model, [g in G_UC, h in  Int.(DT_g[g]+1):H[end]], sum(su[g,hr] for hr in (h-DT_g[g]+1):h) <= 1-o[g,h],base_name = "MDT_con")
		
	#(28) pmin variable bound
	PMINB_con = @constraint(model, [g in G_UC, h in H], pmin[g,h] <= model[:p][g,h],base_name = "PMINB_con")
	#Obj expression
	@expression(model, STCost, sum(STC_g[g]*sum(su[g,h]*P_max[g] for h in H) for g in G_UC)
	)
end

function create_PCM_model(config_set::Dict,input_data::Dict,OPTIMIZER::MOI.OptimizerWithAttributes)
	model_mode = config_set["model_mode"]
	if model_mode == "GTEP"
		return "ModeError: Please use function 'create_GTEP_model' or set model mode to be 'PCM'!" 
	elseif model_mode == "PCM" 
	
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
		#policies
		CBPdata = input_data["CBPdata"]
		CBP_state_data = combine(groupby(CBPdata, :State), Symbol("Allowance (tons)") => sum)
		#rpspolicydata=
		RPSdata = input_data["RPSdata"]
		##penalty_cost, investment budgets, planning reserve margins etc. single parameters
		SinglePardata = input_data["Singlepar"]

		#Calculate number of elements of input data
		Num_bus=size(Zonedata,1);
		Num_gen=size(Gendata,1);
		Num_load=size(Zonedata,1);
		Num_Eline=size(Linedata,1);
		Num_zone=length(Zonedata[:,"Zone_id"]);
		Num_sto=size(Storagedata,1);
		

		#Index-Zone Mapping dict
		Idx_zone_dict = Dict(zip([i for i=1:Num_zone],Zonedata[:,"Zone_id"]))
		Zone_idx_dict = Dict(zip(Zonedata[:,"Zone_id"],[i for i=1:Num_zone]))
		#Ordered zone
		Ordered_zone_nm = [Idx_zone_dict[i] for i=1:Num_zone]

		#representative day clustering
		if config_set["representative_day!"]==1
			println("Setting representative_day to 1, but it is not support for current PCM mode  ")
			time_periods = config_set["time_periods"]
			#get representative time seires
			Load_tp_match = get_TPmatched_ts(Loaddata,time_periods,Ordered_zone_nm)[1]
			Wind_tp_match = get_TPmatched_ts(Winddata,time_periods,Ordered_zone_nm)[1]
			Solar_tp_match = get_TPmatched_ts(Solardata,time_periods,Ordered_zone_nm)[1]

			Loaddata_ordered = select(Loaddata, [Ordered_zone_nm;"Hour";"NI"])
			Solardata_ordered = select(Solardata, [Ordered_zone_nm;"Hour"])
			Winddata_ordered = select(Winddata, [Ordered_zone_nm;"Hour"])
		end
		time_periods = config_set["time_periods"]
		Load_tp_match = get_TPmatched_ts(Loaddata,time_periods,Ordered_zone_nm)[1]
		Wind_tp_match = get_TPmatched_ts(Winddata,time_periods,Ordered_zone_nm)[1]
		Solar_tp_match = get_TPmatched_ts(Solardata,time_periods,Ordered_zone_nm)[1]

		Loaddata_ordered = select(Loaddata, [Ordered_zone_nm;"Hour";"NI"])
		Solardata_ordered = select(Solardata, [Ordered_zone_nm;"Hour"])
		Winddata_ordered = select(Winddata, [Ordered_zone_nm;"Hour"])
		#Sets--------------------------------------------------
		D=[d for d=1:Num_load] 									#Set of demand, index d
		G=[g for g=1:Num_gen]							#Set of all types of generating units, index g
		K=unique(Gendata[:,"Type"]) 							#Set of technology types, index k
		H=[h for h=1:8760]										#Set of hours, index h
		T=[t for t=1:4]	#	[1]#								#Set of time periods (e.g., representative days of seasons), index t
		S=[s for s=1:Num_sto]							#Set of storage units, index s
		I=[i for i=1:Num_zone]									#Set of zones, index i
		J=I														#Set of zones, index j
		L=[l for l=1:Num_Eline]						#Set of transmission corridors, index l
		W=unique(Zonedata[:,"State"])							#Set of states, index w/w’
		W_prime = W												#Set of states, index w/w’

		#SubSets------------------------------------------------
		D_i=[[d] for d in D]											#Set of demand connected to zone i, a subset of D
		G_PV_E=findall(Gendata[:,"Type"].=="SolarPV")					#Set of existingsolar, subsets of G
		G_PV=[G_PV_E;]											#Set of all solar, subsets of G
		G_W_E=findall(x -> x in ["WindOn","WindOff"], Gendata[:,"Type"])#Set of existing wind, subsets of G
		G_W=[G_W_E;]                                               #Set of all wind, subsets of G
		#G_F_E=findall(x -> x in ["Coal", "Oil", "NGCT", "NuC", "MSW", "Bio", "Landfill_NG", "NGCC"], Gendata[:,"Type"])
		G_F_E=findall(x -> x in [1], Gendata[:,"Flag_thermal"])
		G_F=[G_F_E;]
		G_RPS_E = findall(x -> x in ["Hydro", "MSW", "Bio", "Landfill_NG", "WindOn","WindOff","SolarPV"], Gendata[:,"Type"])
		G_RPS = [G_RPS_E;]
		#Set of dispatchable generators, subsets of G
		G_exist=[g for g=1:Num_gen]										#Set of existing generation units, index g, subset of G  
		G_i=[findall(Gendata[:,"Zone"].==Idx_zone_dict[i]) for i in I]						#Set of generating units connected to zone i, subset of G  
		if config_set["unit_commitment"] !=0
			G_UC = findall(x -> x in [1], Gendata[:,"Flag_UC"])
		end
		HD = [h for h in 1:24]											#Set of hours in one day, index h, subset of H
		H_D = [h for h in 0:24:8760]
		H_t=[Load_tp_match[t].Hour for t in T]							#Set of hours in time period (day) t, index h, subset of H
		H_T = collect(unique(reduce(vcat,H_t)))							#Set of unique hours in time period, index h, subset of H
		S_exist=[s for s=1:Num_sto]										#Set of existing storage units, subset of S  
		S_i=[findall(Storagedata[:,"Zone"].==Idx_zone_dict[i]) for i in I]				#Set of storage units connected to zone i, subset of S  
		L_exist=[l for l=1:Num_Eline]									#Set of existing transmission corridors
		LS_i=[findall(Linedata[:,"From_zone"].==Idx_zone_dict[i]) for i in I]	#Set of sending transmission corridors of zone i, subset of L
		LR_i=[findall(Linedata[:,"To_zone"].==Idx_zone_dict[i]) for i in I]		#Set of receiving transmission corridors of zone i， subset of L
		IL_l = Dict(zip(L,[[i,j] for i in map(x -> Zone_idx_dict[x],Linedata[:,"From_zone"]) for j in map(x -> Zone_idx_dict[x],Linedata[:,"To_zone"])]))
		I_w=Dict(zip(W, [findall(Zonedata[:,"State"].== w) for w in W]))	#Set of zones in state w, subset of I
		WER_w=Dict(zip(unique(RPSdata[:, :From_state]),[RPSdata[findall(RPSdata[:,"From_state"].==i),"To_state"] for i in unique(RPSdata[:, :From_state])]))		#Set of states that state w can import renewable credits from (includes w itself), subset of W
		[WER_w[w] = [] for w in unique(RPSdata[:, :From_state]) if [w] == WER_w[w]]
		WIR_w=Dict(zip(unique(RPSdata[:, :From_state]), unique(push!(RPSdata[findall(RPSdata[:,"From_state"].==i),"To_state"], i)) for i in unique(RPSdata[:, :From_state])))					#Set of states that state w can export renewable credits to (excludes w itself), subset of W

		G_L = Dict(zip([l for l in L], [G_i[i] for l in L for i in IL_l[l]]))			#Set of generation units that linked to line l, index g, subset of G

		#Parameters--------------------------------------------
		ALW = Dict((row["Time Period"], row["State"]) => row["Allowance (tons)"] for row in eachrow(CBPdata))#(t,w)														#Total carbon allowance in time period t in state w, ton
		#AFRES=Dict([(g, h, i) => Solardata[:,Idx_zone_dict[i]][h] for g in G_PV for h in H for i in I])#(g,h,i)												#Availability factor of renewable energy source g in hour h in zone i, g∈G^PV∪G^W 
		#AFREW=Dict([(g, h, i) => Winddata[:,Idx_zone_dict[i]][h] for g in G_W for h in H for i in I])#(g,h,i)													#Availability factor of renewable energy source g in hour h in zone i, g∈G^PV∪G^W 
		#AFRES_tg = Dict([(t,g) => Dict([(h, i) => Solar_rep[t][:,Idx_zone_dict[i]][h] for h in H[t] for i in I]) for t in T for g in G_PV])
		#AFREW_tg = Dict([(t,g) => Dict([(h, i) => Wind_rep[t][:,Idx_zone_dict[i]][h] for h in H[t] for i in I]) for t in T for g in G_W])
		#AFRE_tg = merge(+, AFRES_tg, AFREW_tg)
		BM = SinglePardata[1,"BigM"];														#big M penalty
		CC_g = [Gendata[:,"CC"];]#g       		#Capacity credit of generating units, unitless
		CC_s = [Storagedata[:,"CC"];]#s  #Capacity credit of storage units, unitless
		CP=29#g $/ton													#Carbon price of generation g〖∈G〗^F, M$/t (∑_(g∈G^F,t∈T)〖〖CP〗_g  .N_t.∑_(h∈H_t)p_(g,h) 〗)
		EF=[Gendata[:,"EF"];]#g				#Carbon emission factor of generator g, t/MWh
		ELMT=Dict(zip(CBP_state_data[!,"State"],CBP_state_data[!,"Allowance (tons)_sum"]))#w							#Carbon emission limits at state w, t
		F_max=[Linedata[!,"Capacity (MW)"];]#l			#Maximum capacity of transmission corridor/line l, MW
		FOR_g = Dict(zip(G,Gendata[:,Symbol("FOR")]))#g					#Forced outage rate
		#N=get_TPmatched_ts(Loaddata,time_periods,Ordered_zone_nm)[2]#t						#Number of time periods (days) represented by time period (day) t per year, ∑_(t∈T)▒〖N_t.|H_t |〗= 8760
		NI=Dict([(i,h) =>-NIdata[h]*(Zonedata[:,"Demand (MW)"][i]/sum(Zonedata[:,"Demand (MW)"])) for i in I for h in H])#IH	#Net imports in zone i in h, MWh
		#NI_t = Dict([t => Dict([(i,h) =>Load_rep[t][!,"NI"][h]*(Zonedata[:,"Demand (MW)"][i]/sum(Zonedata[:,"Demand (MW)"])) for i in I for h in H_t[t]]) for t in T]) #tih
		#P=Dict([(d,h) => Loaddata[:,Idx_zone_dict[d]][h] for d in D for h in H])#d,h			#Active power demand of d in hour h, MW
		P_t = Loaddata_ordered
		PK=Zonedata[:,"Demand (MW)"]#i						#Peak power demand, MW
		PT_rps=SinglePardata[1, "PT_RPS"]											#RPS volitation penalty, $/MWh
		PT_emis=SinglePardata[1, "PT_emis"]										#Carbon emission volitation penalty, $/t
		P_min=[Gendata[:,"Pmin (MW)"];]#g						#Minimum power generation of unit g, MW
		P_max=[Gendata[:,"Pmax (MW)"];]#g						#Maximum power generation of unit g, MW
		RPS=Dict(zip(RPSdata[:,:From_state],RPSdata[:,:RPS]))							#w						#Renewable portfolio standard in state w,  unitless
		#RM=0.02#											#Planning reserve margin, unitless
		RM_SPIN_g = Dict(zip(G,Gendata[:,Symbol("RM_SPIN")]))
		RU_g = Dict(zip(G,Gendata[:,Symbol("RU")]))
		RD_g = Dict(zip(G,Gendata[:,Symbol("RD")]))
		SECAP=[Storagedata[:,"Capacity (MWh)"];]#s		#Maximum energy capacity of storage unit s, MWh
		SCAP=[Storagedata[:,"Max Power (MW)"];]#s		#Maximum capacity of storage unit s, MWh
		SC=[Storagedata[:,"Charging Rate"];]#s									#The maximum rates of charging, unitless
		SD=[Storagedata[:,"Discharging Rate"];]#s									#The maximum rates of discharging, unitless
		VCG=[Gencostdata;]#g						#Variable cost of generation unit g, $/MWh
		VCS=[Storagedata[:,Symbol("Cost (\$/MWh)")];]#s					#Variable (degradation) cost of storage unit s, $/MWh
		VOLL=SinglePardata[1, "VOLL"]#d										#Value of loss of load d, $/MWh
		e_ch=[Storagedata[:,"Charging efficiency"];]#s				#Charging efficiency of storage unit s, unitless
		e_dis=[Storagedata[:,"Discharging efficiency"];]#s		#Discharging efficiency of storage unit s, unitless
			
		#for multiple time period, we need to use following TS parameters
		#NI_t = Dict([t => Dict([(h,i) =>-Loaddata[!,"NI"][h]*(Zonedata[:,"Demand (MW)"][i]/sum(Zonedata[:,"Demand (MW)"])) for i in I for h in H_t[t]]) for t in T]) #tih
		NI_h = Dict([(h,i)=>-Loaddata[!,"NI"][h]*(Zonedata[:,"Demand (MW)"][i]/sum(Zonedata[:,"Demand (MW)"])) for i in I for h in H])
		P_t = Loaddata_ordered  #hi
		
		#For T
		#AFRES_tg = Dict([(t,g) => Dict([(h, i) => Solardata_ordered[:,Idx_zone_dict[i]][h] for i in I for h in H_t[t] ]) for t in T for g in G_PV])
		#AFREW_tg = Dict([(t,g) => Dict([(h, i) => Winddata_ordered[:,Idx_zone_dict[i]][h] for h in H_t[t] for i in I]) for t in T for g in G_W])
		#AFRE_tg = merge(+, AFRES_tg, AFREW_tg)#[t,g][h,i]
		
		AFRES_hg = Dict([(g) => Dict([(h, i) => Solardata[:,Idx_zone_dict[i]][h] for h in H for i in I]) for g in G_PV])
		AFREW_hg = Dict([(g) => Dict([(h, i) => Winddata[:,Idx_zone_dict[i]][h] for h in H for i in I]) for g in G_W])
		AFRE_hg = merge(+, AFRES_hg, AFREW_hg)#[g][h,i]
			
		unit_converter = 10^6



		model=Model(OPTIMIZER)
		#Variables---------------------------------------------
		@variable(model, a[G,T]>=0) 							#Bidding carbon allowance of unit g in time period t, ton
		@variable(model, b[G,T]>=0) 							#Banking of allowance of g in time period t, ton
	#	@variable(model, f[G,L,T,H])							#Active power in transmission corridor/line l in h from resrource g, MW
		@variable(model, f[L,H])							#Active power in transmission corridor/line l in h, MW
		@variable(model, em_emis[W]>=0)							#Carbon emission violated emission limit in state  w, ton
		@variable(model, ni[H,I])							#net import used in i
		@variable(model, p[G,H]>=0)							#Active power generation of unit g in hour h, MW
		@variable(model, pw[G,W]>=0)							#Total renewable generation of unit g in state w, MWh
		@variable(model, p_LS[D,H]>=0)						#Load shedding of demand d in hour h, MW
		@variable(model, pt_rps[W,H]>=0)							#Amount of active power violated RPS policy in state w, MW
		@variable(model, pwi[G,W,W_prime]>=0)					#State w imported renewable credits from state w' annually, MWh	
		@variable(model, r_G[G,H]>=0)							#Spining reserve for g in h				#r_(g,h)^G
		@variable(model, r_S[S,H]>=0)							#Spining reserve for s in h				#r_(s,h)^S
		@variable(model, soc[S,H]>=0)						#State of charge level of storage s in hour h, MWh
		@variable(model, c[S,H]==0)							#Charging power of storage s from grid in hour h, MW
		@variable(model, dc[S,H]==0)						#Discharging power of storage s into grid in hour h, MW
		#@variable(model, slack_pos[H,I]>=0)					#Slack varbale for debuging
		#@variable(model, slack_neg[H,I]>=0)					#Slack varbale for debuging
		#unregister(model, :p)

		#Temporaty constraint for debugging
		#@constraint(model, [g in G_new], x[g]==0);
		#@constraint(model, [l in L_new], y[l]==0);
		#@constraint(model, [s in S_new], z[s]==0);

		if config_set["unit_commitment"]!=0
			unit_commitment!(config_set, input_data, model)
		elseif config_set["unit_commitment"]>2
			uc_set = config_set["unit_commitment"]
			print("Invalid settings $uc_set for unit_commitment! Please set it tobe '0' or '1' or '2'!")
		end
		#Constraints--------------------------------------------
		
		#(3) Power balance: power generation from generators + power generation from storages + power transmissed + net import = Load demand - Loadshedding	
			PB_con = @constraint(model, [i in I, h in H], sum(p[g,h] for g in G_i[i]) 
			+ sum(dc[s,h] - c[s,h] for s in S_i[i])
			- sum(f[l,h] for l in LS_i[i])#LS
			+ sum(f[l,h] for l in LR_i[i])#LR
			+ ni[h,i]
			#+ slack_pos[h,i]-slack_neg[h,i]
			== sum(P_t[h,i]*PK[i] - p_LS[d,h] for d in D_i[i]),base_name = "PB_con"); 
		
			#TC_con =  @constraint(model, [i in I, t in T, h in H_t[t]], - sum(f[l,t,h] for l in LS_i[i]) == sum(f[l,t,h] for l in LR_i[i]),base_name = "TC_con" )
			NI_con = @constraint(model, [h in H, i in I], ni[h,i] <= NI_h[h,i],base_name = "NI_con")
		
		#(4) Transissim power flow limit for existing lines	
		TLe_con = @constraint(model, [l in L_exist,h in H], -F_max[l] <= f[l,h] <= F_max[l],base_name = "TLe_con")

		if config_set["unit_commitment"] == 0
			#(5) Maximum capacity limits for existing power generator
			CLe_con = @constraint(model, [g in G_exist, h in H], P_min[g] <= p[g,h] +r_G[g,h] <= (1-FOR_g[g])*P_max[g],base_name = "CLe_con")
		
			#(6) Spining reserve
			SPIN_con = @constraint(model, [g in G_exist, h in H], r_G[g,h] <= RM_SPIN_g[g]*(1-FOR_g[g])*P_max[g],base_name = "SPIN_con")
		
			#(7) Ramp up limits
			RP_UP_con = @constraint(model, [g in G_F, h in setdiff(H, [1])],  p[g,h] +r_G[g,h]-p[g,h-1]<= RU_g[g]*(1-FOR_g[g])*P_max[g],base_name = "RP_UP_con" )
		
			#(8) Ramp down limits
			RP_DN_con = @constraint(model, [g in G_F, h in setdiff(H, [1])],  p[g,h] +r_G[g,h]-p[g,h-1]>= -RD_g[g]*(1-FOR_g[g])*P_max[g],base_name = "RP_DN_con" )
		else
			#(5) Maximum capacity limits for existing power generator
			CLe_con = @constraint(model, [g in setdiff(G_exist,G_UC), h in H], P_min[g] <= p[g,h] +r_G[g,h] <= (1-FOR_g[g])*P_max[g],base_name = "CLe_con")
			CLeL_con = @constraint(model, [g in G_UC, h in H], P_min[g] <= p[g,h] +r_G[g,h] ,base_name = "CLeL_con")
			CLeU_con = @constraint(model, [g in G_UC, h in H], p[g,h] +r_G[g,h] <= (1-FOR_g[g])*P_max[g]*model[:o][g,h],base_name = "CLeU_con")
			#(6) Spining reserve
			SPIN_con = @constraint(model, [g in setdiff(G_exist,G_UC), h in H], r_G[g,h] <= RM_SPIN_g[g]*(1-FOR_g[g])*P_max[g],base_name = "SPIN_con")
			SPINUC_con = @constraint(model, [g in G_UC, h in H], r_G[g,h] <= RM_SPIN_g[g]*(1-FOR_g[g])*P_max[g]*model[:o][g,h],base_name = "SPINUC_con")
	
			#(7) Ramp up limits
			RP_UP_con = @constraint(model, [g in setdiff(G_F,G_UC), h in setdiff(H, [1])],  p[g,h] +r_G[g,h]-p[g,h-1]<= RU_g[g]*(1-FOR_g[g])*P_max[g],base_name = "RP_UP_con" )
			RP_UP_UC_con = @constraint(model, [g in G_UC, h in setdiff(H, [1])],  p[g,h] +r_G[g,h] - model[:pmin][g,h] - (p[g,h-1]-model[:pmin][g,h-1])<= RU_g[g]*(1-FOR_g[g])*P_max[g]*model[:o][g,h],base_name = "RP_UP_UC_con" )
		
			#(8) Ramp down limits
			RP_DN_con = @constraint(model, [g in setdiff(G_F,G_UC), h in setdiff(H, [1])],  p[g,h] +r_G[g,h]-p[g,h-1]>= -RD_g[g]*(1-FOR_g[g])*P_max[g],base_name = "RP_DN_con" )
			RP_DN_UC_con = @constraint(model, [g in G_UC, h in setdiff(H, [1])],  (p[g,h]-model[:pmin][g,h]) - (r_G[g,h]+p[g,h-1] - model[:pmin][g,h-1])>= -RD_g[g]*(1-FOR_g[g])*P_max[g]*model[:o][g,h],base_name = "RP_DN_UC_con" )
			
		end

		#(9) Load shedding limit	
		LS_con = @constraint(model, [i in I, d in D_i[i], h in H], 0 <= p_LS[d,h]<= P_t[h,i]*PK[i],base_name = "LS_con")
		
		
		##############
		##Renewbales##
		##############
		#(10) Renewables generation availability for the existing plants: p_(g,h)≤AFRE_(g,h)∙P_g^max; ∀h∈H_t,g∈G^E∩(G^PV∪G^W)  
		ReAe_con=@constraint(model, [i in I, g in intersect(G_exist,G_i[i],union(G_PV,G_W)), h in H], p[g,h] <= AFRE_hg[g][h,i]*P_max[g],base_name = "ReAe_con")

		
		
		
		##############
		###Storages###
		##############
		#(11) Storage charging rate limit for existing units
		ChLe_con=@constraint(model, [ h in H, s in S_exist], c[s,h]/SC[s] <= SCAP[s],base_name = "ChLe_con")
		
		#(12) Storage discharging rate limit for existing units
		DChLe_con=@constraint(model, [ h in H,  s in S_exist], dc[s,h]/SD[s] <= SCAP[s],base_name = "DChLe_con")
		
		#(13) State of charge limit for existing units: 0≤ soc_(s,h) ≤ SCAP_s;   ∀h∈H_t,t∈T,s∈ S^E
		SoCLe_con=@constraint(model, [ h in H, s in S_exist], 0 <= soc[s,h] <= SECAP[s], base_name = "SoCLe_con")
		#(14) Spining reserve provided by storage 〖dc〗_(s,h)+r_(s,h)^S  ≤〖SD〗_s∙〖SCAP〗_s;   ∀ h∈H
		#SR_ES_con = @constraint(model, [h in H, s in S_exist], dc[s,h] + r_S[s,h] <= SD[s]* SCAP[s],base_name = "SR_ES_con")
		#(15) Storage operation constraints
		SoC_con=@constraint(model, [t in T, h in setdiff(H, [1]),s in S_exist], soc[s,h] == soc[s,h-1] + e_ch[s]*c[s,h] - dc[s,h]/e_dis[s],base_name = "SoC_con")
		#Ch_1_con=@constraint(model, [t in T, s in S], c[s,t,1] ==0)
		#DCh_1_con=@constraint(model, [t in T, s in S], dc[s,t,1] ==0)
		
		#(16) Daily 50% of storage level balancing for existing units
		SDBe_st_con=@constraint(model, [s in S_exist], soc[s,1] == soc[s,end],base_name = "SDBe_st_con")
		SDBe_ps_con=@constraint(model, [s in S_exist, h in setdiff(H_D, [0,8760])],soc[s,1]==soc[s,h],base_name="SDBe_ps_con")
		SDBe_ed_con=@constraint(model, [s in S_exist], soc[s,end] == 0.5 * SECAP[s],base_name = "SDBe_ed_con")
		
		

		##############
		##RPSPolices##
		##############
		#(17) RPS, state level total Defining
		RPS_pw_con = @constraint(model, [w in W, g in intersect(union([G_i[i] for i in I_w[w]]...),G_RPS)],
							pw[g,w] == sum(p[g,h] for h in H), base_name = "RPS_pw_con")

		
		#(18) State renewable credits export limitation 
		RPS_expt_con = @constraint(model, [w in W, g in intersect(union([G_i[i] for i in I_w[w]]...),G_RPS) ], pw[g,w] >= sum(pwi[g,w_prime,w] for w_prime in WER_w[w]), base_name = "RPS_expt_con")

		#(19) State renewable credits import limitation 
		RPS_impt_con = @constraint(model, [w in W, w_prime in WIR_w[w],g in intersect(union([G_i[i] for i in I_w[w_prime]]...),G_RPS)], pw[g,w_prime] >= pwi[g,w,w_prime], base_name = "RPS_impt_con")

		#(20) Renewable credits trading meets state RPS requirements
		RPS_con = @constraint(model, [w in W], sum(pwi[g,w,w_prime]  for w_prime in WIR_w[w] for g in intersect(union([G_i[i] for i in I_w[w_prime]]...),G_RPS))
									- sum(pwi[g,w_prime,w] for w_prime in WER_w[w] for g in intersect(union([G_i[i] for i in I_w[w]]...),G_RPS))
									+ sum(pt_rps[w,h] for h in H)
									>= sum(sum(P_t[h,i]*PK[i]*RPS[w] for d in D_i[i]) for i in I_w[w] for h in H), base_name = "RPS_con") 
		
		###############
		#CarbonPolices#				
		###############
		#(21) State carbon emission limit
		CL_con = @constraint(model, [w in W], sum(sum(sum(EF[g]*p[g,h] for g in intersect(G_F,G_i[i]) for h in H) for t in T) for i in I_w[w])<=ELMT[w], base_name = "CL_con")


		
		#=
		##Cap & Trade##
		#(22) State carbon allowance cap
		SCAL_con = @constraint(model, [w in W, t in T], sum(a[g,t] for g in intersect(union([G_i[i] for i in I_w[w]]...), G_F)) - em_emis[w] <= ALW[t,w],base_name = "SCAL_con")

		#(23) Balance between allowances and write_emissions
		BAL_con = @constraint(model, [w in W, g in intersect(union([G_i[i] for i in I_w[w]]...), G_F), t in setdiff(T,[1])], sum(EF[g]*p[g,h] for h in H_t[t]) == a[g,t]+b[g,t-1]-b[g,t],base_name = "BAL_con")

		#(24) No cross-year banking
		NCrY_in_con = @constraint(model, [g in G_F], b[g,1] == b[g,end],base_name="NCrY_in_con")
		NCrY_end_con = @constraint(model, [g in G_F], b[g,end] == 0, base_name="NCrY_end_con")
		=#

		#Objective function and solve--------------------------
		#Investment cost of generator, lines, and storages
		#@expression(model, INVCost, sum(INV_g[g]*unit_converter*x[g] for g in G_new)+sum(INV_l[l]*unit_converter*y[l] for l in L_new)+sum(INV_s[s]*unit_converter*z[s] for s in S_new))			
		

		#Operation cost of generator and storages
		@expression(model, OPCost, sum(VCG[g]*sum(p[g,h] for h in H) for g in G)
					+ sum(VCS[s]*sum(c[s,h]+dc[s,h] for h in H) for s in S)
					)	

		#Loss of load penalty
		@expression(model, LoadShedding, sum(VOLL*sum(p_LS[d,h] for h in H) for d in D))

		#RPS volitation penalty
		@expression(model, RPSPenalty, PT_rps*sum(pt_rps[w,h] for w in W for h in H))

		#Carbon cap volitation penalty
		@expression(model, CarbonCapPenalty, PT_emis*sum(em_emis[w] for w in W))
		@expression(model, CarbonEmission[w in W], sum(EF[g]*p[g,h] for g in intersect(union([G_i[i] for i in I_w[w]]...), G_F) for t in T for h in H_t[t] ))
		#Slack variable penalty
		#@expression(model, SlackPenalty, BM *sum(slack_pos[h,i]+slack_neg[h,i] for h in H for i in I))

		#Minmize objective fuction: INVCost + OPCost + RPSPenalty + CarbonCapPenalty + SlackPenalty
		if config_set["unit_commitment"] == 0
			@objective(model,Min, OPCost + LoadShedding + RPSPenalty + CarbonCapPenalty)#+ SlackPenalty
		else
			@objective(model,Min, model[:STCost] + OPCost + LoadShedding + RPSPenalty + CarbonCapPenalty)
		end
		return model
	end
end 
