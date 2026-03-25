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

function _materialize_hitlist(pointer::Ptr{Nothing}, corpus::Corpus)
	hitlist_populate_context(pointer, corpus.pointer)
	starts = hitlist_starts(pointer)
	ends = hitlist_ends(pointer)
	document_indices = hitlist_document_indices(pointer)
	sentence_indices = hitlist_sentence_indices(pointer)
	capture_store = _build_capture_store(pointer, length(starts))
	HitList(pointer, corpus, starts, ends, document_indices, sentence_indices, capture_store)
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

# ---- column extraction ----

function column(hitlist::HitList, layer::Layer)
	layer_str = _layer_name(layer)
	cached = get(hitlist.column_cache, layer_str, nothing)
	cached !== nothing && return cached

	n = length(hitlist)
	result = Vector{Vector{String}}(undef, n)
	for i in 1:n
		result[i] = corpus_token_annotations(hitlist.corpus.pointer, hitlist.starts[i], hitlist.ends[i], layer_str)
	end
	hitlist.column_cache[layer_str] = result
	return result
end

function column(hitlist::HitList, capture_name::AbstractString, layer::Layer)
	store = hitlist.capture_store
	haskey(store.starts, capture_name) || throw(KeyError(capture_name))

	layer_str = _layer_name(layer)
	cap_starts = store.starts[capture_name]
	cap_ends = store.ends[capture_name]

	n = length(hitlist)
	result = Vector{Vector{String}}(undef, n)
	for i in 1:n
		result[i] = corpus_token_annotations(hitlist.corpus.pointer, cap_starts[i], cap_ends[i], layer_str)
	end
	return result
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
	projected = _materialize_hitlist(raw.pointer, corpus)
	ProjectionResult(projected, raw.unmapped, raw.no_alignment, raw.projected)
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

# ---- frequency ----

function frequency(corpus::Corpus, hitlist::HitList; by::Layer = :word)
	layer_data = column(hitlist, by)
	counts = Dict{String, Int}()
	for tokens in layer_data
		key = join(tokens, " ")
		counts[key] = get(counts, key, 0) + 1
	end
	sort!([(; value, count) for (value, count) in counts]; by = last, rev = true)
end

function frequency(corpus::Corpus, cql::AbstractString; by::Layer = :word, component::Union{AbstractString, Nothing} = nothing)
	frequency(corpus, query(corpus, cql; component); by = by)
end

frequency(hitlist::HitList; kwargs...) = frequency(hitlist.corpus, hitlist; kwargs...)

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
frequency(corpus::Corpus, cql::CQL; kwargs...) = frequency(corpus, cql.query; kwargs...)
collocates(corpus::Corpus, cql::CQL; kwargs...) = collocates(corpus, cql.query; kwargs...)
project(corpus::Corpus, cql::CQL, alignment::AbstractString) = project(corpus, cql.query, alignment)

# ---- ProjectionResult forwarding ----

column(pr::ProjectionResult, args...) = column(pr.hits, args...)
captures(pr::ProjectionResult, args...) = captures(pr.hits, args...)
concordance(pr::ProjectionResult; kwargs...) = concordance(pr.hits; kwargs...)
frequency(pr::ProjectionResult; kwargs...) = frequency(pr.hits; kwargs...)
collocates(pr::ProjectionResult; kwargs...) = collocates(pr.hits; kwargs...)

# ---- display helpers ----

const _conllu_layers = ["word", "lemma", "pos", "xpos", "feats", "head", "deprel"]

function _corpus_conllu_layers(corpus::Corpus)
	available = Set(layers(corpus))
	filter(l -> l in available, _conllu_layers)
end

function _show_hit(io::IO, corpus::Corpus, hit_index::Int, hit_start::Int, hit_end::Int, doc_idx::Int, capture_store::CaptureStore; show_layers::Vector{String})
	doc_name = something(corpus_document_name(corpus.pointer, doc_idx), "?")
	sent = corpus_span_containing(corpus.pointer, "sentence", hit_start)

	print(io, "\e[1;34mHit $(hit_index)\e[0m")
	if sent !== nothing
		sent_span = sent.span
		sent_start = first(sent_span)
		sent_end = last(sent_span) + 1

		# sent_id = document-sentence_index_within_doc
		doc_span_result = corpus_span_containing(corpus.pointer, "document", hit_start)
		if doc_span_result !== nothing
			doc_start = first(doc_span_result.span)
			local_sent = corpus_span_containing(corpus.pointer, "sentence", hit_start)
			if local_sent !== nothing
				first_sent = corpus_span_containing(corpus.pointer, "sentence", doc_start)
				sent_within_doc = if first_sent !== nothing
					local_sent.index - first_sent.index + 1
				else
					local_sent.index + 1
				end
				println(io)
				print(io, "\e[2m# sent_id = $(doc_name)-$(sent_within_doc)\e[0m")
			end
		end

		# text line with match bolded
		pre = corpus_span_text(corpus.pointer, sent_start, hit_start, "word")
		matched = corpus_span_text(corpus.pointer, hit_start, hit_end, "word")
		post = corpus_span_text(corpus.pointer, hit_end, sent_end, "word")

		println(io)
		print(io, "\e[2m# text = \e[0m")
		pre !== nothing && length(pre) > 0 && print(io, "\e[2m", pre, " \e[0m")
		print(io, "\e[1m", something(matched, ""), "\e[0m")
		post !== nothing && length(post) > 0 && print(io, "\e[2m ", post, "\e[0m")
	else
		print(io, " \e[2m($(doc_name))\e[0m")
	end

	# token rows for matched span
	n_tokens = hit_end - hit_start
	n_tokens == 0 && return

	# figure out which capture labels apply to which positions
	capture_labels = Dict{Int, Vector{String}}()
	if !isempty(capture_store)
		for name in capture_store.names
			cap_start = capture_store.starts[name][hit_index]
			cap_end = capture_store.ends[name][hit_index]
			for pos in cap_start:cap_end - 1
				labels = get!(capture_labels, pos, String[])
				push!(labels, name)
			end
		end
	end

	# get sentence start for computing local token IDs
	local_id_offset = if sent !== nothing
		first(sent.span)
	else
		hit_start
	end

	# collect column data
	col_values = Dict{String, Vector{String}}()
	for layer in show_layers
		vals = corpus_token_annotations(corpus.pointer, hit_start, hit_end, layer)
		col_values[layer] = isempty(vals) ? fill("_", n_tokens) : vals
	end

	# compute column widths
	id_strings = [string(hit_start - local_id_offset + i) for i in 1:n_tokens]
	id_width = maximum(length, id_strings)
	col_widths = Dict(layer => max(length(layer), maximum(length, get(col_values, layer, ["_"]))) for layer in show_layers)

	println(io)
	for j in 1:n_tokens
		global_pos = hit_start + j - 1

		# capture label annotation in margin
		if haskey(capture_labels, global_pos)
			label_str = join(capture_labels[global_pos], ",")
			print(io, "\e[33m", lpad(label_str, 3), "\e[0m ")
		else
			print(io, "    ")
		end

		print(io, lpad(id_strings[j], id_width), "\t")
		for (k, layer) in enumerate(show_layers)
			val = col_values[layer][j]
			print(io, val)
			k < length(show_layers) && print(io, "\t")
		end
		j < n_tokens && println(io)
	end
end

function Base.show(io::IO, ::MIME"text/plain", hitlist::HitList)
	n = length(hitlist)
	n_docs = length(unique(hitlist.document_indices))
	print(io, "\e[1m$(n) hits\e[0m across $(n_docs) documents")

	n == 0 && return

	show_layers = _corpus_conllu_layers(hitlist.corpus)
	display_count = min(n, 5)

	for i in 1:display_count
		println(io)
		println(io)
		_show_hit(
			io, hitlist.corpus, i,
			hitlist.starts[i], hitlist.ends[i], hitlist.document_indices[i],
			hitlist.capture_store;
			show_layers = show_layers,
		)
	end

	if n > display_count
		println(io)
		print(io, "\n\e[2m… $(n - display_count) more hits\e[0m")
	end
end

function Base.show(io::IO, hitlist::HitList)
	print(io, "HitList($(length(hitlist)) hits)")
end

function Base.show(io::IO, ::MIME"text/plain", hit::Hit)
	print(io, "Hit($(first(hit.span)):$(last(hit.span))")
	if !isempty(hit.captures)
		print(io, ", ")
		join(io, ("$(p.first)=$(first(p.second)):$(last(p.second))" for p in hit.captures), ", ")
	end
	print(io, ")")
end

function Base.show(io::IO, hit::Hit)
	print(io, "Hit($(first(hit.span)):$(last(hit.span)))")
end

function Base.show(io::IO, cql::CQL)
	print(io, "cql\"", replace(cql.query, "\"" => "'"), "\"")
end

function Base.show(io::IO, line::ConcordanceLine)
	print(io, lpad(line.left, 30), "  ", "\e[1m", line.match_text, "\e[0m", "  ", line.right)
end

function _truncate(s::AbstractString, width::Int)
	textwidth(s) <= width && return s
	chars = collect(s)
	w = 0
	for (i, c) in enumerate(chars)
		w += textwidth(c)
		if w > width - 1
			return String(chars[1:i-1]) * "…"
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

		print(io, "\e[3m", rpad(doc, doc_width), "\e[0m")
		print(io, " ", lpad(left, side_width))
		print(io, " \e[1m", match, "\e[0m ")
		print(io, rpad(right, side_width))
		line !== last(lines) && println(io)
	end
end

function Base.show(io::IO, pr::ProjectionResult)
	print(io, "ProjectionResult($(pr.projected) projected, $(pr.unmapped) unmapped, $(pr.no_alignment) unaligned)")
end
