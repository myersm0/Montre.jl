function query(corpus::Corpus, cql::AbstractString; component::Union{AbstractString, Nothing} = nothing)
	pointer = if component === nothing
		query(corpus.pointer, cql)
	else
		query_in_component(corpus.pointer, cql, component)
	end
	hitlist = HitList(pointer, corpus)
	hitlist_populate_context(hitlist.pointer, corpus.pointer)
	return hitlist
end

function Base.count(corpus::Corpus, cql::AbstractString; component::Union{AbstractString, Nothing} = nothing)
	if component === nothing
		Int(query_count(corpus.pointer, cql))
	else
		length(query(corpus, cql; component))
	end
end

# ---- HitList iteration and indexing ----

Base.length(hitlist::HitList) = Int(hitlist_len(hitlist.pointer))
Base.size(hitlist::HitList) = (length(hitlist),)
Base.firstindex(::HitList) = 1
Base.lastindex(hitlist::HitList) = length(hitlist)
Base.eltype(::Type{HitList}) = Hit

function Base.getindex(hitlist::HitList, index::Integer)
	@boundscheck if index < 1 || index > length(hitlist)
		throw(BoundsError(hitlist, index))
	end
	zero_index = UInt64(index - 1)
	start = Int(hit_start(hitlist.pointer, zero_index))
	stop = Int(hit_end(hitlist.pointer, zero_index)) - 1
	document_index = Int(hit_document_index(hitlist.pointer, zero_index))
	sentence_index = Int(hit_sentence_index(hitlist.pointer, zero_index))
	return Hit(start:stop, document_index, sentence_index)
end

function Base.iterate(hitlist::HitList, state = 1)
	state > length(hitlist) && return nothing
	return (hitlist[state], state + 1)
end

# ---- bulk text extraction ----

function texts(hitlist::HitList; layer::AbstractString = "word")
	hitlist_texts(hitlist.pointer, hitlist.corpus.pointer, layer)
end

# ---- projection ----

function project(corpus::Corpus, hitlist::HitList, alignment::AbstractString)
	pointer = project(corpus.pointer, hitlist.pointer, alignment)
	projected = HitList(pointer, corpus)
	hitlist_populate_context(projected.pointer, corpus.pointer)
	return projected
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
	layer::AbstractString = "word",
	limit::Integer = 20,
)
	total = min(length(hitlist), limit)
	token_total = token_count(corpus)

	lines = map(1:total) do i
		hit = hitlist[i]
		left_start = max(first(hit.span) - context, 0)
		right_end = min(last(hit.span) + 1 + context, token_total)

		left_text = span_text(corpus, left_start, first(hit.span); layer = layer)
		match_text = span_text(corpus, hit; layer = layer)
		right_text = span_text(corpus, last(hit.span) + 1, right_end; layer = layer)

		document_name = corpus_document_name(corpus.pointer, hit.document_index)
		if document_name === nothing
			document_name = "?"
		end

		ConcordanceLine(
			something(left_text, ""),
			something(match_text, ""),
			something(right_text, ""),
			document_name,
			first(hit.span),
		)
	end

	Concordance(lines)
end

function concordance(corpus::Corpus, cql::AbstractString; component::Union{AbstractString, Nothing} = nothing, kwargs...)
	concordance(corpus, query(corpus, cql; component); kwargs...)
end

concordance(hitlist::HitList; kwargs...) = concordance(hitlist.corpus, hitlist; kwargs...)

# ---- frequency ----

function frequency(corpus::Corpus, hitlist::HitList; by::AbstractString = "word")
	forms = texts(hitlist; layer = by)
	counts = Dict{String, Int}()
	for form in forms
		counts[form] = get(counts, form, 0) + 1
	end
	sort!([(; value, count) for (value, count) in counts]; by = last, rev = true)
end

function frequency(corpus::Corpus, cql::AbstractString; by::AbstractString = "word", component::Union{AbstractString, Nothing} = nothing)
	frequency(corpus, query(corpus, cql; component); by = by)
end

frequency(hitlist::HitList; kwargs...) = frequency(hitlist.corpus, hitlist; kwargs...)

# ---- collocates ----

function collocates(
	corpus::Corpus,
	hitlist::HitList;
	window::Integer = 5,
	layer::AbstractString = "lemma",
	positional::Bool = false,
)
	raw = context_tokens(hitlist.pointer, corpus.pointer, window, layer)

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

# ---- display ----

function Base.show(io::IO, hitlist::HitList)
	print(io, "HitList($(length(hitlist)) hits)")
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

# ---- CQL dispatch ----

query(corpus::Corpus, cql::CQL; kwargs...) = query(corpus, cql.query; kwargs...)
Base.count(corpus::Corpus, cql::CQL; kwargs...) = count(corpus, cql.query; kwargs...)
concordance(corpus::Corpus, cql::CQL; kwargs...) = concordance(corpus, cql.query; kwargs...)
frequency(corpus::Corpus, cql::CQL; kwargs...) = frequency(corpus, cql.query; kwargs...)
collocates(corpus::Corpus, cql::CQL; kwargs...) = collocates(corpus, cql.query; kwargs...)
project(corpus::Corpus, cql::CQL, alignment::AbstractString) = project(corpus, cql.query, alignment)
