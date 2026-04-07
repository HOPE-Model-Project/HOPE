using HOPE

function main(args)
    if length(args) != 2
        println("Usage: julia --project=. tools/repo_utils/audit_holistic_case_pair.jl <GTEP_case> <PCM_case>")
        return 1
    end

    gtep_case, pcm_case = args
    try
        gtep_path, gtep_config = HOPE.load_case_config_for_holistic(gtep_case; context = "audit_holistic_case_pair")
        pcm_path, pcm_config = HOPE.load_case_config_for_holistic(pcm_case; context = "audit_holistic_case_pair")

        println("Auditing holistic pair:")
        println("  GTEP: ", gtep_path)
        println("  PCM : ", pcm_path)

        gtep_input = HOPE.load_data(gtep_config, gtep_path)
        pcm_input = HOPE.load_data(pcm_config, pcm_path)
        HOPE.validate_holistic_case_pair!(gtep_path, gtep_config, gtep_input, pcm_path, pcm_config, pcm_input)

        println("Holistic pair audit passed.")
        return 0
    catch err
        println(err)
        return 2
    end
end

exit(main(ARGS))
