
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

function frequency(hitlist::HitList; by::Layer = :word)
	layer_str = String(by)
	counts = Dict{String, Int}()
	for i in 1:length(hitlist)
		text = corpus_span_text(
			hitlist.corpus.pointer,
			hitlist.starts[i], hitlist.ends[i],
			layer_str,
		)
		key = something(text, "")
		counts[key] = get(counts, key, 0) + 1
	end
	[(; value = k, count = v) for (k, v) in counts]
end

