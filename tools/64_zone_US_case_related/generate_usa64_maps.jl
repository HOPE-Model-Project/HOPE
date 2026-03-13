using CSV
using DataFrames
using Printf
using Shapefile
using Statistics

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const SHP_PATH = joinpath(ROOT, "tmp_ipm_v6_regions", "IPM_Regions_201770405.shp")
const GEN_PATH = joinpath(ROOT, "ModelCases", "USA_64zone", "Parameter_527", "Generators_data.csv")
const LINE_EXIST_PATH = joinpath(ROOT, "ModelCases", "USA_64zone_GTEP_case", "Data_USA64_GTEP", "linedata.csv")
const LINE_BUILD_PATH = joinpath(ROOT, "ModelCases", "USA_64zone_GTEP_case", "output", "line.csv")

const OUT_BASE = joinpath(ROOT, "docs", "src", "assets", "modelcases_usa64_base_network_map.svg")
const OUT_BUILD = joinpath(ROOT, "docs", "src", "assets", "modelcases_usa64_buildout_map.svg")

parse_num(x, d = 0.0) = begin
    sx = strip(string(x))
    isempty(sx) && return d
    sl = lowercase(sx)
    sl in ("na", "n/a", "#n/a", "missing") && return d
    v = tryparse(Float64, sx)
    isnothing(v) ? d : v
end

zone_idx(z::AbstractString) = parse(Int, replace(lowercase(strip(z)), "z" => ""))

function zone_pair(a::AbstractString, b::AbstractString)
    ia = zone_idx(a)
    ib = zone_idx(b)
    ia <= ib ? (a, b) : (b, a)
end

function normalize_trans_region(x::AbstractString)
    s = strip(x)
    lowercase(s) == "caiso" ? "California" : s
end

function load_zone_maps()
    gen = CSV.read(GEN_PATH, DataFrame)
    g = combine(
        groupby(gen, :Zone),
        :region => (x -> first(unique(string.(x)))) => :ipm_region,
        Symbol("Transmission Region") => (x -> first(unique(string.(x)))) => :trans_region,
    )
    sort!(g, :Zone)
    zone_to_ipm = Dict{String, String}()
    zone_to_trans = Dict{String, String}()
    ipm_to_zone = Dict{String, String}()
    for r in eachrow(g)
        z = "z$(Int(r.Zone))"
        ipm = String(r.ipm_region)
        tr = normalize_trans_region(String(r.trans_region))
        zone_to_ipm[z] = ipm
        zone_to_trans[z] = tr
        ipm_to_zone[ipm] = z
    end
    return zone_to_ipm, zone_to_trans, ipm_to_zone
end

function polygon_rings(poly::Shapefile.Polygon)
    starts = Int.(poly.parts) .+ 1
    ends = vcat(starts[2:end] .- 1, length(poly.points))
    rings = Vector{Vector{Tuple{Float64, Float64}}}()
    for (s, e) in zip(starts, ends)
        s > e && continue
        ring = [(poly.points[i].x, poly.points[i].y) for i in s:e]
        length(ring) >= 3 && push!(rings, ring)
    end
    return rings
end

function load_shapes(ipm_to_zone::Dict{String, String})
    tbl = Shapefile.Table(SHP_PATH)
    out = Dict{String, Vector{Vector{Tuple{Float64, Float64}}}}()
    for row in tbl
        ipm = String(getproperty(row, :IPM_Region))
        haskey(ipm_to_zone, ipm) || continue
        geom = getproperty(row, :geometry)
        geom isa Shapefile.Polygon || continue
        out[ipm] = polygon_rings(geom)
    end
    return out
end

function polygon_centroid(rings::Vector{Vector{Tuple{Float64, Float64}}})
    sx = 0.0
    sy = 0.0
    n = 0
    for ring in rings, (x, y) in ring
        sx += x
        sy += y
        n += 1
    end
    n == 0 && return (0.0, 0.0)
    return (sx / n, sy / n)
end

struct Transform
    cx::Float64
    cy::Float64
    θ::Float64
    xmin::Float64
    xmax::Float64
    ymin::Float64
    ymax::Float64
    panel_x::Float64
    panel_y::Float64
    panel_w::Float64
    panel_h::Float64
    margin::Float64
end

function rotate_xy(x::Float64, y::Float64, cx::Float64, cy::Float64, θ::Float64)
    dx = x - cx
    dy = y - cy
    ct = cos(θ)
    st = sin(θ)
    return (ct * dx - st * dy + cx, st * dx + ct * dy + cy)
end

function build_transform(shapes::Dict{String, Vector{Vector{Tuple{Float64, Float64}}}}; panel_x = 34.0, panel_y = 118.0, panel_w = 1360.0, panel_h = 900.0, margin = 64.0, extra_rot_deg = 3.5)
    xs = Float64[]
    ys = Float64[]
    for rings in values(shapes), ring in rings, (x, y) in ring
        push!(xs, x)
        push!(ys, y)
    end
    cx = mean(xs)
    cy = mean(ys)
    dx = xs .- cx
    dy = ys .- cy
    covxx = mean(dx .* dx)
    covyy = mean(dy .* dy)
    covxy = mean(dx .* dy)
    major = 0.5 * atan(2 * covxy, covxx - covyy)
    θ = -major + extra_rot_deg * pi / 180

    xmin = Inf
    xmax = -Inf
    ymin = Inf
    ymax = -Inf
    for i in eachindex(xs)
        xr, yr = rotate_xy(xs[i], ys[i], cx, cy, θ)
        xmin = min(xmin, xr)
        xmax = max(xmax, xr)
        ymin = min(ymin, yr)
        ymax = max(ymax, yr)
    end
    return Transform(cx, cy, θ, xmin, xmax, ymin, ymax, panel_x, panel_y, panel_w, panel_h, margin)
end

function xy(t::Transform, x::Float64, y::Float64)
    xr, yr = rotate_xy(x, y, t.cx, t.cy, t.θ)
    wr = t.xmax - t.xmin
    hr = t.ymax - t.ymin
    avail_w = t.panel_w - 2t.margin
    avail_h = t.panel_h - 2t.margin
    s = min(avail_w / wr, avail_h / hr)
    padx = (t.panel_w - s * wr) / 2
    pady = (t.panel_h - s * hr) / 2
    sx = t.panel_x + padx + (xr - t.xmin) * s
    sy = t.panel_y + (t.panel_h - (pady + (yr - t.ymin) * s))
    return sx, sy
end

function ring_path(ring::Vector{Tuple{Float64, Float64}}, t::Transform)
    isempty(ring) && return ""
    io = IOBuffer()
    x0, y0 = xy(t, ring[1][1], ring[1][2])
    print(io, @sprintf("M %.1f %.1f ", x0, y0))
    for i in 2:length(ring)
        x, y = xy(t, ring[i][1], ring[i][2])
        print(io, @sprintf("L %.1f %.1f ", x, y))
    end
    print(io, "Z")
    return String(take!(io))
end

function read_edges(path::AbstractString; build_only::Bool = false)
    df = CSV.read(path, DataFrame)
    caps = Dict{Tuple{String, String}, Float64}()
    for r in eachrow(df)
        a = String(r.From_zone)
        b = String(r.To_zone)
        c = parse_num(r[Symbol("Capacity (MW)")], 0.0)
        build_only && c <= 1e-6 && continue
        !build_only && c <= 0.0 && continue
        p = zone_pair(a, b)
        caps[p] = get(caps, p, 0.0) + c
    end
    return caps
end

function build_segments(caps::Dict{Tuple{String, String}, Float64}, zone_to_ipm::Dict{String, String}, centroids::Dict{String, Tuple{Float64, Float64}})
    segs = NamedTuple[]
    for (p, cap) in caps
        a, b = p
        haskey(zone_to_ipm, a) || continue
        haskey(zone_to_ipm, b) || continue
        ia = zone_to_ipm[a]
        ib = zone_to_ipm[b]
        haskey(centroids, ia) || continue
        haskey(centroids, ib) || continue
        xa, ya = centroids[ia]
        xb, yb = centroids[ib]
        push!(segs, (a = a, b = b, cap = cap, xa = xa, ya = ya, xb = xb, yb = yb))
    end
    sort!(segs, by = x -> x.cap)
    return segs
end

function three_bin_thresholds(vals::Vector{Float64})
    isempty(vals) && return (0.0, 0.0)
    q = quantile(vals, [1 / 3, 2 / 3])
    return (q[1], q[2])
end

function width_bin(cap::Float64, q1::Float64, q2::Float64; w1::Float64 = 0.9, w2::Float64 = 2.2, w3::Float64 = 4.2)
    if cap <= q1
        return w1
    elseif cap <= q2
        return w2
    else
        return w3
    end
end

function opacity_bin(cap::Float64, q1::Float64, q2::Float64; o1::Float64 = 0.40, o2::Float64 = 0.58, o3::Float64 = 0.78)
    if cap <= q1
        return o1
    elseif cap <= q2
        return o2
    else
        return o3
    end
end

function offset_segment(x1::Float64, y1::Float64, x2::Float64, y2::Float64, offset_px::Float64)
    dx = x2 - x1
    dy = y2 - y1
    len = hypot(dx, dy)
    if len < 1e-6
        return (x1, y1, x2, y2)
    end
    nx = -dy / len
    ny = dx / len
    return (x1 + offset_px * nx, y1 + offset_px * ny, x2 + offset_px * nx, y2 + offset_px * ny)
end

const TRANS_COLORS = Dict(
    "Texas" => "#d73027",
    "Florida" => "#fee08b",
    "Midwest" => "#4575b4",
    "Northeast" => "#74add1",
    "New York" => "#abd9e9",
    "Mid-Atlantic" => "#66c2a5",
    "Southeast" => "#fdae61",
    "Central" => "#e6ab02",
    "California" => "#1b9e77",
    "Northwest" => "#6a3d9a",
    "Southwest" => "#b15928",
)

function svg_header(io, width::Int, height::Int)
    println(io, """<svg xmlns="http://www.w3.org/2000/svg" width="$width" height="$height" viewBox="0 0 $width $height">""")
end

function draw_common_background(io)
    println(io, """<rect x="0" y="0" width="1960" height="1100" fill="#eceff4"/>""")
    println(io, """<rect x="24" y="98" width="1380" height="960" rx="12" fill="#f8fafc" stroke="#c9d2de"/>""")
    println(io, """<rect x="1420" y="98" width="516" height="960" rx="10" fill="#ffffff" stroke="#c9d2de"/>""")
end

function write_base_svg(path::AbstractString, shapes, ipm_to_zone, zone_to_trans, centroids, segs)
    t = build_transform(shapes)
    caps = [s.cap for s in segs]
    q1, q2 = three_bin_thresholds(caps)
    low_lbl = @sprintf("Low: up to %.0f MW", q1)
    mid_lbl = @sprintf("Medium: %.0f to %.0f MW", q1, q2)
    high_lbl = @sprintf("High: above %.0f MW", q2)

    open(path, "w") do io
        svg_header(io, 1960, 1100)
        draw_common_background(io)
        println(io, """<text x="34" y="56" font-size="50" font-family="Georgia, serif" fill="#111827">USA64 GTEP: Existing Transmission Network</text>""")
        println(io, """<text x="34" y="88" font-size="22" font-family="Arial, sans-serif" fill="#334155">EPA IPM v6 64-zone boundaries with existing inter-zonal corridor capacities from HOPE input data.</text>""")

        for ipm in sort(collect(keys(shapes)))
            rings = shapes[ipm]
            zone = ipm_to_zone[ipm]
            col = get(TRANS_COLORS, get(zone_to_trans, zone, "Unknown"), "#cbd5e1")
            d = join((ring_path(r, t) for r in rings), " ")
            println(io, """<path d="$d" fill="$col" fill-opacity="0.84" stroke="#5f6b7c" stroke-width="0.45" stroke-linejoin="round"/>""")
        end

        for s in segs
            x1, y1 = xy(t, s.xa, s.ya)
            x2, y2 = xy(t, s.xb, s.yb)
            w = width_bin(s.cap, q1, q2; w1 = 1.2, w2 = 2.8, w3 = 4.9)
            op = opacity_bin(s.cap, q1, q2; o1 = 0.42, o2 = 0.60, o3 = 0.80)
            println(io, @sprintf("<line x1=\"%.1f\" y1=\"%.1f\" x2=\"%.1f\" y2=\"%.1f\" stroke=\"#475569\" stroke-width=\"%.2f\" opacity=\"%.2f\"/>", x1, y1, x2, y2, w, op))
        end

        for (ipm, (cx, cy)) in centroids
            z = ipm_to_zone[ipm]
            sx, sy = xy(t, cx, cy)
            println(io, @sprintf("<circle cx=\"%.1f\" cy=\"%.1f\" r=\"3.6\" fill=\"#0f172a\"/>", sx, sy))
            println(io, @sprintf("<text x=\"%.1f\" y=\"%.1f\" font-size=\"17.6\" text-anchor=\"middle\" font-family=\"Arial, sans-serif\" fill=\"#0f172a\">%s</text>", sx, sy - 9.8, z))
        end

        println(io, """<text x="1442" y="145" font-size="52" font-family="Georgia, serif" fill="#111827">Legend</text>""")
        println(io, """<text x="1442" y="180" font-size="20" font-family="Arial, sans-serif" fill="#334155">Polygon color = 11 transmission regions.</text>""")

        reg_names = sort(collect(keys(TRANS_COLORS)))
        for (i, r) in enumerate(reg_names)
            y = 220 + 37 * (i - 1)
            println(io, """<rect x="1442" y="$(y-15)" width="20" height="20" fill="$(TRANS_COLORS[r])" stroke="#334155" stroke-width="0.7"/>""")
            println(io, """<text x="1474" y="$y" font-size="20" font-family="Arial, sans-serif" fill="#334155">$r</text>""")
        end
        y0 = 220 + 37 * length(reg_names) + 46
        println(io, """<text x="1442" y="$(y0-16)" font-size="19" font-family="Arial, sans-serif" fill="#334155">Line width = capacity bin (MW)</text>""")
        println(io, """<line x1="1442" y1="$y0" x2="1530" y2="$y0" stroke="#475569" stroke-width="1.2" opacity="0.48"/>""")
        println(io, """<line x1="1442" y1="$(y0+34)" x2="1530" y2="$(y0+34)" stroke="#475569" stroke-width="2.8" opacity="0.62"/>""")
        println(io, """<line x1="1442" y1="$(y0+68)" x2="1530" y2="$(y0+68)" stroke="#475569" stroke-width="4.9" opacity="0.80"/>""")
        println(io, """<text x="1542" y="$(y0+6)" font-size="18" font-family="Arial, sans-serif" fill="#334155">$low_lbl</text>""")
        println(io, """<text x="1542" y="$(y0+40)" font-size="18" font-family="Arial, sans-serif" fill="#334155">$mid_lbl</text>""")
        println(io, """<text x="1542" y="$(y0+74)" font-size="18" font-family="Arial, sans-serif" fill="#334155">$high_lbl</text>""")
        println(io, """<text x="1442" y="$(y0+112)" font-size="18" font-family="Arial, sans-serif" fill="#475569">Node labels are HOPE zones (z1..z64).</text>""")
        println(io, """<text x="1442" y="$(y0+138)" font-size="18" font-family="Arial, sans-serif" fill="#475569">Boundaries from EPA IPM v6 region shapefile.</text>""")
        println(io, "</svg>")
    end
end

function write_build_svg(path::AbstractString, shapes, ipm_to_zone, zone_to_trans, centroids, seg_exist, seg_build)
    t = build_transform(shapes)
    caps_exist = [s.cap for s in seg_exist]
    caps_build = [s.cap for s in seg_build]
    q1e, q2e = three_bin_thresholds(caps_exist)
    q1b, q2b = three_bin_thresholds(caps_build)
    low_exist_lbl = @sprintf("Existing low: up to %.0f MW", q1e)
    mid_exist_lbl = @sprintf("Existing med: %.0f to %.0f MW", q1e, q2e)
    high_exist_lbl = @sprintf("Existing high: above %.0f MW", q2e)
    low_build_lbl = @sprintf("Buildout low: up to %.0f MW", q1b)
    mid_build_lbl = @sprintf("Buildout med: %.0f to %.0f MW", q1b, q2b)
    high_build_lbl = @sprintf("Buildout high: above %.0f MW", q2b)
    existing_cap = Dict{Tuple{String, String}, Float64}()
    for s in seg_exist
        existing_cap[zone_pair(s.a, s.b)] = s.cap
    end
    build_cap = Dict{Tuple{String, String}, Float64}()
    for s in seg_build
        build_cap[zone_pair(s.a, s.b)] = s.cap
    end
    top = sort(seg_build, by = x -> x.cap, rev = true)[1:min(12, length(seg_build))]

    open(path, "w") do io
        svg_header(io, 1960, 1100)
        draw_common_background(io)
        println(io, """<text x="34" y="56" font-size="50" font-family="Georgia, serif" fill="#111827">USA64 GTEP: Optimized Transmission Buildouts</text>""")
        println(io, """<text x="34" y="88" font-size="22" font-family="Arial, sans-serif" fill="#334155">Colored regions with HOPE buildout overlay: gray = existing, red = optimized expansion.</text>""")

        for ipm in sort(collect(keys(shapes)))
            rings = shapes[ipm]
            zone = ipm_to_zone[ipm]
            col = get(TRANS_COLORS, get(zone_to_trans, zone, "Unknown"), "#cbd5e1")
            d = join((ring_path(r, t) for r in rings), " ")
            println(io, """<path d="$d" fill="$col" fill-opacity="0.74" stroke="#5f6b7c" stroke-width="0.42" stroke-linejoin="round"/>""")
        end

        for s in seg_exist
            x1, y1 = xy(t, s.xa, s.ya)
            x2, y2 = xy(t, s.xb, s.yb)
            p = zone_pair(s.a, s.b)
            has_build = haskey(build_cap, p)
            sx1, sy1, sx2, sy2 = has_build ? offset_segment(x1, y1, x2, y2, -3.6) : (x1, y1, x2, y2)
            w = width_bin(s.cap, q1e, q2e; w1 = 1.0, w2 = 2.4, w3 = 4.6)
            op = opacity_bin(s.cap, q1e, q2e; o1 = 0.40, o2 = 0.60, o3 = 0.78)
            println(io, @sprintf("<line x1=\"%.1f\" y1=\"%.1f\" x2=\"%.1f\" y2=\"%.1f\" stroke=\"#64748b\" stroke-width=\"%.2f\" opacity=\"%.2f\"/>", sx1, sy1, sx2, sy2, w, op))
        end

        for s in seg_build
            x1, y1 = xy(t, s.xa, s.ya)
            x2, y2 = xy(t, s.xb, s.yb)
            p = zone_pair(s.a, s.b)
            has_exist = haskey(existing_cap, p)
            sx1, sy1, sx2, sy2 = has_exist ? offset_segment(x1, y1, x2, y2, 3.6) : (x1, y1, x2, y2)
            w = width_bin(s.cap, q1b, q2b; w1 = 1.2, w2 = 2.9, w3 = 5.4)
            op = opacity_bin(s.cap, q1b, q2b; o1 = 0.48, o2 = 0.70, o3 = 0.90)
            println(io, @sprintf("<line x1=\"%.1f\" y1=\"%.1f\" x2=\"%.1f\" y2=\"%.1f\" stroke=\"#dc2626\" stroke-width=\"%.2f\" opacity=\"%.2f\"/>", sx1, sy1, sx2, sy2, w, op))
        end

        for (ipm, (cx, cy)) in centroids
            z = ipm_to_zone[ipm]
            sx, sy = xy(t, cx, cy)
            println(io, @sprintf("<circle cx=\"%.1f\" cy=\"%.1f\" r=\"3.5\" fill=\"#0f172a\"/>", sx, sy))
            println(io, @sprintf("<text x=\"%.1f\" y=\"%.1f\" font-size=\"17.2\" text-anchor=\"middle\" font-family=\"Arial, sans-serif\" fill=\"#0f172a\">%s</text>", sx, sy - 9.6, z))
        end

        println(io, """<text x="1442" y="145" font-size="52" font-family="Georgia, serif" fill="#111827">Legend</text>""")
        println(io, """<line x1="1442" y1="194" x2="1556" y2="194" stroke="#64748b" stroke-width="2.2" opacity="0.72"/>""")
        println(io, """<text x="1548" y="202" font-size="22" font-family="Arial, sans-serif" fill="#334155">Existing corridor</text>""")
        println(io, """<line x1="1442" y1="236" x2="1556" y2="236" stroke="#dc2626" stroke-width="4.3" opacity="0.84"/>""")
        println(io, """<text x="1548" y="244" font-size="22" font-family="Arial, sans-serif" fill="#334155">HOPE expansion buildout</text>""")
        println(io, """<text x="1442" y="286" font-size="20" font-family="Arial, sans-serif" fill="#1f2937">Line width = capacity bin (MW)</text>""")
        println(io, """<line x1="1442" y1="314" x2="1518" y2="314" stroke="#64748b" stroke-width="1.0" opacity="0.42"/>""")
        println(io, """<text x="1528" y="321" font-size="16" font-family="Arial, sans-serif" fill="#334155">$low_exist_lbl</text>""")
        println(io, """<line x1="1442" y1="344" x2="1518" y2="344" stroke="#64748b" stroke-width="2.4" opacity="0.60"/>""")
        println(io, """<text x="1528" y="351" font-size="16" font-family="Arial, sans-serif" fill="#334155">$mid_exist_lbl</text>""")
        println(io, """<line x1="1442" y1="374" x2="1518" y2="374" stroke="#64748b" stroke-width="4.6" opacity="0.78"/>""")
        println(io, """<text x="1528" y="381" font-size="16" font-family="Arial, sans-serif" fill="#334155">$high_exist_lbl</text>""")
        println(io, """<line x1="1442" y1="408" x2="1518" y2="408" stroke="#dc2626" stroke-width="1.2" opacity="0.48"/>""")
        println(io, """<text x="1528" y="415" font-size="16" font-family="Arial, sans-serif" fill="#334155">$low_build_lbl</text>""")
        println(io, """<line x1="1442" y1="438" x2="1518" y2="438" stroke="#dc2626" stroke-width="2.9" opacity="0.70"/>""")
        println(io, """<text x="1528" y="445" font-size="16" font-family="Arial, sans-serif" fill="#334155">$mid_build_lbl</text>""")
        println(io, """<line x1="1442" y1="468" x2="1518" y2="468" stroke="#dc2626" stroke-width="5.4" opacity="0.90"/>""")
        println(io, """<text x="1528" y="475" font-size="16" font-family="Arial, sans-serif" fill="#334155">$high_build_lbl</text>""")
        println(io, """<text x="1442" y="526" font-size="20" font-family="Arial, sans-serif" fill="#1f2937">Top HOPE built corridors (MW)</text>""")
        y = 560
        for s in top
            println(io, @sprintf("<text x=\"1442\" y=\"%d\" font-size=\"16\" font-family=\"Arial, sans-serif\" fill=\"#334155\">%s-%s: %.1f</text>", y, s.a, s.b, s.cap))
            y += 24
        end
        println(io, "</svg>")
    end
end

function main()
    zone_to_ipm, zone_to_trans, ipm_to_zone = load_zone_maps()
    shapes = load_shapes(ipm_to_zone)
    centroids = Dict(ipm => polygon_centroid(rings) for (ipm, rings) in shapes)

    e_exist = read_edges(LINE_EXIST_PATH)
    e_build = read_edges(LINE_BUILD_PATH; build_only = true)
    seg_exist = build_segments(e_exist, zone_to_ipm, centroids)
    seg_build = build_segments(e_build, zone_to_ipm, centroids)

    write_base_svg(OUT_BASE, shapes, ipm_to_zone, zone_to_trans, centroids, seg_exist)
    write_build_svg(OUT_BUILD, shapes, ipm_to_zone, zone_to_trans, centroids, seg_exist, seg_build)

    println("Wrote:")
    println(" - ", OUT_BASE)
    println(" - ", OUT_BUILD)
end

main()
