# ---- SoA construction ----

function build_capture_store(pointer::Ptr{Nothing}, n::Int)
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

function materialize_hitlist(pointer::Ptr{Nothing}, corpus::Corpus)
	hitlist_populate_context(pointer, corpus.pointer)
	starts = hitlist_starts(pointer)
	ends = hitlist_ends(pointer)
	document_indices = hitlist_document_indices(pointer)
	sentence_indices = hitlist_sentence_indices(pointer)
	capture_store = build_capture_store(pointer, length(starts))
	HitList(pointer, corpus, starts, ends, document_indices, sentence_indices, capture_store)
end

# ---- query ----

function query(corpus::Corpus, cql::AbstractString; component::Union{AbstractString, Nothing} = nothing)
	pointer = if component === nothing
		query(corpus.pointer, cql)
	else
		query_in_component(corpus.pointer, cql, component)
	end
	materialize_hitlist(pointer, corpus)
end

function Base.count(corpus::Corpus, cql::AbstractString; component::Union{AbstractString, Nothing} = nothing)
	if component === nothing
		Int(query_count(corpus.pointer, cql))
	else
		Int(query_count_in_component(corpus.pointer, cql, component))
	end
end

# ---- token construction ----

function conllu_layers(corpus::Corpus)
	filter(l -> !startswith(l, "feats."), layers(corpus))
end

function fetch_layer(corpus_ptr::Ptr{Nothing}, start::Int, stop::Int, layer::String)
	vals = corpus_token_annotations(corpus_ptr, start, stop, layer)
	isempty(vals) ? nothing : vals
end

function build_nodes(hitlist::HitList, i::Integer)
	corpus = hitlist.corpus
	hit_start = hitlist.starts[i]
	hit_end = hitlist.ends[i]
	n = hit_end - hit_start
	n == 0 && return UD.Node[]

	ptr = corpus.pointer
	available = Set(conllu_layers(corpus))

	words = "word" in available ? fetch_layer(ptr, hit_start, hit_end, "word") : nothing
	lemmas = "lemma" in available ? fetch_layer(ptr, hit_start, hit_end, "lemma") : nothing
	pos_tags = "pos" in available ? fetch_layer(ptr, hit_start, hit_end, "pos") : nothing
	xpos_tags = "xpos" in available ? fetch_layer(ptr, hit_start, hit_end, "xpos") : nothing
	feats_strs = "feats" in available ? fetch_layer(ptr, hit_start, hit_end, "feats") : nothing
	heads = "head" in available ? fetch_layer(ptr, hit_start, hit_end, "head") : nothing
	deprels = "deprel" in available ? fetch_layer(ptr, hit_start, hit_end, "deprel") : nothing

	val(v, j) = v !== nothing && j <= length(v) ? v[j] : "_"

	[
		UD.Node(
			id = j,
			form = val(words, j),
			lemma = val(lemmas, j),
			upos = val(pos_tags, j),
			xpos = val(xpos_tags, j),
			feats = parse(UD.Features, val(feats_strs, j)),
			head = let s = val(heads, j)
				something(tryparse(Int, s), 0)
			end,
			deprel = val(deprels, j),
		)
		for j in 1:n
	]
end

function tokens(hitlist::HitList, i::Integer)
	1 <= i <= length(hitlist) || throw(BoundsError(hitlist, i))
	build_nodes(hitlist, i)
end

function tokens(hitlist::HitList)
	[build_nodes(hitlist, i) for i in 1:length(hitlist)]
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
	materialize_hitlist(raw.pointer, corpus)
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
	layer_str = String(layer)
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
	raw = context_tokens(hitlist.pointer, corpus.pointer, window, String(layer))

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
