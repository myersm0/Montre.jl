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

function component_index(corpus::Corpus, name::AbstractString)
	idx = corpuscomponent_index_by_name(corpus.pointer, name)
	idx === nothing && error("Montre: component not found: $name")
	return idx
end

function resolve_document(
		corpus::Corpus, document::AbstractString; 
		component::Union{AbstractString, Nothing} = nothing
	)
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

function token_count(corpus::Corpus; component = nothing, document = nothing)
	if document !== nothing
		doc_idx = resolve_document(corpus, document; component)
		return length(span_at(corpus, "document", doc_idx))
	end
	if component !== nothing
		idx = component_index(corpus, component)
		return something(corpus_component_token_count(corpus.pointer, idx), 0)
	end
	Int(corpus_token_count(corpus.pointer))
end

function component_token_range(corpus::Corpus, component::AbstractString)
	idx = component_index(corpus, component)
	r = corpus_component_document_range(corpus.pointer, idx)
	first_doc = span_at(corpus, "document", first(r))
	last_doc = span_at(corpus, "document", last(r))
	return first(first_doc):last(last_doc)
end

function document_count(corpus::Corpus; component = nothing)
	if component !== nothing
		return length(document_range(corpus, component))
	end
	Int(corpus_document_count(corpus.pointer))
end

function sentence_count(corpus::Corpus; component = nothing, document = nothing)
	if document !== nothing
		doc_idx = resolve_document(corpus, document; component)
		doc_span = span_at(corpus, "document", doc_idx)
		return something(corpus_span_count_in_range(corpus.pointer, "sentence", first(doc_span), last(doc_span) + 1), 0)
	end
	if component !== nothing
		r = component_token_range(corpus, component)
		return something(corpus_span_count_in_range(corpus.pointer, "sentence", first(r), last(r) + 1), 0)
	end
	something(corpus_span_count(corpus.pointer, "sentence"), 0)
end

function component_count(corpus::Corpus)
	Int(corpus_component_count(corpus.pointer))
end

function layers(corpus::Corpus)
	n = Int(corpus_layer_count(corpus.pointer))
	[corpus_layer_name(corpus.pointer, i) for i in 0:n - 1]
end

function features(corpus::Corpus)
	filter(l -> startswith(l, "feats."), layers(corpus))
end

function documents(corpus::Corpus; component = nothing)
	if component === nothing
		n = Int(corpus_document_count(corpus.pointer))
		return [corpus_document_name(corpus.pointer, i) for i in 0:n - 1]
	end
	r = document_range(corpus, component)
	[corpus_document_name(corpus.pointer, i) for i in r]
end

function document_name(corpus::Corpus, index::Integer)
	corpus_document_name(corpus.pointer, index)
end

function document_name(corpus::Corpus, hit::Hit)
	something(corpus_document_name(corpus.pointer, hit.document_index), "?")
end

function document_name(hitlist::HitList, i::Integer)
	something(corpus_document_name(hitlist.corpus.pointer, hitlist.document_indices[i]), "?")
end

function document_range(corpus::Corpus, component::AbstractString)
	idx = component_index(corpus, component)
	corpus_component_document_range(corpus.pointer, idx)
end

function span_at(corpus::Corpus, layer::Layer, index::Integer)
	result = corpus_span_at(corpus.pointer, String(layer), index)
	result === nothing && error("Montre: invalid span layer or index")
	return result
end

function span_containing(corpus::Corpus, layer::Layer, position::Integer)
	corpus_span_containing(corpus.pointer, String(layer), position)
end

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

function span_layers(corpus::Corpus)
	n = Int(corpus_span_layer_count(corpus.pointer))
	[corpus_span_layer_name(corpus.pointer, i) for i in 0:n - 1]
end

function vocabulary(corpus::Corpus, layer::Layer; top::Union{Integer, Nothing} = nothing)
	values, counts = corpus_inverted_counts(corpus.pointer, String(layer))
	entries = [(; value = v, count = c) for (v, c) in zip(values, counts)]
	sort!(entries; by = e -> e.count, rev = true)
	top === nothing ? entries : first(entries, min(top, length(entries)))
end

function annotation(corpus::Corpus, position::Integer, layer::Layer)
	corpus_token_annotation(corpus.pointer, position, String(layer))
end

function annotations(corpus::Corpus, range::UnitRange, layer::Layer)
	corpus_token_annotations(corpus.pointer, first(range), last(range) + 1, String(layer))
end

function span_text(corpus::Corpus, start::Integer, stop::Integer; layer::Layer = :word)
	corpus_span_text(corpus.pointer, start, stop, String(layer))
end

function span_text(corpus::Corpus, range::UnitRange; layer::Layer = :word)
	span_text(corpus, first(range), last(range) + 1; layer = layer)
end

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

function build(
		input::AbstractString, output::AbstractString;
		name = "corpus", decompose_feats = false, strict = false,
	)
	if endswith(input, ".toml")
		build_manifest(input, output; decompose_feats, strict)
	else
		build_directory(name, input, output; decompose_feats, strict)
	end
end

