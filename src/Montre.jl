module Montre

const deps_file = joinpath(@__DIR__, "..", "deps", "deps.jl")
if isfile(deps_file)
	include(deps_file)
else
	error(
		"Montre not built. Run: julia $(joinpath(@__DIR__, "..", "deps", "build.jl"))\n" *
		"Or set MONTRE_ROOT and run: using Pkg; Pkg.build(\"Montre\")"
	)
end

include("types.jl")
export Corpus, HitList, Hit, Component, Alignment, ConcordanceLine, CQL, @cql_str

include("ffi.jl")

include("corpus.jl")
export token_count, layers, documents, components, alignments, annotation, span_text

include("query.jl")
export query, texts, concordance, frequency, project

include("tables.jl")

end
