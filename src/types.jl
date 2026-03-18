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

mutable struct Corpus
	pointer::Ptr{Nothing}

	function Corpus(pointer::Ptr{Nothing})
		corpus = new(pointer)
		finalizer(corpus) do c
			if c.pointer != C_NULL
				FFI.corpus_close(c.pointer)
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
			if h.pointer != C_NULL
				FFI.hitlist_free(h.pointer)
				h.pointer = C_NULL
			end
		end
		return hitlist
	end
end
