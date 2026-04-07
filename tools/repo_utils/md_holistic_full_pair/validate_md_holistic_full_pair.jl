using DataFrames
using HOPE

const GTEP_CASE = "ModelCases/MD_GTEP_holistic_full8760_case_v20260406g"
const PCM_CASE = "ModelCases/MD_PCM_holistic_full8760_case_v20260406g"

function main()
    gtep_path, gtep_config = HOPE.load_case_config_for_holistic(GTEP_CASE; context="validate_md_holistic_full_pair")
    pcm_path, pcm_config = HOPE.load_case_config_for_holistic(PCM_CASE; context="validate_md_holistic_full_pair")
    gtep_input = HOPE.load_data(gtep_config, gtep_path)
    pcm_input = HOPE.load_data(pcm_config, pcm_path)
    HOPE.validate_holistic_case_pair!(gtep_path, gtep_config, gtep_input, pcm_path, pcm_config, pcm_input)
    println("MD holistic full pair validated successfully.")
    println("  GTEP: ", gtep_path)
    println("  PCM : ", pcm_path)
    println("  Zones: ", nrow(gtep_input["Zonedata"]))
    println("  Corridors: ", nrow(gtep_input["Linedata"]))
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end