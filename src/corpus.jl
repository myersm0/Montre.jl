"""
	Montre.open(path::AbstractString) -> Corpus
	Montre.open(f::Function, path::AbstractString)

Open a montre corpus at `path`. The `do`-block form closes the corpus automatically.

```julia
corpus = Montre.open("./my-corpus")
# ...
close(corpus)

Montre.open("./my-corpus") do corpus
    query(corpus, cql"[pos='NOUN']")
end
```
"""
function open(path::AbstractString)
	pointer = corpus_open(path)
	return Corpus(pointer)
end

function open(f::Function, path::AbstractString)
	corpus = open(path)
	try
		f(corpus)
	finally
		close(corpus)
	end
end

function Base.close(corpus::Corpus)
	if corpus.pointer != C_NULL
		corpus_close(corpus.pointer)
		corpus.pointer = C_NULL
	end
end

Base.isopen(corpus::Corpus) = corpus.pointer != C_NULL

"""
	token_count(corpus; component=nothing, document=nothing) -> Int

Token count for the corpus, a component, or a single document.

```julia
token_count(corpus)
token_count(corpus; component="maupassant-fr")
token_count(corpus; document="allouma.conllu")
```
"""
function token_count(corpus::Corpus; component::Union{AbstractString, Nothing} = nothing, document::Union{AbstractString, Nothing} = nothing)
	if component !== nothing && document !== nothing
		error("Montre: specify component or document, not both")
	end
	if component !== nothing
		comps = components(corpus)
		idx = findfirst(c -> c.name == component, comps)
		idx === nothing && error("Montre: component not found: $component")
		return comps[idx].token_count
	end
	if document !== nothing
		docs = documents(corpus)
		idx = findfirst(d -> d == document, docs)
		idx === nothing && error("Montre: document not found: $document")
		return length(span_at(corpus, "document", idx - 1))
	end
	Int(corpus_token_count(corpus.pointer))
end

"""
	layers(corpus::Corpus) -> Vector{String}

Available annotation layers, e.g. `["word", "lemma", "pos", "deprel", "feats"]`.
"""
function layers(corpus::Corpus)
	n = Int(corpus_layer_count(corpus.pointer))
	[corpus_layer_name(corpus.pointer, i) for i in 0:n - 1]
end

"""
	features(corpus::Corpus) -> Vector{String}

Decomposed morphological feature layers (those starting with `"feats."`).
"""
function features(corpus::Corpus)
	filter(l -> startswith(l, "feats."), layers(corpus))
end

"""
	documents(corpus; component=nothing) -> Vector{String}

Document names in the corpus (typically source filenames).
With `component`, returns only documents belonging to that component.
"""
function documents(corpus::Corpus; component::Union{AbstractString, Nothing} = nothing)
	if component === nothing
		n = Int(corpus_document_count(corpus.pointer))
		return [corpus_document_name(corpus.pointer, i) for i in 0:n - 1]
	end
	r = document_range(corpus, component)
	[corpus_document_name(corpus.pointer, i) for i in r]
end

"""
	document_name(corpus::Corpus, index::Integer) -> String

Document name by 0-based index.
"""
function document_name(corpus::Corpus, index::Integer)
	corpus_document_name(corpus.pointer, index)
end

"""
	document_range(corpus, component_name::AbstractString) -> UnitRange{Int}

0-based document index range for a named component.
"""
function document_range(corpus::Corpus, component_name::AbstractString)
	comps = components(corpus)
	idx = findfirst(c -> c.name == component_name, comps)
	idx === nothing && error("Montre: component not found: $component_name")
	corpus_component_document_range(corpus.pointer, idx - 1)
end

"""
	span_at(corpus, layer, index) -> UnitRange{Int}

Token range for a span by layer name and 0-based index.
"""
function span_at(corpus::Corpus, layer::AbstractString, index::Integer)
	result = corpus_span_at(corpus.pointer, layer, index)
	result === nothing && error("Montre: invalid span layer or index")
	return result
end

"""
	span_containing(corpus, layer, position) -> (; index, span)

Find the span containing a token position. Returns a named tuple
with the span index and its token range, or `nothing` if not found.
"""
function span_containing(corpus::Corpus, layer::AbstractString, position::Integer)
	corpus_span_containing(corpus.pointer, layer, position)
end

"""
	components(corpus::Corpus) -> Vector{Component}

Named subcorpora (languages, editions, etc.) in the corpus.
"""
function components(corpus::Corpus)
	n = Int(corpus_component_count(corpus.pointer))
	[
		Component(
			corpus_component_name(corpus.pointer, i),
			corpus_component_language(corpus.pointer, i),
			something(corpus_component_token_count(corpus.pointer, i), 0),
		)
		for i in 0:n - 1
	]
end

"""
	span_layers(corpus::Corpus) -> Vector{String}

Available span layers (e.g. `["sentence", "document", "paragraph"]`).
"""
function span_layers(corpus::Corpus)
	n = Int(corpus_span_layer_count(corpus.pointer))
	[corpus_span_layer_name(corpus.pointer, i) for i in 0:n - 1]
end

"""
	vocabulary(corpus::Corpus, layer::AbstractString) -> Vector{String}

All distinct values for a layer from the inverted index.
For high-cardinality layers like `"word"` or `"lemma"`, this may return
tens of thousands of entries.
"""
function vocabulary(corpus::Corpus, layer::AbstractString)
	corpus_inverted_values(corpus.pointer, layer)
end

"""
	annotation(corpus::Corpus, position::Integer, layer::AbstractString) -> String

Value of a single annotation layer at a given token position.

```julia
annotation(corpus, 42, "pos")    # => "NOUN"
annotation(corpus, 42, "lemma")  # => "âme"
```
"""
function annotation(corpus::Corpus, position::Integer, layer::AbstractString)
	corpus_token_annotation(corpus.pointer, position, layer)
end

"""
	annotations(corpus::Corpus, range::UnitRange, layer::AbstractString) -> Vector{String}

Bulk annotation extraction for a contiguous position range.
"""
function annotations(corpus::Corpus, range::UnitRange, layer::AbstractString)
	corpus_token_annotations(corpus.pointer, first(range), last(range) + 1, layer)
end

"""
	span_text(corpus, start, stop; layer="word")
	span_text(corpus, range::UnitRange; layer="word")
	span_text(corpus, hit::Hit; layer="word")

Concatenated text of tokens in a span, joined by spaces.
Accepts raw integer bounds (half-open), a `UnitRange`, or a `Hit`.
"""
function span_text(corpus::Corpus, start::Integer, stop::Integer; layer::AbstractString = "word")
	corpus_span_text(corpus.pointer, start, stop, layer)
end

function span_text(corpus::Corpus, range::UnitRange; layer::AbstractString = "word")
	span_text(corpus, first(range), last(range) + 1; layer = layer)
end

function span_text(corpus::Corpus, hit::Hit; layer::AbstractString = "word")
	span_text(corpus, hit.span; layer = layer)
end

"""
	alignments(corpus::Corpus) -> Vector{Alignment}

Named alignment relations between components (e.g. sentence-level translation alignments).
"""
function alignments(corpus::Corpus)
	n = Int(corpus_alignment_count(corpus.pointer))
	[
		Alignment(
			corpus_alignment_name(corpus.pointer, i),
			corpus_alignment_source(corpus.pointer, i),
			corpus_alignment_target(corpus.pointer, i),
			something(corpus_alignment_source_layer(corpus.pointer, i), ""),
			something(corpus_alignment_target_layer(corpus.pointer, i), ""),
			something(corpus_alignment_directed(corpus.pointer, i), true),
			Int(corpus_alignment_edge_count(corpus.pointer, i)),
		)
		for i in 0:n - 1
	]
end

"""
	Montre.build(input_dir, output_dir; name="corpus", decompose_feats=false, strict=false)
	Montre.build(manifest_path, output_dir; decompose_feats=false, strict=false)

Build a montre corpus from CoNLL-U files. The first form builds a single-component
corpus from a directory. The second form (when `manifest_path` ends in `.toml`)
builds a multi-component corpus from a TOML manifest.

```julia
Montre.build("data/conllu/", "my-corpus/"; name="maupassant", decompose_feats=true)
Montre.build("corpus.toml", "my-corpus/")
```
"""
function build(input::AbstractString, output::AbstractString;
	name::AbstractString = "corpus", decompose_feats::Bool = false, strict::Bool = false,
)
	if endswith(input, ".toml")
		build_manifest(input, output; decompose_feats, strict)
	else
		build_directory(name, input, output; decompose_feats, strict)
	end
end

# ---- display ----

function Base.show(io::IO, corpus::Corpus)
	if !isopen(corpus)
		print(io, "Corpus (closed)")
		return
	end
	tokens = token_count(corpus)
	n_documents = Int(corpus_document_count(corpus.pointer))
	n_components = Int(corpus_component_count(corpus.pointer))
	print(io, "Corpus($(tokens) tokens, $(n_documents) documents")
	if n_components > 1
		print(io, ", $(n_components) components")
	end
	print(io, ")")
end

function Base.show(io::IO, component::Component)
	print(io, "Component(\"$(component.name)\", $(component.language), $(component.token_count) tokens)")
end

function Base.show(io::IO, alignment::Alignment)
	print(io, "Alignment(\"$(alignment.name)\", $(alignment.source) → $(alignment.target), $(alignment.edge_count) edges)")
end
