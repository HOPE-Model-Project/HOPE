using CSV
using DataFrames

const TARGET_FILES = Set([
    "load_timeseries_regional.csv",
    "wind_timeseries_regional.csv",
    "solar_timeseries_regional.csv",
    "gen_availability_timeseries.csv",
    "dr_timeseries_regional.csv",
])

to_int(x, default::Int) = (ismissing(x) || string(x) == "") ? default : parse(Int, string(x))

function normalize_timeseries_time_columns!(df::DataFrame)
    n = nrow(df)
    cols = Set(string.(names(df)))

    if !("Time Period" in cols)
        insertcols!(df, 1, "Time Period" => ones(Int, n))
    end

    cols = Set(string.(names(df)))
    if !("Hours" in cols)
        if "Period" in cols
            rename!(df, "Period" => "Hours")
        elseif "Hour" in cols
            rename!(df, "Hour" => "Hours")
        else
            insertcols!(df, "Hours" => collect(1:n))
        end
    end

    df[!, "Time Period"] = [to_int(df[r, "Time Period"], 1) for r in 1:n]
    df[!, "Hours"] = [to_int(df[r, "Hours"], r) for r in 1:n]
    return df
end

function reorder_columns(df::DataFrame)
    ordered = String[]
    if "Time Period" in names(df)
        push!(ordered, "Time Period")
    end
    if "Month" in names(df)
        push!(ordered, "Month")
    end
    if "Day" in names(df)
        push!(ordered, "Day")
    end
    if "Hours" in names(df)
        push!(ordered, "Hours")
    end
    rest = [c for c in names(df) if !(c in ordered)]
    return select(df, vcat(ordered, rest))
end

function main()
    root = "ModelCases"
    touched = 0
    for (dir, _, files) in walkdir(root)
        for f in files
            if !(f in TARGET_FILES)
                continue
            end
            fp = joinpath(dir, f)
            df = CSV.read(fp, DataFrame)
            normalize_timeseries_time_columns!(df)
            df = reorder_columns(df)
            CSV.write(fp, df)
            touched += 1
            println("updated: ", fp)
        end
    end
    println("timeseries files updated: ", touched)
end

main()
