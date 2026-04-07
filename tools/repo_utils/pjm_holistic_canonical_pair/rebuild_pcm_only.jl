include(normpath(joinpath(@__DIR__, "..", "build_pjm_holistic_canonical_pair.jl")))

pcm_zones = Set(String.(read_csv(joinpath(MODEL_CASES_DIR, PCM_SOURCE_CASE, "Data_PJM_PCM_subzones", "zonedata.csv"))[!, "Zone_id"]))
pcm_case_dir = build_pcm_case(pcm_zones)

println("Rebuilt canonical PCM case:")
println("  PCM : ", pcm_case_dir)