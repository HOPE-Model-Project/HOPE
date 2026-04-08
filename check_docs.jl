import Pkg
Pkg.activate(".")
using HOPE

exported = names(HOPE; all=false)
println("Exported: $(length(exported)) symbols")
for s in exported
    fn = getfield(HOPE, s)
    doc_str = string(@doc(fn))
    has_doc = !startswith(doc_str, "No documentation found") && length(doc_str) > 5
    println("$(has_doc ? "OK " : "MISS") $s")
end
