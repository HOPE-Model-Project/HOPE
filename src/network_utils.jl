"""
Network helper utilities shared by PCM network formulations.
"""

function first_existing_col(colset::Set{String}, candidates::Vector{String})
    for c in candidates
        if c in colset
            return c
        end
    end
    return nothing
end

"""
Resolve a reference node from either:
- integer index in 1..n_nodes
- node id key found in node_idx_map
"""
function resolve_reference_index(reference_raw, n_nodes::Int, node_idx_map::AbstractDict, node_label::String)
    if reference_raw isa Integer
        ref_idx = Int(reference_raw)
        if ref_idx < 1 || ref_idx > n_nodes
            throw(ArgumentError("Invalid $(node_label) reference index=$(ref_idx). Expected integer in [1,$(n_nodes)]."))
        end
        return ref_idx
    end
    ref_key = reference_raw
    if haskey(node_idx_map, ref_key)
        return node_idx_map[ref_key]
    end
    ref_key_str = string(reference_raw)
    if haskey(node_idx_map, ref_key_str)
        return node_idx_map[ref_key_str]
    end
    throw(ArgumentError("Invalid $(node_label) reference=$(reference_raw). Provide either a valid index or an existing node id."))
end

"""
Compute PTDF matrix from line incidence and reactance data.
"""
function compute_ptdf_from_incidence(from_idx::Vector{Int}, to_idx::Vector{Int}, x_vals::Vector{Float64}, n_nodes::Int, reference_node::Int)
    n_line = length(from_idx)
    if n_nodes < 2
        throw(ArgumentError("PTDF requires at least 2 nodes; got $(n_nodes)."))
    end
    A = zeros(Float64, n_line, n_nodes)
    b = zeros(Float64, n_line)
    for l in 1:n_line
        x = x_vals[l]
        if x == 0.0
            throw(ArgumentError("Line $(l) has zero reactance, cannot compute PTDF."))
        end
        b[l] = 1.0 / x
        A[l, from_idx[l]] = 1.0
        A[l, to_idx[l]] = -1.0
    end
    Bdiag = Diagonal(b)
    Bf = Bdiag * A
    Bbus = transpose(A) * Bdiag * A
    keep = [i for i in 1:n_nodes if i != reference_node]
    Bbus_red = Bbus[keep, keep]
    Bbus_red_inv = if rank(Bbus_red) < length(keep)
        println("Warning: Reduced B matrix is singular (likely disconnected network). Using pseudo-inverse for PTDF construction.")
        pinv(Bbus_red)
    else
        inv(Bbus_red)
    end
    ptdf = zeros(Float64, n_line, n_nodes)
    ptdf[:, keep] .= Bf[:, keep] * Bbus_red_inv
    ptdf[:, reference_node] .= 0.0
    return ptdf
end

"""
Convenience wrapper for zonal PTDF construction from linedata.
Reserved for a future zonal-PTDF network mode.
Current PCM behavior does not call this function:
- network_model=1 uses zonal transport
- network_model=2/3 use nodal DCOPF
"""
function compute_zone_ptdf_from_linedata(Linedata::DataFrame, ordered_zone_nm::Vector, reference_bus::Int)
    num_line = size(Linedata, 1)
    num_zone = length(ordered_zone_nm)
    zone_idx = Dict(ordered_zone_nm[i] => i for i in 1:num_zone)
    linedata_cols = Set(string.(names(Linedata)))
    x_col = first_existing_col(linedata_cols, ["X", "Reactance"])
    use_unit_reactance = x_col === nothing
    if use_unit_reactance
        println("Warning: PTDF auto-computation found no line reactance column (X/Reactance). Using unit reactance X=1.0 for all lines.")
    end
    to_float(x) = x isa Number ? Float64(x) : parse(Float64, string(x))
    from_idx = Vector{Int}(undef, num_line)
    to_idx = Vector{Int}(undef, num_line)
    x_vals = Vector{Float64}(undef, num_line)
    for l in 1:num_line
        from_zone = Linedata[l, "From_zone"]
        to_zone = Linedata[l, "To_zone"]
        if !haskey(zone_idx, from_zone) || !haskey(zone_idx, to_zone)
            throw(ArgumentError("Line $(l) uses zones ($(from_zone), $(to_zone)) not found in zonedata Zone_id list."))
        end
        from_idx[l] = zone_idx[from_zone]
        to_idx[l] = zone_idx[to_zone]
        x_vals[l] = use_unit_reactance ? 1.0 : to_float(Linedata[l, x_col])
    end
    return compute_ptdf_from_incidence(from_idx, to_idx, x_vals, num_zone, reference_bus)
end
