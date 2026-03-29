# ---- SoA construction ----

function _build_capture_store(pointer::Ptr{Nothing}, n::Int)
	n == 0 && return CaptureStore()
	n_captures = Int(hit_capture_count(pointer, 0))
	n_captures == 0 && return CaptureStore()

	names = [hit_capture_name(pointer, 0, UInt32(j)) for j in 0:n_captures - 1]
	starts = Dict(name => Vector{Int}(undef, n) for name in names)
	ends = Dict(name => Vector{Int}(undef, n) for name in names)

	for i in 0:n - 1
		for (j, name) in enumerate(names)
			starts[name][i + 1] = Int(hit_capture_start(pointer, i, UInt32(j - 1)))
			ends[name][i + 1] = Int(hit_capture_end(pointer, i, UInt32(j - 1)))
		end
	end

	CaptureStore(names, starts, ends)
end

function _materialize_hitlist(pointer::Ptr{Nothing}, corpus::Corpus; kwargs...)
	hitlist_populate_context(pointer, corpus.pointer)
	starts = hitlist_starts(pointer)
	ends = hitlist_ends(pointer)
	document_indices = hitlist_document_indices(pointer)
	sentence_indices = hitlist_sentence_indices(pointer)
	capture_store = _build_capture_store(pointer, length(starts))
	show_layers = _corpus_conllu_layers(corpus)
	HitList(
		pointer, corpus, starts, ends, document_indices, sentence_indices,
		capture_store, show_layers; kwargs...,
	)
end

# ---- query ----

function query(corpus::Corpus, cql::AbstractString; component::Union{AbstractString, Nothing} = nothing)
	pointer = if component === nothing
		query(corpus.pointer, cql)
	else
		query_in_component(corpus.pointer, cql, component)
	end
	_materialize_hitlist(pointer, corpus)
end

function Base.count(corpus::Corpus, cql::AbstractString; component::Union{AbstractString, Nothing} = nothing)
	if component === nothing
		Int(query_count(corpus.pointer, cql))
	else
		Int(query_count_in_component(corpus.pointer, cql, component))
	end
end

# ---- token construction ----

function _fetch_layer(corpus_ptr::Ptr{Nothing}, start::Int, stop::Int, layer::String)
	vals = corpus_token_annotations(corpus_ptr, start, stop, layer)
	isempty(vals) ? nothing : vals
end

function _build_nodes(hitlist::HitList, i::Integer)
	corpus = hitlist.corpus
	hit_start = hitlist.starts[i]
	hit_end = hitlist.ends[i]
	n = hit_end - hit_start
	n == 0 && return UD.Node[]

	ptr = corpus.pointer
	available = Set(hitlist.show_layers)

	words = "word" in available ? _fetch_layer(ptr, hit_start, hit_end, "word") : nothing
	lemmas = "lemma" in available ? _fetch_layer(ptr, hit_start, hit_end, "lemma") : nothing
	pos_tags = "pos" in available ? _fetch_layer(ptr, hit_start, hit_end, "pos") : nothing
	xpos_tags = "xpos" in available ? _fetch_layer(ptr, hit_start, hit_end, "xpos") : nothing
	feats_strs = "feats" in available ? _fetch_layer(ptr, hit_start, hit_end, "feats") : nothing
	heads = "head" in available ? _fetch_layer(ptr, hit_start, hit_end, "head") : nothing
	deprels = "deprel" in available ? _fetch_layer(ptr, hit_start, hit_end, "deprel") : nothing

	_val(v, j) = v !== nothing && j <= length(v) ? v[j] : "_"

	[
		UD.Node(
			id = j,
			form = _val(words, j),
			lemma = _val(lemmas, j),
			upos = _val(pos_tags, j),
			xpos = _val(xpos_tags, j),
			feats = parse(UD.Features, _val(feats_strs, j)),
			head = let s = _val(heads, j)
				something(tryparse(Int, s), 0)
			end,
			deprel = _val(deprels, j),
		)
		for j in 1:n
	]
end

function tokens(hitlist::HitList, i::Integer)
	1 <= i <= length(hitlist) || throw(BoundsError(hitlist, i))
	_build_nodes(hitlist, i)
end

function tokens(hitlist::HitList)
	[_build_nodes(hitlist, i) for i in 1:length(hitlist)]
end

# ---- captures at hitlist level ----

function captures(hitlist::HitList)
	hitlist.capture_store.names
end

function captures(hitlist::HitList, name::AbstractString)
	store = hitlist.capture_store
	haskey(store.starts, name) || throw(KeyError(name))
	[store.starts[name][i]:store.ends[name][i] - 1 for i in 1:length(hitlist)]
end

# ---- projection ----

function project(corpus::Corpus, hitlist::HitList, alignment::AbstractString)
	raw = project(corpus.pointer, hitlist.pointer, alignment)
	_materialize_hitlist(
		raw.pointer, corpus;
		projected = raw.projected,
		unmapped = raw.unmapped,
		no_alignment = raw.no_alignment,
	)
end

project(hitlist::HitList, alignment::AbstractString) = project(hitlist.corpus, hitlist, alignment)

function project(corpus::Corpus, cql::AbstractString, alignment::AbstractString)
	project(corpus, query(corpus, cql), alignment)
end

# ---- concordance ----

function concordance(
	corpus::Corpus,
	hitlist::HitList;
	context::Integer = 5,
	layer::Layer = :word,
	limit::Integer = 20,
)
	layer_str = _layer_name(layer)
	total = min(length(hitlist), limit)
	total_tokens = token_count(corpus)

	lines = map(1:total) do i
		hit_start = hitlist.starts[i]
		hit_end = hitlist.ends[i]

		left_start = max(hit_start - context, 0)
		right_end = min(hit_end + context, total_tokens)

		left_text = corpus_span_text(corpus.pointer, left_start, hit_start, layer_str)
		match_text = corpus_span_text(corpus.pointer, hit_start, hit_end, layer_str)
		right_text = corpus_span_text(corpus.pointer, hit_end, right_end, layer_str)
		doc_name = corpus_document_name(corpus.pointer, hitlist.document_indices[i])

		ConcordanceLine(
			something(left_text, ""),
			something(match_text, ""),
			something(right_text, ""),
			something(doc_name, "?"),
			hit_start,
		)
	end

	Concordance(lines)
end

function concordance(corpus::Corpus, cql::AbstractString; component::Union{AbstractString, Nothing} = nothing, kwargs...)
	concordance(corpus, query(corpus, cql; component); kwargs...)
end

concordance(hitlist::HitList; kwargs...) = concordance(hitlist.corpus, hitlist; kwargs...)

# ---- collocates ----

function collocates(
	corpus::Corpus,
	hitlist::HitList;
	window::Integer = 5,
	layer::Layer = :lemma,
	positional::Bool = false,
)
	raw = context_tokens(hitlist.pointer, corpus.pointer, window, _layer_name(layer))

	if positional
		counts = Dict{Tuple{String, Int}, Int}()
		for (pos, tok) in zip(raw.positions, raw.tokens)
			key = (tok, Int(pos))
			counts[key] = get(counts, key, 0) + 1
		end
		result = [(; token, position, count) for ((token, position), count) in counts]
		sort!(result; by = x -> -x.count)
	else
		counts = Dict{String, Int}()
		for tok in raw.tokens
			counts[tok] = get(counts, tok, 0) + 1
		end
		result = [(; token, count) for (token, count) in counts]
		sort!(result; by = last, rev = true)
	end
end

function collocates(corpus::Corpus, cql::AbstractString; component::Union{AbstractString, Nothing} = nothing, kwargs...)
	collocates(corpus, query(corpus, cql; component); kwargs...)
end

collocates(hitlist::HitList; kwargs...) = collocates(hitlist.corpus, hitlist; kwargs...)

# ---- CQL dispatch ----

query(corpus::Corpus, cql::CQL; kwargs...) = query(corpus, cql.query; kwargs...)
Base.count(corpus::Corpus, cql::CQL; kwargs...) = count(corpus, cql.query; kwargs...)
concordance(corpus::Corpus, cql::CQL; kwargs...) = concordance(corpus, cql.query; kwargs...)
frequency(corpus::Corpus, cql::CQL; kwargs...) = frequency(query(corpus, cql.query); kwargs...)
collocates(corpus::Corpus, cql::CQL; kwargs...) = collocates(corpus, cql.query; kwargs...)
project(corpus::Corpus, cql::CQL, alignment::AbstractString) = project(corpus, cql.query, alignment)

# ---- display ----

function _capture_margin_labels(hitlist::HitList, i::Integer)
	store = hitlist.capture_store
	isempty(store) && return Dict{Int, String}()
	hit_start = hitlist.starts[i]
	labels = Dict{Int, String}()
	for name in store.names
		cs = store.starts[name][i]
		ce = store.ends[name][i]
		for pos in cs:ce - 1
			local_idx = pos - hit_start + 1
			existing = get(labels, local_idx, "")
			labels[local_idx] = existing == "" ? name : existing * "," * name
		end
	end
	return labels
end

function _capture_highlights(hitlist::HitList, i::Integer)
	store = hitlist.capture_store
	isempty(store) && return UnitRange{Int}[]
	hit_start = hitlist.starts[i]
	[
		let
			local_start = store.starts[name][i] - hit_start + 1
			local_end = store.ends[name][i] - hit_start
			local_start:local_end
		end
		for name in store.names
	]
end

function _render_hit(io::IO, hitlist::HitList, i::Integer)
	hit = hitlist[i]
	printstyled(io, "Hit $i", bold = true)
	printstyled(io, " ($(hit.document))", color = :light_black)
	println(io)

	nodes = _build_nodes(hitlist, i)
	margin_labels = _capture_margin_labels(hitlist, i)
	highlights = _capture_highlights(hitlist, i)

	kw = Dict{Symbol, Any}()
	isempty(margin_labels) || (kw[:margin_labels] = margin_labels)
	isempty(highlights) || (kw[:highlights] = highlights)
	render(TableStyle(), io, nodes; kw...)
end

function Base.show(io::IO, ::MIME"text/plain", hitlist::HitList)
	n = length(hitlist)
	n_docs = length(unique(hitlist.document_indices))
	printstyled(io, "$(n) hits", bold = true)
	print(io, " across $(n_docs) documents")
	if is_projection(hitlist)
		print(io, " ($(hitlist.projected) projected, $(hitlist.unmapped) unmapped, $(hitlist.no_alignment) unaligned)")
	end

	n == 0 && return

	display_count = min(n, 5)
	for i in 1:display_count
		println(io)
		println(io)
		_render_hit(io, hitlist, i)
	end

	if n > display_count
		println(io)
		println(io)
		printstyled(io, "⋮ $(n - display_count) more hits", color = :light_black)
	end
end

function Base.show(io::IO, hitlist::HitList)
	print(io, "HitList($(length(hitlist)) hits)")
end

function Base.show(io::IO, hit::Hit)
	print(io, "Hit($(hit.document)")
	if !isempty(hit.captures)
		for (name, span) in hit.captures
			print(io, ", $name=$(first(span)):$(last(span))")
		end
	else
		print(io, ", $(first(hit.span)):$(last(hit.span))")
	end
	print(io, ")")
end

function Base.show(io::IO, cql::CQL)
	print(io, "cql\"", replace(cql.query, "\"" => "'"), "\"")
end

function Base.show(io::IO, line::ConcordanceLine)
	print(io, lpad(line.left, 30), "  ")
	printstyled(io, line.match_text, bold = true)
	print(io, "  ", line.right)
end

function _truncate(s::AbstractString, width::Int)
	textwidth(s) <= width && return s
	chars = collect(s)
	w = 0
	for (i, c) in enumerate(chars)
		w += textwidth(c)
		if w > width - 1
			return String(chars[1:i - 1]) * "…"
		end
	end
	return s
end

function Base.show(io::IO, ::MIME"text/plain", conc::Concordance)
	n = length(conc)
	n == 0 && (print(io, "Concordance (empty)"); return)

	lines = conc.lines
	term_width = displaysize(io)[2]

	doc_width = min(maximum(textwidth(l.document) for l in lines), 24)
	match_width = min(maximum(textwidth(l.match_text) for l in lines), 30)

	fixed = doc_width + match_width + 6
	remaining = max(term_width - fixed, 20)
	side_width = remaining ÷ 2

	println(io, "Concordance ($(n) lines)")
	for line in lines
		doc = _truncate(line.document, doc_width)
		left = _truncate(line.left, side_width)
		match = _truncate(line.match_text, match_width)
		right = _truncate(line.right, side_width)

		printstyled(io, rpad(doc, doc_width), color = :light_black)
		print(io, " ", lpad(left, side_width), " ")
		printstyled(io, match, bold = true)
		print(io, " ", rpad(right, side_width))
		line !== last(lines) && println(io)
	end
end
