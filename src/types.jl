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

# ---- Hit ----

struct Hit
	span::UnitRange{Int}
	document::String
	document_index::Int
	sentence_index::Int
	captures::Vector{Pair{String, UnitRange{Int}}}
end

function Hit(span::UnitRange{Int}, document::String, document_index::Int, sentence_index::Int)
	Hit(span, document, document_index, sentence_index, Pair{String, UnitRange{Int}}[])
end

Base.haskey(hit::Hit, name::AbstractString) = any(p -> p.first == name, hit.captures)

function Base.getindex(hit::Hit, name::AbstractString)
	for p in hit.captures
		p.first == name && return p.second
	end
	throw(KeyError(name))
end

Base.keys(hit::Hit) = [p.first for p in hit.captures]

# ---- CaptureStore (internal SoA) ----

struct CaptureStore
	names::Vector{String}
	starts::Dict{String, Vector{Int}}
	ends::Dict{String, Vector{Int}}
end

CaptureStore() = CaptureStore(String[], Dict{String, Vector{Int}}(), Dict{String, Vector{Int}}())
Base.isempty(store::CaptureStore) = isempty(store.names)

# ---- HitList ----

const _conllu_layers = ["word", "lemma", "pos", "xpos", "feats", "deprel"]

function _corpus_conllu_layers(corpus::Corpus)
	available = Set(layers(corpus))
	filter(l -> l in available, _conllu_layers)
end

mutable struct HitList <: AbstractVector{Hit}
	pointer::Ptr{Nothing}
	corpus::Corpus
	starts::Vector{Int}
	ends::Vector{Int}
	document_indices::Vector{Int}
	sentence_indices::Vector{Int}
	capture_store::CaptureStore
	show_layers::Vector{String}
	column_cache::Dict{String, Vector{Vector{String}}}
	projected::Union{Int, Nothing}
	unmapped::Union{Int, Nothing}
	no_alignment::Union{Int, Nothing}

	function HitList(
		pointer, corpus, starts, ends, document_indices, sentence_indices,
		capture_store, show_layers;
		projected = nothing, unmapped = nothing, no_alignment = nothing,
	)
		hitlist = new(
			pointer, corpus, starts, ends,
			document_indices, sentence_indices,
			capture_store, show_layers,
			Dict{String, Vector{Vector{String}}}(),
			projected, unmapped, no_alignment,
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

function _document_name_cached(hitlist::HitList, i::Int)
	something(corpus_document_name(hitlist.corpus.pointer, hitlist.document_indices[i]), "?")
end

function Base.getindex(hitlist::HitList, i::Int)
	@boundscheck checkbounds(hitlist, i)
	store = hitlist.capture_store
	caps = if isempty(store)
		Pair{String, UnitRange{Int}}[]
	else
		[name => store.starts[name][i]:store.ends[name][i] - 1 for name in store.names]
	end
	Hit(
		hitlist.starts[i]:hitlist.ends[i] - 1,
		_document_name_cached(hitlist, i),
		hitlist.document_indices[i],
		hitlist.sentence_indices[i],
		caps,
	)
end

is_projection(hitlist::HitList) = hitlist.projected !== nothing

# ---- Concordance ----

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

# ---- CQL ----

struct CQL
	query::String
	CQL(s::AbstractString) = new(replace(s, "'" => "\""))
end

macro cql_str(s)
	:(CQL($s))
end

# ---- Reducers ----

abstract type Reducer end

struct Join <: Reducer
	layer::String
	sep::String
end
Join(layer::Layer; sep::String = " ") = Join(_layer_name(layer), sep)

struct First <: Reducer
	layer::String
end
First(layer::Layer) = First(_layer_name(layer))

struct Last <: Reducer
	layer::String
end
Last(layer::Layer) = Last(_layer_name(layer))

struct Only <: Reducer
	layer::String
end
Only(layer::Layer) = Only(_layer_name(layer))

struct Collect <: Reducer
	layer::String
end
Collect(layer::Layer) = Collect(_layer_name(layer))

struct Width <: Reducer end

struct Document <: Reducer end

struct Sentence <: Reducer end

# ---- Capture-scoped reducer ----

struct Capture <: Reducer
	name::String
	inner::Reducer
end

Capture(name::Layer, inner::Reducer) = Capture(_layer_name(name), inner)
