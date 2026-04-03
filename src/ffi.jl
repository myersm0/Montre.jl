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

function take_string_array(array::Ptr{Ptr{Cchar}}, n::Integer)
	if array == C_NULL || n == 0
		return String[]
	end
	result = [unsafe_string(unsafe_load(array, i)) for i in 1:n]
	ccall((:montre_string_array_free, libmontre), Cvoid, (Ptr{Ptr{Cchar}}, UInt64), array, UInt64(n))
	return result
end

function take_u64_array(array::Ptr{UInt64}, n::Integer)
	if array == C_NULL || n == 0
		return Int[]
	end
	result = [Int(unsafe_load(array, i)) for i in 1:n]
	ccall((:montre_u64_array_free, libmontre), Cvoid, (Ptr{UInt64}, UInt64), array, UInt64(n))
	return result
end

function take_u32_array(array::Ptr{UInt32}, n::Integer)
	if array == C_NULL || n == 0
		return Int[]
	end
	result = [Int(unsafe_load(array, i)) for i in 1:n]
	ccall((:montre_u32_array_free, libmontre), Cvoid, (Ptr{UInt32}, UInt64), array, UInt64(n))
	return result
end

function take_i32_array(array::Ptr{Int32}, n::Integer)
	if array == C_NULL || n == 0
		return Int32[]
	end
	result = [unsafe_load(array, i) for i in 1:n]
	ccall((:montre_i32_array_free, libmontre), Cvoid, (Ptr{Int32}, UInt64), array, UInt64(n))
	return result
end

# ---- corpus lifecycle ----

function corpus_open(path::AbstractString)
	pointer = ccall((:montre_corpus_open, libmontre), Ptr{Nothing}, (Cstring,), path)
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
		(:montre_corpus_layer_name, libmontre), Ptr{Cchar},
		(Ptr{Nothing}, UInt32), pointer, UInt32(index),
	)
	return take_string(raw)
end

# ---- documents ----

function corpus_document_count(pointer::Ptr{Nothing})
	ccall((:montre_corpus_document_count, libmontre), UInt32, (Ptr{Nothing},), pointer)
end

function corpus_document_name(pointer::Ptr{Nothing}, index::Integer)
	raw = ccall(
		(:montre_corpus_document_name, libmontre), Ptr{Cchar},
		(Ptr{Nothing}, UInt32), pointer, UInt32(index),
	)
	return take_string(raw)
end

function corpus_document_index_by_name(pointer::Ptr{Nothing}, name::AbstractString)
	result = ccall(
		(:montre_corpus_document_index_by_name, libmontre), Int64,
		(Ptr{Nothing}, Cstring), pointer, name,
	)
	result < 0 && return nothing
	return Int(result)
end

# ---- components ----

function corpus_component_count(pointer::Ptr{Nothing})
	ccall((:montre_corpus_component_count, libmontre), UInt32, (Ptr{Nothing},), pointer)
end

function corpus_component_name(pointer::Ptr{Nothing}, index::Integer)
	raw = ccall(
		(:montre_corpus_component_name, libmontre), Ptr{Cchar},
		(Ptr{Nothing}, UInt32), pointer, UInt32(index),
	)
	return take_string(raw)
end

function corpus_component_language(pointer::Ptr{Nothing}, index::Integer)
	raw = ccall(
		(:montre_corpus_component_language, libmontre), Ptr{Cchar},
		(Ptr{Nothing}, UInt32), pointer, UInt32(index),
	)
	return take_string(raw)
end

function corpus_component_document_range(pointer::Ptr{Nothing}, index::Integer)
	out_start = Ref{UInt32}(0)
	out_end = Ref{UInt32}(0)
	ok = ccall(
		(:montre_corpus_component_document_range, libmontre), Int32,
		(Ptr{Nothing}, UInt32, Ptr{UInt32}, Ptr{UInt32}),
		pointer, UInt32(index), out_start, out_end,
	)
	ok == 0 && return nothing
	return Int(out_start[]):Int(out_end[]) - 1
end

function corpus_component_for_document(pointer::Ptr{Nothing}, doc_index::Integer)
	result = ccall(
		(:montre_corpus_component_for_document, libmontre), Int32,
		(Ptr{Nothing}, UInt32), pointer, UInt32(doc_index),
	)
	result < 0 && return nothing
	return Int(result)
end

function corpus_component_token_count(pointer::Ptr{Nothing}, index::Integer)
	result = ccall(
		(:montre_corpus_component_token_count, libmontre), Int64,
		(Ptr{Nothing}, UInt32), pointer, UInt32(index),
	)
	result < 0 && return nothing
	return Int(result)
end

function corpus_component_index_by_name(pointer::Ptr{Nothing}, name::AbstractString)
	result = ccall(
		(:montre_corpus_component_index_by_name, libmontre), Int32,
		(Ptr{Nothing}, Cstring), pointer, name,
	)
	result < 0 && return nothing
	return Int(result)
end

# ---- inverted index ----

function corpus_inverted_values(pointer::Ptr{Nothing}, layer::AbstractString)
	out_len = Ref{UInt64}(0)
	array = ccall(
		(:montre_corpus_inverted_values, libmontre), Ptr{Ptr{Cchar}},
		(Ptr{Nothing}, Cstring, Ptr{UInt64}), pointer, layer, out_len,
	)
	return take_string_array(array, Int(out_len[]))
end

function corpus_inverted_count(pointer::Ptr{Nothing}, layer::AbstractString, value::AbstractString)
	result = ccall(
		(:montre_corpus_inverted_count, libmontre), Int64,
		(Ptr{Nothing}, Cstring, Cstring), pointer, layer, value,
	)
	result < 0 && return nothing
	return Int(result)
end

function corpus_inverted_counts(pointer::Ptr{Nothing}, layer::AbstractString)
	out_len = Ref{UInt64}(0)
	out_values = Ref{Ptr{Ptr{Cchar}}}(C_NULL)
	out_counts = Ref{Ptr{UInt64}}(C_NULL)
	ok = ccall(
		(:montre_corpus_inverted_counts, libmontre), Int32,
		(Ptr{Nothing}, Cstring, Ptr{Ptr{Ptr{Cchar}}}, Ptr{Ptr{UInt64}}, Ptr{UInt64}),
		pointer, layer, out_values, out_counts, out_len,
	)
	ok == 0 && return (String[], Int[])
	n = Int(out_len[])
	values = take_string_array(out_values[], n)
	counts = take_u64_array(out_counts[], n)
	return (values, counts)
end

# ---- token access ----

function corpus_token_annotation(pointer::Ptr{Nothing}, position::Integer, layer::AbstractString)
	raw = ccall(
		(:montre_corpus_token_annotation, libmontre), Ptr{Cchar},
		(Ptr{Nothing}, UInt64, Cstring), pointer, UInt64(position), layer,
	)
	return take_string(raw)
end

function corpus_span_text(pointer::Ptr{Nothing}, start::Integer, stop::Integer, layer::AbstractString)
	raw = ccall(
		(:montre_corpus_span_text, libmontre), Ptr{Cchar},
		(Ptr{Nothing}, UInt64, UInt64, Cstring), pointer, UInt64(start), UInt64(stop), layer,
	)
	return take_string(raw)
end

function corpus_token_annotations(pointer::Ptr{Nothing}, start::Integer, stop::Integer, layer::AbstractString)
	out_len = Ref{UInt64}(0)
	array = ccall(
		(:montre_corpus_token_annotations, libmontre), Ptr{Ptr{Cchar}},
		(Ptr{Nothing}, UInt64, UInt64, Cstring, Ptr{UInt64}),
		pointer, UInt64(start), UInt64(stop), layer, out_len,
	)
	return take_string_array(array, Int(out_len[]))
end

# ---- span layers ----

function corpus_span_layer_count(pointer::Ptr{Nothing})
	ccall((:montre_corpus_span_layer_count, libmontre), UInt32, (Ptr{Nothing},), pointer)
end

function corpus_span_layer_name(pointer::Ptr{Nothing}, index::Integer)
	raw = ccall(
		(:montre_corpus_span_layer_name, libmontre), Ptr{Cchar},
		(Ptr{Nothing}, UInt32), pointer, UInt32(index),
	)
	return take_string(raw)
end

function corpus_span_count(pointer::Ptr{Nothing}, layer::AbstractString)
	result = ccall(
		(:montre_corpus_span_count, libmontre), Int64,
		(Ptr{Nothing}, Cstring), pointer, layer,
	)
	result < 0 && return nothing
	return Int(result)
end

function corpus_span_at(pointer::Ptr{Nothing}, layer::AbstractString, index::Integer)
	out_start = Ref{UInt64}(0)
	out_end = Ref{UInt64}(0)
	ok = ccall(
		(:montre_corpus_span_at, libmontre), Int32,
		(Ptr{Nothing}, Cstring, UInt64, Ptr{UInt64}, Ptr{UInt64}),
		pointer, layer, UInt64(index), out_start, out_end,
	)
	ok == 0 && return nothing
	return Int(out_start[]):Int(out_end[]) - 1
end

function corpus_span_containing(pointer::Ptr{Nothing}, layer::AbstractString, position::Integer)
	out_start = Ref{UInt64}(0)
	out_end = Ref{UInt64}(0)
	result = ccall(
		(:montre_corpus_span_containing, libmontre), Int64,
		(Ptr{Nothing}, Cstring, UInt64, Ptr{UInt64}, Ptr{UInt64}),
		pointer, layer, UInt64(position), out_start, out_end,
	)
	result < 0 && return nothing
	return (; index = Int(result), span = Int(out_start[]):Int(out_end[]) - 1)
end

function corpus_span_count_in_range(pointer::Ptr{Nothing}, layer::AbstractString, token_start::Integer, token_end::Integer)
	result = ccall(
		(:montre_corpus_span_count_in_range, libmontre), Int64,
		(Ptr{Nothing}, Cstring, UInt64, UInt64),
		pointer, layer, UInt64(token_start), UInt64(token_end),
	)
	result < 0 && return nothing
	return Int(result)
end

function corpus_sentence_span(
		pointer::Ptr{Nothing}, component_index::Integer,
		doc_within_component::Integer, sentence_within_doc::Integer,
	)
	out_start = Ref{UInt64}(0)
	out_end = Ref{UInt64}(0)
	result = ccall(
		(:montre_corpus_sentence_span, libmontre), Int64,
		(Ptr{Nothing}, UInt32, UInt32, UInt32, Ptr{UInt64}, Ptr{UInt64}),
		pointer, UInt32(component_index), UInt32(doc_within_component),
		UInt32(sentence_within_doc), out_start, out_end,
	)
	result < 0 && return nothing
	return (; index = Int(result), span = Int(out_start[]):Int(out_end[]) - 1)
end

# ---- query ----

function query(pointer::Ptr{Nothing}, cql::AbstractString)
	result = ccall(
		(:montre_query, libmontre), Ptr{Nothing},
		(Ptr{Nothing}, Cstring), pointer, cql,
	)
	if result == C_NULL
		check_error()
		error("Montre: query failed")
	end
	return result
end

function query_in_component(pointer::Ptr{Nothing}, cql::AbstractString, component::AbstractString)
	result = ccall(
		(:montre_query_in_component, libmontre), Ptr{Nothing},
		(Ptr{Nothing}, Cstring, Cstring), pointer, cql, component,
	)
	if result == C_NULL
		check_error()
		error("Montre: query failed")
	end
	return result
end

function query_count(pointer::Ptr{Nothing}, cql::AbstractString)
	result = ccall(
		(:montre_query_count, libmontre), Int64,
		(Ptr{Nothing}, Cstring), pointer, cql,
	)
	if result < 0
		check_error()
		error("Montre: query count failed")
	end
	return result
end

function query_count_in_component(pointer::Ptr{Nothing}, cql::AbstractString, component::AbstractString)
	result = ccall(
		(:montre_query_count_in_component, libmontre), Int64,
		(Ptr{Nothing}, Cstring, Cstring), pointer, cql, component,
	)
	if result < 0
		check_error()
		error("Montre: query count failed")
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
	ccall((:montre_hit_start, libmontre), UInt64, (Ptr{Nothing}, UInt64), pointer, UInt64(index))
end

function hit_end(pointer::Ptr{Nothing}, index::Integer)
	ccall((:montre_hit_end, libmontre), UInt64, (Ptr{Nothing}, UInt64), pointer, UInt64(index))
end

function hit_document_index(pointer::Ptr{Nothing}, index::Integer)
	ccall((:montre_hit_document_index, libmontre), UInt32, (Ptr{Nothing}, UInt64), pointer, UInt64(index))
end

function hit_sentence_index(pointer::Ptr{Nothing}, index::Integer)
	ccall((:montre_hit_sentence_index, libmontre), UInt32, (Ptr{Nothing}, UInt64), pointer, UInt64(index))
end

function hit_capture_count(pointer::Ptr{Nothing}, index::Integer)
	ccall((:montre_hit_capture_count, libmontre), UInt32, (Ptr{Nothing}, UInt64), pointer, UInt64(index))
end

function hit_capture_name(pointer::Ptr{Nothing}, hit_index::Integer, capture_index::Integer)
	raw = ccall(
		(:montre_hit_capture_name, libmontre), Ptr{Cchar},
		(Ptr{Nothing}, UInt64, UInt32), pointer, UInt64(hit_index), UInt32(capture_index),
	)
	return take_string(raw)
end

function hit_capture_start(pointer::Ptr{Nothing}, hit_index::Integer, capture_index::Integer)
	ccall(
		(:montre_hit_capture_start, libmontre), UInt64,
		(Ptr{Nothing}, UInt64, UInt32), pointer, UInt64(hit_index), UInt32(capture_index),
	)
end

function hit_capture_end(pointer::Ptr{Nothing}, hit_index::Integer, capture_index::Integer)
	ccall(
		(:montre_hit_capture_end, libmontre), UInt64,
		(Ptr{Nothing}, UInt64, UInt32), pointer, UInt64(hit_index), UInt32(capture_index),
	)
end

function hitlist_populate_context(hits::Ptr{Nothing}, corpus::Ptr{Nothing})
	ccall(
		(:montre_hitlist_populate_context, libmontre), Cvoid,
		(Ptr{Nothing}, Ptr{Nothing}), hits, corpus,
	)
end

# ---- bulk hit field extraction ----

function hitlist_starts(hits::Ptr{Nothing})
	out_len = Ref{UInt64}(0)
	array = ccall(
		(:montre_hitlist_starts, libmontre), Ptr{UInt64},
		(Ptr{Nothing}, Ptr{UInt64}), hits, out_len,
	)
	return take_u64_array(array, Int(out_len[]))
end

function hitlist_ends(hits::Ptr{Nothing})
	out_len = Ref{UInt64}(0)
	array = ccall(
		(:montre_hitlist_ends, libmontre), Ptr{UInt64},
		(Ptr{Nothing}, Ptr{UInt64}), hits, out_len,
	)
	return take_u64_array(array, Int(out_len[]))
end

function hitlist_document_indices(hits::Ptr{Nothing})
	out_len = Ref{UInt64}(0)
	array = ccall(
		(:montre_hitlist_document_indices, libmontre), Ptr{UInt64},
		(Ptr{Nothing}, Ptr{UInt64}), hits, out_len,
	)
	return take_u64_array(array, Int(out_len[]))
end

function hitlist_sentence_indices(hits::Ptr{Nothing})
	out_len = Ref{UInt64}(0)
	array = ccall(
		(:montre_hitlist_sentence_indices, libmontre), Ptr{UInt64},
		(Ptr{Nothing}, Ptr{UInt64}), hits, out_len,
	)
	return take_u64_array(array, Int(out_len[]))
end

# ---- bulk text extraction ----

function hitlist_texts(hits::Ptr{Nothing}, corpus::Ptr{Nothing}, layer::AbstractString)
	out_len = Ref{UInt64}(0)
	array = ccall(
		(:montre_hitlist_texts, libmontre), Ptr{Ptr{Cchar}},
		(Ptr{Nothing}, Ptr{Nothing}, Cstring, Ptr{UInt64}),
		hits, corpus, layer, out_len,
	)
	if array == C_NULL
		check_error()
		return String[]
	end
	return take_string_array(array, Int(out_len[]))
end

function context_tokens(hits::Ptr{Nothing}, corpus::Ptr{Nothing}, window::Integer, layer::AbstractString)
	out_len = Ref{UInt64}(0)
	out_positions = Ref{Ptr{Int32}}(C_NULL)
	out_tokens = Ref{Ptr{Ptr{Cchar}}}(C_NULL)
	out_offsets = Ref{Ptr{UInt64}}(C_NULL)

	ccall(
		(:montre_context_tokens, libmontre), Cvoid,
		(Ptr{Nothing}, Ptr{Nothing}, UInt32, Cstring,
		 Ptr{Ptr{Int32}}, Ptr{Ptr{Ptr{Cchar}}}, Ptr{Ptr{UInt64}}, Ptr{UInt64}),
		hits, corpus, UInt32(window), layer,
		out_positions, out_tokens, out_offsets, out_len,
	)

	n = Int(out_len[])
	tokens_ptr = out_tokens[]

	if tokens_ptr == C_NULL || n == 0
		check_error()
		return (positions = Int32[], tokens = String[], offsets = Int[])
	end

	n_hits = Int(hitlist_len(hits))
	positions = take_i32_array(out_positions[], n)
	tokens = take_string_array(tokens_ptr, n)
	offsets = take_u64_array(out_offsets[], n_hits + 1)

	return (; positions, tokens, offsets)
end

# ---- alignments ----

function corpus_alignment_count(pointer::Ptr{Nothing})
	ccall((:montre_corpus_alignment_count, libmontre), UInt32, (Ptr{Nothing},), pointer)
end

function corpus_alignment_name(pointer::Ptr{Nothing}, index::Integer)
	raw = ccall(
		(:montre_corpus_alignment_name, libmontre), Ptr{Cchar},
		(Ptr{Nothing}, UInt32), pointer, UInt32(index),
	)
	return take_string(raw)
end

function corpus_alignment_source(pointer::Ptr{Nothing}, index::Integer)
	raw = ccall(
		(:montre_corpus_alignment_source, libmontre), Ptr{Cchar},
		(Ptr{Nothing}, UInt32), pointer, UInt32(index),
	)
	return take_string(raw)
end

function corpus_alignment_target(pointer::Ptr{Nothing}, index::Integer)
	raw = ccall(
		(:montre_corpus_alignment_target, libmontre), Ptr{Cchar},
		(Ptr{Nothing}, UInt32), pointer, UInt32(index),
	)
	return take_string(raw)
end

function corpus_alignment_edge_count(pointer::Ptr{Nothing}, index::Integer)
	ccall(
		(:montre_corpus_alignment_edge_count, libmontre), UInt64,
		(Ptr{Nothing}, UInt32), pointer, UInt32(index),
	)
end

function corpus_alignment_source_layer(pointer::Ptr{Nothing}, index::Integer)
	raw = ccall(
		(:montre_corpus_alignment_source_layer, libmontre), Ptr{Cchar},
		(Ptr{Nothing}, UInt32), pointer, UInt32(index),
	)
	return take_string(raw)
end

function corpus_alignment_target_layer(pointer::Ptr{Nothing}, index::Integer)
	raw = ccall(
		(:montre_corpus_alignment_target_layer, libmontre), Ptr{Cchar},
		(Ptr{Nothing}, UInt32), pointer, UInt32(index),
	)
	return take_string(raw)
end

function corpus_alignment_directed(pointer::Ptr{Nothing}, index::Integer)
	result = ccall(
		(:montre_corpus_alignment_directed, libmontre), Int32,
		(Ptr{Nothing}, UInt32), pointer, UInt32(index),
	)
	result < 0 && return nothing
	return result != 0
end

function corpus_alignment_edges(pointer::Ptr{Nothing}, name::AbstractString)
	out_len = Ref{UInt64}(0)
	array = ccall(
		(:montre_corpus_alignment_edges, libmontre), Ptr{UInt32},
		(Ptr{Nothing}, Cstring, Ptr{UInt64}), pointer, name, out_len,
	)
	n = Int(out_len[])
	flat = take_u32_array(array, n * 4)
	return flat, n
end

function corpus_alignment_coverage(pointer::Ptr{Nothing}, alignment_name::AbstractString)
	out_doc_indices = Ref{Ptr{UInt32}}(C_NULL)
	out_aligned = Ref{Ptr{UInt32}}(C_NULL)
	out_total = Ref{Ptr{UInt32}}(C_NULL)
	out_len = Ref{UInt64}(0)
	ok = ccall(
		(:montre_corpus_alignment_coverage, libmontre), Int32,
		(Ptr{Nothing}, Cstring, Ptr{Ptr{UInt32}}, Ptr{Ptr{UInt32}}, Ptr{Ptr{UInt32}}, Ptr{UInt64}),
		pointer, alignment_name, out_doc_indices, out_aligned, out_total, out_len,
	)
	ok == 0 && return (; doc_indices = Int[], aligned = Int[], total = Int[])
	n = Int(out_len[])
	doc_indices = take_u32_array(out_doc_indices[], n)
	aligned = take_u32_array(out_aligned[], n)
	total = take_u32_array(out_total[], n)
	return (; doc_indices, aligned, total)
end

# ---- projection ----

function project(corpus::Ptr{Nothing}, hits::Ptr{Nothing}, alignment::AbstractString)
	out_unmapped = Ref{UInt64}(0)
	out_no_alignment = Ref{UInt64}(0)
	out_projected = Ref{UInt64}(0)
	result = ccall(
		(:montre_project, libmontre), Ptr{Nothing},
		(Ptr{Nothing}, Ptr{Nothing}, Cstring, Ptr{UInt64}, Ptr{UInt64}, Ptr{UInt64}),
		corpus, hits, alignment, out_unmapped, out_no_alignment, out_projected,
	)
	if result == C_NULL
		check_error()
		error("Montre: projection failed")
	end
	return (;
		pointer = result,
		unmapped = Int(out_unmapped[]),
		no_alignment = Int(out_no_alignment[]),
		projected = Int(out_projected[]),
	)
end

# ---- build ----

function build_directory(name::AbstractString, input_dir::AbstractString, output_dir::AbstractString;
	decompose_feats::Bool = false, strict::Bool = false,
)
	result = ccall(
		(:montre_build_directory, libmontre), Int32,
		(Cstring, Cstring, Cstring, Int32, Int32),
		name, input_dir, output_dir, Int32(decompose_feats), Int32(strict),
	)
	if result == 0
		check_error()
		error("Montre: build failed")
	end
end

function build_manifest(manifest_path::AbstractString, output_dir::AbstractString;
	decompose_feats::Bool = false, strict::Bool = false,
)
	result = ccall(
		(:montre_build_manifest, libmontre), Int32,
		(Cstring, Cstring, Int32, Int32),
		manifest_path, output_dir, Int32(decompose_feats), Int32(strict),
	)
	if result == 0
		check_error()
		error("Montre: build failed")
	end
end
