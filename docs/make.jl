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
    authors="Shen Wang, Mahdi Mehrtash, Zoe Song and contributors",
    #repo="https://github.com/SW/HOPE.jl/blob/{commit}{path}#{line}",
    sitename="HOPE.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="github.com/swang22/HOPE.git",
        edit_link="master",
        assets = ["assets/favicon.ico"],
        assets = ["assets/logo.png"],
    ),
    pages=[p for p in pages]
)

deploydocs(;
    repo="github.com/swang22/HOPE.git",
    devbranch="master",
)
