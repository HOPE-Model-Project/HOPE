#Function use for aggregrating generation data:
function aggregate_gendata_gtep(df)
	agg_df = combine(groupby(df, [:Zone,:Type]),
	Symbol("Pmax (MW)") => sum,
	Symbol("Pmin (MW)") => sum,
	Symbol("Cost (\$/MWh)")=> mean,
	:EF => mean,
	:CC => mean)
	rename!(agg_df, [Symbol("Pmax (MW)_sum"), Symbol("Pmin (MW)_sum"),Symbol("Cost (\$/MWh)_mean"),:EF_mean,:CC_mean] .=>  [Symbol("Pmax (MW)"), Symbol("Pmin (MW)"), Symbol("Cost (\$/MWh)"),:EF,:CC] )
	#Note: below line and the derived file is just for developer use
    #CSV.write("D:\\Coding\\Master\\HOPE\\ModelCases\\PJM_case\\debug_report\\agg_gen.csv", agg_df, writeheader=true)
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
        input_data["VOLL"] = config_set["value_of_loss_of_load"]
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
            input_data["Gencostdata"]=input_data["Gendata"][:,Symbol("Cost (\$/MWh)")]
            #time series
            println("Reading time series")
            input_data["Winddata"]=DataFrame(XLSX.readtable(joinpath(folderpath,"GTEP_input_total.xlsx"),"wind_timeseries_regional"))
            input_data["Solardata"]=DataFrame(XLSX.readtable(joinpath(folderpath,"GTEP_input_total.xlsx"),"solar_timeseries_regional"))
            input_data["Loaddata"]=DataFrame(XLSX.readtable(joinpath(folderpath,"GTEP_input_total.xlsx"),"load_timeseries_regional"))
            input_data["NIdata"]=input_data["Loaddata"][:,"NI"]
            #candidate
            println("Reading resourc candidate")
            input_data["Estoragedata_candidate"]=DataFrame(XLSX.readtable(joinpath(folderpath,"GTEP_input_total.xlsx"),"Estoragedata_candidate"))
            input_data["Linedata_candidate"]=DataFrame(XLSX.readtable(joinpath(folderpath,"GTEP_input_total.xlsx"),"linedata_candidate"))
            input_data["Gendata_candidate"]=DataFrame(XLSX.readtable(joinpath(folderpath,"GTEP_input_total.xlsx"),"gendata_candidate"))
            #policies
            println("Reading polices")
            input_data["CBPdata"]=DataFrame(XLSX.readtable(joinpath(folderpath,"GTEP_input_total.xlsx"),"carbonpolicies"))
            #rpspolicydata=
            input_data["RPSdata"]=DataFrame(XLSX.readtable(joinpath(folderpath,"GTEP_input_total.xlsx"),"rpspolicies"))
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
            input_data["Gencostdata"]=input_data["Gendata"][:,Symbol("Cost (\$/MWh)")]
            #time series
            println("Reading time series")
            input_data["Winddata"]=CSV.read(joinpath(folderpath,"wind_timeseries_regional.csv"),DataFrame)
            input_data["Solardata"]=CSV.read(joinpath(folderpath,"solar_timeseries_regional.csv"),DataFrame)
            input_data["Loaddata"]=CSV.read(joinpath(folderpath,"load_timeseries_regional.csv"),DataFrame)
            input_data["NIdata"]=input_data["Loaddata"][:,"NI"]
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
            println("CSV Files Successfully Load From $folderpath")
        end


    
    elseif model_mode == "PCM"          #read data for production cost model
        input_data = Dict()
        println("Reading Input_Data Files for PCM mode")
        folderpath = joinpath(path*"/"*Data_case)
        files = readdir(folderpath)
        input_data["VOLL"] = config_set["value_of_loss_of_load"]
        if any(endswith.(files, ".xlsx"))
            println("The directory $folderpath contains .xlsx file, then try to read input data from PCM_input_total.xlsx")
            #xlsx_file = XLSX.readxlsx(path*Data_case*"PCM_input_total.xlsx")

            #network
            println("Reading network")
            input_data["Zonedata"]=DataFrame(XLSX.readtable(joinpath(folderpath,"PCM_input_total.xlsx"),"zonedata"))
            input_data["Linedata"]=DataFrame(XLSX.readtable(joinpath(folderpath,"PCM_input_total.xlsx"),"linedata"))
            #technology
            println("Reading technology")
            if config_set["aggregated!"]==1
                input_data["Gendata"] = aggregate_gendata_pcm(DataFrame(XLSX.readtable(joinpath(folderpath,"PCM_input_total.xlsx"),"gendata")))
            else
                input_data["Gendata"]=DataFrame(XLSX.readtable(joinpath(folderpath,"PCM_input_total.xlsx"),"gendata"))
            end 
            
            input_data["Storagedata"]=DataFrame(XLSX.readtable(joinpath(folderpath,"PCM_input_total.xlsx"),"storagedata"))
            input_data["Gencostdata"]=input_data["Gendata"][:,Symbol("Cost (\$/MWh)")]

        
            #time series
            println("Reading time series")
            input_data["Winddata"]=DataFrame(XLSX.readtable(joinpath(folderpath,"PCM_input_total.xlsx"),"wind_timeseries_regional"))
            input_data["Solardata"]=DataFrame(XLSX.readtable(joinpath(folderpath,"PCM_input_total.xlsx"),"solar_timeseries_regional"))
            input_data["Loaddata"]=DataFrame(XLSX.readtable(joinpath(folderpath*"PCM_input_total.xlsx"),"load_timeseries_regional"))
            input_data["NIdata"]=input_data["Loaddata"][:,"NI"]

            #policies
            println("Reading polices")
            input_data["CBPdata"]=DataFrame(XLSX.readtable(joinpath(folderpath,"PCM_input_total.xlsx"),"carbonpolicies"))
            #rpspolicydata=
            input_data["RPSdata"]=DataFrame(XLSX.readtable(joinpath(folderpath,"PCM_input_total.xlsx"),"rpspolicies"))
            println("xlsx Files Successfully Load From $folderpath")
        else
            println("No xlsx file found in the directory $folderpath, try to read data from .csv files")
            
            println("Reading network")
            input_data["Zonedata"]=CSV.read(joinpath(folderpath,"zonedata.csv"),DataFrame)
            input_data["Linedata"]=CSV.read(joinpath(folderpath,"linedata.csv"),DataFrame)
            #technology
            println("Reading technology")
            if config_set["aggregated!"]==1
                input_data["Gendata"] = aggregate_gendata_pcm(CSV.read(joinpath(folderpath,"gendata.csv"),DataFrame))
            else
                input_data["Gendata"]=CSV.read(joinpath(folderpath,"gendata.csv"),DataFrame)
            end 
            
            input_data["Storagedata"]=CSV.read(joinpath(folderpath,"storagedata.csv"),DataFrame)
            input_data["Gencostdata"]=input_data["Gendata"][:,Symbol("Cost (\$/MWh)")]

        
            #time series
            println("Reading time series")
            input_data["Winddata"]=CSV.read(joinpath(folderpath,"wind_timeseries_regional.csv"),DataFrame)
            input_data["Solardata"]=CSV.read(joinpath(folderpath,"solar_timeseries_regional.csv"),DataFrame)
            input_data["Loaddata"]=CSV.read(joinpath(folderpath,"load_timeseries_regional.csv"),DataFrame)
            input_data["NIdata"]=input_data["Loaddata"][:,"NI"]

            #policies
            println("Reading policies")
            input_data["CBPdata"]=CSV.read(joinpath(folderpath,"carbonpolicies.csv"),DataFrame)
            #rpspolicydata=
            input_data["RPSdata"]=CSV.read(joinpath(folderpath,"rpspolicies.csv"),DataFrame)
            println("CSV Files Successfully Load From $folderpath")
        end   
    end
    return input_data
end
