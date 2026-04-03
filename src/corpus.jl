
## lifecycle

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


## component and document resolution

function component_index(corpus::Corpus, name::AbstractString)
	idx = corpus_component_index_by_name(corpus.pointer, name)
	idx === nothing && error("Montre: component not found: $name")
	return idx
end

function resolve_document(corpus::Corpus, document::AbstractString; component = nothing)
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

function component_token_range(corpus::Corpus, component::AbstractString)
	idx = component_index(corpus, component)
	r = corpus_component_document_range(corpus.pointer, idx)
	first_doc = span_at(corpus, "document", first(r))
	last_doc = span_at(corpus, "document", last(r))
	return first(first_doc):last(last_doc)
end


## counting

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


## layers

function layers(corpus::Corpus)
	n = Int(corpus_layer_count(corpus.pointer))
	[corpus_layer_name(corpus.pointer, i) for i in 0:n - 1]
end

function features(corpus::Corpus)
	filter(l -> startswith(l, "feats."), layers(corpus))
end


## documents

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

function document_name(hitlist::HitList, i::Integer)
	something(corpus_document_name(hitlist.corpus.pointer, hitlist.document_indices[i]), "?")
end

function document_range(corpus::Corpus, component::AbstractString)
	idx = component_index(corpus, component)
	corpus_component_document_range(corpus.pointer, idx)
end


## components and alignments

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


## alignment analysis

function alignment_coverage(corpus::Corpus, alignment_name::AbstractString)
	raw = corpus_alignment_coverage(corpus.pointer, alignment_name)
	map(1:length(raw.doc_indices)) do i
		doc_idx = raw.doc_indices[i]
		name = something(document_name(corpus, doc_idx), "?")
		aligned = raw.aligned[i]
		total = raw.total[i]
		coverage = total > 0 ? aligned / total : 0.0
		(; document = name, aligned_sentences = aligned, total_sentences = total, coverage)
	end
end

function paired_documents(corpus::Corpus, alignment_name::AbstractString)
	aligns = alignments(corpus)
	al_idx = findfirst(a -> a.name == alignment_name, aligns)
	al_idx === nothing && error("Montre: alignment not found: $alignment_name")
	meta = aligns[al_idx]

	source_range = document_range(corpus, meta.source)
	target_range = document_range(corpus, meta.target)

	edge_data = edges(corpus, alignment_name)
	pairings = Dict{Int, Set{Int}}()
	for e in edge_data
		if !haskey(pairings, e.source_document)
			pairings[e.source_document] = Set{Int}()
		end
		push!(pairings[e.source_document], e.target_document)
	end

	map(sort(collect(keys(pairings)))) do src_doc
		tgt_doc = first(pairings[src_doc])
		src_global = first(source_range) + src_doc
		tgt_global = first(target_range) + tgt_doc

		src_name = something(document_name(corpus, src_global), "?")
		tgt_name = something(document_name(corpus, tgt_global), "?")
		src_tokens = length(span_at(corpus, "document", src_global))
		tgt_tokens = length(span_at(corpus, "document", tgt_global))

		(; source = src_name, target = tgt_name,
			source_tokens = src_tokens, target_tokens = tgt_tokens,
			ratio = tgt_tokens / src_tokens)
	end
end

function unaligned_sentences(corpus::Corpus, alignment_name::AbstractString, document::AbstractString;
		component = nothing,
	)
	aligns = alignments(corpus)
	al_idx = findfirst(a -> a.name == alignment_name, aligns)
	al_idx === nothing && error("Montre: alignment not found: $alignment_name")
	meta = aligns[al_idx]

	source_comp = component !== nothing ? component : meta.source
	comp_idx = component_index(corpus, source_comp)
	source_range = document_range(corpus, source_comp)
	doc_global = resolve_document(corpus, document; component = source_comp)
	doc_within = doc_global - first(source_range)

	total = sentence_count(corpus; component = source_comp, document = document)

	edge_data = edges(corpus, alignment_name)
	aligned = Set{Int}()
	for e in edge_data
		if e.source_document == doc_within
			push!(aligned, e.source_sentence)
		end
	end

	map(filter(i -> i ∉ aligned, 0:total - 1)) do sent_idx
		result = corpus_sentence_span(corpus.pointer, comp_idx, doc_within, sent_idx)
		if result !== nothing
			text = something(span_text(corpus, result.span), "")
			(; sentence_index = sent_idx, span = result.span, text)
		else
			(; sentence_index = sent_idx, span = 0:-1, text = "")
		end
	end
end


## spans

function span_layers(corpus::Corpus)
	n = Int(corpus_span_layer_count(corpus.pointer))
	[corpus_span_layer_name(corpus.pointer, i) for i in 0:n - 1]
end

function span_at(corpus::Corpus, layer::Layer, index::Integer)
	result = corpus_span_at(corpus.pointer, String(layer), index)
	result === nothing && error("Montre: invalid span layer or index")
	return result
end

function span_containing(corpus::Corpus, layer::Layer, position::Integer)
	corpus_span_containing(corpus.pointer, String(layer), position)
end

function sentence_span(corpus::Corpus, component::AbstractString, document::AbstractString, sentence_within_doc::Integer)
	comp_idx = component_index(corpus, component)
	source_range = document_range(corpus, component)
	doc_global = resolve_document(corpus, document; component)
	doc_within = doc_global - first(source_range)
	result = corpus_sentence_span(corpus.pointer, comp_idx, doc_within, sentence_within_doc)
	result === nothing && error("Montre: sentence not found (doc=$document, sent=$sentence_within_doc)")
	return result.span
end


## token access

function vocabulary(corpus::Corpus, layer::Layer)
	vals = corpus_inverted_values(corpus.pointer, String(layer))
	sort(vals)
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


## build

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
