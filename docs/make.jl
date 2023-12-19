using HOPE
using Documenter

DocMeta.setdocmeta!(HOPE, :DocTestSetup, :(using HOPE); recursive=true)

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
    pages=[
        "Home" => "index.md",
        "Reference" => "reference.md",
    ],
)

deploydocs(;
    repo="github.com/SW/HOPE.jl",
    devbranch="master",
)
