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
	token_count(corpus::Corpus) -> Int

Total number of tokens in the corpus (across all components).
"""
function token_count(corpus::Corpus)
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
	documents(corpus::Corpus) -> Vector{String}

Document names in the corpus (typically source filenames).
"""
function documents(corpus::Corpus)
	n = Int(corpus_document_count(corpus.pointer))
	[corpus_document_name(corpus.pointer, i) for i in 0:n - 1]
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
		)
		for i in 0:n - 1
	]
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
	print(io, "Component(\"$(component.name)\", $(component.language))")
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
		)
		for i in 0:n - 1
	]
end

function Base.show(io::IO, alignment::Alignment)
	print(io, "Alignment(\"$(alignment.name)\", $(alignment.source) → $(alignment.target))")
end
