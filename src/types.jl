const _exiting = Ref(false)
atexit(() -> _exiting[] = true)

_layer_name(x::Symbol) = String(x)
_layer_name(x::AbstractString) = String(x)

const Layer = Union{Symbol, AbstractString}

mutable struct Corpus
	pointer::Ptr{Nothing}

	function Corpus(pointer::Ptr{Nothing})
		corpus = new(pointer)
		finalizer(corpus) do c
			if !_exiting[] && c.pointer != C_NULL
				corpus_close(c.pointer)
				c.pointer = C_NULL
			end
		end
		return corpus
	end
end

struct Component
	name::String
	language::String
	token_count::Int
end

struct Alignment
	name::String
	source::String
	target::String
	source_layer::String
	target_layer::String
	directed::Bool
	edge_count::Int
end

struct CaptureStore
	names::Vector{String}
	starts::Dict{String, Vector{Int}}
	ends::Dict{String, Vector{Int}}
end

CaptureStore() = CaptureStore(String[], Dict{String, Vector{Int}}(), Dict{String, Vector{Int}}())
Base.isempty(store::CaptureStore) = isempty(store.names)

const _no_captures = Pair{String, UnitRange{Int}}[]

struct Hit
	span::UnitRange{Int}
	document_index::Int
	sentence_index::Int
	captures::Vector{Pair{String, UnitRange{Int}}}
end

Hit(span, document_index, sentence_index) = Hit(span, document_index, sentence_index, _no_captures)

function captures(hit::Hit)
	hit.captures
end

function captures(hit::Hit, name::AbstractString)
	for (n, span) in hit.captures
		n == name && return span
	end
	throw(KeyError(name))
end

Base.haskey(hit::Hit, name::AbstractString) = any(p -> p.first == name, hit.captures)

mutable struct HitList <: AbstractVector{Hit}
	pointer::Ptr{Nothing}
	corpus::Corpus
	starts::Vector{Int}
	ends::Vector{Int}
	document_indices::Vector{Int}
	sentence_indices::Vector{Int}
	capture_store::CaptureStore
	column_cache::Dict{String, Vector{Vector{String}}}

	function HitList(pointer, corpus, starts, ends, document_indices, sentence_indices, capture_store)
		hitlist = new(
			pointer, corpus, starts, ends,
			document_indices, sentence_indices,
			capture_store, Dict{String, Vector{Vector{String}}}(),
		)
		finalizer(hitlist) do h
			if !_exiting[] && h.pointer != C_NULL
				hitlist_free(h.pointer)
				h.pointer = C_NULL
			end
		end
		return hitlist
	end
end

Base.size(hitlist::HitList) = (length(hitlist.starts),)

function Base.getindex(hitlist::HitList, i::Integer)
	@boundscheck checkbounds(hitlist, i)
	store = hitlist.capture_store
	caps = if isempty(store)
		_no_captures
	else
		[name => store.starts[name][i]:store.ends[name][i] - 1 for name in store.names]
	end
	Hit(hitlist.starts[i]:hitlist.ends[i] - 1, hitlist.document_indices[i], hitlist.sentence_indices[i], caps)
end

struct ConcordanceLine
	left::String
	match_text::String
	right::String
	document::String
	position::Int
end

struct Concordance
	lines::Vector{ConcordanceLine}
end

Base.length(c::Concordance) = length(c.lines)
Base.getindex(c::Concordance, i) = c.lines[i]
Base.iterate(c::Concordance, s...) = iterate(c.lines, s...)
Base.firstindex(::Concordance) = 1
Base.lastindex(c::Concordance) = length(c.lines)
Base.eltype(::Type{Concordance}) = ConcordanceLine

struct ProjectionResult
	hits::HitList
	unmapped::Int
	no_alignment::Int
	projected::Int
end

Base.length(pr::ProjectionResult) = length(pr.hits)

struct CQL
	query::String
	CQL(s::AbstractString) = new(replace(s, "'" => "\""))
end

macro cql_str(s)
	:(CQL($s))
end
