function open_corpus(path::AbstractString)
	pointer = corpus_open(path)
	return Corpus(pointer)
end

function open_corpus(f::Function, path::AbstractString)
	corpus = open_corpus(path)
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

function token_count(corpus::Corpus)
	Int(corpus_token_count(corpus.pointer))
end

function layers(corpus::Corpus)
	n = Int(corpus_layer_count(corpus.pointer))
	[corpus_layer_name(corpus.pointer, i) for i in 0:n - 1]
end

function documents(corpus::Corpus)
	n = Int(corpus_document_count(corpus.pointer))
	[corpus_document_name(corpus.pointer, i) for i in 0:n - 1]
end

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

function annotation(corpus::Corpus, position::Integer, layer::AbstractString)
	corpus_token_annotation(corpus.pointer, position, layer)
end

function span_text(corpus::Corpus, start::Integer, stop::Integer; layer::AbstractString = "word")
	corpus_span_text(corpus.pointer, start, stop, layer)
end

function span_text(corpus::Corpus, range::UnitRange; layer::AbstractString = "word")
	# convert inclusive Julia range to half-open Rust interval
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
