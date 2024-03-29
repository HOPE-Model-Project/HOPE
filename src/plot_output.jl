using DataFrames, CSV, PlotlyJS

input_dir = "D:\\Coding\\Master\\HOPE\\ModelCases\\PJM_GTEP_case\\Output\\" # Please change it to your home directory where HOPE and your Output file of the ModelCases exist
outpath = "D:\\Coding\\Master\\HOPE\\ModelCases\\PJM_GTEP_case\\Output\\"

#Function use for aggregrating generation data:
function aggregate_capdata(df)
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
    "Hydro"=>"MidnightBlue",
    "Hydro_pump"=>"LightPurple",
    "Hydro_pump_c"=>"LightPurple",
    "Hydro_pump_dis"=>"LightPurple",
    "NuC"=>"Orange",
    "MSW"=>"Saddlebrown",
    "Bio" =>"LightGreen",
    "Landfill_NG"=> "Gold",
    "NGCC"=>"LightSteelBlue",
    "NG" =>"LightSteelBlue",
    "WindOn"=>"LightSkyBlue",
    "SolarPV"=>"Yellow",
    "Battery" => "Purple",
    "Battery_dis" => "Purple",
    "Battery_c" => "Purple",
    "Other" => "Pink"
)
#Technology ordered

ordered_tech = ["NGCC","NuC","Coal","NGCT","Landfill_NG", "NG", "Hydro","Oil","MSW","Bio","WindOn","SolarPV","Battery","Other"]

#read output data#
#capacity
Output_capacity=CSV.read(input_dir*"capacity.csv",DataFrame)
Output_es_capacity=CSV.read(input_dir*"es_capacity.csv",DataFrame)
#power
#Output_power= CSV.read(input_dir*"power_hourly.csv",DataFrame) ###
#Output_es_power =  CSV.read(input_dir*"es_power_hourly.csv",DataFrame) ###
#Existing 
Exist_capacity = filter(row -> row.EC_Category  == "Existing", Output_capacity)
Exist_es_capacity = filter(row -> row.EC_Category  == "Existing", Output_es_capacity)

#New_Build
New_capacity = filter(row -> row.New_Build == 1, Output_capacity)
New_es_capacity = filter(row -> row.New_Build == 1, Output_es_capacity)

#Aggregrate by technology
All_agg_cap_df = aggregate_capdata(vcat(aggregate_capdata(Exist_capacity),aggregate_capdata(Exist_es_capacity),aggregate_capdata(New_capacity),aggregate_capdata(New_es_capacity)))
Exist_agg_cap_df = aggregate_capdata(vcat(aggregate_capdata(Exist_capacity),aggregate_capdata(Exist_es_capacity)))

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


#All_agg_cap_df.Color =  map(x -> get(color_map, x, missing), All_agg_cap_df.Technology)
#Exist_agg_cap_df.Color =  map(x -> get(color_map, x, missing), Exist_agg_cap_df.Technology)

#re-order
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
    yaxis_title_text="Capacity (MW)", yaxis_range=[0,1.1*max_zone_cap]))
end
plot_gen_mix(fill_gendf_zero(All_agg_cap_df), ordered_tech, color_map,  "Generation Capacity Mix at 2030")
plot_gen_mix(fill_gendf_zero(Exist_agg_cap_df), ordered_tech, color_map,  "Generation Capacity Mix at 2022")
#plot capacity--------------------------------------------------------#

#plot power output --------------------------------------------------------#
#aggregrated 

#agg_zone_data = combine(groupby(Output_power, [:Technology]), names(Output_power, r"h\d+") .=> sum) ###
#agg_es_dc_zone_data = combine(groupby(Output_es_power,[:Technology]), names(Output_es_power, r"dc_h\d+") .=> sum) ###
#agg_es_soc_zone_data = combine(groupby(Output_es_power,[:Technology]), names(Output_es_power, r"soc_h\d+") .=> sum) ###
#agg_es_c_zone_data = combine(groupby(Output_es_power,[:Technology]), names(Output_es_power, r"^c_h\d+") .=> sum) ###

```power_output_data_df = Dict(
    "agg_zone_data" =>agg_zone_data ,
    "agg_es_dc_zone_data"=>agg_es_dc_zone_data,
    "agg_es_soc_zone_data"=>agg_es_soc_zone_data,
    "agg_es_c_zone_data" => agg_es_c_zone_data 
)```

hours=1:168
ordered_tech_power = ["NuC","Coal","NGCC","NGCT","NG","Hydro","Oil","MSW","Bio","WindOn","WindOff","SolarPV","Hydro_pump","Battery","Other"]
ordered_es_tech = ["Hydro_pump","Battery"]
```function plot_power_output(data::Dict, ordered_tech_power::Vector,ordered_es_tech ::Vector, color_map::Dict,hours::UnitRange)
    agg_es_dc_zone_data=data["agg_es_dc_zone_data"]
    agg_es_c_zone_data=data["agg_es_c_zone_data"]
    agg_zone_data=data["agg_zone_data"]
    agg_es_soc_zone_data=data["agg_es_soc_zone_data"]
    data= [[if (isempty(agg_es_soc_zone_data[agg_es_soc_zone_data[!,:Technology] .==tech,:])) filter!(!=(tech), ordered_es_tech )
            elseif (tech == "Battery") scatter(x=hours, y=-Vector(agg_es_c_zone_data[agg_es_c_zone_data[!,:Technology] .==tech,:][1,2:end]),mode="lines",  line=attr(dash="dash"), line_color=color_map[tech],stackgroup="two", hoverinfo="x+y",name=tech*"_c")
            elseif (tech == "Hydro_pump") scatter(x=hours, y=-Vector(agg_es_c_zone_data[agg_es_c_zone_data[!,:Technology] .==tech,:][1,2:end]),mode="lines", line=attr(dash="dash"), line_color=color_map[tech],stackgroup="two", hoverinfo="x+y",name=tech*"_c")end 
            for tech in ordered_es_tech];
            [if (isempty(agg_zone_data[agg_zone_data[!,:Technology] .==tech,:])) filter!(!=(tech), ordered_tech_power)
            else scatter(x=hours, y=Vector(agg_zone_data[agg_zone_data[!,:Technology] .==tech,:][1,2:end]), mode="lines",line_color=color_map[tech], stackgroup="one", hoverinfo="x+y",name=tech)end 
            for tech in ordered_tech_power];
            [if (isempty(agg_es_dc_zone_data[agg_es_dc_zone_data[!,:Technology] .==tech,:])) filter!(!=(tech), ordered_es_tech )
            elseif (tech == "Battery") scatter(x=hours, y=Vector(agg_es_dc_zone_data[agg_es_dc_zone_data[!,:Technology] .==tech,:][1,2:end]),mode="lines", line_color=color_map[tech],stackgroup="one", hoverinfo="x+y",name=tech*"_dis")
            elseif (tech == "Hydro_pump") scatter(x=hours, y=Vector(agg_es_dc_zone_data[agg_es_dc_zone_data[!,:Technology] .==tech,:][1,2:end]),mode="lines", line_color=color_map[tech],stackgroup="one", hoverinfo="x+y",name=tech*"_dis")end 
            for tech in ordered_es_tech]
            ]

    max_y_cap = maximum(sum, eachcol(agg_zone_data[:,2:end]))
    min_y_cap = maximum(sum, eachcol(agg_es_c_zone_data[:,2:end]))
    return plot(data, 
                Layout(
                title="Power Generation from Different Sources",
                xaxis_title="Time (Hours)",
                yaxis_title="Power Generation (MW)",
                yaxis_type="linear",
                yaxis_range=[-10*min_y_cap-1000,1.1*max_y_cap],
                showlegend=true,
                barmode="stack")
                )
end```

plot_power_output(power_output_data_df, ordered_tech_power, ordered_es_tech, color_map, hours)



