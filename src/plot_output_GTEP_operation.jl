using DataFrames, CSV, PlotlyJS

input_dir = "E:\\Dropbox (MIT)\\PJMShen\\HOPE\\ModelCases\\MD_DataCenter_case\\Output\\" # Please change it to your home directory where HOPE and your Output file of the ModelCases exist
outpath = "E:\\Dropbox (MIT)\\PJMShen\\HOPE\\ModelCases\\MD_DataCenter_case\\" #choose by user

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
    "Hydro_pump_dc"=>"LightPurple",
    "Nuc"=>"Orange",
    "MSW"=>"Saddlebrown",
    "Bio" =>"LightGreen",
    "Landfill_NG"=> "Gold",
    "NGCC"=>"LightSteelBlue",
    "NG" =>"LightSteelBlue",
    "WindOn"=>"LightSkyBlue",
    "WindOff"=>"Blue",
    "SolarPV"=>"Yellow",
    "Battery" => "Purple",
    "Battery_dc" => "Purple",
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

#read output data#

#power
#Output_power= CSV.read(input_dir*"power_hourly.csv",DataFrame) 
#Output_es_power =  CSV.read(input_dir*"es_power_hourly.csv",DataFrame) 
Output_power= CSV.read(input_dir*"power.csv",DataFrame) 
Output_es_power =  CSV.read(input_dir*"es_power.csv",DataFrame) 

Output_power.Technology = map(x -> get(tech_acromy_map_dict, x, x), Output_power.Technology)
Output_es_power.Technology =  map(x -> get(tech_acromy_map_dict, x, x), Output_es_power.Technology)
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


#re-order (not in use for now)
#indices = sortperm([findfirst(x -> x == y, ordered_tech) for y in All_agg_cap_df.Technology])
#All_agg_cap_reod_df =  All_agg_cap_df[indices,:]


#plot power output --------------------------------------------------------#
#aggregrated 

agg_zone_data = combine(groupby(Output_power, [:Technology]), names(Output_power, r"h\d+") .=> sum) 
agg_es_dc_zone_data = combine(groupby(Output_es_power,[:Technology]), names(Output_es_power, r"dc_t\d+") .=> sum) 
agg_es_soc_zone_data = combine(groupby(Output_es_power,[:Technology]), names(Output_es_power, r"soc_t\d+") .=> sum) 
agg_es_c_zone_data = combine(groupby(Output_es_power,[:Technology]), names(Output_es_power, r"^c_t\d+") .=> sum) 

power_output_data_df = Dict(
    "agg_zone_data" =>agg_zone_data ,
    "agg_es_dc_zone_data"=>agg_es_dc_zone_data,
    "agg_es_soc_zone_data"=>agg_es_soc_zone_data,
    "agg_es_c_zone_data" => agg_es_c_zone_data 
)

hours=3625:3792 #8401:8568 #3625:3792
ordered_tech_power = ["Nuc","Coal","NGCC","NGCT","Hydro","Oil","Bio","WindOn","WindOff","SolarPV","Other"]
ordered_es_tech = ["Hydro_pump","Battery"]
function plot_power_output(data::Dict, ordered_tech_power::Vector,ordered_es_tech ::Vector, color_map::Dict,hours::UnitRange)
    agg_es_dc_zone_data=data["agg_es_dc_zone_data"]
    agg_es_c_zone_data=data["agg_es_c_zone_data"]
    agg_zone_data=data["agg_zone_data"]
    agg_es_soc_zone_data=data["agg_es_soc_zone_data"]
    plot_data= [[if (isempty(agg_es_soc_zone_data[agg_es_soc_zone_data[!,:Technology] .==tech,:])) filter!(!=(tech), ordered_es_tech )
            elseif (tech == "Battery") scatter(x=hours, y=-Vector(agg_es_c_zone_data[agg_es_c_zone_data[!,:Technology] .==tech,:][1,broadcast(x -> x + 1, collect(hours))]),mode="lines",  line=attr(dash="dash"), line_color=color_map[tech],stackgroup="two", hoverinfo="x+y",name=tech*"_c")
            elseif (tech == "Hydro_pump") scatter(x=hours, y=-Vector(agg_es_c_zone_data[agg_es_c_zone_data[!,:Technology] .==tech,:][1,broadcast(x -> x + 1, collect(hours))]),mode="lines", line=attr(dash="dash"), line_color=color_map[tech],stackgroup="two", hoverinfo="x+y",name=tech*"_c")end 
            for tech in ordered_es_tech];
            [if (isempty(agg_zone_data[agg_zone_data[!,:Technology] .==tech,:])) filter!(!=(tech), ordered_tech_power)
            else scatter(x=hours, y=Vector(agg_zone_data[agg_zone_data[!,:Technology] .==tech,:][1,broadcast(x -> x + 1, collect(hours))]), mode="lines",line_color=color_map[tech], stackgroup="one", hoverinfo="x+y",name=tech)end 
            for tech in ordered_tech_power];
            [if (isempty(agg_es_dc_zone_data[agg_es_dc_zone_data[!,:Technology] .==tech,:])) filter!(!=(tech), ordered_es_tech )
            elseif (tech == "Battery") scatter(x=hours, y=Vector(agg_es_dc_zone_data[agg_es_dc_zone_data[!,:Technology] .==tech,:][1,broadcast(x -> x + 1, collect(hours))]),mode="lines", line_color=color_map[tech],stackgroup="one", hoverinfo="x+y",name=tech*"_dc")
            elseif (tech == "Hydro_pump") scatter(x=hours, y=Vector(agg_es_dc_zone_data[agg_es_dc_zone_data[!,:Technology] .==tech,:][1,broadcast(x -> x + 1, collect(hours))]),mode="lines", line_color=color_map[tech],stackgroup="one", hoverinfo="x+y",name=tech*"_dc")end 
            for tech in ordered_es_tech]
            ]

    max_y_cap = maximum(sum, eachcol(agg_zone_data[:,2:end]))
    min_y_cap = maximum(sum, eachcol(agg_es_c_zone_data[:,2:end]))
    traces = GenericTrace[]
    for trace in plot_data
        push!(traces,trace)
    end
    return plot(traces, 
                Layout(
                title="Power Generation from Different Sources",
                xaxis_title="Time (Hours)",
                yaxis_title="Power Generation (MW)",
                yaxis_type="linear",
                yaxis_range=[-9000,32000],
                showlegend=true,
                barmode="stack")
                )
end

plot_power_output(power_output_data_df, ordered_tech_power, ordered_es_tech, color_map, hours)



