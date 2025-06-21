"""
Modified version of the old PCM.jl that uses 24 hours instead of 8760
for fair comparison with the new model.

This file contains the same logic as src/PCM.jl but with hardcoded 24-hour horizon.
"""

function get_TPmatched_ts(Loaddata::DataFrame,time_periods::Int64,Ordered_zone_nm::Vector{String})
    n_hours = 24  # Modified: Use 24 hours instead of extracting from data
    ndays = Int(time_periods)
    
    rep_dat_dict = Dict()
    ndays_dict = Dict()
    
    for (i,z) in enumerate(Ordered_zone_nm)
        rep_dat_dict[z] = Dict()  
        ndays_dict[z] = Dict()
        for nh in 1:n_hours
            ndays_dict[z][nh] = ndays
        end
        tp_df = DataFrame()
        tp_df.Day = [1]  # Single day
        tp_df.Hour = [h for h in 1:24]  # 24 hours
        tp_df[z] = ones(24) * mean(Loaddata[1:24, z])  # Use mean of first 24 hours
        
        n_days = Int(size(tp_df,1)/24)
        for day in 1:n_days
            rep_dat_dict[z][day] = Dict()
            for nh in 1:24
                rep_dat_dict[z][day][nh] = tp_df[(day-1)*24+nh,z]
            end
        end
        
    end
    return (rep_dat_dict,ndays_dict)
end


function unit_commitment!(config_set::Dict, input_data::Dict, model::Model)
	Gendata = input_data["Gendata"]
	Num_gen=size(Gendata,1)
	#UC sets
	G = [g for g=1:Num_gen]									#Set of all types of generating units, index g
	G_UC = findall(x -> x in [1], Gendata[:,"Flag_UC"])
	H=[h for h=1:24]										#Set of hours, index h - MODIFIED: 24 instead of 8760
	#UC parameters
	FOR_g = Dict(zip(G,Gendata[:,Symbol("FOR")]))#g			#Forced outage rate
	P_max=[Gendata[:,"Pmax (MW)"];]							#Maximum power generation of unit g, MW
	P_min=[Gendata[:,"Pmin (MW)"];]							#Maximum power generation of unit g, MW
	DT_g = Gendata[:,"Min_down_time"]					#Minimum down time
	UT_g = Gendata[:,"Min_up_time"]						#Minimum up time
	STC_g = [Gendata[:,Symbol("Start_up_cost (\$/MW)")];]	#Start up cost
	#UC variables
	if config_set["unit_commitment"] == 1
		@variable(model, z[g in G_UC,h in H], Bin, base_name = "z_UC")
		@variable(model, y[g in G_UC,h in H], Bin, base_name = "y_UC")
		@variable(model, x[g in G_UC,h in H], Bin, base_name = "x_UC")
		@variable(model, p_G[g in G_UC,h in H] >= 0, base_name = "p_G_UC")
		#UC Constraints
		#(10) Generation limits
		GLe_UC_con=@constraint(model, [g in G_UC, h in H], p_G[g,h] <= (1-FOR_g[g]) * P_max[g] * z[g,h],base_name = "GLe_UC_con")
		GLb_UC_con=@constraint(model, [g in G_UC, h in H], p_G[g,h] >= P_min[g] * z[g,h],base_name = "GLb_UC_con")
		#(11) Logical constraint
		if length(H) > 1
			LC_UC_con=@constraint(model, [g in G_UC, h in H[2:end]], z[g,h] - z[g,h-1] == y[g,h] - x[g,h],base_name = "LC_UC_con")
		end
		#(12) Minimum up time
		if length(H) > 1
			for g in G_UC
				if UT_g[g] > 1
					for h in H[1:min(length(H)-UT_g[g]+1,length(H))]
						MUT_UC_con=@constraint(model, sum(y[g,t] for t in h:h+UT_g[g]-1) <= z[g,h+UT_g[g]-1],base_name = "MUT_UC_con")
					end
				end
			end
		end
		#(13) Minimum down time
		if length(H) > 1
			for g in G_UC
				if DT_g[g] > 1
					for h in H[1:min(length(H)-DT_g[g]+1,length(H))]
						MDT_UC_con=@constraint(model, sum(x[g,t] for t in h:h+DT_g[g]-1) <= 1-z[g,h+DT_g[g]-1],base_name = "MDT_UC_con")
					end
				end
			end
		end
		return (G_UC, p_G, z, y, x)
	else
		return (G_UC, nothing, nothing, nothing, nothing)
	end
end

function unit_commitment_cost!(config_set::Dict, input_data::Dict, model::Model,G_UC,z,y,x)
	if config_set["unit_commiment_cost"] == 1 && config_set["unit_commitment"] == 1
		Gendata = input_data["Gendata"]
		STC_g = [Gendata[:,Symbol("Start_up_cost (\$/MW)")];]	#Start up cost
		H=[h for h=1:24]										#Set of hours, index h - MODIFIED: 24 instead of 8760
		#(14) Start up cost
		@variable(model, C_s[g in G_UC,h in H] >= 0, base_name = "C_s")
		SC_UC_con=@constraint(model, [g in G_UC, h in H], C_s[g,h] >= STC_g[g] * y[g,h],base_name = "SC_UC_con")
		return C_s
	else
		return nothing
	end
end

function demand_response!(config_set::Dict, input_data::Dict, model::Model)
	if config_set["demand_response"] == 1
		Demanddata = input_data["Demanddata"]
		Num_DR=size(Demanddata,1)
		#DR sets
		D = [d for d=1:Num_DR]									#Set of all types of flexible demand, index d
		H=[h for h=1:24]										#Set of hours, index h - MODIFIED: 24 instead of 8760
		HD = [h for h in 1:24]									#Set of hours in one day, index h, subset of H
		H_D = [h for h in 0:24:24]								#Set of first hours in each day - MODIFIED: single day
		T = [t for t=1:1]										#Set of time periods (days), index t - MODIFIED: single day
		#DR parameters
		DRcap_d = [Demanddata[:,"DRcap(MW)"];]					#DR capacity, MW
		penalty_DR = [Demanddata[:,"Penalty(\$/MWh)"];]			#DR penalty, $/MWh
		#DR variables
		@variable(model, dr_UP[d in D,h in H] >= 0, base_name = "dr_UP")
		@variable(model, dr_DN[d in D,h in H] >= 0, base_name = "dr_DN")
		#DR Constraints
		#(22) DR capacity limit
		DRcap_UP_con=@constraint(model, [d in D, h in H], dr_UP[d,h] <= DRcap_d[d],base_name = "DRcap_UP_con")
		DRcap_DN_con=@constraint(model, [d in D, h in H], dr_DN[d,h] <= DRcap_d[d],base_name = "DRcap_DN_con")
		#(23) DR energy balance
		if length(H_D) > 1  # Skip if only one day
			DR_day_con=@constraint(model, [d in D, h in setdiff(H_D, [0,24])], sum(dr_UP[d,h1] for h1 in h:h+23)==sum(dr_DN[d,h1] for h1 in h:h+23),base_name="DR_day_con")
		end
		return (D, dr_UP, dr_DN)
	else
		return (nothing, nothing, nothing)
	end
end

function production_cost_model!(config_set::Dict, input_data::Dict, model::Model)
	
	# Check if separate unit commitment is used
	separate_uc = get(config_set, "unit_commitment", 0) == 1
	
	if separate_uc
		println("    Separate unit commitment model detected")
		(G_UC, p_G_UC, z, y, x) = unit_commitment!(config_set, input_data, model)
		C_s = unit_commitment_cost!(config_set, input_data, model, G_UC, z, y, x)
		(D, dr_UP, dr_DN) = demand_response!(config_set, input_data, model)
	else
		G_UC = []
		p_G_UC = nothing
		z = nothing
		y = nothing 
		x = nothing
		C_s = nothing
		D = nothing
		dr_UP = nothing
		dr_DN = nothing
	end
	
	# Data extraction
	Gendata = input_data["Gendata"]
	Storagedata = input_data["Storagedata"]
	Zonedata = input_data["Zonedata"]
	Linedata = input_data["Linedata"] 
	Line_distances = input_data["Line_distances"]
	Load_timeseries = input_data["Load_timeseries"]
	Wind_timeseries = input_data["Wind_timeseries"]
	Solar_timeseries = input_data["Solar_timeseries"]
	Flexibledemand_timeseries = get(input_data, "Flexibledemand_timeseries", DataFrame())  # Handle missing key
	
	# Dimensions
	Num_gen=size(Gendata,1)
	Num_stor=size(Storagedata,1)
	Num_zone=size(Zonedata,1)
	Num_line=size(Linedata,1)
	
	# Modified: Use 24 hours instead of 8760
	H=[h for h=1:24]										#Set of hours, index h
	HD = [h for h in 1:24]									#Set of hours in one day, index h, subset of H
	H_D = [h for h in 0:24:24]								#Set of first hours in each day - MODIFIED
	
	# Sets
	G = [g for g=1:Num_gen]									#Set of all types of generating units, index g
	S = [s for s=1:Num_stor]								#Set of all types of storage units, index s
	Z = [z for z=1:Num_zone]								#Set of zones, index z
	L = [l for l=1:Num_line]								#Set of lines, index l
	
	S_exist = findall(x -> x in [1], Storagedata[:,"Flag_retrofit"])
	S_new = findall(x -> x in [0], Storagedata[:,"Flag_retrofit"])
	
	G_exist = findall(x -> (x in [1]) && !(x in [0]), Gendata[:,"Flag_retrofit"])
	G_new = findall(x -> x in [0], Gendata[:,"Flag_retrofit"])
	G_must_run = findall(x -> x in [1], Gendata[:,"Flag_must_run"])
	
	# Parameters
	println("      Loading generator parameters...")
	FOR_g = Dict(zip(G,Gendata[:,Symbol("FOR")]))
	c_g = Dict(zip(G,Gendata[:,Symbol("Variable_cost (\$/MWh)")]))
	P_max = Dict(zip(G,Gendata[:,Symbol("Pmax (MW)")]))
	P_min = Dict(zip(G,Gendata[:,Symbol("Pmin (MW)")]))
	
	# Network parameters
	TCAP = Dict(zip(L,Linedata[:,Symbol("Capacity (MW)")]))
	B = Dict(L => Inf for l in L)  # Susceptance (not used in DC model)
	
	println("      Loading load data...")
	# Load data - only use first 24 hours
	P_load = Dict()
	for i in 1:Num_zone
		zone_name = Zonedata[i, "Zone"]
		if zone_name in names(Load_timeseries)
			full_load = Load_timeseries[1:24, zone_name]  # Only first 24 hours
			P_load[i] = full_load
		else
			P_load[i] = ones(24)  # Default
		end
	end
	
	println("      Loading renewable data...")
	# Renewable capacity factors - only use first 24 hours
	CF_wind = Dict()
	CF_solar = Dict()
	for g in G
		gen_name = Gendata[g, "Resource"]
		
		if occursin("Wind", gen_name) && gen_name in names(Wind_timeseries)
			CF_wind[g] = Wind_timeseries[1:24, gen_name]  # Only first 24 hours
		else
			CF_wind[g] = zeros(24)
		end
		
		if occursin("Solar", gen_name) && gen_name in names(Solar_timeseries)
			CF_solar[g] = Solar_timeseries[1:24, gen_name]  # Only first 24 hours
		else
			CF_solar[g] = zeros(24)
		end
	end
	
	# Storage parameters
	ETA_in = Dict(zip(S,Storagedata[:,Symbol("Eta_in")]))
	ETA_out = Dict(zip(S,Storagedata[:,Symbol("Eta_out")]))
	SECAP = Dict(zip(S,Storagedata[:,Symbol("Energy_cap (MWh)")]))
	SPCAP = Dict(zip(S,Storagedata[:,Symbol("Power_cap (MW)")]))
	
	# Economic parameters
	carbon_price = get(config_set, "carbon_price", 0.0)
	println("      Carbon price: $(carbon_price) \$/tCO2")
	
	# Variables
	println("    Creating variables...")
	@variable(model, p_G[g in G, h in H] >= 0, base_name = "p_G")
	@variable(model, p_wind[g in G, h in H] >= 0, base_name = "p_wind")
	@variable(model, p_solar[g in G, h in H] >= 0, base_name = "p_solar")
	@variable(model, p_charge[s in S, h in H] >= 0, base_name = "p_charge")
	@variable(model, p_discharge[s in S, h in H] >= 0, base_name = "p_discharge")
	@variable(model, soc[s in S, h in H] >= 0, base_name = "soc")
	@variable(model, p_shed[z in Z, h in H] >= 0, base_name = "p_shed")
	@variable(model, p_flow[l in L, h in H], base_name = "p_flow")  # Can be negative
	
	println("    Creating constraints...")
	
	# Generation limits
	@constraint(model, [g in G, h in H], p_G[g,h] <= (1-FOR_g[g]) * P_max[g])
	@constraint(model, [g in G, h in H], p_G[g,h] >= P_min[g])
	
	# Renewable generation limits
	@constraint(model, [g in G, h in H], p_wind[g,h] <= P_max[g] * CF_wind[g][h])
	@constraint(model, [g in G, h in H], p_solar[g,h] <= P_max[g] * CF_solar[g][h])
	
	# Storage constraints
	@constraint(model, [s in S, h in H], p_charge[s,h] <= SPCAP[s])
	@constraint(model, [s in S, h in H], p_discharge[s,h] <= SPCAP[s])
	@constraint(model, [s in S, h in H], soc[s,h] <= SECAP[s])
	
	# Storage energy balance
	for s in S
		@constraint(model, soc[s,1] == 0.5 * SECAP[s] + ETA_in[s] * p_charge[s,1] - p_discharge[s,1])
		for h in H[2:end]
			@constraint(model, soc[s,h] == soc[s,h-1] + ETA_in[s] * p_charge[s,h] - p_discharge[s,h])
		end
	end
	
	# Periodic storage constraint - Modified for 24 hours
	@constraint(model, [s in S_exist], soc[s,1] == soc[s,24])  # MODIFIED: 24 instead of 8760
	@constraint(model, [s in S_exist], soc[s,24] == 0.5 * SECAP[s])  # MODIFIED: 24 instead of 8760
	
	# Transmission constraints
	@constraint(model, [l in L, h in H], p_flow[l,h] <= TCAP[l])
	@constraint(model, [l in L, h in H], p_flow[l,h] >= -TCAP[l])
	
	# Network flow balance (simplified - no network topology)
	# For each zone, generation + imports = load + exports
	for z in Z
		for h in H
			# Find generators in this zone
			gens_in_zone = findall(x -> x == z, Gendata[:,"Zone"])
			stor_in_zone = findall(x -> x == z, Storagedata[:,"Zone"])
			
			# Find lines connected to this zone
			lines_from_zone = findall(x -> x == z, Linedata[:,"From_zone"])
			lines_to_zone = findall(x -> x == z, Linedata[:,"To_zone"])
			
			@constraint(model, 
				sum(p_G[g,h] + p_wind[g,h] + p_solar[g,h] for g in gens_in_zone) +
				sum(p_discharge[s,h] - p_charge[s,h] for s in stor_in_zone) +
				sum(p_flow[l,h] for l in lines_to_zone) -
				sum(p_flow[l,h] for l in lines_from_zone) +
				p_shed[z,h] == P_load[z][h]
			)
		end
	end
	
	# Objective function
	println("    Creating objective...")
	
	# Generation costs
	gen_cost = sum(c_g[g] * p_G[g,h] for g in G, h in H)
	
	# Load shedding penalty
	shed_cost = sum(1000.0 * p_shed[z,h] for z in Z, h in H)  # $1000/MWh penalty
	
	# Unit commitment costs
	if separate_uc && C_s !== nothing
		startup_cost = sum(C_s[g,h] for g in G_UC, h in H)
	else
		startup_cost = 0
	end
	
	# Demand response costs
	if separate_uc && dr_UP !== nothing && dr_DN !== nothing
		dr_cost = sum(penalty_DR[d] * (dr_UP[d,h] + dr_DN[d,h]) for d in D, h in H)
	else
		dr_cost = 0
	end
	
	@objective(model, Min, gen_cost + shed_cost + startup_cost + dr_cost)
	
	println("    PCM model created successfully!")
	println("      Variables: $(num_variables(model))")
	println("      Constraints: $(num_constraints(model, include_variable_in_set_constraints=false))")
	
	return model
end
