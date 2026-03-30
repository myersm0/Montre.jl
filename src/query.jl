
## hitlist materialization

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


## query

function query(corpus::Corpus, cql::AbstractString; component = nothing)
	pointer = if component === nothing
		query(corpus.pointer, cql)
	else
		query_in_component(corpus.pointer, cql, component)
	end
	materialize_hitlist(pointer, corpus)
end

function Base.count(corpus::Corpus, cql::AbstractString; component = nothing)
	if component === nothing
		Int(query_count(corpus.pointer, cql))
	else
		Int(query_count_in_component(corpus.pointer, cql, component))
	end
end


## captures

function captures(hitlist::HitList)
	hitlist.capture_store.names
end

function captures(hitlist::HitList, name::AbstractString)
	store = hitlist.capture_store
	haskey(store.starts, name) || throw(KeyError(name))
	[store.starts[name][i]:store.ends[name][i] - 1 for i in 1:length(hitlist)]
end


## projection

function project(corpus::Corpus, hitlist::HitList, alignment::AbstractString)
	raw = project(corpus.pointer, hitlist.pointer, alignment)
	materialize_hitlist(raw.pointer, corpus)
end

project(hitlist::HitList, alignment::AbstractString) = project(hitlist.corpus, hitlist, alignment)

function project(corpus::Corpus, cql::AbstractString, alignment::AbstractString)
	project(corpus, query(corpus, cql), alignment)
end


## CQL dispatch

query(corpus::Corpus, cql::CQL; kwargs...) = query(corpus, cql.query; kwargs...)
Base.count(corpus::Corpus, cql::CQL; kwargs...) = count(corpus, cql.query; kwargs...)
project(corpus::Corpus, cql::CQL, alignment::AbstractString) = project(corpus, cql.query, alignment)
