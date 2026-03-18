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
include("ffi.jl")
include("corpus.jl")
include("query.jl")
include("tables.jl")

export Corpus,
	Hit,
	HitList,
	Component,
	Alignment,
	ConcordanceLine,
	open_corpus,
	token_count,
	layers,
	documents,
	components,
	alignments,
	annotation,
	span_text,
	texts,
	query,
	concordance,
	frequency,
	project

end
