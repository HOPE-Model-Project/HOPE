#Function use for aggregrating generation data:
function aggregate_gendata_gtep(df)
    if !("AF" in names(df))
        df = copy(df)
        df[!, :AF] = fill(1.0, nrow(df))
    end
    #print(df)
    if "Flag_RPS" in names(df)
	    agg_df = combine(groupby(df, [:Zone,:Type]),
	    Symbol("Pmax (MW)") .=> sum,
	    Symbol("Pmin (MW)") .=> sum,
	    Symbol("Cost (\$/MWh)") .=> mean,
	    :EF .=> mean,
	    :CC .=> mean,
        :AF .=> mean,
        :Flag_thermal .=> mean,
        :Flag_VRE .=> mean,
        :Flag_RET .=> mean,
        :Flag_mustrun .=> mean,
        :Flag_RPS .=> mean,)
        rename!(agg_df, [Symbol("Pmax (MW)_sum"), Symbol("Pmin (MW)_sum"),Symbol("Cost (\$/MWh)_mean"),:EF_mean,:CC_mean,:AF_mean,:Flag_thermal_mean,:Flag_VRE_mean,:Flag_RET_mean,:Flag_mustrun_mean,:Flag_RPS_mean] .=>  [Symbol("Pmax (MW)"), Symbol("Pmin (MW)"), Symbol("Cost (\$/MWh)"),:EF,:CC,:AF,:Flag_thermal,:Flag_VRE,:Flag_RET,:Flag_mustrun,:Flag_RPS] )
    else
	    agg_df = combine(groupby(df, [:Zone,:Type]),
	    Symbol("Pmax (MW)") .=> sum,
	    Symbol("Pmin (MW)") .=> sum,
	    Symbol("Cost (\$/MWh)") .=> mean,
	    :EF .=> mean,
	    :CC .=> mean,
        :AF .=> mean,
        :Flag_thermal .=> mean,
        :Flag_VRE .=> mean,
        :Flag_RET .=> mean,
        :Flag_mustrun .=> mean,)
        rename!(agg_df, [Symbol("Pmax (MW)_sum"), Symbol("Pmin (MW)_sum"),Symbol("Cost (\$/MWh)_mean"),:EF_mean,:CC_mean,:AF_mean,:Flag_thermal_mean,:Flag_VRE_mean,:Flag_RET_mean,:Flag_mustrun_mean] .=>  [Symbol("Pmax (MW)"), Symbol("Pmin (MW)"), Symbol("Cost (\$/MWh)"),:EF,:CC,:AF,:Flag_thermal,:Flag_VRE,:Flag_RET,:Flag_mustrun] )
    end
    agg_df[agg_df.Flag_thermal .> 0, :Flag_thermal] .=1
    agg_df[agg_df.Flag_VRE .> 0, :Flag_VRE] .=1
    agg_df[agg_df.Flag_RET .> 0, :Flag_RET] .=1
    agg_df[agg_df.Flag_mustrun .> 0, :Flag_mustrun] .=1
    if "Flag_RPS" in names(agg_df)
        agg_df[agg_df.Flag_RPS .> 0, :Flag_RPS] .=1
    end
	#Note: below line and the derived file is just for developer use
    #CSV.write("D:\\Coding\\Master\\HOPE\\ModelCases\\PJM_case\\debug_report\\agg_gen.csv", agg_df, writeheader=true)
    return agg_df
end

function aggregate_gendata_pcm(df::DataFrame, config_set::Dict)
	if config_set["unit_commitment"] == 0
        agg_df = combine(groupby(df, [:Zone,:Type]),
        Symbol("Pmax (MW)") .=> sum,
        Symbol("Pmin (MW)") .=> sum,
        Symbol("Cost (\$/MWh)") .=> mean,
        :EF .=> mean,
        :CC .=> mean,
        :FOR .=> mean,
        :RM_SPIN .=> mean,
        :RU .=> mean,
        :RD .=> mean,
        :Flag_thermal .=> mean,
        :Flag_VRE .=> mean,
        :Flag_mustrun .=> mean)
        rename!(agg_df, [Symbol("Pmax (MW)_sum"), Symbol("Pmin (MW)_sum"),Symbol("Cost (\$/MWh)_mean"),:EF_mean,:CC_mean,:FOR_mean,:RM_SPIN_mean,:RU_mean,:RD_mean,:Flag_thermal_mean,:Flag_VRE_mean,:Flag_mustrun_mean] 
        .=>  [Symbol("Pmax (MW)"), Symbol("Pmin (MW)"), Symbol("Cost (\$/MWh)"),:EF,:CC,:FOR,:RM_SPIN,:RU,:RD,:Flag_thermal,:Flag_VRE,:Flag_mustrun])
        #:Flag_UC .=> mean
        agg_df[agg_df.Flag_thermal .> 0, :Flag_thermal] .=1
        agg_df[agg_df.Flag_VRE .> 0, :Flag_VRE] .=1
        agg_df[agg_df.Flag_mustrun .> 0, :Flag_mustrun] .=1
        for rm_col in (:RM_REG_UP, :RM_REG_DN, :RM_NSPIN)
            if rm_col in names(df)
                rm_df = combine(groupby(df, [:Zone,:Type]), rm_col => mean => rm_col)
                agg_df = leftjoin(agg_df, rm_df, on=[:Zone,:Type])
            end
        end
        return agg_df
    else
        agg_df = combine(groupby(df, [:Zone,:Type]),
        Symbol("Pmax (MW)") .=> sum,
        Symbol("Pmin (MW)") .=> sum,
        Symbol("Cost (\$/MWh)") .=> mean,
        :EF .=> mean,
        :CC .=> mean,
        :FOR .=> mean,
        :RM_SPIN .=> mean,
        :RU .=> mean,
        :RD .=> mean,
        :Flag_thermal .=> mean,
        :Flag_VRE .=> mean,
        :Flag_UC .=> mean,
        :Flag_mustrun .=> mean,
        Symbol("Start_up_cost (\$/MW)") .=> mean,
        :Min_down_time .=> mean,
        :Min_up_time .=> mean
        )
        rename!(agg_df, [Symbol("Pmax (MW)_sum"), Symbol("Pmin (MW)_sum"),Symbol("Cost (\$/MWh)_mean"),:EF_mean,:CC_mean,:FOR_mean,:RM_SPIN_mean,:RU_mean,:RD_mean,:Flag_thermal_mean,:Flag_VRE_mean,:Flag_mustrun_mean,:Flag_UC_mean,Symbol("Start_up_cost (\$/MW)_mean"),:Min_down_time_mean,:Min_up_time_mean] 
        .=>  [Symbol("Pmax (MW)"), Symbol("Pmin (MW)"), Symbol("Cost (\$/MWh)"),:EF,:CC,:FOR,:RM_SPIN,:RU,:RD,:Flag_thermal,:Flag_VRE,:Flag_mustrun,:Flag_UC,Symbol("Start_up_cost (\$/MW)"),:Min_down_time,:Min_up_time])
        agg_df[agg_df.Flag_thermal .> 0, :Flag_thermal] .=1
        agg_df[agg_df.Flag_VRE .> 0, :Flag_VRE] .=1
        agg_df[agg_df.Flag_mustrun .> 0, :Flag_mustrun] .=1
        agg_df[agg_df.Flag_UC .> 0, :Flag_UC] .=1
        for rm_col in (:RM_REG_UP, :RM_REG_DN, :RM_NSPIN)
            if rm_col in names(df)
                rm_df = combine(groupby(df, [:Zone,:Type]), rm_col => mean => rm_col)
                agg_df = leftjoin(agg_df, rm_df, on=[:Zone,:Type])
            end
        end
        return agg_df
    end
end

function load_data(config_set::Dict,path::AbstractString)
    Data_case = config_set["DataCase"]
    model_mode = config_set["model_mode"]
    flexible_demand_raw = get(config_set, "flexible_demand", 0)
    flexible_demand = flexible_demand_raw isa Integer ? Int(flexible_demand_raw) : parse(Int, string(flexible_demand_raw))
    
    if model_mode == "GTEP"                 #read data for generation and transmission expansion model
        input_data = Dict()
        println("Reading Input_Data Files for GTEP mode")
        #input_data["VOLL"] = config_set["value_of_loss_load"]
        folderpath = joinpath(path,Data_case)
        files = readdir(folderpath)
        if any(endswith.(files, ".xlsx"))
            println("The directory $folderpath contains .xlsx file, then try to read input data from GTEP_input_total.xlsx")
            #xlsx_file = XLSX.readxlsx(path*Data_case*"GTEP_input_total.xlsx")
            
            #network
            println("Reading network")
            input_data["Zonedata"]=DataFrame(XLSX.readtable(joinpath(folderpath,"GTEP_input_total.xlsx"),"zonedata"))
            input_data["Linedata"]=DataFrame(XLSX.readtable(joinpath(folderpath,"GTEP_input_total.xlsx"),"linedata"))
            #technology
            println("Reading technology")
            if config_set["aggregated!"]==1
                input_data["Gendata"] = aggregate_gendata_gtep(DataFrame(XLSX.readtable(joinpath(folderpath,"GTEP_input_total.xlsx"),"gendata")))
            else
                input_data["Gendata"]=DataFrame(XLSX.readtable(joinpath(folderpath,"GTEP_input_total.xlsx"),"gendata"))
            end 
            
            input_data["Storagedata"]=DataFrame(XLSX.readtable(joinpath(folderpath,"GTEP_input_total.xlsx"),"storagedata"))
            if flexible_demand == 1
                input_data["DRdata"]=DataFrame(XLSX.readtable(joinpath(folderpath,"flexddata.xlsx"),"storagedata"))
            end
            #time series
            println("Reading time series")
            input_data["Loaddata"]=DataFrame(XLSX.readtable(joinpath(folderpath,"GTEP_input_total.xlsx"),"load_timeseries_regional"))
            input_data["NIdata"]=input_data["Loaddata"][:,"NI"]
            if flexible_demand == 1
                input_data["DRtsdata"]=DataFrame(XLSX.readtable(joinpath(folderpath,"GTEP_input_total.xlsx"),"dr_timeseries_regional"))
            end
            #candidate
            println("Reading resource candidate")
            input_data["Estoragedata_candidate"]=DataFrame(XLSX.readtable(joinpath(folderpath,"GTEP_input_total.xlsx"),"Estoragedata_candidate"))
            input_data["Linedata_candidate"]=DataFrame(XLSX.readtable(joinpath(folderpath,"GTEP_input_total.xlsx"),"linedata_candidate"))
            input_data["Gendata_candidate"]=DataFrame(XLSX.readtable(joinpath(folderpath,"GTEP_input_total.xlsx"),"gendata_candidate"))
            #policies
            println("Reading polices")
            input_data["CBPdata"]=DataFrame(XLSX.readtable(joinpath(folderpath,"GTEP_input_total.xlsx"),"carbonpolicies"))
            #rpspolicydata
            input_data["RPSdata"]=DataFrame(XLSX.readtable(joinpath(folderpath,"GTEP_input_total.xlsx"),"rpspolicies"))
            #penalty_cost, investment budgets, planning reserve margins etc. single parameters
            println("Reading single parameters")
            input_data["Singlepar"]=DataFrame(XLSX.readtable(joinpath(folderpath, "GTEP_input_total.xlsx"),"single_parameter"))
            xlsx_path = joinpath(folderpath,"GTEP_input_total.xlsx")
            sheets = XLSX.sheetnames(xlsx_path)
            if "gen_availability_timeseries" in sheets
                input_data["AFdata"] = DataFrame(XLSX.readtable(xlsx_path, "gen_availability_timeseries"))
            else
                throw(ArgumentError("Missing required generator availability timeseries input. Provide sheet 'gen_availability_timeseries' in GTEP_input_total.xlsx."))
            end

            println("xlsx Files Successfully Load From $folderpath")

        else
            println("No xlsx file found in the directory $folderpath, try to read data from .csv files")
        
            #network
            #Zonedata=CSV.read("Data/zonedata.csv",DataFrame)
            println("Reading network")
            input_data["Zonedata"]=CSV.read(joinpath(folderpath,"zonedata.csv"),DataFrame) #110% Peak
            input_data["Linedata"]=CSV.read(joinpath(folderpath,"linedata.csv"),DataFrame)
            #technology
            println("Reading technology")
            if config_set["aggregated!"]==1
                input_data["Gendata"] = aggregate_gendata_gtep(CSV.read(joinpath(folderpath,"gendata.csv"),DataFrame))
            else
                input_data["Gendata"]=CSV.read(joinpath(folderpath,"gendata.csv"),DataFrame)
            end 
            
            input_data["Storagedata"]=CSV.read(joinpath(folderpath,"storagedata.csv"),DataFrame)
            if flexible_demand == 1
                input_data["DRdata"]=CSV.read(joinpath(folderpath,"flexddata.csv"),DataFrame)
            end
            #time series
            println("Reading time series")
            input_data["Loaddata"]=CSV.read(joinpath(folderpath,"load_timeseries_regional.csv"),DataFrame)
            input_data["NIdata"]=input_data["Loaddata"][:,"NI"]
            if flexible_demand == 1
                input_data["DRtsdata"]=CSV.read(joinpath(folderpath,"dr_timeseries_regional.csv"),DataFrame)
            end
            #candidate
            println("Reading resource candidate")
            input_data["Estoragedata_candidate"]=CSV.read(joinpath(folderpath,"storagedata_candidate.csv"),DataFrame)
            input_data["Linedata_candidate"]=CSV.read(joinpath(folderpath,"linedata_candidate.csv"),DataFrame)
            input_data["Gendata_candidate"]=CSV.read(joinpath(folderpath,"gendata_candidate.csv"),DataFrame)
            #policies
            println("Reading polices")
            input_data["CBPdata"]=CSV.read(joinpath(folderpath,"carbonpolicies.csv"),DataFrame)
            #rpspolicydata=
            input_data["RPSdata"]=CSV.read(joinpath(folderpath,"rpspolicies.csv"),DataFrame)
            #penalty_cost, investment budgets, planning reserve margins etc. single parameters
            println("Reading single parameters")
            input_data["Singlepar"]=CSV.read(joinpath(folderpath, "single_parameter.csv"),DataFrame)
            af_csv = joinpath(folderpath, "gen_availability_timeseries.csv")
            if isfile(af_csv)
                input_data["AFdata"] = CSV.read(af_csv, DataFrame)
            else
                throw(ArgumentError("Missing required generator availability timeseries input. Provide file 'gen_availability_timeseries.csv'."))
            end

            println("CSV Files Successfully Load From $folderpath")
        end


    
    elseif model_mode == "PCM"          #read data for production cost model
        input_data = Dict()
        println("Reading Input_Data Files for PCM mode")
        folderpath = joinpath(path, Data_case)
        files = readdir(folderpath)
        #input_data["VOLL"] = config_set["value_of_loss_load"]
        if any(endswith.(files, ".xlsx"))
            println("The directory $folderpath contains .xlsx file, then try to read input data from PCM_input_total.xlsx")
            #xlsx_file = XLSX.readxlsx(path*Data_case*"PCM_input_total.xlsx")
            xlsx_path = joinpath(folderpath,"PCM_input_total.xlsx")

            #network
            println("Reading network")
            input_data["Zonedata"]=DataFrame(XLSX.readtable(xlsx_path,"zonedata"))
            input_data["Linedata"]=DataFrame(XLSX.readtable(xlsx_path,"linedata"))
            try
                input_data["Busdata"] = DataFrame(XLSX.readtable(xlsx_path, "busdata"))
                println("Reading optional busdata")
            catch
                # Optional sheet: busdata
            end
            try
                input_data["Branchdata"] = DataFrame(XLSX.readtable(xlsx_path, "branchdata"))
                println("Reading optional branchdata")
            catch
                # Optional sheet: branchdata
            end
            try
                input_data["PTDFdata"] = DataFrame(XLSX.readtable(xlsx_path, "ptdf_matrix"))
                println("Reading optional ptdf_matrix")
            catch
                # Optional sheet: ptdf_matrix
            end
            try
                input_data["PTDFNodalData"] = DataFrame(XLSX.readtable(xlsx_path, "ptdf_matrix_nodal"))
                println("Reading optional ptdf_matrix_nodal")
            catch
                # Optional sheet: ptdf_matrix_nodal
            end
            #technology
            println("Reading technology")
            if config_set["aggregated!"]==1
                input_data["Gendata"] = aggregate_gendata_pcm(DataFrame(XLSX.readtable(xlsx_path,"gendata")),config_set)
            else
                input_data["Gendata"]=DataFrame(XLSX.readtable(xlsx_path,"gendata"))
            end 
            
            input_data["Storagedata"]=DataFrame(XLSX.readtable(xlsx_path,"storagedata"))
            if flexible_demand == 1
                input_data["DRdata"]=DataFrame(XLSX.readtable(xlsx_path,"flexddata"))
            end
        
            #time series
            println("Reading time series")
            input_data["Winddata"]=DataFrame(XLSX.readtable(xlsx_path,"wind_timeseries_regional"))
            input_data["Solardata"]=DataFrame(XLSX.readtable(xlsx_path,"solar_timeseries_regional"))
            input_data["Loaddata"]=DataFrame(XLSX.readtable(xlsx_path,"load_timeseries_regional"))
            input_data["NIdata"]=input_data["Loaddata"][:,"NI"]
            if flexible_demand == 1
                input_data["DRtsdata"]=DataFrame(XLSX.readtable(xlsx_path,"dr_timeseries_regional"))
            end
            #policies
            println("Reading polices")
            input_data["CBPdata"]=DataFrame(XLSX.readtable(xlsx_path,"carbonpolicies"))
            #rpspolicydata=
            input_data["RPSdata"]=DataFrame(XLSX.readtable(xlsx_path,"rpspolicies"))
            #penalty_cost, investment budgets, planning reserve margins etc. single parameters
            println("Reading single parameters")
            input_data["Singlepar"]=DataFrame(XLSX.readtable(xlsx_path,"single_parameter"))

            println("xlsx Files Successfully Load From $folderpath")

        else
            println("No xlsx file found in the directory $folderpath, try to read data from .csv files")
            
            println("Reading network")
            input_data["Zonedata"]=CSV.read(joinpath(folderpath,"zonedata.csv"),DataFrame)
            input_data["Linedata"]=CSV.read(joinpath(folderpath,"linedata.csv"),DataFrame)
            bus_csv_path = joinpath(folderpath, "busdata.csv")
            if isfile(bus_csv_path)
                input_data["Busdata"] = CSV.read(bus_csv_path, DataFrame)
                println("Reading optional busdata.csv")
            end
            branch_csv_path = joinpath(folderpath, "branchdata.csv")
            if isfile(branch_csv_path)
                input_data["Branchdata"] = CSV.read(branch_csv_path, DataFrame)
                println("Reading optional branchdata.csv")
            end
            ptdf_csv_path = joinpath(folderpath, "ptdf_matrix.csv")
            if isfile(ptdf_csv_path)
                input_data["PTDFdata"] = CSV.read(ptdf_csv_path, DataFrame)
                println("Reading optional ptdf_matrix.csv")
            end
            ptdf_nodal_csv_path = joinpath(folderpath, "ptdf_matrix_nodal.csv")
            if isfile(ptdf_nodal_csv_path)
                input_data["PTDFNodalData"] = CSV.read(ptdf_nodal_csv_path, DataFrame)
                println("Reading optional ptdf_matrix_nodal.csv")
            end
            #technology
            println("Reading technology")
            if config_set["aggregated!"]==1
                input_data["Gendata"] = aggregate_gendata_pcm(CSV.read(joinpath(folderpath,"gendata.csv"),DataFrame),config_set)
            else
                input_data["Gendata"]=CSV.read(joinpath(folderpath,"gendata.csv"),DataFrame)
            end 
            
            input_data["Storagedata"]=CSV.read(joinpath(folderpath,"storagedata.csv"),DataFrame)
            if flexible_demand == 1
                input_data["DRdata"]=CSV.read(joinpath(folderpath,"flexddata.csv"),DataFrame)
            end
        
            #time series
            println("Reading time series")
            input_data["Winddata"]=CSV.read(joinpath(folderpath,"wind_timeseries_regional.csv"),DataFrame)
            input_data["Solardata"]=CSV.read(joinpath(folderpath,"solar_timeseries_regional.csv"),DataFrame)
            input_data["Loaddata"]=CSV.read(joinpath(folderpath,"load_timeseries_regional.csv"),DataFrame)
            input_data["NIdata"]=input_data["Loaddata"][:,"NI"]
            if flexible_demand == 1
                input_data["DRtsdata"]=CSV.read(joinpath(folderpath,"dr_timeseries_regional.csv"),DataFrame)
            end
            #policies
            println("Reading policies")
            input_data["CBPdata"]=CSV.read(joinpath(folderpath,"carbonpolicies.csv"),DataFrame)
            #rpspolicydata=
            input_data["RPSdata"]=CSV.read(joinpath(folderpath,"rpspolicies.csv"),DataFrame)
            #penalty_cost, investment budgets, planning reserve margins etc. single parameters
            println("Reading single parameters")
            input_data["Singlepar"]=CSV.read(joinpath(folderpath, "single_parameter.csv"),DataFrame)

            println("CSV Files Successfully Load From $folderpath")
        end   
    end
    return input_data
end
