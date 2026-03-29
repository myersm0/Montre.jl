using DataFrames

# ---- spec parsing ----

struct ExtractSpec
	name::Symbol
	func::Function
end

function _is_structural(name::Symbol)
	String(name) in _structural_fields
end

function _parse_spec(spec::Symbol)
	_is_structural(spec) || error(
		"bare :$spec is ambiguous for annotation layers — " *
		"specify a reduction, e.g. :$spec => join or :$spec => collect"
	)
	ExtractSpec(spec, x -> x[spec])
end

function _parse_spec(spec::Pair{Symbol, <:Function})
	layer, f = spec
	ExtractSpec(layer, x -> f(x[layer]))
end

function _parse_spec(spec::Pair{Pair{Symbol, <:Function}, Symbol})
	(layer, f), name = spec
	ExtractSpec(name, x -> f(x[layer]))
end

function _parse_spec(spec::Pair{<:Function, Symbol})
	f, name = spec
	ExtractSpec(name, f)
end

function _parse_specs(specs)
	isempty(specs) && error("extract requires at least one column spec")
	[_parse_spec(s) for s in specs]
end

# ---- extract ----

function extract(hitlist::HitList, ::Type{DataFrame}, specs...)
	parsed = _parse_specs(specs)
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
		typed[name] = _typed_vector(col)
	end

	DataFrame(typed; copycols = false)[:, [s.name for s in parsed]]
end

function extract(hitlist::HitList, ::Type{Vector}, spec)
	parsed = _parse_spec(spec)
	n = length(hitlist)
	result = Vector{Any}(undef, n)
	for i in 1:n
		row = HitRow(hitlist, i)
		result[i] = parsed.func(row)
	end
	_typed_vector(result)
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

# ---- frequency (convenience) ----

function frequency(hitlist::HitList; by::Union{Pair, Symbol} = :word => join)
	spec = by isa Symbol ? (by => join) : by
	df = extract(hitlist, DataFrame, spec)
	col_name = first(names(df))
	combine(groupby(df, col_name), nrow => :count) |>
		x -> sort(x, :count; rev = true)
end
