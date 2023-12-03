using Clustering, DataFrames, CSV, Statistics


#load time series
Winddata=CSV.read("Data/WT_timeseries_regional.csv",DataFrame)
Solardata=CSV.read("Data/SPV_timeseries_regional.csv",DataFrame)
Loaddata=CSV.read("Data/Load_timeseries_regional.csv",DataFrame)
df = Loaddata
# Define the start and end dates for each season or any time period of interests
time_periods = Dict(
    1 => (3, 20, 6, 20),    # March 20th to June 20th;1;srping
    2 => (6, 21, 9, 21),    # June 21st to September 21st;2;summer
    3 => (9, 22, 12, 20),    # September 22nd to December 20th;3;fall
    4 => (12, 21, 3, 19)    # December 21st to March 19th;4;winter
)

function get_representative_ts(df, time_periods, ordered_zone, k=1)
    #k = 1# Cluster the time series data to find a representative day
    # Function to filter rows based on the season's start and end dates
    filter_time_period(time_period, row) = (row.Month == time_period[1] && row.Day >= time_period[2]) || (row.Month == time_period[3] && row.Day <= time_period[4])
    # Initialize a dictionary to store the representative days for each season
    representative_days = Dict()

    # Loop over the seasons/time periods
    rep_dat_dict=Dict()
    
    for (tp, dates) in time_periods
        local tp_df, n_days ,representative_day_df 
        # Filter the DataFrame for the current season/time periods
        tp_df = filter(row -> filter_time_period(dates, row), df)
        n_days = Int(size(tp_df,1)/24)
        representative_day_df = DataFrame()
        # Extract the time series data for the current season/time periods
        for nm in names(tp_df)[4:end]
            local col_mtx,clustering_result
            col_mtx = reshape(tp_df[!, nm], (24, n_days))
            # Number of clusters (set to 1 for representative day)
            clustering_result = kmeans(col_mtx, k)
            # Store the representative day for the current season in the df
            representative_day_df[!,nm] = clustering_result.centers'[1, :]
        end
		
		if df == Loaddata
			representative_day_df_ordered= select(representative_day_df, [ordered_zone;"NI"])
		else
			representative_day_df_ordered= select(representative_day_df, ordered_zone)
		end
		representative_day_df.Hour = 1:24
        rep_dat_dict[tp]=representative_day_df_ordered
    end
    return rep_dat_dict
end


load_rep = get_representative_ts(Loaddata,time_periods)


