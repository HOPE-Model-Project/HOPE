"""
# PCM_Working.jl - Working version of transparent PCM
# Built step by step to ensure it works
"""

module PCMWorking

using JuMP
using DataFrames

export PCMModel, create_pcm_model, solve_pcm_model

"""
    PCMModel

Working PCM model structure
"""
mutable struct PCMModel
    model::Model
    input_data::Dict
    config::Dict
    results::Dict
    
    function PCMModel()
        new(Model(), Dict(), Dict(), Dict())
    end
end

"""
    create_pcm_model(config_set::Dict, input_data::Dict, optimizer)

Create a working PCM model using the old logic but with transparent structure
"""
function create_pcm_model(config_set::Dict, input_data::Dict, optimizer)
    
    # Create model structure
    pcm = PCMModel()
    pcm.model = Model(optimizer)
    pcm.input_data = input_data
    pcm.config = config_set
    
    # Extract key data (simplified from old PCM)
    Zonedata = input_data["Zonedata"]
    Gendata = input_data["Gendata"] 
    Storagedata = input_data["Storagedata"]
    Linedata = input_data["Linedata"]
    
    # Basic dimensions
    Num_gen = size(Gendata, 1)
    Num_zone = size(Zonedata, 1)
    Num_sto = size(Storagedata, 1)
    Num_line = size(Linedata, 1)
    
    # Basic sets
    G = 1:Num_gen
    I = 1:Num_zone  
    H = 1:8760
    S = 1:Num_sto
    L = 1:Num_line
    
    # Variables (basic set)
    @variable(pcm.model, p[G, H] >= 0)  # Power generation
    @variable(pcm.model, f[L, H])       # Power flow
    @variable(pcm.model, soc[S, H] >= 0) # Storage state of charge
    @variable(pcm.model, c[S, H] >= 0)   # Storage charging
    @variable(pcm.model, dc[S, H] >= 0)  # Storage discharging
      # Basic constraints (simplified)
    # Power balance (example - simplified)
    for i in I, h in H
        # Find generators in zone i
        zone_name = Zonedata[i, "Zone_id"]
        gens_in_zone = findall(row -> row == zone_name, Gendata[:, "Zone"])
        
        # Simple power balance (to be expanded)
        if !isempty(gens_in_zone)
            @constraint(pcm.model, sum(p[g, h] for g in gens_in_zone) >= 0)
        end
    end
    
    # Basic objective (simplified)
    gen_costs = Gendata[:, Symbol("Cost (\$/MWh)")]
    @objective(pcm.model, Min, sum(gen_costs[g] * sum(p[g, h] for h in H) for g in G))
    
    return pcm
end

"""
    solve_pcm_model(pcm::PCMModel)

Solve the PCM model and store results
"""
function solve_pcm_model(pcm::PCMModel)
    optimize!(pcm.model)
    
    if termination_status(pcm.model) == MOI.OPTIMAL
        pcm.results["status"] = "optimal"
        pcm.results["objective"] = objective_value(pcm.model)
        return true
    else
        pcm.results["status"] = "failed"
        pcm.results["termination"] = termination_status(pcm.model)
        return false
    end
end

end # module PCMWorking
