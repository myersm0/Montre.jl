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

function _resolve_document(corpus::Corpus, document::AbstractString; component::Union{AbstractString, Nothing} = nothing)
	if component !== nothing
		r = document_range(corpus, component)
		for i in r
			if corpus_document_name(corpus.pointer, i) == document
				return i
			end
		end
		error("Montre: document '$document' not found in component '$component'")
	end
	doc_idx = corpus_document_index_by_name(corpus.pointer, document)
	doc_idx === nothing && error("Montre: document not found: $document")
	return doc_idx
end

"""
	token_count(corpus; component=nothing, document=nothing) -> Int

Token count for the corpus, a component, or a single document.
When both `component` and `document` are given, resolves the document within the component.

```julia
token_count(corpus)
token_count(corpus; component="maupassant-fr")
token_count(corpus; document="allouma.conllu")
token_count(corpus; component="maupassant-fr", document="allouma.conllu")
```
"""
function token_count(corpus::Corpus; component::Union{AbstractString, Nothing} = nothing, document::Union{AbstractString, Nothing} = nothing)
	if document !== nothing
		doc_idx = _resolve_document(corpus, document; component)
		return length(span_at(corpus, "document", doc_idx))
	end
	if component !== nothing
		comps = components(corpus)
		idx = findfirst(c -> c.name == component, comps)
		idx === nothing && error("Montre: component not found: $component")
		return comps[idx].token_count
	end
	Int(corpus_token_count(corpus.pointer))
end

function _component_token_range(corpus::Corpus, component_name::AbstractString)
	r = document_range(corpus, component_name)
	first_doc = span_at(corpus, "document", first(r))
	last_doc = span_at(corpus, "document", last(r))
	return first(first_doc):last(last_doc)
end

"""
	document_count(corpus; component=nothing) -> Int

Number of documents in the corpus or in a named component.
"""
function document_count(corpus::Corpus; component::Union{AbstractString, Nothing} = nothing)
	if component !== nothing
		return length(document_range(corpus, component))
	end
	Int(corpus_document_count(corpus.pointer))
end

"""
	sentence_count(corpus; component=nothing, document=nothing) -> Int

Sentence count for the corpus, a component, or a single document.
When both `component` and `document` are given, resolves the document within the component.
"""
function sentence_count(corpus::Corpus; component::Union{AbstractString, Nothing} = nothing, document::Union{AbstractString, Nothing} = nothing)
	if document !== nothing
		doc_idx = _resolve_document(corpus, document; component)
		doc_span = span_at(corpus, "document", doc_idx)
		return something(corpus_span_count_in_range(corpus.pointer, "sentence", first(doc_span), last(doc_span) + 1), 0)
	end
	if component !== nothing
		r = _component_token_range(corpus, component)
		return something(corpus_span_count_in_range(corpus.pointer, "sentence", first(r), last(r) + 1), 0)
	end
	something(corpus_span_count(corpus.pointer, "sentence"), 0)
end

"""
	component_count(corpus::Corpus) -> Int

Number of components. Returns 0 for single-component corpora.
"""
function component_count(corpus::Corpus)
	Int(corpus_component_count(corpus.pointer))
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
	vocabulary(corpus::Corpus, layer::AbstractString; top=nothing) -> Vector{NamedTuple}

Frequency-sorted vocabulary for a layer from the inverted index.
Returns `(; value, count)` named tuples, descending by count.
Use `top=N` to limit to the N most frequent entries.

```julia
vocabulary(corpus, "pos")           # all POS tags with frequencies
vocabulary(corpus, "lemma"; top=50) # top 50 lemmas
```
"""
function vocabulary(corpus::Corpus, layer::AbstractString; top::Union{Integer, Nothing} = nothing)
	values = corpus_inverted_values(corpus.pointer, layer)
	entries = [(; value, count = something(corpus_inverted_count(corpus.pointer, layer, value), 0)) for value in values]
	sort!(entries; by = e -> e.count, rev = true)
	top === nothing ? entries : first(entries, min(top, length(entries)))
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
	edges(corpus::Corpus, alignment::AbstractString) -> Vector{NamedTuple}

Raw alignment edges as `(; source_document, source_sentence, target_document, target_sentence)`
named tuples. Document and sentence indices are 0-based within their respective components.

```julia
for e in edges(corpus, "labse")
    println(e.source_document, ":", e.source_sentence, " → ", e.target_document, ":", e.target_sentence)
end
```
"""
function edges(corpus::Corpus, alignment::AbstractString)
	flat, n = corpus_alignment_edges(corpus.pointer, alignment)
	[
		(;
			source_document = flat[4i - 3],
			source_sentence = flat[4i - 2],
			target_document = flat[4i - 1],
			target_sentence = flat[4i],
		)
		for i in 1:n
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
