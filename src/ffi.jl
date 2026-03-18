
function check_error()
	pointer = ccall((:montre_last_error, libmontre), Ptr{Cchar}, ())
	if pointer != C_NULL
		message = unsafe_string(pointer)
		error("Montre: $message")
	end
end

function take_string(pointer::Ptr{Cchar})
	if pointer == C_NULL
		return nothing
	end
	result = unsafe_string(pointer)
	ccall((:montre_string_free, libmontre), Cvoid, (Ptr{Cchar},), pointer)
	return result
end

# ---- corpus lifecycle ----

function corpus_open(path::AbstractString)
	pointer = ccall(
		(:montre_corpus_open, libmontre),
		Ptr{Nothing},
		(Cstring,),
		path,
	)
	if pointer == C_NULL
		check_error()
		error("Montre: failed to open corpus at $path")
	end
	return pointer
end

function corpus_close(pointer::Ptr{Nothing})
	ccall((:montre_corpus_close, libmontre), Cvoid, (Ptr{Nothing},), pointer)
end

function corpus_token_count(pointer::Ptr{Nothing})
	ccall((:montre_corpus_token_count, libmontre), UInt64, (Ptr{Nothing},), pointer)
end

# ---- layers ----

function corpus_layer_count(pointer::Ptr{Nothing})
	ccall((:montre_corpus_layer_count, libmontre), UInt32, (Ptr{Nothing},), pointer)
end

function corpus_layer_name(pointer::Ptr{Nothing}, index::Integer)
	raw = ccall(
		(:montre_corpus_layer_name, libmontre),
		Ptr{Cchar},
		(Ptr{Nothing}, UInt32),
		pointer,
		UInt32(index),
	)
	return take_string(raw)
end

# ---- documents ----

function corpus_document_count(pointer::Ptr{Nothing})
	ccall((:montre_corpus_document_count, libmontre), UInt32, (Ptr{Nothing},), pointer)
end

function corpus_document_name(pointer::Ptr{Nothing}, index::Integer)
	raw = ccall(
		(:montre_corpus_document_name, libmontre),
		Ptr{Cchar},
		(Ptr{Nothing}, UInt32),
		pointer,
		UInt32(index),
	)
	return take_string(raw)
end

# ---- components ----

function corpus_component_count(pointer::Ptr{Nothing})
	ccall((:montre_corpus_component_count, libmontre), UInt32, (Ptr{Nothing},), pointer)
end

function corpus_component_name(pointer::Ptr{Nothing}, index::Integer)
	raw = ccall(
		(:montre_corpus_component_name, libmontre),
		Ptr{Cchar},
		(Ptr{Nothing}, UInt32),
		pointer,
		UInt32(index),
	)
	return take_string(raw)
end

function corpus_component_language(pointer::Ptr{Nothing}, index::Integer)
	raw = ccall(
		(:montre_corpus_component_language, libmontre),
		Ptr{Cchar},
		(Ptr{Nothing}, UInt32),
		pointer,
		UInt32(index),
	)
	return take_string(raw)
end

# ---- token access ----

function corpus_token_annotation(pointer::Ptr{Nothing}, position::Integer, layer::AbstractString)
	raw = ccall(
		(:montre_corpus_token_annotation, libmontre),
		Ptr{Cchar},
		(Ptr{Nothing}, UInt64, Cstring),
		pointer,
		UInt64(position),
		layer,
	)
	return take_string(raw)
end

function corpus_span_text(pointer::Ptr{Nothing}, start::Integer, stop::Integer, layer::AbstractString)
	raw = ccall(
		(:montre_corpus_span_text, libmontre),
		Ptr{Cchar},
		(Ptr{Nothing}, UInt64, UInt64, Cstring),
		pointer,
		UInt64(start),
		UInt64(stop),
		layer,
	)
	return take_string(raw)
end

# ---- query ----

function query(pointer::Ptr{Nothing}, cql::AbstractString)
	result = ccall(
		(:montre_query, libmontre),
		Ptr{Nothing},
		(Ptr{Nothing}, Cstring),
		pointer,
		cql,
	)
	if result == C_NULL
		check_error()
		error("Montre: query failed")
	end
	return result
end

function hitlist_free(pointer::Ptr{Nothing})
	ccall((:montre_hitlist_free, libmontre), Cvoid, (Ptr{Nothing},), pointer)
end

function hitlist_len(pointer::Ptr{Nothing})
	ccall((:montre_hitlist_len, libmontre), UInt64, (Ptr{Nothing},), pointer)
end

function hit_start(pointer::Ptr{Nothing}, index::Integer)
	ccall(
		(:montre_hit_start, libmontre),
		UInt64,
		(Ptr{Nothing}, UInt64),
		pointer,
		UInt64(index),
	)
end

function hit_end(pointer::Ptr{Nothing}, index::Integer)
	ccall(
		(:montre_hit_end, libmontre),
		UInt64,
		(Ptr{Nothing}, UInt64),
		pointer,
		UInt64(index),
	)
end

function hit_document_index(pointer::Ptr{Nothing}, index::Integer)
	ccall(
		(:montre_hit_document_index, libmontre),
		UInt32,
		(Ptr{Nothing}, UInt64),
		pointer,
		UInt64(index),
	)
end

function hit_sentence_index(pointer::Ptr{Nothing}, index::Integer)
	ccall(
		(:montre_hit_sentence_index, libmontre),
		UInt32,
		(Ptr{Nothing}, UInt64),
		pointer,
		UInt64(index),
	)
end

function hitlist_populate_context(hits::Ptr{Nothing}, corpus::Ptr{Nothing})
	ccall(
		(:montre_hitlist_populate_context, libmontre),
		Cvoid,
		(Ptr{Nothing}, Ptr{Nothing}),
		hits,
		corpus,
	)
end

function query_count(pointer::Ptr{Nothing}, cql::AbstractString)
	result = ccall(
		(:montre_query_count, libmontre),
		Int64,
		(Ptr{Nothing}, Cstring),
		pointer,
		cql,
	)
	if result < 0
		check_error()
		error("Montre: query count failed")
	end
	return result
end

# ---- bulk text extraction ----

function hitlist_texts(hits::Ptr{Nothing}, corpus::Ptr{Nothing}, layer::AbstractString)
	out_len = Ref{UInt64}(0)
	array = ccall(
		(:montre_hitlist_texts, libmontre),
		Ptr{Ptr{Cchar}},
		(Ptr{Nothing}, Ptr{Nothing}, Cstring, Ptr{UInt64}),
		hits,
		corpus,
		layer,
		out_len,
	)
	if array == C_NULL
		check_error()
		return String[]
	end
	n = Int(out_len[])
	result = [unsafe_string(unsafe_load(array, i)) for i in 1:n]
	ccall(
		(:montre_string_array_free, libmontre),
		Cvoid,
		(Ptr{Ptr{Cchar}}, UInt64),
		array,
		out_len[],
	)
	return result
end

# ---- alignments ----

function corpus_alignment_count(pointer::Ptr{Nothing})
	ccall((:montre_corpus_alignment_count, libmontre), UInt32, (Ptr{Nothing},), pointer)
end

function corpus_alignment_name(pointer::Ptr{Nothing}, index::Integer)
	raw = ccall(
		(:montre_corpus_alignment_name, libmontre),
		Ptr{Cchar},
		(Ptr{Nothing}, UInt32),
		pointer,
		UInt32(index),
	)
	return take_string(raw)
end

function corpus_alignment_source(pointer::Ptr{Nothing}, index::Integer)
	raw = ccall(
		(:montre_corpus_alignment_source, libmontre),
		Ptr{Cchar},
		(Ptr{Nothing}, UInt32),
		pointer,
		UInt32(index),
	)
	return take_string(raw)
end

function corpus_alignment_target(pointer::Ptr{Nothing}, index::Integer)
	raw = ccall(
		(:montre_corpus_alignment_target, libmontre),
		Ptr{Cchar},
		(Ptr{Nothing}, UInt32),
		pointer,
		UInt32(index),
	)
	return take_string(raw)
end

function corpus_alignment_edge_count(pointer::Ptr{Nothing}, index::Integer)
	ccall(
		(:montre_corpus_alignment_edge_count, libmontre),
		UInt64,
		(Ptr{Nothing}, UInt32),
		pointer,
		UInt32(index),
	)
end

# ---- projection ----

function project(corpus::Ptr{Nothing}, hits::Ptr{Nothing}, alignment::AbstractString)
	result = ccall(
		(:montre_project, libmontre),
		Ptr{Nothing},
		(Ptr{Nothing}, Ptr{Nothing}, Cstring),
		corpus,
		hits,
		alignment,
	)
	if result == C_NULL
		check_error()
		error("Montre: projection failed")
	end
	return result
end

