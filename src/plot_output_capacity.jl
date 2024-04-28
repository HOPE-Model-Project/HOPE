using DataFrames, CSV, PlotlyJS

input_dir = "E:\\Dropbox (MIT)\\PJMShen\\HOPE\\ModelCases\\MD_clean_case0RPS\\Output\\" # Please change it to your home directory where HOPE and your Output file of the ModelCases exist
outpath = "E:\\Dropbox (MIT)\\PJMShen\\HOPE\\ModelCases\\MD_clean_case0RPS\\" #choose by user

#Function use for aggregrating generation data:
function aggregate_capdata(df)
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
#capacity
Output_capacity=CSV.read(input_dir*"capacity.csv",DataFrame)
Output_es_capacity=CSV.read(input_dir*"es_capacity.csv",DataFrame)

Output_capacity.Technology = map(x -> get(tech_acromy_map_dict, x, x), Output_capacity.Technology)
Output_es_capacity.Technology = map(x -> get(tech_acromy_map_dict, x, x), Output_es_capacity.Technology)
#Existing 
Exist_capacity = filter(row -> row.EC_Category  == "Existing", Output_capacity)
Exist_es_capacity = filter(row -> row.EC_Category  == "Existing", Output_es_capacity)

Exist_capacity.Technology = map(x -> get(tech_acromy_map_dict, x, x), Exist_capacity.Technology)
Exist_es_capacity.Technology = map(x -> get(tech_acromy_map_dict, x, x),Exist_es_capacity.Technology)

#New_Build
New_capacity = filter(row -> row.New_Build == 1, Output_capacity)
New_es_capacity = filter(row -> row.New_Build == 1, Output_es_capacity)

#Aggregrate by technology
All_agg_cap_df = aggregate_capdata(Output_capacity)
Fin_agg_cap_df = All_agg_cap_df[:,["Technology","Zone","Capacity_FIN (MW)"]]
rename!(Fin_agg_cap_df,[Symbol("Capacity_FIN (MW)")] .=>  [Symbol("Capacity (MW)")])
Fin_agg_es_cap_df = aggregate_es_capdata(Output_es_capacity)
Fin_agg_all_df = vcat(Fin_agg_cap_df,Fin_agg_es_cap_df)


Initial_agg_cap_df = All_agg_cap_df[:,["Technology","Zone","Capacity_INI (MW)"]]
rename!(Initial_agg_cap_df,[Symbol("Capacity_INI (MW)")] .=>  [Symbol("Capacity (MW)")])
Initial_agg_es_cap_df = aggregate_es_capdata(Exist_es_capacity)
Initial_agg_all_df = vcat(Initial_agg_cap_df,Initial_agg_es_cap_df)


#Fill the missing ones:
function fill_gendf_zero(df)
    combins= DataFrame(Zone = repeat(unique(df[:,:Zone]), inner = length(unique(df[:,:Technology]))),
               Technology = vec(repeat(unique(df[:,:Technology]), outer = length(unique(df[:,:Zone])))))

    combins.Capacity = Array{Union{Missing,Float64}}(undef, size(combins)[1])
    rename!(combins, :Capacity => Symbol("Capacity (MW)"))

    df_combined = leftjoin(combins, df, on = [:Zone, :Technology], makeunique=true)
    df_combined[:,"Capacity (MW)"] = coalesce.(df_combined[:,"Capacity (MW)_1"], 0)
    #drop
    select!(df_combined, Not(Symbol("Capacity (MW)_1")))
    return df_combined
end


Fin_agg_all_df.Color =  map(x -> get(color_map, x, missing), Fin_agg_all_df.Technology)
Initial_agg_all_df.Color =  map(x -> get(color_map, x, missing), Initial_agg_all_df.Technology)

#re-order (not in use)
#indices = sortperm([findfirst(x -> x == y, ordered_tech) for y in All_agg_cap_df.Technology])
#All_agg_cap_reod_df =  All_agg_cap_df[indices,:]

#plot capacity--------------------------------------------------------#
#plot(All_agg_cap_df, kind="bar",x=:Zone, y=Symbol("Capacity (MW)"), marker_color=:Color, symbol=:Technology, Layout(title="Generation Capacity Mix at 2022", barmode="stack", xaxis_categoryorder="category ascending"))
function plot_gen_mix(df::DataFrame, ordered_tech::Vector, color_map::Dict,tt::String)
    agg_df = combine(groupby(df, [:Zone]),Symbol("Capacity (MW)") => sum)
    rename!(agg_df, Symbol("Capacity (MW)_sum") => "Cap")
    max_zone_cap = maximum(agg_df.Cap)

    return plot([bar(x=sort(unique(df[:,:Zone])), y= sort(filter(row -> row.Technology == ordered_tech[i],df), :Zone)[:,"Capacity (MW)"], marker_color=color_map[ordered_tech[i]], name=ordered_tech[i] ) for i in 1:size(ordered_tech)[1]], 
    Layout(title=tt, barmode="stack", 
    xaxis_categoryorder="category ascending", xaxis_title_text="Regions",
    yaxis_title_text="Capacity (MW)", yaxis_range=[0,20000]))
end
plot_gen_mix(fill_gendf_zero(Fin_agg_all_df), ordered_tech, color_map,  "Generation Capacity Mix at 2035")
plot_gen_mix(fill_gendf_zero(Initial_agg_all_df), ordered_tech, color_map,  "Generation Capacity Mix at 2022")
#plot capacity--------------------------------------------------------#

