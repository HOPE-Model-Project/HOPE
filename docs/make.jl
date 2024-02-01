using HOPE
using Documenter
import DataStructures: OrderedDict

DocMeta.setdocmeta!(HOPE, :DocTestSetup, :(using HOPE); recursive=true)
pages = OrderedDict(
    "Home Page" => [
        "Introduction" => "index.md",
        "Installation"=>"installation.md",
        "Run a case"=>"run_case.md",
    ],
    "Model Mode and Formulation" => [
        "Model Introduction" => "model_introduction.md",
        "Notation" => "notation.md",
        "GTEP" => "GTEP.md",
        "PCM" => "PCM.md",
    ]
)  

makedocs(;
    modules=[HOPE],
    authors="swang22 <worldspace321@gmail.com> and contributors",
    repo="https://github.com/SW/HOPE.jl/blob/{commit}{path}#{line}",
    sitename="HOPE.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://SW.github.io/HOPE.jl",
        edit_link="master",
        assets=String[],
    ),
    pages=[p for p in pages]
)

deploydocs(;
    repo="github.com/SW/HOPE.jl",
    devbranch="master",
)
