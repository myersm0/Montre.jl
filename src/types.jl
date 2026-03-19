const _exiting = Ref(false)
atexit(() -> _exiting[] = true)

struct Hit
	span::UnitRange{Int}
	document_index::Int
	sentence_index::Int
end

struct Component
	name::String
	language::String
end

struct Alignment
	name::String
	source::String
	target::String
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
Base.firstindex(c::Concordance) = 1
Base.lastindex(c::Concordance) = length(c.lines)
Base.eltype(::Type{Concordance}) = ConcordanceLine

struct CQL
	query::String
	CQL(s::AbstractString) = new(replace(s, "'" => "\""))
end

macro cql_str(s)
	:(CQL($s))
end

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

mutable struct HitList
	pointer::Ptr{Nothing}
	corpus::Corpus

	function HitList(pointer::Ptr{Nothing}, corpus::Corpus)
		hitlist = new(pointer, corpus)
		finalizer(hitlist) do h
			if !_exiting[] && h.pointer != C_NULL
				hitlist_free(h.pointer)
				h.pointer = C_NULL
			end
		end
		return hitlist
	end
end
