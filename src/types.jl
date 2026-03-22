const _exiting = Ref(false)
atexit(() -> _exiting[] = true)

"""
	Hit

A single query result: a span of token positions plus document and sentence indices.
Access the matched range via `hit.span`, which is a `UnitRange{Int}`.
"""
struct Hit
	span::UnitRange{Int}
	document_index::Int
	sentence_index::Int
end

"""
	Component

A named subcorpus within a multi-component corpus (e.g. a language or edition).
"""
struct Component
	name::String
	language::String
	token_count::Int
end

"""
	Alignment

A named alignment relation between two components, e.g. sentence-level
translation alignments produced by LaBSE or vecalign.
"""
struct Alignment
	name::String
	source::String
	target::String
	source_layer::String
	target_layer::String
	directed::Bool
	edge_count::Int
end

"""
	ConcordanceLine

A single KWIC (Key Word In Context) line: left context, matched text, right context,
source document name, and corpus position.
"""
struct ConcordanceLine
	left::String
	match_text::String
	right::String
	document::String
	position::Int
end

"""
	Concordance

A collection of [`ConcordanceLine`](@ref)s with a KWIC display.
Implements `Tables.jl` for conversion to `DataFrame`.
Indexable and iterable.
"""
struct Concordance
	lines::Vector{ConcordanceLine}
end

Base.length(c::Concordance) = length(c.lines)
Base.getindex(c::Concordance, i) = c.lines[i]
Base.iterate(c::Concordance, s...) = iterate(c.lines, s...)
Base.firstindex(c::Concordance) = 1
Base.lastindex(c::Concordance) = length(c.lines)
Base.eltype(::Type{Concordance}) = ConcordanceLine

"""
	CQL(s::AbstractString)

A CQL query string. Single quotes in `s` are converted to double quotes,
so you can write `CQL("[pos='NOUN']")` instead of escaping.
Supports interpolation, unlike the [`@cql_str`](@ref) macro.

See also: [`@cql_str`](@ref)
"""
struct CQL
	query::String
	CQL(s::AbstractString) = new(replace(s, "'" => "\""))
end

"""
	@cql_str

String macro for CQL queries. Single quotes become double quotes;
backslashes and `\$` are passed through literally (no interpolation).

```julia
query(corpus, cql"[pos='NOUN']")
query(corpus, cql"[lemma='être' & pos='VERB']")
query(corpus, cql"[lemma=/^(bleu|blanc)\$/]")
```

For dynamic queries with interpolation, use [`CQL()`](@ref) instead.
"""
macro cql_str(s)
	:(CQL($s))
end

"""
	Corpus

A handle to an opened montre corpus. Created via [`Montre.open`](@ref).
Close with `close(corpus)` or use the `do`-block form of `Montre.open`.
"""
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

"""
	HitList

A materialized set of query results, backed by a Rust-side `Vec<Hit>`.
Indexable (`hits[i]` returns a [`Hit`](@ref)) and iterable.
Holds a reference to its parent [`Corpus`](@ref), so functions like
[`texts`](@ref), [`concordance`](@ref), and [`project`](@ref) can
be called on it directly without passing the corpus.

Implements `Tables.jl` for conversion to `DataFrame`.
"""
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

"""
	ProjectionResult

Result of projecting hits through an alignment. Contains the projected
[`HitList`](@ref) plus diagnostic counts.
"""
struct ProjectionResult
	hits::HitList
	unmapped::Int
	no_alignment::Int
	projected::Int
end

Base.length(pr::ProjectionResult) = length(pr.hits)
