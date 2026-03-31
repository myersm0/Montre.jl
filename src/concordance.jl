
## tokens (UD node construction)

function conllu_layers(corpus::Corpus)
	filter(l -> !startswith(l, "feats."), layers(corpus))
end

function fetch_layer(corpus_ptr::Ptr{Nothing}, start::Int, stop::Int, layer::String)
	vals = corpus_token_annotations(corpus_ptr, start, stop, layer)
	!isempty(vals) || return nothing
	return vals
end

function build_nodes(hitlist::HitList, i::Integer)
	corpus = hitlist.corpus
	hit_start = hitlist.starts[i]
	hit_end = hitlist.ends[i]
	n = hit_end - hit_start
	n == 0 && return UD.Node[]

	ptr = corpus.pointer
	available = Set(conllu_layers(corpus))

	words = fetch_layer(ptr, hit_start, hit_end, "word")
	lemmas = fetch_layer(ptr, hit_start, hit_end, "lemma")
	pos_tags = fetch_layer(ptr, hit_start, hit_end, "pos")
	xpos_tags = fetch_layer(ptr, hit_start, hit_end, "xpos")
	feats_strs = fetch_layer(ptr, hit_start, hit_end, "feats")
	heads = fetch_layer(ptr, hit_start, hit_end, "head")
	deprels = fetch_layer(ptr, hit_start, hit_end, "deprel")

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


function concordance(
		corpus::Corpus, hitlist::HitList;
		context::Integer = 5, layer::Layer = :word, limit::Integer = 20
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
		doc_name = document_name(hitlist, i)

		ConcordanceLine(
			something(left_text, ""),
			something(match_text, ""),
			something(right_text, ""),
			doc_name,
			hit_start,
		)
	end

	Concordance(lines)
end

concordance(corpus::Corpus, cql::AbstractString; component = nothing, kwargs...) =
	concordance(corpus, query(corpus, cql; component); kwargs...)

concordance(hitlist::HitList; kwargs...) = 
	concordance(hitlist.corpus, hitlist; kwargs...)

concordance(corpus::Corpus, cql::CQL; kwargs...) = 
	concordance(corpus, cql.query; kwargs...)


function collocates(corpus::Corpus, hitlist::HitList; window = 5, layer = :lemma)
	raw = context_tokens(hitlist.pointer, corpus.pointer, window, String(layer))
	counts = Dict{Tuple{String, Int}, Int}()
	for (pos, tok) in zip(raw.positions, raw.tokens)
		key = (tok, Int(pos))
		counts[key] = get(counts, key, 0) + 1
	end
	[(; token, position, count) for ((token, position), count) in counts]
end

collocates(corpus::Corpus, cql::AbstractString; component = nothing, kwargs...) =
	collocates(corpus, query(corpus, cql; component); kwargs...)

collocates(hitlist::HitList; kwargs...) = 
	collocates(hitlist.corpus, hitlist; kwargs...)

collocates(corpus::Corpus, cql::CQL; kwargs...) = 
	collocates(corpus, cql.query; kwargs...)


function cooccurrences(corpus::Corpus, hitlist::HitList; window = 5, layer = :lemma)
	raw = context_tokens(hitlist.pointer, corpus.pointer, window, String(layer))
	counts = Dict{String, Int}()
	for tok in raw.tokens
		counts[tok] = get(counts, tok, 0) + 1
	end
	[(; token, count) for (token, count) in counts]
end

cooccurrences(corpus::Corpus, cql::AbstractString; component = nothing, kwargs...) =
	cooccurrences(corpus, query(corpus, cql; component); kwargs...)

cooccurrences(hitlist::HitList; kwargs...) = 
	cooccurrences(hitlist.corpus, hitlist; kwargs...)

cooccurrences(corpus::Corpus, cql::CQL; kwargs...) = 
	cooccurrences(corpus, cql.query; kwargs...)






