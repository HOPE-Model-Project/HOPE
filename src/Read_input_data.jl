#Function use for aggregrating generation data:
function aggregate_gendata_gtep(df)
	agg_df = combine(groupby(df, [:Zone,:Type]),
	Symbol("Pmax (MW)") => sum,
	Symbol("Pmin (MW)") => sum,
	Symbol("Cost (\$/MWh)")=> mean,
	:EF => mean,
	:CC => mean)
	rename!(agg_df, [Symbol("Pmax (MW)_sum"), Symbol("Pmin (MW)_sum"),Symbol("Cost (\$/MWh)_mean"),:EF_mean,:CC_mean] .=>  [Symbol("Pmax (MW)"), Symbol("Pmin (MW)"), Symbol("Cost (\$/MWh)"),:EF,:CC] )
	return agg_df
end

function aggregate_gendata_pcm(df)
	agg_df = combine(groupby(df, [:Zone,:Type]),
	Symbol("Pmax (MW)") => sum,
	Symbol("Pmin (MW)") => sum,
	Symbol("Cost (\$/MWh)")=> mean,
	:EF => mean,
	:CC => mean,
	:FOR => mean,
	:RM_SPIN => mean,
	:RU => mean,
	:RD => mean)
	rename!(agg_df, [Symbol("Pmax (MW)_sum"), Symbol("Pmin (MW)_sum"),Symbol("Cost (\$/MWh)_mean"),:EF_mean,:CC_mean,:FOR_mean,:RM_SPIN_mean,:RU_mean,:RD_mean] 
	.=>  [Symbol("Pmax (MW)"), Symbol("Pmin (MW)"), Symbol("Cost (\$/MWh)"),:EF,:CC,:FOR,:RM_SPIN,:RU,:RD])
	return agg_df
end

function load_data(config_set::Dict,path::AbstractString)
    Data_case = config_set["DataCase"]
    model_mode = config_set["model_mode"]
    if model_mode == "GTEP"                 #read data for generation and transmission expansion model
        input_data = Dict()
        println("Reading Input_Data Files for GTEP mode")
        folderpath = joinpath(path,Data_case)
        files = readdir(folderpath)
        if any(endswith.(files, ".xlsx"))
            println("The directory $folderpath contains .xlsx file, then try to read input data from GTEP_input_total.xlsx")
            #xlsx_file = XLSX.readxlsx(path*Data_case*"GTEP_input_total.xlsx")
            
            #network
            println("Reading network")
            input_data["Busdata"]=DataFrame(XLSX.readtable(joinpath(folderpath,"GTEP_input_total.xlsx"),"busdata"))
            input_data["Branchdata"]=DataFrame(XLSX.readtable(joinpath(folderpath,"GTEP_input_total.xlsx"),"branchdata"))
            #technology
            println("Reading technology")
            if config_set["aggregated!"]==1
                input_data["Gendata"] = aggregate_gendata_gtep(DataFrame(XLSX.readtable(joinpath(folderpath,"GTEP_input_total.xlsx"),"gendata")))
            else
                input_data["Gendata"]=DataFrame(XLSX.readtable(joinpath(folderpath,"GTEP_input_total.xlsx"),"gendata"))
            end 
            
            input_data["Estoragedata"]=DataFrame(XLSX.readtable(joinpath(folderpath,"GTEP_input_total.xlsx"),"Estoragedata"))
            input_data["Gencostdata"]=input_data["Gendata"][:,Symbol("Cost (\$/MWh)")]
            #time series
            println("Reading time series")
            input_data["Winddata"]=DataFrame(XLSX.readtable(joinpath(folderpath,"GTEP_input_total.xlsx"),"WT_timeseries_regional"))
            input_data["Solardata"]=DataFrame(XLSX.readtable(joinpath(folderpath,"GTEP_input_total.xlsx"),"SPV_timeseries_regional"))
            input_data["Loaddata"]=DataFrame(XLSX.readtable(joinpath(folderpath,"GTEP_input_total.xlsx"),"Load_timeseries_regional"))
            input_data["NIdata"]=input_data["Loaddata"][:,"NI"]
            #candidate
            println("Reading resourc candidate")
            input_data["Estoragedata_candidate"]=DataFrame(XLSX.readtable(joinpath(folderpath,"GTEP_input_total.xlsx"),"Estoragedata_candidate"))
            input_data["Linedata_candidate"]=DataFrame(XLSX.readtable(joinpath(folderpath,"GTEP_input_total.xlsx"),"Linedata_candidate"))
            input_data["Gendata_candidate"]=DataFrame(XLSX.readtable(joinpath(folderpath,"GTEP_input_total.xlsx"),"Gendata_candidate"))
            #policies
            println("Reading polices")
            input_data["CBPdata"]=DataFrame(XLSX.readtable(joinpath(folderpath,"GTEP_input_total.xlsx"),"carbonpolices"))
            #rpspolicydata=
            input_data["RPSdata"]=DataFrame(XLSX.readtable(joinpath(folderpath,"GTEP_input_total.xlsx"),"rpspolicies"))
            println("xlsx Files Successfully Load From $folderpath")

        else
            println("No xlsx file found in the directory $folderpath, try to read data from .csv files")
        
            #network
            #Busdata=CSV.read("Data/busdata.csv",DataFrame)
            println("Reading network")
            input_data["Busdata"]=CSV.read(joinpath(folderpath,"busdata.csv"),DataFrame) #110% Peak
            input_data["Branchdata"]=CSV.read(joinpath(folderpath,"branchdata.csv"),DataFrame)
            #technology
            println("Reading technology")
            if config_set["aggregated!"]==1
                input_data["Gendata"] = aggregate_gendata_gtep(CSV.read(joinpath(folderpath,"gendata.csv"),DataFrame))
            else
                input_data["Gendata"]=CSV.read(joinpath(folderpath,"gendata.csv"),DataFrame)
            end 
            
            input_data["Estoragedata"]=CSV.read(joinpath(folderpath,"Estoragedata.csv"),DataFrame)
            input_data["Gencostdata"]=input_data["Gendata"][:,Symbol("Cost (\$/MWh)")]
            #time series
            println("Reading time series")
            input_data["Winddata"]=CSV.read(joinpath(folderpath,"WT_timeseries_regional.csv"),DataFrame)
            input_data["Solardata"]=CSV.read(joinpath(folderpath,"SPV_timeseries_regional.csv"),DataFrame)
            input_data["Loaddata"]=CSV.read(joinpath(folderpath,"Load_timeseries_regional.csv"),DataFrame)
            input_data["NIdata"]=input_data["Loaddata"][:,"NI"]
            #candidate
            println("Reading resource candidate")
            input_data["Estoragedata_candidate"]=CSV.read(joinpath(folderpath,"Estoragedata_candidate.csv"),DataFrame)
            input_data["Linedata_candidate"]=CSV.read(joinpath(folderpath,"Linedata_candidate.csv"),DataFrame)
            input_data["Gendata_candidate"]=CSV.read(joinpath(folderpath,"Gendata_candidate.csv"),DataFrame)
            #policies
            println("Reading polices")
            input_data["CBPdata"]=CSV.read(joinpath(folderpath,"carbonpolices.csv"),DataFrame)
            #rpspolicydata=
            input_data["RPSdata"]=CSV.read(joinpath(folderpath,"rpspolicies.csv"),DataFrame)
            println("CSV Files Successfully Load From $folderpath")
        end


    
    elseif model_mode == "PCM"          #read data for production cost model
        input_data = Dict()
        println("Reading Input_Data Files for PCM mode")
        folderpath = joinpath(path*"/"*Data_case)
        files = readdir(folderpath)
        if any(endswith.(files, ".xlsx"))
            println("The directory $folderpath contains .xlsx file, then try to read input data from PCM_input_total.xlsx")
            #xlsx_file = XLSX.readxlsx(path*Data_case*"PCM_input_total.xlsx")

            #network
            println("Reading network")
            input_data["Busdata"]=DataFrame(XLSX.readtable(joinpath(folderpath,"PCM_input_total.xlsx"),"busdata"))
            input_data["Branchdata"]=DataFrame(XLSX.readtable(joinpath(folderpath,"PCM_input_total.xlsx"),"branchdata"))
            #technology
            println("Reading technology")
            if config_set["aggregated!"]==1
                input_data["Gendata"] = aggregate_gendata_pcm(DataFrame(XLSX.readtable(joinpath(folderpath,"PCM_input_total.xlsx"),"gendata")))
            else
                input_data["Gendata"]=DataFrame(XLSX.readtable(joinpath(folderpath,"PCM_input_total.xlsx"),"gendata"))
            end 
            
            input_data["Estoragedata"]=DataFrame(XLSX.readtable(joinpath(folderpath,"PCM_input_total.xlsx"),"Estoragedata"))
            input_data["Gencostdata"]=input_data["Gendata"][:,Symbol("Cost (\$/MWh)")]

        
            #time series
            println("Reading time series")
            input_data["Winddata"]=DataFrame(XLSX.readtable(joinpath(folderpath,"PCM_input_total.xlsx"),"WT_timeseries_regional"))
            input_data["Solardata"]=DataFrame(XLSX.readtable(joinpath(folderpath,"PCM_input_total.xlsx"),"SPV_timeseries_regional"))
            input_data["Loaddata"]=DataFrame(XLSX.readtable(joinpath(folderpath*"PCM_input_total.xlsx"),"Load_timeseries_regional"))
            input_data["NIdata"]=input_data["Loaddata"][:,"NI"]

            #policies
            println("Reading polices")
            input_data["CBPdata"]=DataFrame(XLSX.readtable(joinpath(folderpath,"PCM_input_total.xlsx"),"carbonpolices"))
            #rpspolicydata=
            input_data["RPSdata"]=DataFrame(XLSX.readtable(joinpath(folderpath,"PCM_input_total.xlsx"),"rpspolicies"))
            println("xlsx Files Successfully Load From $folderpath")
        else
            println("No xlsx file found in the directory $folderpath, try to read data from .csv files")
            
            println("Reading network")
            input_data["Busdata"]=CSV.read(joinpath(folderpath,"busdata.csv"),DataFrame)
            input_data["Branchdata"]=CSV.read(joinpath(folderpath,"branchdata.csv"),DataFrame)
            #technology
            println("Reading technology")
            if config_set["aggregated!"]==1
                input_data["Gendata"] = aggregate_gendata_pcm(CSV.read(joinpath(folderpath,"gendata.csv"),DataFrame))
            else
                input_data["Gendata"]=CSV.read(joinpath(folderpath,"gendata.csv"),DataFrame)
            end 
            
            input_data["Estoragedata"]=CSV.read(joinpath(folderpath,"Estoragedata.csv"),DataFrame)
            input_data["Gencostdata"]=input_data["Gendata"][:,Symbol("Cost (\$/MWh)")]

        
            #time series
            println("Reading time series")
            input_data["Winddata"]=CSV.read(joinpath(folderpath,"WT_timeseries_regional.csv"),DataFrame)
            input_data["Solardata"]=CSV.read(joinpath(folderpath,"SPV_timeseries_regional.csv"),DataFrame)
            input_data["Loaddata"]=CSV.read(joinpath(folderpath,"Load_timeseries_regional.csv"),DataFrame)
            input_data["NIdata"]=input_data["Loaddata"][:,"NI"]

            #policies
            println("Reading polices")
            input_data["CBPdata"]=CSV.read(joinpath(folderpath,"carbonpolices.csv"),DataFrame)
            #rpspolicydata=
            input_data["RPSdata"]=CSV.read(joinpath(folderpath,"rpspolicies.csv"),DataFrame)
            println("CSV Files Successfully Load From $folderpath")
        end   
    end
    return input_data
end
