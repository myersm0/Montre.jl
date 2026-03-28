# ---- reducer application ----

function _apply_reducer(r::Join, corpus::Corpus, start::Int, stop::Int)
	text = corpus_span_text(corpus.pointer, start, stop, r.layer)
	something(text, "")
end

function _apply_reducer(r::First, corpus::Corpus, start::Int, stop::Int)
	start >= stop && return ""
	something(corpus_token_annotation(corpus.pointer, start, r.layer), "")
end

function _apply_reducer(r::Last, corpus::Corpus, start::Int, stop::Int)
	start >= stop && return ""
	something(corpus_token_annotation(corpus.pointer, stop - 1, r.layer), "")
end

function _apply_reducer(r::Only, corpus::Corpus, start::Int, stop::Int)
	stop - start != 1 && error("Only: span has $(stop - start) tokens, expected 1")
	something(corpus_token_annotation(corpus.pointer, start, r.layer), "")
end

function _apply_reducer(r::Collect, corpus::Corpus, start::Int, stop::Int)
	corpus_token_annotations(corpus.pointer, start, stop, r.layer)
end

function _apply_reducer(::Width, ::Corpus, start::Int, stop::Int)
	stop - start
end

function _apply_reducer(::Document, corpus::Corpus, hitlist::HitList, i::Int)
	_document_name_cached(hitlist, i)
end

function _apply_reducer(::Sentence, ::Corpus, hitlist::HitList, i::Int)
	hitlist.sentence_indices[i]
end

function _resolve_reducer(r::Reducer, corpus::Corpus, hitlist::HitList, i::Int)
	_apply_reducer(r, corpus, hitlist.starts[i], hitlist.ends[i])
end

function _resolve_reducer(r::Document, corpus::Corpus, hitlist::HitList, i::Int)
	_apply_reducer(r, corpus, hitlist, i)
end

function _resolve_reducer(r::Sentence, corpus::Corpus, hitlist::HitList, i::Int)
	_apply_reducer(r, corpus, hitlist, i)
end

function _resolve_reducer(r::Capture, corpus::Corpus, hitlist::HitList, i::Int)
	store = hitlist.capture_store
	haskey(store.starts, r.name) || throw(KeyError(r.name))
	cap_start = store.starts[r.name][i]
	cap_end = store.ends[r.name][i]
	_apply_reducer(r.inner, corpus, cap_start, cap_end)
end

# ---- column name derivation ----

_reducer_name(r::Join) = r.layer
_reducer_name(r::First) = r.layer
_reducer_name(r::Last) = r.layer * "_last"
_reducer_name(r::Only) = r.layer
_reducer_name(r::Collect) = r.layer
_reducer_name(r::Width) = "width"
_reducer_name(r::Document) = "document"
_reducer_name(r::Sentence) = "sentence"
_reducer_name(r::Capture) = r.name * "_" * _reducer_name(r.inner)

# ---- select ----

struct Selected{T <: NamedTuple}
	rows::Vector{T}
end

Base.length(s::Selected) = length(s.rows)
Base.getindex(s::Selected, i) = s.rows[i]
Base.iterate(s::Selected, st...) = iterate(s.rows, st...)
Base.firstindex(::Selected) = 1
Base.lastindex(s::Selected) = length(s.rows)
Base.eltype(::Type{Selected{T}}) where {T} = T

function select(hitlist::HitList, reducers::Reducer...)
	isempty(reducers) && error("select requires at least one reducer")
	corpus = hitlist.corpus
	n = length(hitlist)

	names = Tuple(Symbol(_reducer_name(r)) for r in reducers)
	columns = Tuple(Vector{Any}(undef, n) for _ in reducers)

	for i in 1:n
		for (j, r) in enumerate(reducers)
			columns[j][i] = _resolve_reducer(r, corpus, hitlist, i)
		end
	end

	typed_columns = Tuple(
		_typed_vector(col) for col in columns
	)
	T = NamedTuple{names, Tuple{eltype.(typed_columns)...}}
	rows = [T(Tuple(col[i] for col in typed_columns)) for i in 1:n]
	Selected{T}(rows)
end

function _typed_vector(col::Vector{Any})
	isempty(col) && return col
	t = typeof(col[1])
	if all(x -> typeof(x) === t, col)
		convert(Vector{t}, col)
	else
		col
	end
end

# ---- frequency built on select ----

function frequency(hitlist::HitList, reducers::Reducer...; by::Union{Reducer, Nothing} = nothing)
	if by !== nothing
		reducers = (by,)
	end
	isempty(reducers) && (reducers = (Join(:word),))

	sel = select(hitlist, reducers...)
	counts = Dict{Any, Int}()
	for row in sel
		key = length(row) == 1 ? first(row) : row
		counts[key] = get(counts, key, 0) + 1
	end
	result = [(; value = k, count = v) for (k, v) in counts]
	sort!(result; by = last, rev = true)
end
