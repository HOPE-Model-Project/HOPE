#Function use for aggregrating generation data:
to_float_agg(x, d=0.0) = ismissing(x) || x === nothing || string(x) == "" ? d : (x isa Number ? Float64(x) : parse(Float64, string(x)))

function agg_weights_from_pmax(gdf::SubDataFrame)
    w = [max(to_float_agg(v, 0.0), 0.0) for v in gdf[!, Symbol("Pmax (MW)")]]
    sw = sum(w)
    if sw <= 0
        return fill(1.0, nrow(gdf))
    end
    return w
end

function wmean_col(gdf::SubDataFrame, col::Symbol, w::Vector{Float64}; default::Float64=0.0)
    vals = [to_float_agg(v, default) for v in gdf[!, col]]
    sw = sum(w)
    if sw <= 0
        return isempty(vals) ? default : mean(vals)
    end
    return sum(vals .* w) / sw
end

flag_any(gdf::SubDataFrame, col::Symbol) = any(to_float_agg(v, 0.0) > 0 for v in gdf[!, col]) ? 1 : 0

function aggregate_gendata_gtep(df::DataFrame)
    work = copy(df)
    if !("AF" in names(work))
        work[!, :AF] = fill(1.0, nrow(work))
    end
    has_rps = "Flag_RPS" in names(work)
    out = DataFrame(
        :Zone => Any[],
        :Type => Any[],
        Symbol("Pmax (MW)") => Float64[],
        Symbol("Pmin (MW)") => Float64[],
        Symbol("Cost (\$/MWh)") => Float64[],
        :EF => Float64[],
        :CC => Float64[],
        :AF => Float64[],
        :Flag_thermal => Int[],
        :Flag_VRE => Int[],
        :Flag_RET => Int[],
        :Flag_mustrun => Int[],
    )
    if has_rps
        out[!, :Flag_RPS] = Int[]
    end

    for gdf in groupby(work, [:Zone, :Type])
        w = agg_weights_from_pmax(gdf)
        if has_rps
            row = (
                gdf[1, :Zone],
                gdf[1, :Type],
                sum(to_float_agg(v, 0.0) for v in gdf[!, Symbol("Pmax (MW)")]),
                sum(to_float_agg(v, 0.0) for v in gdf[!, Symbol("Pmin (MW)")]),
                wmean_col(gdf, Symbol("Cost (\$/MWh)"), w; default=0.0),
                wmean_col(gdf, :EF, w; default=0.0),
                wmean_col(gdf, :CC, w; default=0.0),
                wmean_col(gdf, :AF, w; default=1.0),
                flag_any(gdf, :Flag_thermal),
                flag_any(gdf, :Flag_VRE),
                flag_any(gdf, :Flag_RET),
                flag_any(gdf, :Flag_mustrun),
                flag_any(gdf, :Flag_RPS),
            )
            push!(out, row)
        else
            row = (
                gdf[1, :Zone],
                gdf[1, :Type],
                sum(to_float_agg(v, 0.0) for v in gdf[!, Symbol("Pmax (MW)")]),
                sum(to_float_agg(v, 0.0) for v in gdf[!, Symbol("Pmin (MW)")]),
                wmean_col(gdf, Symbol("Cost (\$/MWh)"), w; default=0.0),
                wmean_col(gdf, :EF, w; default=0.0),
                wmean_col(gdf, :CC, w; default=0.0),
                wmean_col(gdf, :AF, w; default=1.0),
                flag_any(gdf, :Flag_thermal),
                flag_any(gdf, :Flag_VRE),
                flag_any(gdf, :Flag_RET),
                flag_any(gdf, :Flag_mustrun),
            )
            push!(out, row)
        end
    end
    return out
end

function aggregate_gendata_pcm(df::DataFrame, config_set::Dict)
    work = copy(df)
    has_uc = config_set["unit_commitment"] != 0
    has_reg_up = :RM_REG_UP in names(work)
    has_reg_dn = :RM_REG_DN in names(work)
    has_nspin = :RM_NSPIN in names(work)

    out = DataFrame(
        :Zone => Any[],
        :Type => Any[],
        Symbol("Pmax (MW)") => Float64[],
        Symbol("Pmin (MW)") => Float64[],
        Symbol("Cost (\$/MWh)") => Float64[],
        :EF => Float64[],
        :CC => Float64[],
        :FOR => Float64[],
        :RM_SPIN => Float64[],
        :RU => Float64[],
        :RD => Float64[],
        :Flag_thermal => Int[],
        :Flag_VRE => Int[],
        :Flag_mustrun => Int[],
    )
    if has_uc
        out[!, :Flag_UC] = Int[]
        out[!, Symbol("Start_up_cost (\$/MW)")] = Float64[]
        out[!, :Min_down_time] = Float64[]
        out[!, :Min_up_time] = Float64[]
    end
    if has_reg_up
        out[!, :RM_REG_UP] = Float64[]
    end
    if has_reg_dn
        out[!, :RM_REG_DN] = Float64[]
    end
    if has_nspin
        out[!, :RM_NSPIN] = Float64[]
    end

    for gdf in groupby(work, [:Zone, :Type])
        w = agg_weights_from_pmax(gdf)
        row = Dict{Symbol,Any}(
            :Zone => gdf[1, :Zone],
            :Type => gdf[1, :Type],
            Symbol("Pmax (MW)") => sum(to_float_agg(v, 0.0) for v in gdf[!, Symbol("Pmax (MW)")]),
            Symbol("Pmin (MW)") => sum(to_float_agg(v, 0.0) for v in gdf[!, Symbol("Pmin (MW)")]),
            Symbol("Cost (\$/MWh)") => wmean_col(gdf, Symbol("Cost (\$/MWh)"), w; default=0.0),
            :EF => wmean_col(gdf, :EF, w; default=0.0),
            :CC => wmean_col(gdf, :CC, w; default=0.0),
            :FOR => wmean_col(gdf, :FOR, w; default=0.0),
            :RM_SPIN => wmean_col(gdf, :RM_SPIN, w; default=0.0),
            :RU => wmean_col(gdf, :RU, w; default=0.0),
            :RD => wmean_col(gdf, :RD, w; default=0.0),
            :Flag_thermal => flag_any(gdf, :Flag_thermal),
            :Flag_VRE => flag_any(gdf, :Flag_VRE),
            :Flag_mustrun => flag_any(gdf, :Flag_mustrun),
        )
        if has_uc
            row[:Flag_UC] = flag_any(gdf, :Flag_UC)
            row[Symbol("Start_up_cost (\$/MW)")] = wmean_col(gdf, Symbol("Start_up_cost (\$/MW)"), w; default=0.0)
            row[:Min_down_time] = wmean_col(gdf, :Min_down_time, w; default=0.0)
            row[:Min_up_time] = wmean_col(gdf, :Min_up_time, w; default=0.0)
        end
        if has_reg_up
            row[:RM_REG_UP] = wmean_col(gdf, :RM_REG_UP, w; default=0.0)
        end
        if has_reg_dn
            row[:RM_REG_DN] = wmean_col(gdf, :RM_REG_DN, w; default=0.0)
        end
        if has_nspin
            row[:RM_NSPIN] = wmean_col(gdf, :RM_NSPIN, w; default=0.0)
        end
        push!(out, row)
    end
    return out
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
                try
                    input_data["DRdata"]=DataFrame(XLSX.readtable(joinpath(folderpath,"flexddata.xlsx"),"flexddata"))
                catch
                    # Backward compatibility for older DR workbook templates
                    input_data["DRdata"]=DataFrame(XLSX.readtable(joinpath(folderpath,"flexddata.xlsx"),"storagedata"))
                end
            end
            #time series
            println("Reading time series")
            input_data["Loaddata"]=DataFrame(XLSX.readtable(joinpath(folderpath,"GTEP_input_total.xlsx"),"load_timeseries_regional"))
            normalize_timeseries_time_columns!(input_data["Loaddata"]; context="load_timeseries_regional")
            input_data["NIdata"]=input_data["Loaddata"][:,"NI"]
            if flexible_demand == 1
                input_data["DRtsdata"]=DataFrame(XLSX.readtable(joinpath(folderpath,"GTEP_input_total.xlsx"),"dr_timeseries_regional"))
                normalize_timeseries_time_columns!(input_data["DRtsdata"]; context="dr_timeseries_regional")
                validate_aligned_time_columns!(input_data["Loaddata"], input_data["DRtsdata"], "dr_timeseries_regional")
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
                normalize_timeseries_time_columns!(input_data["AFdata"]; context="gen_availability_timeseries")
                validate_aligned_time_columns!(input_data["Loaddata"], input_data["AFdata"], "gen_availability_timeseries")
            else
                throw(ArgumentError("Missing required generator availability timeseries input. Provide sheet 'gen_availability_timeseries' in GTEP_input_total.xlsx."))
            end
            if "rep_period_weights" in sheets
                input_data["RepWeightData"] = DataFrame(XLSX.readtable(xlsx_path, "rep_period_weights"))
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
            normalize_timeseries_time_columns!(input_data["Loaddata"]; context="load_timeseries_regional")
            input_data["NIdata"]=input_data["Loaddata"][:,"NI"]
            if flexible_demand == 1
                input_data["DRtsdata"]=CSV.read(joinpath(folderpath,"dr_timeseries_regional.csv"),DataFrame)
                normalize_timeseries_time_columns!(input_data["DRtsdata"]; context="dr_timeseries_regional")
                validate_aligned_time_columns!(input_data["Loaddata"], input_data["DRtsdata"], "dr_timeseries_regional")
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
                normalize_timeseries_time_columns!(input_data["AFdata"]; context="gen_availability_timeseries")
                validate_aligned_time_columns!(input_data["Loaddata"], input_data["AFdata"], "gen_availability_timeseries")
            else
                throw(ArgumentError("Missing required generator availability timeseries input. Provide file 'gen_availability_timeseries.csv'."))
            end
            rep_weight_csv = joinpath(folderpath, "rep_period_weights.csv")
            if isfile(rep_weight_csv)
                input_data["RepWeightData"] = CSV.read(rep_weight_csv, DataFrame)
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
            normalize_timeseries_time_columns!(input_data["Loaddata"]; context="load_timeseries_regional")
            normalize_timeseries_time_columns!(input_data["Winddata"]; context="wind_timeseries_regional")
            normalize_timeseries_time_columns!(input_data["Solardata"]; context="solar_timeseries_regional")
            validate_aligned_time_columns!(input_data["Loaddata"], input_data["Winddata"], "wind_timeseries_regional")
            validate_aligned_time_columns!(input_data["Loaddata"], input_data["Solardata"], "solar_timeseries_regional")
            input_data["NIdata"]=input_data["Loaddata"][:,"NI"]
            if flexible_demand == 1
                input_data["DRtsdata"]=DataFrame(XLSX.readtable(xlsx_path,"dr_timeseries_regional"))
                normalize_timeseries_time_columns!(input_data["DRtsdata"]; context="dr_timeseries_regional")
                validate_aligned_time_columns!(input_data["Loaddata"], input_data["DRtsdata"], "dr_timeseries_regional")
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
            normalize_timeseries_time_columns!(input_data["Loaddata"]; context="load_timeseries_regional")
            normalize_timeseries_time_columns!(input_data["Winddata"]; context="wind_timeseries_regional")
            normalize_timeseries_time_columns!(input_data["Solardata"]; context="solar_timeseries_regional")
            validate_aligned_time_columns!(input_data["Loaddata"], input_data["Winddata"], "wind_timeseries_regional")
            validate_aligned_time_columns!(input_data["Loaddata"], input_data["Solardata"], "solar_timeseries_regional")
            input_data["NIdata"]=input_data["Loaddata"][:,"NI"]
            if flexible_demand == 1
                input_data["DRtsdata"]=CSV.read(joinpath(folderpath,"dr_timeseries_regional.csv"),DataFrame)
                normalize_timeseries_time_columns!(input_data["DRtsdata"]; context="dr_timeseries_regional")
                validate_aligned_time_columns!(input_data["Loaddata"], input_data["DRtsdata"], "dr_timeseries_regional")
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
