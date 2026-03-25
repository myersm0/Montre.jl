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
export Corpus, HitList, Hit, Component, Alignment, ProjectionResult,
	Concordance, ConcordanceLine, CQL, @cql_str

include("ffi.jl")

include("corpus.jl")
export token_count, document_count, sentence_count, component_count,
	layers, features, documents, document_name, document_range,
	components, alignments, edges, span_layers, span_at, span_containing,
	vocabulary, annotation, annotations, span_text

include("query.jl")
export query, texts, concordance, frequency, collocates, project

include("tables.jl")

end
