module Montre

using DataFrames
using Tables
using UniversalDependencies
using Montre_jll

const exiting = Ref(false)
atexit(() -> exiting[] = true)

const Layer = Union{Symbol, AbstractString}

include("types.jl")
export Corpus, HitList, Component, Alignment,
	Concordance, ConcordanceLine, CQL, @cql_str

include("ffi.jl")

include("corpus.jl")
export token_count, document_count, sentence_count, component_count,
	layers, features, documents, document_name, document_range,
	components, alignments, edges, span_layers, span_at, span_containing,
	sentence_span, alignment_coverage, paired_documents, unaligned_sentences,
	vocabulary, annotation, annotations, span_text

include("query.jl")
export query, captures, project

include("concordance.jl")
export tokens, concordance, collocates, cooccurrences

include("extract.jl")
export extract, frequency

include("show.jl")

include("tables.jl")

end
