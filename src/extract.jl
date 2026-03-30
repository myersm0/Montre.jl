
## HitRow (per-hit accessor for lambda specs)

struct HitRow
	corpus::Corpus
	hit_start::Int
	hit_end::Int
	document::String
	sentence_index::Int
	capture_starts::Dict{String, Int}
	capture_ends::Dict{String, Int}
end

function HitRow(hitlist::HitList, i::Int)
	store = hitlist.capture_store
	cap_starts = Dict{String, Int}()
	cap_ends = Dict{String, Int}()
	for name in store.names
		cap_starts[name] = store.starts[name][i]
		cap_ends[name] = store.ends[name][i]
	end
	HitRow(
		hitlist.corpus,
		hitlist.starts[i], hitlist.ends[i],
		document_name(hitlist, i),
		hitlist.sentence_indices[i],
		cap_starts, cap_ends,
	)
end

function Base.getindex(row::HitRow, layer::Layer)
	name = String(layer)
	name == "document" && return row.document
	name == "width" && return row.hit_end - row.hit_start
	name == "span" && return row.hit_start:row.hit_end - 1
	name == "start" && return row.hit_start
	name == "stop" && return row.hit_end - 1
	name == "sentence_index" && return row.sentence_index
	corpus_token_annotations(row.corpus.pointer, row.hit_start, row.hit_end, name)
end

function Base.getindex(row::HitRow, capture_name::AbstractString, layer::Layer)
	haskey(row.capture_starts, capture_name) || throw(KeyError(capture_name))
	cs = row.capture_starts[capture_name]
	ce = row.capture_ends[capture_name]
	corpus_token_annotations(row.corpus.pointer, cs, ce, String(layer))
end


## spec parsing

struct ExtractSpec
	name::Symbol
	func::Function
end

function parse_spec(spec::Symbol)
	structural_fields = ["document", "width", "span", "start", "stop", "sentence_index"]
	String(spec) in structural_fields || error(
		"bare :$spec is ambiguous for annotation layers — " *
		"specify a reduction, e.g. :$spec => join or :$spec => collect"
	)
	ExtractSpec(spec, x -> x[spec])
end

function parse_spec(spec::Pair{Symbol, <:Function})
	layer, f = spec
	ExtractSpec(layer, x -> f(x[layer]))
end

function parse_spec(spec::Pair{Pair{Symbol, <:Function}, Symbol})
	(layer, f), name = spec
	ExtractSpec(name, x -> f(x[layer]))
end

function parse_spec(spec::Pair{<:Function, Symbol})
	f, name = spec
	ExtractSpec(name, f)
end

function parse_specs(specs)
	isempty(specs) && error("extract requires at least one column spec")
	[parse_spec(s) for s in specs]
end


## extract

function extract(hitlist::HitList, ::Type{DataFrame}, specs...)
	parsed = parse_specs(specs)
	n = length(hitlist)
	columns = Dict{Symbol, Vector}()
	for s in parsed
		columns[s.name] = Vector{Any}(undef, n)
	end

	for i in 1:n
		row = HitRow(hitlist, i)
		for s in parsed
			columns[s.name][i] = s.func(row)
		end
	end

	typed = Dict{Symbol, Vector}()
	for (name, col) in columns
		typed[name] = typed_vector(col)
	end

	DataFrame(typed; copycols = false)[:, [s.name for s in parsed]]
end

function extract(hitlist::HitList, ::Type{Vector}, spec)
	parsed = parse_spec(spec)
	n = length(hitlist)
	result = Vector{Any}(undef, n)
	for i in 1:n
		row = HitRow(hitlist, i)
		result[i] = parsed.func(row)
	end
	typed_vector(result)
end

function typed_vector(col::Vector{Any})
	isempty(col) && return col
	t = typeof(col[1])
	if all(x -> typeof(x) === t, col)
		convert(Vector{t}, col)
	else
		col
	end
end


## frequency

function frequency(hitlist::HitList; by::Union{Pair, Symbol} = :word => join)
	spec = by isa Symbol ? (by => join) : by
	df = extract(hitlist, DataFrame, spec)
	col_name = first(names(df))
	combine(groupby(df, col_name), nrow => :count) |>
		x -> sort(x, :count; rev = true)
end

frequency(corpus::Corpus, cql::CQL; kwargs...) = frequency(query(corpus, cql.query); kwargs...)
