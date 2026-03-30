# ---- Corpus, Component, Alignment ----

function Base.show(io::IO, corpus::Corpus)
	if !isopen(corpus)
		print(io, "Corpus (closed)")
		return
	end
	tokens = token_count(corpus)
	n_documents = Int(corpus_document_count(corpus.pointer))
	n_components = Int(corpus_component_count(corpus.pointer))
	print(io, "Corpus($(tokens) tokens, $(n_documents) documents")
	if n_components > 1
		print(io, ", $(n_components) components")
	end
	print(io, ")")
end

function Base.show(io::IO, component::Component)
	print(io, "Component(\"$(component.name)\", $(component.language), $(component.token_count) tokens)")
end

function Base.show(io::IO, alignment::Alignment)
	print(io, "Alignment(\"$(alignment.name)\", $(alignment.source) → $(alignment.target), $(alignment.edge_count) edges)")
end

# ---- Hit ----

function Base.show(io::IO, hit::Hit)
	print(io, "Hit($(hit.document)")
	if !isempty(hit.captures)
		for (name, span) in hit.captures
			print(io, ", $name=$(first(span)):$(last(span))")
		end
	else
		print(io, ", $(first(hit.span)):$(last(hit.span))")
	end
	print(io, ")")
end

# ---- HitList ----

function capture_margin_labels(hitlist::HitList, i::Integer)
	store = hitlist.capture_store
	isempty(store) && return Dict{Int, String}()
	hit_start = hitlist.starts[i]
	labels = Dict{Int, String}()
	for name in store.names
		cs = store.starts[name][i]
		ce = store.ends[name][i]
		for pos in cs:ce - 1
			local_idx = pos - hit_start + 1
			existing = get(labels, local_idx, "")
			labels[local_idx] = existing == "" ? name : existing * "," * name
		end
	end
	return labels
end

function capture_highlights(hitlist::HitList, i::Integer)
	store = hitlist.capture_store
	isempty(store) && return UnitRange{Int}[]
	hit_start = hitlist.starts[i]
	[
		let
			local_start = store.starts[name][i] - hit_start + 1
			local_end = store.ends[name][i] - hit_start
			local_start:local_end
		end
		for name in store.names
	]
end

function render_hit(io::IO, hitlist::HitList, i::Integer)
	hit = hitlist[i]
	printstyled(io, "Hit $i", bold = true)
	printstyled(io, " ($(hit.document))", color = :light_black)
	println(io)

	nodes = build_nodes(hitlist, i)
	margin_labels = capture_margin_labels(hitlist, i)
	highlights = capture_highlights(hitlist, i)

	kw = Dict{Symbol, Any}()
	isempty(margin_labels) || (kw[:margin_labels] = margin_labels)
	render(CompactStyle(), io, nodes; kw...)
end

function Base.show(io::IO, ::MIME"text/plain", hitlist::HitList)
	n = length(hitlist)
	n_docs = length(unique(hitlist.document_indices))
	printstyled(io, "$(n) hits", bold = true)
	print(io, " across $(n_docs) documents")

	n == 0 && return

	display_count = min(n, 5)
	for i in 1:display_count
		println(io)
		render_hit(io, hitlist, i)
	end

	if n > display_count
		println(io)
		printstyled(io, "⋮ $(n - display_count) more hits")
	end
end

function Base.show(io::IO, hitlist::HitList)
	print(io, "HitList($(length(hitlist)) hits)")
end

# ---- CQL ----

function Base.show(io::IO, cql::CQL)
	print(io, "cql\"", replace(cql.query, "\"" => "'"), "\"")
end

# ---- Concordance ----

function Base.show(io::IO, line::ConcordanceLine)
	print(io, lpad(line.left, 30), "  ")
	printstyled(io, line.match_text, bold = true)
	print(io, "  ", line.right)
end

function truncate_text(s::AbstractString, width::Int)
	textwidth(s) <= width && return s
	chars = collect(s)
	w = 0
	for (i, c) in enumerate(chars)
		w += textwidth(c)
		if w > width - 1
			return String(chars[1:i - 1]) * "…"
		end
	end
	return s
end

function Base.show(io::IO, ::MIME"text/plain", conc::Concordance)
	n = length(conc)
	n == 0 && (print(io, "Concordance (empty)"); return)

	lines = conc.lines
	term_width = displaysize(io)[2]

	doc_width = min(maximum(textwidth(l.document) for l in lines), 24)
	match_width = min(maximum(textwidth(l.match_text) for l in lines), 30)

	fixed = doc_width + match_width + 6
	remaining = max(term_width - fixed, 20)
	side_width = remaining ÷ 2

	println(io, "Concordance ($(n) lines)")
	for line in lines
		doc = truncate_text(line.document, doc_width)
		left = truncate_text(line.left, side_width)
		match = truncate_text(line.match_text, match_width)
		right = truncate_text(line.right, side_width)

		printstyled(io, rpad(doc, doc_width), color = :light_black)
		print(io, " ", lpad(left, side_width), " ")
		printstyled(io, match, bold = true)
		print(io, " ", rpad(right, side_width))
		line !== last(lines) && println(io)
	end
end
