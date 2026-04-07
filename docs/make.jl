using HOPE
using Documenter
import DataStructures: OrderedDict

DocMeta.setdocmeta!(HOPE, :DocTestSetup, :(using HOPE); recursive=true)

function normalize_ascii_page_titles(build_dir::AbstractString)
    for file in readdir(build_dir; join=true)
        if isfile(file) && endswith(file, ".html")
            text = read(file, String)
            text = replace(text, " · HOPE.jl" => " - HOPE.jl")
            write(file, text)
        end
    end
    return nothing
end

pages = OrderedDict(
    "Home Page" => [
        "Introduction" => "index.md",
        "Installation"=>"installation.md",
        "Run a case"=>"run_case.md",
    ],
    "Example Cases" => [
        "PJM MD100 GTEP Case" => "case_pjm_md100_gtep.md",
        "Maryland Full-Year Holistic Case" => "case_md_holistic_full8760.md",
        "USA 64-Zone GTEP Case" => "case_usa64_gtep.md",
        "RTS24 PCM Multizone4 Congested 1-Month Case" => "case_rts24_pcm_multizone4.md",
        "ISO-NE 250-Bus PCM Case" => "case_isone_pcm_250bus.md",
        "Germany PCM Case" => "case_germany_pcm.md",
    ],
    "Model Mode and Formulation" => [
        "Model Introduction" => "model_introduction.md",
        "Notation" => "notation.md",
        "GTEP" => "GTEP.md",
        "PCM" => "PCM.md",
    ],
    "Input Data Explanation" => [
        "GTEP Inputs" => "GTEP_inputs.md",
        "PCM Inputs" => "PCM_inputs.md",
    ],
    "Model Settings" => [
        "HOPE Settings" => "hope_model_settings.md",
        "Representative Days" => "rep_day.md",
        "Resource Aggregation" => "resource_aggregation.md",
        "Solver Settings" => "solver_settings.md",
    ],
    "Postprocessing" => [
        "EREC" => "EREC.md",
    ],
    "Reference" => [
        "API Reference" => "95-reference.md",
    ],
    "Project" => [
        "Contributing" => "90-contributing.md",
        "Developer Guide" => "91-developer.md",
    ]
)  

makedocs(;
    modules=[HOPE],
    authors="Shen Wang, Mahdi Mehrtash, Zoe Song and contributors",
    clean=false,
    remotes=nothing,
    sitename="HOPE.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="github.com/swang22/HOPE.git",
        edit_link="master-dev",
        assets = ["assets/favicon.ico", "assets/hope-docs-brand.css"]
    ),
    pages=[p for p in pages]
)

normalize_ascii_page_titles(joinpath(@__DIR__, "build"))

deploydocs(;
    repo="github.com/swang22/HOPE.git",
    devbranch="master-dev",
)
