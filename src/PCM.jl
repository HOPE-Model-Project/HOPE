function get_TPmatched_ts(df, time_periods, ordered_zone)
    #k = 1# Cluster the time series data to find a representative day
    # Function to filter rows based on the season's start and end dates
    filter_time_period(time_period, row) = (row.Month == time_period[1] && row.Day >= time_period[2]) || (row.Month == time_period[3] && row.Day <= time_period[4]) || (row.Month > time_period[1] && row.Month < time_period[3])|| ( time_period[1]>time_period[3] && row.Month < time_period[3])
    # Initialize a dictionary to store the representative days and number of days for each season  
    rep_dat_dict=Dict()
    ndays_dict=Dict()
	
	n_hour = size(df, 1)
	df.Hour = [h for h in 1:n_hour]

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
	Num_hour=size(input_data["Loaddata"],1)
	#UC sets
	G = [g for g=1:Num_gen]									#Set of all types of generating units, index g
	G_UC = findall(x -> x in [1], Gendata[:,"Flag_UC"])
	H=[h for h=1:Num_hour]									#Set of hours, index h
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
	MUT_con = @constraint(model, [g in G_UC, h in Int.(UT_g[g]+1):H[end]], sum(su[g,hr] for hr in (h-UT_g[g]+1):h) <= o[g,h],base_name = "MUT_con")
		
	#(27) Minimum down time constraint
	MDT_con = @constraint(model, [g in G_UC, h in Int(DT_g[g]+1):H[end]], sum(sd[g,hr] for hr in (h-DT_g[g]+1):h) <= 1-o[g,h],base_name = "MDT_con")
		
	#(28) pmin variable bound
	PMINB_con = @constraint(model, [g in G_UC, h in H], pmin[g,h] <= model[:p][g,h],base_name = "PMINB_con")
	# Startup-cost objective term is assembled in create_PCM_model to avoid duplicate model names.
end

function create_PCM_model(config_set::Dict,input_data::Dict,OPTIMIZER::MOI.OptimizerWithAttributes)
	model_mode = config_set["model_mode"]
	if model_mode == "GTEP"
		return "ModeError: Please use function 'create_GTEP_model' or set model mode to be 'PCM'!" 
	elseif model_mode == "PCM" 
		# Policy switches (aligned with GTEP):
		# carbon_policy: 0 off; 1 emissions cap; 2 cap-and-trade
		carbon_policy_raw = get(config_set, "carbon_policy", 1)
		carbon_policy = carbon_policy_raw isa Integer ? Int(carbon_policy_raw) : parse(Int, string(carbon_policy_raw))
		if !(carbon_policy in [0, 1, 2])
			throw(ArgumentError("Invalid carbon_policy=$(carbon_policy). Expected 0, 1, or 2."))
		end
		# clean_energy_policy: 0 off; 1 enforce RPS
		clean_energy_policy_raw = get(config_set, "clean_energy_policy", 1)
		clean_energy_policy = clean_energy_policy_raw isa Integer ? Int(clean_energy_policy_raw) : parse(Int, string(clean_energy_policy_raw))
		if !(clean_energy_policy in [0, 1])
			throw(ArgumentError("Invalid clean_energy_policy=$(clean_energy_policy). Expected 0 or 1."))
		end
		# operation_reserve_mode:
		# 0 = disable operation reserve constraints
		# 1 = REG + SPIN reserve (NSPIN disabled)
		# 2 = REG + SPIN + NSPIN reserve
		operation_reserve_mode_raw = get(config_set, "operation_reserve_mode", 0)
		operation_reserve_mode = operation_reserve_mode_raw isa Integer ? Int(operation_reserve_mode_raw) : parse(Int, string(operation_reserve_mode_raw))
		if !(operation_reserve_mode in [0, 1, 2])
			throw(ArgumentError("Invalid operation_reserve_mode=$(operation_reserve_mode). Expected 0, 1, or 2."))
		end
		# flexible_demand:
		# 0 = disable DR variables/constraints
		# 1 = enable DR variables/constraints
		flexible_demand_raw = get(config_set, "flexible_demand", 0)
		flexible_demand = flexible_demand_raw isa Integer ? Int(flexible_demand_raw) : parse(Int, string(flexible_demand_raw))
		if !(flexible_demand in [0, 1])
			throw(ArgumentError("Invalid flexible_demand=$(flexible_demand). Expected 0 or 1."))
		end
		# network_model:
		# 0 = no network constraints (copper plate)
		# 1 = zonal transport
		# 2 = nodal DCOPF angle-based
		# 3 = nodal DCOPF PTDF-based
		network_model_raw = get(config_set, "network_model", 0)
		network_model = network_model_raw isa Integer ? Int(network_model_raw) : parse(Int, string(network_model_raw))
		if !(network_model in [0, 1, 2, 3])
			throw(ArgumentError("Invalid network_model=$(network_model). Expected 0, 1, 2, or 3."))
		end
	
		#network
		Zonedata = input_data["Zonedata"]
		Linedata = input_data["Linedata"]
		Busdata = haskey(input_data, "Busdata") ? input_data["Busdata"] : nothing
		Branchdata = haskey(input_data, "Branchdata") ? input_data["Branchdata"] : nothing
		if network_model in [2, 3] && Branchdata !== nothing
			Linedata = Branchdata
		end
		#technology
		Gendata = input_data["Gendata"]
		Storagedata = input_data["Storagedata"]
		Gencostdata = input_data["Gendata"][:,Symbol("Cost (\$/MWh)")]
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
		
		#DR related
		if flexible_demand == 1
			DRdata = input_data["DRdata"]
			DRtsdata = input_data["DRtsdata"]
			#[findall(row -> row.Zone == Idx_zone_dict[i], eachrow(DRdata))[1] for i=1:Num_zone] #reorder 
			DRC_d = [DRdata[idx, "Cost (\$/MW)"] for idx in [findall(row -> row.Zone == Idx_zone_dict[i], eachrow(DRdata))[1] for i=1:Num_zone]]
			DR_MAX = [DRdata[idx, "Max Power (MW)"] for idx in [findall(row -> row.Zone == Idx_zone_dict[i], eachrow(DRdata))[1] for i=1:Num_zone]]
			DR_tp_match = get_TPmatched_ts(DRtsdata,time_periods,Ordered_zone_nm)[1]
			DRdata_ordered = select(DRtsdata, [Ordered_zone_nm;"Hour"])
			DR_t = DRdata_ordered
		end
		#Sets--------------------------------------------------
		D=[d for d=1:Num_load] 									#Set of demand, index d
		G=[g for g=1:Num_gen]							#Set of all types of generating units, index g
		K=unique(Gendata[:,"Type"]) 							#Set of technology types, index k
		Num_hour = size(Loaddata,1)
		H=[h for h=1:Num_hour]									#Set of hours, index h
		T=[t for t=1:length(time_periods)]								#Set of time periods (e.g., representative days of seasons), index t
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
		G_MR_E=findall(x -> x in [1], Gendata[:,"Flag_mustrun"])
		G_MR = [G_MR_E;]
		G_RPS_E = findall(x -> x in ["Hydro", "MSW", "Bio", "Landfill_NG", "WindOn","WindOff","SolarPV"], Gendata[:,"Type"])
		G_RPS = [G_RPS_E;]
		#Set of dispatchable generators, subsets of G
		G_exist=[g for g=1:Num_gen]										#Set of existing generation units, index g, subset of G  
		G_i=[findall(Gendata[:,"Zone"].==Idx_zone_dict[i]) for i in I]						#Set of generating units connected to zone i, subset of G  
		if config_set["unit_commitment"] !=0
			G_UC = findall(x -> x in [1], Gendata[:,"Flag_UC"])
		end
		HD = [h for h in 1:24]											#Set of hours in one day, index h, subset of H
		H_D = [h for h in 0:24:Num_hour]
		H_t=[Load_tp_match[t].Hour for t in T]							#Set of hours in time period (day) t, index h, subset of H
		H_T = collect(unique(reduce(vcat,H_t)))							#Set of unique hours in time period, index h, subset of H
		S_exist=[s for s=1:Num_sto]										#Set of existing storage units, subset of S  
		S_i=[findall(Storagedata[:,"Zone"].==Idx_zone_dict[i]) for i in I]				#Set of storage units connected to zone i, subset of S  
		#print(S_exist)
		L_exist=[l for l=1:Num_Eline]									#Set of existing transmission corridors
		linedata_cols = Set(string.(names(Linedata)))
		from_zone_col = first_existing_col(linedata_cols, ["From_zone", "from_zone"])
		to_zone_col = first_existing_col(linedata_cols, ["To_zone", "to_zone"])
		from_bus_col = first_existing_col(linedata_cols, ["from_bus", "From_bus", "f_bus", "F_BUS"])
		to_bus_col = first_existing_col(linedata_cols, ["to_bus", "To_bus", "t_bus", "T_BUS"])
		if (from_zone_col === nothing || to_zone_col === nothing) && Busdata !== nothing
			bus_cols = Set(string.(names(Busdata)))
			bus_id_col = first_existing_col(bus_cols, ["Bus_id", "bus_id", "bus_i", "BUS_I", "Bus"])
			bus_zone_col = first_existing_col(bus_cols, ["Zone_id", "zone_id", "Zone", "zone"])
			if bus_id_col !== nothing && bus_zone_col !== nothing && from_bus_col !== nothing && to_bus_col !== nothing
				bus_zone_map = Dict(Busdata[r, bus_id_col] => Busdata[r, bus_zone_col] for r in 1:size(Busdata, 1))
				Linedata = copy(Linedata)
				Linedata[!, "From_zone"] = [haskey(bus_zone_map, Linedata[l, from_bus_col]) ? bus_zone_map[Linedata[l, from_bus_col]] : missing for l in L]
				Linedata[!, "To_zone"] = [haskey(bus_zone_map, Linedata[l, to_bus_col]) ? bus_zone_map[Linedata[l, to_bus_col]] : missing for l in L]
				from_zone_col = "From_zone"
				to_zone_col = "To_zone"
			end
		end
		if from_zone_col === nothing || to_zone_col === nothing
			throw(ArgumentError("Linedata must include From_zone/To_zone (or provide Busdata with bus-to-zone mapping)."))
		end
		if from_bus_col === nothing || to_bus_col === nothing
			Linedata = copy(Linedata)
			Linedata[!, "from_bus"] = [Linedata[l, from_zone_col] for l in L]
			Linedata[!, "to_bus"] = [Linedata[l, to_zone_col] for l in L]
			from_bus_col = "from_bus"
			to_bus_col = "to_bus"
		end
		LS_i=[findall(Linedata[:,from_zone_col].==Idx_zone_dict[i]) for i in I]
		LR_i=[findall(Linedata[:,to_zone_col].==Idx_zone_dict[i]) for i in I]
		IL_l = Dict(l => [Zone_idx_dict[Linedata[l, from_zone_col]], Zone_idx_dict[Linedata[l, to_zone_col]]] for l in L)
		L_from_i = Dict(l => IL_l[l][1] for l in L)
		L_to_i = Dict(l => IL_l[l][2] for l in L)
		# Nodal layer (active only when network_model in [2,3])
		bus_labels = Any[]
		bus_to_zone_idx = Dict{Any,Int}()
		if network_model in [2, 3]
			if Busdata !== nothing
				bus_cols = Set(string.(names(Busdata)))
				bus_id_col = first_existing_col(bus_cols, ["Bus_id", "bus_id", "bus_i", "BUS_I", "Bus"])
				bus_zone_col = first_existing_col(bus_cols, ["Zone_id", "zone_id", "Zone", "zone"])
				if bus_id_col === nothing || bus_zone_col === nothing
					throw(ArgumentError("Busdata for nodal mode must include Bus_id and Zone_id (or equivalent)."))
				end
				bus_labels = [Busdata[r, bus_id_col] for r in 1:size(Busdata, 1)]
				for r in 1:size(Busdata, 1)
					zone_nm = Busdata[r, bus_zone_col]
					if !haskey(Zone_idx_dict, zone_nm)
						throw(ArgumentError("Busdata row $(r) has zone $(zone_nm) not found in zonedata.Zone_id."))
					end
					bus_to_zone_idx[Busdata[r, bus_id_col]] = Zone_idx_dict[zone_nm]
				end
			else
				bus_labels = collect(unique(vcat([Linedata[l, from_bus_col] for l in L], [Linedata[l, to_bus_col] for l in L])))
				for l in L
					bus_to_zone_idx[Linedata[l, from_bus_col]] = Zone_idx_dict[Linedata[l, from_zone_col]]
					bus_to_zone_idx[Linedata[l, to_bus_col]] = Zone_idx_dict[Linedata[l, to_zone_col]]
				end
			end
		end
		Bus_idx_dict = Dict(bus_labels[n] => n for n in 1:length(bus_labels))
		N = [n for n in 1:length(bus_labels)]
		if network_model in [2, 3] && isempty(N)
			throw(ArgumentError("Nodal network_model=$(network_model) requires non-empty bus set. Provide busdata/branchdata (or linedata with from_bus/to_bus)."))
		end
		bus_zone_of_n = Dict{Int,Int}()
		if network_model in [2, 3]
			for n in N
				if !haskey(bus_to_zone_idx, bus_labels[n])
					throw(ArgumentError("No zone mapping found for bus $(bus_labels[n])."))
				end
				bus_zone_of_n[n] = bus_to_zone_idx[bus_labels[n]]
			end
		end
		N_i = [network_model in [2, 3] ? [n for n in N if haskey(bus_to_zone_idx, bus_labels[n]) && bus_to_zone_idx[bus_labels[n]] == i] : Int[] for i in I]
		L_from_n = Dict(l => (network_model in [2, 3] ? Bus_idx_dict[Linedata[l, from_bus_col]] : 0) for l in L)
		L_to_n = Dict(l => (network_model in [2, 3] ? Bus_idx_dict[Linedata[l, to_bus_col]] : 0) for l in L)
		LS_n = [network_model in [2, 3] ? findall(l -> L_from_n[l] == n, L) : Int[] for n in N]
		LR_n = [network_model in [2, 3] ? findall(l -> L_to_n[l] == n, L) : Int[] for n in N]
		G_n = [Int[] for _ in N]
		S_n = [Int[] for _ in N]
		bus_load_share = Dict{Int,Float64}()
		if network_model in [2, 3]
			gendata_cols_local = Set(string.(names(Gendata)))
			gen_bus_col = first_existing_col(gendata_cols_local, ["Bus_id", "bus_id", "Bus", "bus"])
			for g in G
				n_idx = if gen_bus_col !== nothing && haskey(Bus_idx_dict, Gendata[g, gen_bus_col])
					Bus_idx_dict[Gendata[g, gen_bus_col]]
				else
					zone_idx = Zone_idx_dict[Gendata[g, "Zone"]]
					isempty(N_i[zone_idx]) ? throw(ArgumentError("No buses found in zone $(Gendata[g, "Zone"]) for generator $(g).")) : N_i[zone_idx][1]
				end
				push!(G_n[n_idx], g)
			end
			st_cols_local = Set(string.(names(Storagedata)))
			st_bus_col = first_existing_col(st_cols_local, ["Bus_id", "bus_id", "Bus", "bus"])
			for s in S
				n_idx = if st_bus_col !== nothing && haskey(Bus_idx_dict, Storagedata[s, st_bus_col])
					Bus_idx_dict[Storagedata[s, st_bus_col]]
				else
					zone_idx = Zone_idx_dict[Storagedata[s, "Zone"]]
					isempty(N_i[zone_idx]) ? throw(ArgumentError("No buses found in zone $(Storagedata[s, "Zone"]) for storage $(s).")) : N_i[zone_idx][1]
				end
				push!(S_n[n_idx], s)
			end
			if Busdata !== nothing
				bus_cols = Set(string.(names(Busdata)))
				bus_id_col = first_existing_col(bus_cols, ["Bus_id", "bus_id", "bus_i", "BUS_I", "Bus"])
				load_share_col = first_existing_col(bus_cols, ["Load_share", "load_share", "Demand_share", "demand_share"])
				load_mw_col = first_existing_col(bus_cols, ["Demand (MW)", "Load (MW)", "Pd", "PD"])
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
						elseif load_share_col !== nothing
							raw[k_idx] = Float64(Busdata[row_idx, load_share_col])
						elseif load_mw_col !== nothing
							raw[k_idx] = Float64(Busdata[row_idx, load_mw_col])
						else
							raw[k_idx] = 1.0
						end
					end
					den = sum(raw)
					if den <= 0
						for n_idx in nodes
							bus_load_share[n_idx] = 1.0 / length(nodes)
						end
					else
						for (k_idx, n_idx) in enumerate(nodes)
							bus_load_share[n_idx] = raw[k_idx] / den
						end
					end
				end
			else
				for i in I
					nodes = N_i[i]
					if !isempty(nodes)
						for n_idx in nodes
							bus_load_share[n_idx] = 1.0 / length(nodes)
						end
					end
				end
			end
		end
		I_w=Dict(zip(W, [findall(Zonedata[:,"State"].== w) for w in W]))	#Set of zones in state w, subset of I
		WER_w = Dict{Any,Vector{Any}}() #Set of states that state w can export renewable credits to (excludes w itself), subset of W
		WIR_w = Dict{Any,Vector{Any}}() #Set of states that state w can import renewable credits from (excludes w itself), subset of W
		W_set = Set(W)
		for w in W
			export_targets = unique(RPSdata[RPSdata[:, "From_state"] .== w, "To_state"])
			import_sources = unique(RPSdata[RPSdata[:, "To_state"] .== w, "From_state"])
			WER_w[w] = [w_prime for w_prime in export_targets if (w_prime in W_set) && (w_prime != w)]
			WIR_w[w] = [w_prime for w_prime in import_sources if (w_prime in W_set) && (w_prime != w)]
		end

		G_L = Dict(zip([l for l in L], [G_i[i] for l in L for i in IL_l[l]]))			#Set of generation units that linked to line l, index g, subset of G

		#Parameters--------------------------------------------
		to_float(x) = x isa Number ? Float64(x) : parse(Float64, string(x))
		singlepar_cols = Set(string.(names(SinglePardata)))
		get_singlepar(name::AbstractString, default::Float64) = (name in singlepar_cols) ? to_float(SinglePardata[1, name]) : default
		gendata_cols = Set(string.(names(Gendata)))
		linedata_cols = Set(string.(names(Linedata)))
		ALW = Dict((row["Time Period"], row["State"]) => row["Allowance (tons)"] for row in eachrow(CBPdata))#(t,w)														#Total carbon allowance in time period t in state w, ton
		#AFRES=Dict([(g, h, i) => Solardata[:,Idx_zone_dict[i]][h] for g in G_PV for h in H for i in I])#(g,h,i)												#Availability factor of renewable energy source g in hour h in zone i, g∈G^PV∪G^W 
		#AFREW=Dict([(g, h, i) => Winddata[:,Idx_zone_dict[i]][h] for g in G_W for h in H for i in I])#(g,h,i)													#Availability factor of renewable energy source g in hour h in zone i, g∈G^PV∪G^W 
		#AFRES_tg = Dict([(t,g) => Dict([(h, i) => Solar_rep[t][:,Idx_zone_dict[i]][h] for h in H[t] for i in I]) for t in T for g in G_PV])
		#AFREW_tg = Dict([(t,g) => Dict([(h, i) => Wind_rep[t][:,Idx_zone_dict[i]][h] for h in H[t] for i in I]) for t in T for g in G_W])
		#AFRE_tg = merge(+, AFRES_tg, AFREW_tg)
		BM = get_singlepar("BigM", 1.0e10);												#big M penalty
		CC_g = [Gendata[:,"CC"];]#g       		#Capacity credit of generating units, unitless
		CC_s = [Storagedata[:,"CC"];]#s  #Capacity credit of storage units, unitless
		CP=29#g $/ton													#Carbon price of generation g〖∈G〗^F, M$/t (∑_(g∈G^F,t∈T)〖〖CP〗_g  .N_t.∑_(h∈H_t)p_(g,h) 〗)
		EF=[Gendata[:,"EF"];]#g				#Carbon emission factor of generator g, t/MWh
		ELMT=Dict(zip(CBP_state_data[!,"State"],CBP_state_data[!,"Allowance (tons)_sum"]))#w							#Carbon emission limits at state w, t
		ALW_state = Dict(zip(CBP_state_data[!,"State"],CBP_state_data[!,"Allowance (tons)_sum"])) #w			#Total annual carbon allowances by state
		F_max=[Linedata[!,"Capacity (MW)"];]#l			#Maximum capacity of transmission corridor/line l, MW
		if "X" in linedata_cols
			B_l = Dict(l => (to_float(Linedata[l, "X"]) == 0.0 ? 0.0 : 1.0 / to_float(Linedata[l, "X"])) for l in L)
		elseif "Reactance" in linedata_cols
			B_l = Dict(l => (to_float(Linedata[l, "Reactance"]) == 0.0 ? 0.0 : 1.0 / to_float(Linedata[l, "Reactance"])) for l in L)
		else
			if network_model == 2
				println("Warning: network_model=2 (nodal DCOPF-angle) but no line reactance column found (X/Reactance). Using unit susceptance B_l=1.0.")
			end
			B_l = Dict(l => 1.0 for l in L)
		end
		FOR_g = Dict(zip(G,Gendata[:,Symbol("FOR")]))#g					#Forced outage rate
		#N=get_TPmatched_ts(Loaddata,time_periods,Ordered_zone_nm)[2]#t						#Number of time periods (days) represented by time period (day) t per year, ∑_(t∈T)▒〖N_t.|H_t |〗= 8760
		NI=Dict([(i,h) =>NIdata[h]*(Zonedata[:,"Demand (MW)"][i]/sum(Zonedata[:,"Demand (MW)"])) for i in I for h in H])#IH	#Net imports in zone i in h, MWh
		#NI_t = Dict([t => Dict([(i,h) =>Load_rep[t][!,"NI"][h]*(Zonedata[:,"Demand (MW)"][i]/sum(Zonedata[:,"Demand (MW)"])) for i in I for h in H_t[t]]) for t in T]) #tih
		#P=Dict([(d,h) => Loaddata[:,Idx_zone_dict[d]][h] for d in D for h in H])#d,h			#Active power demand of d in hour h, MW
		P_t = Loaddata_ordered
		PK=Zonedata[:,"Demand (MW)"]#d						#Peak power demand, MW
		PT_rps = get_singlepar("PT_RPS", 1.0e13)									#RPS violation penalty, $/MWh
		PT_emis = get_singlepar("PT_emis", 1.0e13)								#Carbon emission violation penalty, $/t
		reg_up_requirement = get_singlepar("reg_up_requirement", 0.0)
		reg_dn_requirement = get_singlepar("reg_dn_requirement", 0.0)
		spin_requirement = get_singlepar("spin_requirement", 0.03)
		nspin_requirement = get_singlepar("nspin_requirement", 0.0)
		delta_reg = get_singlepar("delta_reg", 1.0 / 12.0)
		delta_spin = get_singlepar("delta_spin", 1.0 / 6.0)
		delta_nspin = get_singlepar("delta_nspin", 1.0 / 2.0)
		theta_max = get_singlepar("theta_max", 1.0e3)
		reference_bus_raw = get(config_set, "reference_bus", 1)
		reference_bus = if network_model in [2, 3]
			resolve_reference_index(reference_bus_raw, length(N), Bus_idx_dict, "bus")
		else
			resolve_reference_index(reference_bus_raw, length(I), Dict(Idx_zone_dict[i] => i for i in I), "zone")
		end
		PTDF_l_n = Dict{Tuple{Int,Int},Float64}()
		if network_model == 3
			ptdf_nodal_data = haskey(input_data, "PTDFNodalData") ? input_data["PTDFNodalData"] : (haskey(input_data, "PTDFdata") ? input_data["PTDFdata"] : nothing)
			ptdf_matrix = zeros(Float64, Num_Eline, length(N))
			if ptdf_nodal_data !== nothing
				ptdf_cols = Set(string.(names(ptdf_nodal_data)))
				missing_bus_cols = [string(bus_labels[n]) for n in N if !(string(bus_labels[n]) in ptdf_cols)]
				if !isempty(missing_bus_cols)
					throw(ArgumentError("Nodal PTDF input is missing bus columns: $(missing_bus_cols)."))
				end
				if size(ptdf_nodal_data, 1) != Num_Eline
					throw(ArgumentError("Nodal PTDF row count $(size(ptdf_nodal_data,1)) does not match line row count $(Num_Eline)."))
				end
				for n in N
					ptdf_matrix[:, n] .= [to_float(v) for v in ptdf_nodal_data[:, string(bus_labels[n])]]
				end
				println("Using user-provided nodal PTDF input.")
			else
				x_col = first_existing_col(linedata_cols, ["X", "Reactance", "x"])
				x_vals = x_col === nothing ? fill(1.0, Num_Eline) : [to_float(Linedata[l, x_col]) for l in L]
				if x_col === nothing
					println("Warning: nodal PTDF auto-computation found no reactance column (X/Reactance/x). Using X=1.0 for all lines.")
				end
				ptdf_matrix .= compute_ptdf_from_incidence([L_from_n[l] for l in L], [L_to_n[l] for l in L], x_vals, length(N), reference_bus)
				println("No nodal PTDF input found; nodal PTDF matrix computed from branch endpoints and reactance.")
			end
			PTDF_l_n = Dict((l, n) => ptdf_matrix[l, n] for l in L for n in N)
		end
		for (nm, v) in [("reg_up_requirement", reg_up_requirement), ("reg_dn_requirement", reg_dn_requirement), ("spin_requirement", spin_requirement), ("nspin_requirement", nspin_requirement), ("delta_reg", delta_reg), ("delta_spin", delta_spin), ("delta_nspin", delta_nspin)]
			if v < 0
				throw(ArgumentError("Invalid $(nm)=$(v). Expected non-negative value."))
			end
		end
		P_min=[Gendata[:,"Pmin (MW)"];]#g						#Minimum power generation of unit g, MW
		P_max=[Gendata[:,"Pmax (MW)"];]#g						#Maximum power generation of unit g, MW
		RPS = Dict{Any,Float64}() #w							#Renewable portfolio standard in state w, unitless
		for w in W
			rps_vals = unique([to_float(v) for v in RPSdata[RPSdata[:, "From_state"] .== w, "RPS"]])
			if isempty(rps_vals)
				RPS[w] = 0.0
			elseif length(rps_vals) == 1
				RPS[w] = rps_vals[1]
			else
				throw(ArgumentError("Inconsistent RPS values for state $(w) in RPSdata From_state rows: $(rps_vals)."))
			end
		end
		#RM=0.02#											#Planning reserve margin, unitless
		RM_SPIN_g = Dict(zip(G,[to_float(v) for v in Gendata[:,Symbol("RM_SPIN")]]))
		RM_REG_UP_g = "RM_REG_UP" in gendata_cols ? Dict(zip(G, [to_float(v) for v in Gendata[:, "RM_REG_UP"]])) : Dict(g => RM_SPIN_g[g] for g in G)
		RM_REG_DN_g = "RM_REG_DN" in gendata_cols ? Dict(zip(G, [to_float(v) for v in Gendata[:, "RM_REG_DN"]])) : Dict(g => RM_SPIN_g[g] for g in G)
		RM_NSPIN_g = "RM_NSPIN" in gendata_cols ? Dict(zip(G, [to_float(v) for v in Gendata[:, "RM_NSPIN"]])) : Dict(g => RM_SPIN_g[g] for g in G)
		RU_g = Dict(zip(G,Gendata[:,Symbol("RU")]))
		RD_g = Dict(zip(G,Gendata[:,Symbol("RD")]))
		SECAP=[Storagedata[:,"Capacity (MWh)"];]#s		#Maximum energy capacity of storage unit s, MWh
		SCAP=[Storagedata[:,"Max Power (MW)"];]#s		#Maximum capacity of storage unit s, MWh
		SC=[Storagedata[:,"Charging Rate"];]#s									#The maximum rates of charging, unitless
		SD=[Storagedata[:,"Discharging Rate"];]#s									#The maximum rates of discharging, unitless
		VCG=[Gencostdata;]#g						#Variable cost of generation unit g, $/MWh
		VCS=[Storagedata[:,Symbol("Cost (\$/MWh)")];]#s					#Variable (degradation) cost of storage unit s, $/MWh
		VOLL = get_singlepar("VOLL", 100000.0)										#Value of loss of load d, $/MWh
		e_ch=[Storagedata[:,"Charging efficiency"];]#s				#Charging efficiency of storage unit s, unitless
		e_dis=[Storagedata[:,"Discharging efficiency"];]#s		#Discharging efficiency of storage unit s, unitless
			
		#for multiple time period, we need to use following TS parameters
		#NI_t = Dict([t => Dict([(h,i) =>-Loaddata[!,"NI"][h]*(Zonedata[:,"Demand (MW)"][i]/sum(Zonedata[:,"Demand (MW)"])) for i in I for h in H_t[t]]) for t in T]) #tih
		NI_h = Dict([(h,i)=>Loaddata[!,"NI"][h]*(Zonedata[:,"Demand (MW)"][i]/sum(Zonedata[:,"Demand (MW)"])) for i in I for h in H])
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
		if carbon_policy == 2
			@variable(model, a[G]>=0) 						#Bidding carbon allowance of unit g, ton
		end
	#	@variable(model, f[G,L,T,H])							#Active power in transmission corridor/line l in h from resrource g, MW
		@variable(model, f[L,H])							#Active power in transmission corridor/line l in h, MW
		@variable(model, em_emis[W]>=0)							#Carbon emission violated emission limit in state  w, ton
		@variable(model, ni[H,I])							#net import used in i
		@variable(model, p[G,H]>=0)							#Active power generation of unit g in hour h, MW
		@variable(model, pw[G,W]>=0)							#Total renewable generation of unit g in state w, MWh
		@variable(model, p_LS[I,H]>=0)						#Load shedding of demand in zone i in hour h, MW
		@variable(model, pt_rps[W]>=0)							#Amount of energy violated RPS policy in state w, MWh
		@variable(model, pwe[G,W,W_prime]>=0)					#Renewable credits generated by unit g in state w and exported from w to w' annually, MWh	
		@variable(model, r_G_REG_UP[G,H]>=0)					#REG_UP reserve provided by generator g in hour h, MW
		@variable(model, r_G_REG_DN[G,H]>=0)					#REG_DN reserve provided by generator g in hour h, MW
		@variable(model, r_G_SPIN[G,H]>=0)						#SPIN reserve provided by generator g in hour h, MW
		@variable(model, r_G_NSPIN[G,H]>=0)					#NSPIN reserve provided by generator g in hour h, MW
		@variable(model, r_S_REG_UP[S,H]>=0)					#REG_UP reserve provided by storage s in hour h, MW
		@variable(model, r_S_REG_DN[S,H]>=0)					#REG_DN reserve provided by storage s in hour h, MW
		@variable(model, r_S_SPIN[S,H]>=0)						#SPIN reserve provided by storage s in hour h, MW
		@variable(model, r_S_NSPIN[S,H]>=0)					#NSPIN reserve provided by storage s in hour h, MW
		if network_model == 2
			@variable(model, theta[N,H])						#Voltage angle of bus n in hour h, rad
		elseif network_model == 3
			@variable(model, inj[N,H])							#Net nodal injection for PTDF-based DCOPF, MW
		end
		@variable(model, soc[S,H]>=0)						#State of charge level of storage s in hour h, MWh
		@variable(model, c[S,H]>=0)							#Charging power of storage s from grid in hour h, MW
		@variable(model, dc[S,H]>=0)						#Discharging power of storage s into grid in hour h, MW
		if flexible_demand == 1
			@variable(model, dr[D,H]>=0)						#Demand from DR aggregator during t, h, MW
			@variable(model, dr_UP[D,H]>=0)						#Demand change up relative to reference demand during t, h, MW
			@variable(model, dr_DN[D,H]>=0)						#Demand change down relative to reference demand during t, h, MW
		end
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
		if flexible_demand != 0
			@expression(model, DR_OPT[i in I, h in H], sum(dr[d,h]-DR_t[h,d]*DR_MAX[d] for d in D_i[i]))
		else
			@expression(model, DR_OPT[i in I, h in H], 0)
		end
		if network_model == 0
			# Copper-plate: one system-wide balance, no network flow constraints
			SystemPB_con = @constraint(model, [h in H],
				sum(p[g,h] for g in G) + sum(dc[s,h] - c[s,h] for s in S) + sum(NI_h[h,i] for i in I)
				== sum(sum(P_t[h,d]*PK[d] for d in D_i[i]) + DR_OPT[i,h] - p_LS[i,h] for i in I),
				base_name = "SystemPB_con")
			NoNetworkFlow_con = @constraint(model, [l in L, h in H], f[l,h] == 0, base_name = "NoNetworkFlow_con")
		elseif network_model == 1
			# Zonal transport
			@constraint(model, PB_con[i in I, h in H], sum(p[g,h] for g in G_i[i])
				+ sum(dc[s,h] - c[s,h] for s in S_i[i])
				- sum(f[l,h] for l in LS_i[i])
				+ sum(f[l,h] for l in LR_i[i])
				+ NI_h[h,i]
				== sum(P_t[h,d]*PK[d] for d in D_i[i]) + DR_OPT[i,h] - p_LS[i,h],base_name = "PB_con")
		elseif network_model == 2
			# Nodal DCOPF angle-based
			@expression(model, NodeLoad[n in N, h in H], bus_load_share[n] * (sum(P_t[h,d]*PK[d] for d in D_i[bus_zone_of_n[n]]) + DR_OPT[bus_zone_of_n[n],h] - p_LS[bus_zone_of_n[n],h]))
			@expression(model, NodeNI[n in N, h in H], bus_load_share[n] * NI_h[h, bus_zone_of_n[n]])
			@constraint(model, PBNode_con[n in N, h in H], sum(p[g,h] for g in G_n[n])
				+ sum(dc[s,h] - c[s,h] for s in S_n[n])
				- sum(f[l,h] for l in LS_n[n])
				+ sum(f[l,h] for l in LR_n[n])
				+ NodeNI[n,h]
				== NodeLoad[n,h], base_name = "PBNode_con")
			FAngle_con = @constraint(model, [l in L, h in H], f[l,h] == B_l[l] * (model[:theta][L_from_n[l],h] - model[:theta][L_to_n[l],h]), base_name = "FAngle_con")
			RefAngle_con = @constraint(model, [h in H], model[:theta][reference_bus,h] == 0, base_name = "RefAngle_con")
			ThetaBound_con = @constraint(model, [n in N, h in H], -theta_max <= model[:theta][n,h] <= theta_max, base_name = "ThetaBound_con")
		else
			# Nodal DCOPF PTDF-based
			@expression(model, NodeLoad[n in N, h in H], bus_load_share[n] * (sum(P_t[h,d]*PK[d] for d in D_i[bus_zone_of_n[n]]) + DR_OPT[bus_zone_of_n[n],h] - p_LS[bus_zone_of_n[n],h]))
			@expression(model, NodeNI[n in N, h in H], bus_load_share[n] * NI_h[h, bus_zone_of_n[n]])
			@expression(model, NetInj[n in N, h in H], sum(p[g,h] for g in G_n[n])
				+ sum(dc[s,h] - c[s,h] for s in S_n[n])
				+ NodeNI[n,h]
				- NodeLoad[n,h])
			@constraint(model, PTDFInjDef_con[n in N, h in H], model[:inj][n,h] == NetInj[n,h], base_name = "PTDFInjDef_con")
			@constraint(model, PTDFBalance_con[h in H], sum(model[:inj][n,h] for n in N) == 0, base_name = "PTDFBalance_con")
			@constraint(model, FPTDF_con[l in L, h in H], f[l,h] == sum(PTDF_l_n[(l,n)] * model[:inj][n,h] for n in N), base_name = "FPTDF_con")
		end
		NI_con = @constraint(model, [h in H, i in I], ni[h,i] <= NI_h[h,i],base_name = "NI_con")
		if operation_reserve_mode == 2
			@expression(model, ReserveUpG[g in G, h in H], r_G_REG_UP[g,h] + r_G_SPIN[g,h] + r_G_NSPIN[g,h])
			@expression(model, ReserveDnG[g in G, h in H], r_G_REG_DN[g,h])
			@expression(model, ReserveUpS[s in S, h in H], r_S_REG_UP[s,h] + r_S_SPIN[s,h] + r_S_NSPIN[s,h])
			@expression(model, ReserveDnS[s in S, h in H], r_S_REG_DN[s,h])
		elseif operation_reserve_mode == 1
			@expression(model, ReserveUpG[g in G, h in H], r_G_REG_UP[g,h] + r_G_SPIN[g,h])
			@expression(model, ReserveDnG[g in G, h in H], r_G_REG_DN[g,h])
			@expression(model, ReserveUpS[s in S, h in H], r_S_REG_UP[s,h] + r_S_SPIN[s,h])
			@expression(model, ReserveDnS[s in S, h in H], r_S_REG_DN[s,h])
		else
			@expression(model, ReserveUpG[g in G, h in H], 0)
			@expression(model, ReserveDnG[g in G, h in H], 0)
			@expression(model, ReserveUpS[s in S, h in H], 0)
			@expression(model, ReserveDnS[s in S, h in H], 0)
		end
		@expression(model, Load_system[h in H], sum(sum(P_t[h,d]*PK[d] for d in D_i[i]) for i in I))
		@expression(model, REG_UP_requirement[h in H], reg_up_requirement * Load_system[h])
		@expression(model, REG_DN_requirement[h in H], reg_dn_requirement * Load_system[h])
		@expression(model, SPIN_requirement[h in H], spin_requirement * Load_system[h])
		@expression(model, NSPIN_requirement[h in H], nspin_requirement * Load_system[h])
		if operation_reserve_mode == 2
			REG_UP_req_con = @constraint(model, [h in H], sum(r_G_REG_UP[g,h] for g in G_F) + sum(r_S_REG_UP[s,h] for s in S) >= REG_UP_requirement[h], base_name = "REG_UP_req_con")
			REG_DN_req_con = @constraint(model, [h in H], sum(r_G_REG_DN[g,h] for g in G_F) + sum(r_S_REG_DN[s,h] for s in S) >= REG_DN_requirement[h], base_name = "REG_DN_req_con")
			SPIN_req_con = @constraint(model, [h in H], sum(r_G_SPIN[g,h] for g in G_F) + sum(r_S_SPIN[s,h] for s in S) >= SPIN_requirement[h], base_name = "SPIN_req_con")
			NSPIN_req_con = @constraint(model, [h in H], sum(r_G_NSPIN[g,h] for g in G_F) + sum(r_S_NSPIN[s,h] for s in S) >= NSPIN_requirement[h], base_name = "NSPIN_req_con")
		elseif operation_reserve_mode == 1
			REG_UP_req_con = @constraint(model, [h in H], sum(r_G_REG_UP[g,h] for g in G_F) + sum(r_S_REG_UP[s,h] for s in S) >= REG_UP_requirement[h], base_name = "REG_UP_req_con")
			REG_DN_req_con = @constraint(model, [h in H], sum(r_G_REG_DN[g,h] for g in G_F) + sum(r_S_REG_DN[s,h] for s in S) >= REG_DN_requirement[h], base_name = "REG_DN_req_con")
			SPIN_req_con = @constraint(model, [h in H], sum(r_G_SPIN[g,h] for g in G_F) + sum(r_S_SPIN[s,h] for s in S) >= SPIN_requirement[h], base_name = "SPIN_req_con")
			NSPIN_off_con = @constraint(model, [g in G, h in H], r_G_NSPIN[g,h] == 0, base_name = "NSPIN_off_con")
			NSPIN_S_off_con = @constraint(model, [s in S, h in H], r_S_NSPIN[s,h] == 0, base_name = "NSPIN_S_off_con")
		else
			REG_UP_off_con = @constraint(model, [g in G, h in H], r_G_REG_UP[g,h] == 0, base_name = "REG_UP_off_con")
			REG_DN_off_con = @constraint(model, [g in G, h in H], r_G_REG_DN[g,h] == 0, base_name = "REG_DN_off_con")
			SPIN_off_con = @constraint(model, [g in G, h in H], r_G_SPIN[g,h] == 0, base_name = "SPIN_off_con")
			NSPIN_off_con = @constraint(model, [g in G, h in H], r_G_NSPIN[g,h] == 0, base_name = "NSPIN_off_con")
			REG_UP_S_off_con = @constraint(model, [s in S, h in H], r_S_REG_UP[s,h] == 0, base_name = "REG_UP_S_off_con")
			REG_DN_S_off_con = @constraint(model, [s in S, h in H], r_S_REG_DN[s,h] == 0, base_name = "REG_DN_S_off_con")
			SPIN_S_off_con = @constraint(model, [s in S, h in H], r_S_SPIN[s,h] == 0, base_name = "SPIN_S_off_con")
			NSPIN_S_off_con = @constraint(model, [s in S, h in H], r_S_NSPIN[s,h] == 0, base_name = "NSPIN_S_off_con")
		end
		ReserveThermalOnly_REGUP_con = @constraint(model, [g in setdiff(G, G_F), h in H], r_G_REG_UP[g,h] == 0, base_name = "ReserveThermalOnly_REGUP_con")
		ReserveThermalOnly_REGDN_con = @constraint(model, [g in setdiff(G, G_F), h in H], r_G_REG_DN[g,h] == 0, base_name = "ReserveThermalOnly_REGDN_con")
		ReserveThermalOnly_SPIN_con = @constraint(model, [g in setdiff(G, G_F), h in H], r_G_SPIN[g,h] == 0, base_name = "ReserveThermalOnly_SPIN_con")
		ReserveThermalOnly_NSPIN_con = @constraint(model, [g in setdiff(G, G_F), h in H], r_G_NSPIN[g,h] == 0, base_name = "ReserveThermalOnly_NSPIN_con")
		
		#(4) Transissim power flow limit for existing lines	
		@constraint(model, TLe_con[l in L_exist,h in H], -F_max[l] <= f[l,h] <= F_max[l],base_name = "TLe_con")

		if config_set["unit_commitment"] == 0
			#(5) Maximum capacity limits for existing power generator
			CLe_con = @constraint(model, [g in G_exist, h in H], P_min[g] <= p[g,h] + ReserveUpG[g,h] <= (1-FOR_g[g])*P_max[g],base_name = "CLe_con")
			CLe_MR_con =  @constraint(model, [g in intersect(G_exist,G_MR), h in H],  p[g,h] == (1-FOR_g[g])*P_max[g], base_name = "CLe_MR_con")
			#(5b) Downward headroom for thermal generators with REG_DN reserve
			HeadroomDN_con = @constraint(model, [g in G_F, h in H], P_min[g] <= p[g,h] - r_G_REG_DN[g,h], base_name = "HeadroomDN_con")
			#(6) Reserve capability limits for thermal generators
			REG_UP_con = @constraint(model, [g in G_F, h in H], r_G_REG_UP[g,h] <= RM_REG_UP_g[g]*(1-FOR_g[g])*P_max[g],base_name = "REG_UP_con")
			REG_DN_con = @constraint(model, [g in G_F, h in H], r_G_REG_DN[g,h] <= RM_REG_DN_g[g]*(1-FOR_g[g])*P_max[g],base_name = "REG_DN_con")
			SPIN_con = @constraint(model, [g in G_F, h in H], r_G_SPIN[g,h] <= RM_SPIN_g[g]*(1-FOR_g[g])*P_max[g],base_name = "SPIN_con")
			NSPIN_con = @constraint(model, [g in G_F, h in H], r_G_NSPIN[g,h] <= RM_NSPIN_g[g]*(1-FOR_g[g])*P_max[g],base_name = "NSPIN_con")
			RegUPRampResp_con = @constraint(model, [g in G_F, h in H], r_G_REG_UP[g,h] <= RU_g[g]*(1-FOR_g[g])*P_max[g]*delta_reg, base_name = "RegUPRampResp_con")
			SpinRampResp_con = @constraint(model, [g in G_F, h in H], r_G_SPIN[g,h] <= RU_g[g]*(1-FOR_g[g])*P_max[g]*delta_spin, base_name = "SpinRampResp_con")
			NSpinRampResp_con = @constraint(model, [g in G_F, h in H], r_G_NSPIN[g,h] <= RU_g[g]*(1-FOR_g[g])*P_max[g]*delta_nspin, base_name = "NSpinRampResp_con")
			RegDNRampResp_con = @constraint(model, [g in G_F, h in H], r_G_REG_DN[g,h] <= RD_g[g]*(1-FOR_g[g])*P_max[g]*delta_reg, base_name = "RegDNRampResp_con")
		
			#(7) Ramp up limits
			RP_UP_con = @constraint(model, [g in G_F, h in setdiff(H, [1])],  p[g,h] + ReserveUpG[g,h]-p[g,h-1] <= RU_g[g]*(1-FOR_g[g])*P_max[g],base_name = "RP_UP_con" )
		
			#(8) Ramp down limits
			RP_DN_con = @constraint(model, [g in G_F, h in setdiff(H, [1])],  p[g,h] - ReserveDnG[g,h]-p[g,h-1]>= -RD_g[g]*(1-FOR_g[g])*P_max[g],base_name = "RP_DN_con" )
		else
			#(5) Maximum capacity limits for existing power generator
			CLe_con = @constraint(model, [g in setdiff(G_exist,G_UC), h in H], P_min[g] <= p[g,h] + ReserveUpG[g,h] <= (1-FOR_g[g])*P_max[g],base_name = "CLe_con")
			CLe_MR_con =  @constraint(model, [g in intersect(G_exist,G_MR,G_UC), h in H],  p[g,h] == (1-FOR_g[g])*P_max[g], base_name = "CLe_MR_con")
			CLeL_con = @constraint(model, [g in setdiff(G_UC,G_MR), h in H], P_min[g] <= p[g,h] + ReserveUpG[g,h] ,base_name = "CLeL_con")
			CLeU_con = @constraint(model, [g in setdiff(G_UC,G_MR), h in H], p[g,h] + ReserveUpG[g,h] <= (1-FOR_g[g])*P_max[g]*model[:o][g,h],base_name = "CLeU_con")
			#(5b) Downward headroom for thermal generators with REG_DN reserve
			HeadroomDN_nonUC_con = @constraint(model, [g in setdiff(G_F,G_UC), h in H], P_min[g] <= p[g,h] - r_G_REG_DN[g,h], base_name = "HeadroomDN_nonUC_con")
			HeadroomDN_UC_con = @constraint(model, [g in intersect(G_F,G_UC), h in H], model[:pmin][g,h] <= p[g,h] - r_G_REG_DN[g,h], base_name = "HeadroomDN_UC_con")
			#(6) Reserve capability limits for thermal generators
			REG_UP_con = @constraint(model, [g in setdiff(G_F,G_UC), h in H], r_G_REG_UP[g,h] <= RM_REG_UP_g[g]*(1-FOR_g[g])*P_max[g],base_name = "REG_UP_con")
			REG_DN_con = @constraint(model, [g in setdiff(G_F,G_UC), h in H], r_G_REG_DN[g,h] <= RM_REG_DN_g[g]*(1-FOR_g[g])*P_max[g],base_name = "REG_DN_con")
			SPIN_con = @constraint(model, [g in setdiff(G_F,G_UC), h in H], r_G_SPIN[g,h] <= RM_SPIN_g[g]*(1-FOR_g[g])*P_max[g],base_name = "SPIN_con")
			NSPIN_con = @constraint(model, [g in setdiff(G_F,G_UC), h in H], r_G_NSPIN[g,h] <= RM_NSPIN_g[g]*(1-FOR_g[g])*P_max[g],base_name = "NSPIN_con")
			REG_UP_UC_con = @constraint(model, [g in intersect(G_F,G_UC), h in H], r_G_REG_UP[g,h] <= RM_REG_UP_g[g]*(1-FOR_g[g])*P_max[g]*model[:o][g,h],base_name = "REG_UP_UC_con")
			REG_DN_UC_con = @constraint(model, [g in intersect(G_F,G_UC), h in H], r_G_REG_DN[g,h] <= RM_REG_DN_g[g]*(1-FOR_g[g])*P_max[g]*model[:o][g,h],base_name = "REG_DN_UC_con")
			SPINUC_con = @constraint(model, [g in intersect(G_F,G_UC), h in H], r_G_SPIN[g,h] <= RM_SPIN_g[g]*(1-FOR_g[g])*P_max[g]*model[:o][g,h],base_name = "SPINUC_con")
			NSPINUC_con = @constraint(model, [g in intersect(G_F,G_UC), h in H], r_G_NSPIN[g,h] <= RM_NSPIN_g[g]*(1-FOR_g[g])*P_max[g]*model[:o][g,h],base_name = "NSPINUC_con")
			RegUPRampResp_con = @constraint(model, [g in setdiff(G_F,G_UC), h in H], r_G_REG_UP[g,h] <= RU_g[g]*(1-FOR_g[g])*P_max[g]*delta_reg, base_name = "RegUPRampResp_con")
			SpinRampResp_con = @constraint(model, [g in setdiff(G_F,G_UC), h in H], r_G_SPIN[g,h] <= RU_g[g]*(1-FOR_g[g])*P_max[g]*delta_spin, base_name = "SpinRampResp_con")
			NSpinRampResp_con = @constraint(model, [g in setdiff(G_F,G_UC), h in H], r_G_NSPIN[g,h] <= RU_g[g]*(1-FOR_g[g])*P_max[g]*delta_nspin, base_name = "NSpinRampResp_con")
			RegDNRampResp_con = @constraint(model, [g in setdiff(G_F,G_UC), h in H], r_G_REG_DN[g,h] <= RD_g[g]*(1-FOR_g[g])*P_max[g]*delta_reg, base_name = "RegDNRampResp_con")
			RegUPRampResp_UC_con = @constraint(model, [g in intersect(G_F,G_UC), h in H], r_G_REG_UP[g,h] <= RU_g[g]*(1-FOR_g[g])*P_max[g]*delta_reg*model[:o][g,h], base_name = "RegUPRampResp_UC_con")
			SpinRampResp_UC_con = @constraint(model, [g in intersect(G_F,G_UC), h in H], r_G_SPIN[g,h] <= RU_g[g]*(1-FOR_g[g])*P_max[g]*delta_spin*model[:o][g,h], base_name = "SpinRampResp_UC_con")
			NSpinRampResp_UC_con = @constraint(model, [g in intersect(G_F,G_UC), h in H], r_G_NSPIN[g,h] <= RU_g[g]*(1-FOR_g[g])*P_max[g]*delta_nspin*model[:o][g,h], base_name = "NSpinRampResp_UC_con")
			RegDNRampResp_UC_con = @constraint(model, [g in intersect(G_F,G_UC), h in H], r_G_REG_DN[g,h] <= RD_g[g]*(1-FOR_g[g])*P_max[g]*delta_reg*model[:o][g,h], base_name = "RegDNRampResp_UC_con")
	
			#(7) Ramp up limits
			RP_UP_con = @constraint(model, [g in setdiff(G_F,G_UC), h in setdiff(H, [1])],  p[g,h] + ReserveUpG[g,h]-p[g,h-1] <= RU_g[g]*(1-FOR_g[g])*P_max[g],base_name = "RP_UP_con" )
			RP_UP_UC_con = @constraint(model, [g in G_UC, h in setdiff(H, [1])],  p[g,h] + ReserveUpG[g,h] - model[:pmin][g,h] - (p[g,h-1]-model[:pmin][g,h-1]) <= RU_g[g]*(1-FOR_g[g])*P_max[g]*model[:o][g,h],base_name = "RP_UP_UC_con" )
		
			#(8) Ramp down limits
			RP_DN_con = @constraint(model, [g in setdiff(G_F,G_UC), h in setdiff(H, [1])],  p[g,h] - ReserveDnG[g,h] -p[g,h-1] >= -RD_g[g]*(1-FOR_g[g])*P_max[g],base_name = "RP_DN_con" )
			RP_DN_UC_con = @constraint(model, [g in G_UC, h in setdiff(H, [1])],  (p[g,h]-ReserveDnG[g,h]-model[:pmin][g,h]) - (p[g,h-1] - model[:pmin][g,h-1]) >= -RD_g[g]*(1-FOR_g[g])*P_max[g]*model[:o][g,h],base_name = "RP_DN_UC_con" )
			
		end

		#(9) Load shedding limit	
		LS_con = @constraint(model, [i in I, h in H], 0 <= p_LS[i,h]<= sum(P_t[h,d]*PK[d] for d in D_i[i]),base_name = "LS_con")
		
		
		##############
		##Renewbales##
		##############
		#(10) Renewables generation availability for the existing plants: p_(g,h)≤AFRE_(g,h)∙P_g^max; ∀h∈H_t,g∈G^E∩(G^PV∪G^W)  
		ReAe_con=@constraint(model, [i in I, g in intersect(G_exist,G_i[i],union(G_PV,G_W)), h in H], p[g,h] <= AFRE_hg[g][h,i]*P_max[g],base_name = "ReAe_con")
		ReAe_MR_con=@constraint(model, [i in I, g in intersect(intersect(G_exist,G_MR),G_i[i],union(G_PV,G_W)), h in H], p[g,h] == AFRE_hg[g][h,i]*P_max[g],base_name = "ReAe_MR_con")
		@expression(model, RenewableCurtailExist[i in I, g in intersect(G_exist,G_i[i],union(G_PV,G_W)), h in H], AFRE_hg[g][h,i]*P_max[g]-p[g,h])
		
		
		
		
		##############
		###Storages###
		##############
		#(11) Storage charging rate limit for existing units
		ChLe_con=@constraint(model, [ h in H, s in S_exist], c[s,h] + ReserveDnS[s,h] <= SC[s]*SCAP[s],base_name = "ChLe_con")
		
		#(12) Storage discharging rate limit for existing units
		DChLe_con=@constraint(model, [ h in H,  s in S_exist], dc[s,h] + ReserveUpS[s,h] <= SD[s]*SCAP[s],base_name = "DChLe_con")
		
		#(13) State of charge limit for existing units: 0≤ soc_(s,h) ≤ SCAP_s;   ∀h∈H_t,t∈T,s∈ S^E
		SoCLe_con=@constraint(model, [ h in H, s in S_exist], 0 <= soc[s,h] <= SECAP[s], base_name = "SoCLe_con")
		#(14) Storage reserve deliverability within response windows
		if operation_reserve_mode == 2
			SR_DELIVER_REGUP_con = @constraint(model, [h in H, s in S_exist], r_S_REG_UP[s,h]*delta_reg <= soc[s,h],base_name = "SR_DELIVER_REGUP_con")
			SR_DELIVER_REGDN_con = @constraint(model, [h in H, s in S_exist], r_S_REG_DN[s,h]*delta_reg <= soc[s,h],base_name = "SR_DELIVER_REGDN_con")
			SR_DELIVER_SPIN_con = @constraint(model, [h in H, s in S_exist], r_S_SPIN[s,h]*delta_spin <= soc[s,h],base_name = "SR_DELIVER_SPIN_con")
			SR_DELIVER_NSPIN_con = @constraint(model, [h in H, s in S_exist], r_S_NSPIN[s,h]*delta_nspin <= soc[s,h],base_name = "SR_DELIVER_NSPIN_con")
		elseif operation_reserve_mode == 1
			SR_DELIVER_REGUP_con = @constraint(model, [h in H, s in S_exist], r_S_REG_UP[s,h]*delta_reg <= soc[s,h],base_name = "SR_DELIVER_REGUP_con")
			SR_DELIVER_REGDN_con = @constraint(model, [h in H, s in S_exist], r_S_REG_DN[s,h]*delta_reg <= soc[s,h],base_name = "SR_DELIVER_REGDN_con")
			SR_DELIVER_SPIN_con = @constraint(model, [h in H, s in S_exist], r_S_SPIN[s,h]*delta_spin <= soc[s,h],base_name = "SR_DELIVER_SPIN_con")
		end
		#(15) Storage operation constraints
		SoC_con=@constraint(model, [h in setdiff(H, [1]),s in S_exist], soc[s,h] == soc[s,h-1] + e_ch[s]*c[s,h] - dc[s,h]/e_dis[s],base_name = "SoC_con")
		#Ch_1_con=@constraint(model, [s in S], c[s,1] ==0)
		#DCh_1_con=@constraint(model, [s in S], dc[s,1] ==0)
		
		#(16) Daily 50% of storage level balancing for existing units
		SDBe_st_con=@constraint(model, [s in S_exist], soc[s,1] == soc[s,H[end]],base_name = "SDBe_st_con")
		#SDBe_ps_con=@constraint(model, [s in S_exist, h in setdiff(H_D, [0,Num_hour])],soc[s,1]==soc[s,h],base_name="SDBe_ps_con")
		SDBe_ed_con=@constraint(model, [s in S_exist], soc[s,H[end]] == 0.5 * SECAP[s],base_name = "SDBe_ed_con")
		
		

		##############
		##RPSPolices##
		##############
		if clean_energy_policy == 1
			#(17) RPS, state-level renewable generation accounting
			RPS_pw_con = @constraint(model, [w in W, g in intersect(union([G_i[i] for i in I_w[w]]...),G_RPS)],
								pw[g,w] == sum(p[g,h] for h in H), base_name = "RPS_pw_con")

			#(18) State renewable credits export limitation 
			RPS_expt_con = @constraint(model, [w in W, g in intersect(union([G_i[i] for i in I_w[w]]...),G_RPS)],
								pw[g,w] >= sum(pwe[g,w,w_prime] for w_prime in WER_w[w]), base_name = "RPS_expt_con")

			#(19) State renewable credits import limitation 
			RPS_impt_con = @constraint(model, [w in W, w_prime in WIR_w[w], g in intersect(union([G_i[i] for i in I_w[w_prime]]...),G_RPS)],
								pw[g,w_prime] >= pwe[g,w_prime,w], base_name = "RPS_impt_con")

			#(20) Renewable credits trading meets state RPS requirements
			RPS_con = @constraint(model, [w in W], sum(pw[g,w] for g in intersect(union([G_i[i] for i in I_w[w]]...),G_RPS))
									+ sum(pwe[g,w_prime,w] for w_prime in WIR_w[w] for g in intersect(union([G_i[i] for i in I_w[w_prime]]...),G_RPS))
									- sum(pwe[g,w,w_prime] for w_prime in WER_w[w] for g in intersect(union([G_i[i] for i in I_w[w]]...),G_RPS))
									+ pt_rps[w]
									>= sum(sum(P_t[h,i]*PK[i]*RPS[w] for d in D_i[i]) for i in I_w[w] for h in H), base_name = "RPS_con")
		else
			RPS_off_con = @constraint(model, [w in W], pt_rps[w] == 0, base_name = "RPS_off_con")
		end
		
		###############
		#CarbonPolices#				
		###############
		@expression(model, StateCarbonEmission[w in W],
			sum(sum(EF[g]*p[g,h] for g in intersect(G_F,G_i[i]) for h in H) for i in I_w[w]))
		if carbon_policy == 2
			#(21B) State carbon allowance cap
			SCAL_con = @constraint(model, [w in W],
				sum(a[g] for g in intersect(union([G_i[i] for i in I_w[w]]...), G_F)) <= get(ALW_state, w, 0.0),
				base_name = "SCAL_con")
			#(22B) Allowances must cover annual emissions (with slack penalty)
			BAL_con = @constraint(model, [w in W],
				StateCarbonEmission[w] <= sum(a[g] for g in intersect(union([G_i[i] for i in I_w[w]]...), G_F)) + em_emis[w],
				base_name = "BAL_con")
		elseif carbon_policy == 1
			#(21A) State annual carbon emission limit
			CL_con = @constraint(model, [w in W], StateCarbonEmission[w] <= ELMT[w] + em_emis[w], base_name = "CL_con")
		else
			NoCarbon_con = @constraint(model, [w in W], em_emis[w] == 0, base_name = "NoCarbon_con")
		end
		if flexible_demand == 1
			#Demand response program (load shifting)
			#(25) DR balance
			DR_con = @constraint(model, [d in D, h in H], dr[d,h] == DR_t[h,d]*DR_MAX[d] + dr_UP[d,h]-dr_DN[d,h], base_name="DR_con")

			#(26) DR daily balance
			DR_day_con=@constraint(model, [d in D, h in setdiff(H_D, [0,Num_hour])], sum(dr_UP[d,h1] for h1 in h:h+23)==sum(dr_DN[d,h1] for h1 in h:h+23),base_name="DR_day_con")

			#(27) DR max demand limit
			DR_max_con = @constraint(model, [d in D, h in H], DR_t[h,d]*DR_MAX[d]+dr_UP[d,h] <= DR_MAX[d], base_name = "DR_max_con")
			DR_ref_con =  @constraint(model, [d in D, h in H], dr_DN[d,h] <= DR_t[h,d]*DR_MAX[d], base_name = "DR_ref_con")
		end
		#Objective function and solve--------------------------
		#Investment cost of generator, lines, and storages
		#@expression(model, INVCost, sum(INV_g[g]*unit_converter*x[g] for g in G_new)+sum(INV_l[l]*unit_converter*y[l] for l in L_new)+sum(INV_s[s]*unit_converter*z[s] for s in S_new))			
		

		#Operation cost of generator and storages
		@expression(model, OPCost, sum(VCG[g]*sum(p[g,h] for h in H) for g in G)
					+ sum(VCS[s]*sum(c[s,h]+dc[s,h] for h in H) for s in S)
					)
		@expression(model, OPCost_gen, sum(VCG[g]*sum(p[g,h] for h in H) for g in G)
					)
		@expression(model, OPCost_es, sum(VCS[s]*sum(c[s,h]+dc[s,h] for h in H) for s in S)
					)								

		#Loss of load penalty
		@expression(model, LoadShedding, sum(VOLL*sum(p_LS[i,h] for h in H) for i in I))

		#RPS volitation penalty
		if clean_energy_policy == 1
			@expression(model, RPSPenalty, PT_rps*sum(pt_rps[w] for w in W))
		else
			@expression(model, RPSPenalty, 0)
		end

		#Carbon cap volitation penalty
		if carbon_policy == 0
			@expression(model, CarbonCapPenalty, 0)
		else
			@expression(model, CarbonCapPenalty, PT_emis*sum(em_emis[w] for w in W))
		end
		@expression(model, CarbonEmission[w in W], StateCarbonEmission[w])
		#Slack variable penalty
		#@expression(model, SlackPenalty, BM *sum(slack_pos[h,i]+slack_neg[h,i] for h in H for i in I))

		#Unit commitment Start up cost
		if config_set["unit_commitment"] == 0
			@expression(model,STCost,0)	
		else
			@expression(model,STCost,sum(Gendata[g,Symbol("Start_up_cost (\$/MW)")]*model[:su][g,h]*P_max[g] for h in H for g in G_UC))
		end
		#Demand response operation cost
		if flexible_demand == 0
			@expression(model,DR_OPcost,0)
		else
			@expression(model,DR_OPcost,sum(DRC_d[d]*(dr_UP[d,h]+dr_DN[d,h]) for h in H for d in D))
		end

		#Minmize objective fuction: STCost + DR_OPCost + OPCost + RPSPenalty + CarbonCapPenalty + SlackPenalty
		@objective(model,Min, STCost + DR_OPcost + OPCost + LoadShedding + RPSPenalty + CarbonCapPenalty)
		return model
	end
end 


