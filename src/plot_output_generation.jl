using DataFrames, CSV, PlotlyJS

input_dir = "E:\\Dropbox (MIT)\\PJMShen\\HOPE\\ModelCases\\MD_clean_datacenter_case0RPS\\Output\\" # Please change it to your home directory where HOPE and your Output file of the ModelCases exist
outpath = "E:\\Dropbox (MIT)\\PJMShen\\HOPE\\ModelCases\\MD_clean_datacenter_case0RPS\\" #choose by user

#Function use for aggregrating generation data:
function aggregate_gendata(df)
	agg_df = combine(groupby(df, [:Technology,:Zone]),
	Symbol("Capacity_INI (MW)") => sum,
    Symbol("Capacity_RET (MW)") => sum,
    Symbol("Capacity_FIN (MW)") => sum,
    )
	rename!(agg_df, [Symbol("Capacity_INI (MW)_sum"),Symbol("Capacity_RET (MW)_sum"),Symbol("Capacity_FIN (MW)_sum")] .=>  [Symbol("Capacity_INI (MW)"),Symbol("Capacity_RET (MW)"), Symbol("Capacity_FIN (MW)")] )
	return agg_df
end

function aggregate_es_capdata(df)
	agg_df = combine(groupby(df, [:Technology,:Zone]),
	Symbol("Capacity (MW)") => sum,
    )
	rename!(agg_df, [Symbol("Capacity (MW)_sum")] .=>  [Symbol("Capacity (MW)")] )
	return agg_df
end
#color map
color_map = Dict(
    "Coal" =>"Black",
    "Oil"=>"Bisque",
    "NGCT"=>"LightSlateGray",
    "NGCT_CCS"=>"LightSlateGray",
    "Hydro"=>"MidnightBlue",
    "Hydro_pump"=>"LightPurple",
    "Hydro_pump_c"=>"LightPurple",
    "Hydro_pump_dis"=>"LightPurple",
    "Nuc"=>"Orange",
    "MSW"=>"Saddlebrown",
    "Bio" =>"LightGreen",
    "Landfill_NG"=> "Gold",
    "NGCC"=>"LightSteelBlue",
    "NGCC_CCS"=>"LightSteelBlue",
    "NG" =>"LightSteelBlue",
    "WindOn"=>"LightSkyBlue",
    "WindOff"=>"Blue",
    "SolarPV"=>"Yellow",
    "Battery" => "Purple",
    "Battery_dis" => "Purple",
    "Battery_c" => "Purple",
    "Other" => "Pink"
)

tech_acromy_map_dict = Dict(
    "Batteries" => "Battery",
    "Biomass" => "Bio",
    "HPS" => "Hydro_pump",
    "BES" => "Battery",
    "MSW" =>"Bio",
    "Landfill_NG" => "Bio",
    "NG" => "NGCC",
    "NuC" => "Nuc"
)
#Technology ordered
ordered_tech =  ["Nuc","Coal","NGCC","NGCC_CCS","NGCT","NGCT_CCS","Hydro","Bio","WindOff","WindOn","SolarPV","Battery"]

#read output data#
#read output data#

#power
#Output_power= CSV.read(input_dir*"power_hourly.csv",DataFrame) 
#Output_es_power =  CSV.read(input_dir*"es_power_hourly.csv",DataFrame) 
Output_power= CSV.read(input_dir*"power.csv",DataFrame) 
Output_es_c_power =  CSV.read(input_dir*"es_power_charge.csv",DataFrame)
Output_es_dc_power =  CSV.read(input_dir*"es_power_discharge.csv",DataFrame) 
Output_es_soc_power =  CSV.read(input_dir*"es_power_soc.csv",DataFrame)  


Output_power.Technology = map(x -> get(tech_acromy_map_dict, x, x), Output_power.Technology)
Output_es_c_power.Technology =  map(x -> get(tech_acromy_map_dict, x, x), Output_es_c_power.Technology)
Output_es_dc_power.Technology =  map(x -> get(tech_acromy_map_dict, x, x), Output_es_dc_power.Technology)
Output_es_soc_power.Technology =  map(x -> get(tech_acromy_map_dict, x, x), Output_es_soc_power.Technology)

#Aggregrate by technology
All_agg_gen_df = combine(groupby(Output_power, [:Zone, :Technology]), names(Output_power, "AnnSum") .=> sum) 
rename!(All_agg_gen_df,[Symbol("AnnSum_sum")] .=>  [Symbol("Generation (MWh)")])




#Fill the missing ones:
function fill_gendf_zero(df)
    combins= DataFrame(Zone = repeat(unique(df[:,:Zone]), inner = length(unique(df[:,:Technology]))),
               Technology = vec(repeat(unique(df[:,:Technology]), outer = length(unique(df[:,:Zone])))))

    combins.Generation = Array{Union{Missing,Float64}}(undef, size(combins)[1])
    rename!(combins, :Generation => Symbol("Generation (MWh)"))

    df_combined = leftjoin(combins, df, on = [:Zone, :Technology], makeunique=true)
    df_combined[:,"Generation (MWh)"] = coalesce.(df_combined[:,"Generation (MWh)_1"], 0)
    #drop
    select!(df_combined, Not(Symbol("Generation (MWh)_1")))
    return df_combined
end


All_agg_gen_df.Color =  map(x -> get(color_map, x, missing), All_agg_gen_df.Technology)

#plot capacity--------------------------------------------------------#
#plot(All_agg_cap_df, kind="bar",x=:Zone, y=Symbol("Capacity (MW)"), marker_color=:Color, symbol=:Technology, Layout(title="Generation Capacity Mix at 2022", barmode="stack", xaxis_categoryorder="category ascending"))
function plot_gen_mix(df::DataFrame, ordered_tech::Vector, color_map::Dict,tt::String)
    agg_df = combine(groupby(df, [:Zone]),Symbol("Generation (MWh)") => sum)
    rename!(agg_df, Symbol("Generation (MWh)_sum") => "Cap")
    max_zone_cap = maximum(agg_df.Cap)

    return plot([bar(x=sort(unique(df[:,:Zone])), y= sort(filter(row -> row.Technology == ordered_tech[i],df), :Zone)[:,"Generation (MWh)"] ./1000, marker_color=color_map[ordered_tech[i]], name=ordered_tech[i] ) for i in 1:size(ordered_tech)[1]], 
    Layout(title=tt, barmode="stack", 
    xaxis_categoryorder="category ascending", xaxis_title_text="Regions",
    yaxis_title_text="Generation (GWh)", yaxis_range=[0,50000]))
end
plot_gen_mix(fill_gendf_zero(All_agg_gen_df), ordered_tech, color_map,  "Power Generation Mix at 2035")

#plot capacity--------------------------------------------------------#

