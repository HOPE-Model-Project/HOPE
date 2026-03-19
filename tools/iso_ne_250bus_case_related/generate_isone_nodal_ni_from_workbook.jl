using CSV
using DataFrames
using Dates
using XLSX
using Statistics

const SHEET_TO_INTERFACE = [
    "SALBRYNB" => "SALBRYNB",
    "ROSETON" => "ROSETON",
    "HQ_P1_P2" => "HQ_P1_P2",
    "HQHIGATE" => "HQHIGATE",
    "SHOREHAM" => "SHOREHAM",
    "NORTHPORT" => "NORTHPORT",
]

const INTERFACE_CLUSTER_SPECS = Dict(
    "SALBRYNB" => (
        anchor_buses=["182", "190", "58"],
        states=String[],
        loadzones=String[],
        max_buses=nothing,
        lat_min=nothing,
        lat_max=nothing,
        lon_min=nothing,
        lon_max=nothing,
    ),
    "ROSETON" => (
        anchor_buses=["98", "146", "249"],
        states=String[],
        loadzones=String[],
        max_buses=nothing,
        lat_min=nothing,
        lat_max=nothing,
        lon_min=nothing,
        lon_max=nothing,
    ),
    "HQ_P1_P2" => (
        anchor_buses=["120", "123", "116"],
        states=String[],
        loadzones=String[],
        max_buses=nothing,
        lat_min=nothing,
        lat_max=nothing,
        lon_min=nothing,
        lon_max=nothing,
    ),
    "HQHIGATE" => (
        anchor_buses=["3", "18", "181"],
        states=String[],
        loadzones=String[],
        max_buses=nothing,
        lat_min=nothing,
        lat_max=nothing,
        lon_min=nothing,
        lon_max=nothing,
    ),
    "SHOREHAM" => (
        anchor_buses=["118", "224", "33"],
        states=String[],
        loadzones=String[],
        max_buses=nothing,
        lat_min=nothing,
        lat_max=nothing,
        lon_min=nothing,
        lon_max=nothing,
    ),
    "NORTHPORT" => (
        anchor_buses=["107", "103", "227"],
        states=String[],
        loadzones=String[],
        max_buses=nothing,
        lat_min=nothing,
        lat_max=nothing,
        lon_min=nothing,
        lon_max=nothing,
    ),
)

const TIME_COLS = ["Time Period", "Month", "Day", "Hours"]
const LOCALIZED_NI_SHARE = 0.85

to_int(x) = x isa Number ? Int(x) : parse(Int, strip(string(x)))
to_float(x) = x isa Number ? Float64(x) : parse(Float64, strip(string(x)))
to_date(x) = x isa Date ? x : Date(strip(string(x)))

function july_sheet(path::AbstractString, sheet::AbstractString)
    df = DataFrame(XLSX.readtable(path, sheet))
    dates = to_date.(df[!, :Date])
    mask = year.(dates) .== 2024 .&& month.(dates) .== 7
    out = copy(df[mask, :])
    out[!, :Date] = dates[mask]
    out[!, :Hr_End] = to_int.(out[!, :Hr_End])
    return out
end

function build_interface_df(workbook_path::AbstractString, regional_load_path::AbstractString)
    reg = CSV.read(regional_load_path, DataFrame)
    time_df = select(reg, TIME_COLS)
    interface_df = copy(time_df)

    ca = july_sheet(workbook_path, "ISO NE CA")
    if nrow(ca) != nrow(reg)
        error("ISO NE CA July row count $(nrow(ca)) does not match regional load row count $(nrow(reg)).")
    end

    for (sheet, col) in SHEET_TO_INTERFACE
        df = july_sheet(workbook_path, sheet)
        if nrow(df) != nrow(reg)
            error("Sheet $(sheet) July row count $(nrow(df)) does not match regional load row count $(nrow(reg)).")
        end
        interface_df[!, col] = to_float.(df[!, :NetInt_MWh])
    end

    interface_df[!, :ISO_NE_CA_NetInt_MWh] = to_float.(ca[!, :NetInt_MWh])
    interface_df[!, :InterfaceSum_NetInt_MWh] = [
        sum(interface_df[h, col] for (_, col) in SHEET_TO_INTERFACE) for h in 1:nrow(interface_df)
    ]
    return interface_df
end

bus_id_str(x) = string(to_int(x))

function bus_distance_miles(lat1::Real, lon1::Real, lat2::Real, lon2::Real)
    dy = 69.0 * (Float64(lat1) - Float64(lat2))
    dx = 53.0 * (Float64(lon1) - Float64(lon2))
    return sqrt(dy^2 + dx^2)
end

function bus_allowed(row, spec)
    state_ok = isempty(spec.states) || string(row.State) in spec.states
    zone_ok = isempty(spec.loadzones) || string(row.LoadZone) in spec.loadzones
    lat = Float64(row.Latitude)
    lon = Float64(row.Longitude)
    lat_min_ok = isnothing(spec.lat_min) || lat >= spec.lat_min
    lat_max_ok = isnothing(spec.lat_max) || lat <= spec.lat_max
    lon_min_ok = isnothing(spec.lon_min) || lon >= spec.lon_min
    lon_max_ok = isnothing(spec.lon_max) || lon <= spec.lon_max
    return state_ok && zone_ok && lat_min_ok && lat_max_ok && lon_min_ok && lon_max_ok
end

function build_cluster_weights(busdata_path::AbstractString)
    bus_df = CSV.read(busdata_path, DataFrame)
    rename!(bus_df, Symbol("Demand (MW)") => :Demand_MW)
    bus_df[!, :Bus_id] = bus_id_str.(bus_df[!, :Bus_id])
    bus_df[!, :Latitude] = Float64.(bus_df[!, :Latitude])
    bus_df[!, :Longitude] = Float64.(bus_df[!, :Longitude])
    bus_df[!, :Demand_MW] = Float64.(bus_df[!, :Demand_MW])

    cluster_weights = Dict{String, Dict{String, Float64}}()
    summary_rows = NamedTuple[]

    for (iface, spec) in INTERFACE_CLUSTER_SPECS
        anchor_mask = in.(bus_df[!, :Bus_id], Ref(spec.anchor_buses))
        if !any(anchor_mask)
            error("No anchor buses found for $(iface).")
        end
        anchor_df = bus_df[anchor_mask, :]
        centroid_lat = mean(anchor_df[!, :Latitude])
        centroid_lon = mean(anchor_df[!, :Longitude])

        candidate_df = bus_df[[bus_allowed(row, spec) for row in eachrow(bus_df)], :]
        if nrow(candidate_df) == 0
            error("No candidate buses found for $(iface).")
        end
        candidate_df[!, :DistanceMiles] = [
            bus_distance_miles(row.Latitude, row.Longitude, centroid_lat, centroid_lon) for row in eachrow(candidate_df)
        ]
        sort!(candidate_df, :DistanceMiles)
        if !isnothing(spec.max_buses)
            candidate_df = candidate_df[1:min(spec.max_buses, nrow(candidate_df)), :]
        end

        raw_weights = [
            sqrt(max(row.Demand_MW, 1.0)) / max(row.DistanceMiles, 5.0) for row in eachrow(candidate_df)
        ]
        weight_sum = sum(raw_weights)
        if weight_sum <= 0
            error("Cluster weight sum is non-positive for $(iface).")
        end
        normalized_weights = raw_weights ./ weight_sum
        cluster_weights[iface] = Dict(candidate_df[i, :Bus_id] => normalized_weights[i] for i in 1:nrow(candidate_df))

        for i in 1:nrow(candidate_df)
            row = candidate_df[i, :]
            push!(summary_rows, (
                Interface=iface,
                Bus_id=row.Bus_id,
                State=string(row.State),
                LoadZone=string(row.LoadZone),
                Latitude=row.Latitude,
                Longitude=row.Longitude,
                Demand_MW=row.Demand_MW,
                DistanceMiles=row.DistanceMiles,
                Weight=normalized_weights[i],
                IsAnchor=row.Bus_id in spec.anchor_buses,
            ))
        end
    end

    return cluster_weights, DataFrame(summary_rows)
end

function calibrate_interface_df(interface_df::DataFrame, target_system_ni::AbstractVector{<:Real})
    if length(target_system_ni) != nrow(interface_df)
        error("Target system NI length $(length(target_system_ni)) does not match interface data rows $(nrow(interface_df)).")
    end

    calibrated_df = select(interface_df, TIME_COLS)
    calibrated_df[!, :OfficialSystemNI] = interface_df[!, :ISO_NE_CA_NetInt_MWh]
    calibrated_df[!, :TargetSystemNI] = Float64.(target_system_ni)
    calibrated_df[!, :PositiveImportScale] = zeros(Float64, nrow(calibrated_df))

    for (_, iface) in SHEET_TO_INTERFACE
        calibrated_df[!, iface] = zeros(Float64, nrow(calibrated_df))
    end

    for h in 1:nrow(interface_df)
        official_values = Dict(iface => Float64(interface_df[h, iface]) for (_, iface) in SHEET_TO_INTERFACE)
        positive_total = sum(max(value, 0.0) for value in values(official_values))
        negative_total = sum(min(value, 0.0) for value in values(official_values))
        if positive_total <= 0
            error("Official interchange has no positive imports at row $(h); cannot calibrate to target NI.")
        end

        required_positive_total = Float64(target_system_ni[h]) - negative_total
        if required_positive_total < 0
            error("Target NI $(target_system_ni[h]) is inconsistent with retained exports $(negative_total) at row $(h).")
        end
        scale = required_positive_total / positive_total
        calibrated_df[h, :PositiveImportScale] = scale

        for (_, iface) in SHEET_TO_INTERFACE
            value = official_values[iface]
            calibrated_df[h, iface] = value > 0 ? value * scale : value
        end
    end

    calibrated_df[!, :CalibratedSystemNI] = [
        sum(calibrated_df[h, iface] for (_, iface) in SHEET_TO_INTERFACE) for h in 1:nrow(calibrated_df)
    ]
    return calibrated_df
end

function build_nodal_ni(interface_df::DataFrame, nodal_load_path::AbstractString, cluster_weights::Dict{String, Dict{String, Float64}})
    nodal_load = CSV.read(nodal_load_path, DataFrame)
    if nrow(nodal_load) != nrow(interface_df)
        error("Nodal load row count $(nrow(nodal_load)) does not match interface row count $(nrow(interface_df)).")
    end

    nodal_df = select(nodal_load, TIME_COLS)
    bus_cols = [string(name) for name in names(nodal_load) if !(string(name) in TIME_COLS)]
    for bus in bus_cols
        nodal_df[!, bus] = zeros(Float64, nrow(nodal_df))
    end

    missing_buses = String[]
    for weights in values(cluster_weights)
        for bus in keys(weights)
            if !(bus in bus_cols)
                push!(missing_buses, bus)
            end
        end
    end
    if !isempty(missing_buses)
        error("Portal buses missing from nodal load columns: $(sort(unique(missing_buses))).")
    end

    for (iface, weights) in cluster_weights
        wsum = sum(values(weights))
        for (bus, weight) in weights
            nodal_df[!, bus] .+= interface_df[!, iface] .* (weight / wsum)
        end
    end

    if LOCALIZED_NI_SHARE < 1.0
        target_col = "TargetSystemNI" in string.(names(interface_df)) ? :TargetSystemNI : :CalibratedSystemNI
        localized_cols = [Symbol(bus) for bus in bus_cols]
        for h in 1:nrow(nodal_df)
            target_ni = Float64(interface_df[h, target_col])
            load_weights = Float64.(collect(nodal_load[h, localized_cols]))
            total_load_weight = sum(load_weights)
            if total_load_weight <= 0
                load_weights .= 1.0 / length(load_weights)
            else
                load_weights ./= total_load_weight
            end
            for (idx, bus) in enumerate(bus_cols)
                localized_value = Float64(nodal_df[h, Symbol(bus)])
                background_value = target_ni * load_weights[idx]
                nodal_df[h, Symbol(bus)] = LOCALIZED_NI_SHARE * localized_value + (1.0 - LOCALIZED_NI_SHARE) * background_value
            end
        end
    end

    return nodal_df
end

function main()
    repo_root = normpath(joinpath(@__DIR__, "..", ".."))
    raw_dir = joinpath(@__DIR__, "raw_sources")
    case_dir = joinpath(repo_root, "ModelCases", "ISONE_PCM_250bus_case", "Data_ISONE_PCM_250bus")

    workbook_path = joinpath(raw_dir, "smd_interchange_2024.xlsx")
    regional_load_path = joinpath(case_dir, "load_timeseries_regional.csv")
    nodal_load_path = joinpath(case_dir, "load_timeseries_nodal.csv")
    busdata_path = joinpath(case_dir, "busdata.csv")
    official_interface_csv_path = joinpath(raw_dir, "smd_interchange_2024_07.csv")
    calibrated_interface_csv_path = joinpath(raw_dir, "smd_interchange_2024_07_calibrated_to_case_ni.csv")
    cluster_csv_path = joinpath(raw_dir, "ni_interface_bus_clusters.csv")
    nodal_ni_path = joinpath(case_dir, "ni_timeseries_nodal.csv")

    regional_df = CSV.read(regional_load_path, DataFrame)
    interface_df = build_interface_df(workbook_path, regional_load_path)
    cluster_weights, cluster_summary_df = build_cluster_weights(busdata_path)
    calibrated_interface_df = calibrate_interface_df(interface_df, Float64.(regional_df[!, :NI]))

    CSV.write(official_interface_csv_path, interface_df)
    CSV.write(calibrated_interface_csv_path, calibrated_interface_df)
    CSV.write(cluster_csv_path, cluster_summary_df)

    nodal_df = build_nodal_ni(calibrated_interface_df, nodal_load_path, cluster_weights)
    CSV.write(nodal_ni_path, nodal_df)

    nodal_sum = [sum(Float64.(collect(nodal_df[h, Not(TIME_COLS)]))) for h in 1:nrow(nodal_df)]
    max_official_gap = maximum(abs.(interface_df[!, :ISO_NE_CA_NetInt_MWh] .- interface_df[!, :InterfaceSum_NetInt_MWh]))
    max_target_gap = maximum(abs.(calibrated_interface_df[!, :TargetSystemNI] .- calibrated_interface_df[!, :CalibratedSystemNI]))
    max_nodal_gap = maximum(abs.(Float64.(regional_df[!, :NI]) .- nodal_sum))
    println("Wrote $(official_interface_csv_path)")
    println("Wrote $(calibrated_interface_csv_path)")
    println("Wrote $(cluster_csv_path)")
    println("Wrote $(nodal_ni_path)")
    println("Rows: $(nrow(interface_df))")
    println("Max abs gap between official ISO NE CA net and interface sum: $(max_official_gap)")
    println("Max abs gap between calibrated interface sum and target case NI: $(max_target_gap)")
    println("Max abs gap between nodal NI sum and target case NI: $(max_nodal_gap)")
end

main()
