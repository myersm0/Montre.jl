using Test
using Montre
using DataFrames
using LazyArtifacts
using UniversalDependencies
import Tables

@testset "Montre.jl" begin

	# ── unit tests (no corpus needed) ──

	@testset "CQL strings" begin
		q = cql"[pos='NOUN']"
		@test q isa CQL
		@test q.query == """[pos="NOUN"]"""

		q2 = cql"[pos='ADJ'] [pos='NOUN']"
		@test q2.query == """[pos="ADJ"] [pos="NOUN"]"""

		@test repr(q) == """cql"[pos='NOUN']" """[1:end-1]
	end

	@testset "Concordance Tables.jl" begin
		line = ConcordanceLine("le vieux", "chat", "dormait", "poeme.conllu", 100)
		@test Tables.getcolumn(line, :match_text) == "chat"
		@test Tables.getcolumn(line, :document) == "poeme.conllu"

		conc = Concordance([line])
		@test Tables.istable(typeof(conc))
		schema = Tables.schema(conc)
		@test schema.names == (:document, :position, :left, :match_text, :right)

		df = DataFrame(conc)
		@test nrow(df) == 1
		@test df.match_text[1] == "chat"
	end

	@testset "show methods" begin
		@test repr(Component("fr", "fr", 100)) == "Component(\"fr\", fr, 100 tokens)"
		@test contains(repr(Alignment("labse", "fr", "en", "sentence", "sentence", true, 50)), "→")
	end

	@testset "spec parsing" begin
		@test_throws ErrorException Montre.parse_spec(:lemma)
		spec = Montre.parse_spec(:document)
		@test spec.name == :document

		spec2 = Montre.parse_spec(:word => join)
		@test spec2.name == :word
	end

	# ── integration tests (artifact corpus) ──

	corpus_path = artifact"maupassant_corpus"
	corpus = Montre.open(corpus_path)

	@testset "corpus lifecycle" begin
		@test isopen(corpus)
		@test token_count(corpus) > 0

		c2 = Montre.open(corpus_path)
		close(c2)
		@test !isopen(c2)

		Montre.open(corpus_path) do c
			@test isopen(c)
			@test token_count(c) > 0
		end
	end

	@testset "introspection" begin
		@test token_count(corpus) > 100_000

		ls = layers(corpus)
		@test "word" in ls
		@test "lemma" in ls
		@test "upos" in ls
		@test "xpos" in ls

		docs = documents(corpus)
		@test length(docs) > 0
		@test all(d -> d isa String, docs)

		comps = components(corpus)
		@test length(comps) >= 2
		@test comps[1] isa Component

		comp_names = [c.name for c in comps]
		@test "maupassant-fr" in comp_names
		@test "maupassant-en" in comp_names

		aligns = alignments(corpus)
		@test length(aligns) >= 1
		@test aligns[1] isa Alignment
		@test aligns[1].name == "labse"

		sls = span_layers(corpus)
		@test "sentence" in sls
		@test "document" in sls

		pos_vocab = vocabulary(corpus, :upos)
		@test "NOUN" in pos_vocab
		@test "VERB" in pos_vocab
	end

	@testset "counting with filters" begin
		total = token_count(corpus)
		fr = token_count(corpus; component = "maupassant-fr")
		en = token_count(corpus; component = "maupassant-en")
		@test fr > 0
		@test en > 0
		@test fr + en == total

		fr_docs = document_count(corpus; component = "maupassant-fr")
		en_docs = document_count(corpus; component = "maupassant-en")
		@test fr_docs + en_docs == document_count(corpus)

		fr_sents = sentence_count(corpus; component = "maupassant-fr")
		@test fr_sents > 0

		doc_name = documents(corpus; component = "maupassant-fr")[1]
		doc_tokens = token_count(corpus; component = "maupassant-fr", document = doc_name)
		@test 0 < doc_tokens < fr
	end

	@testset "query and count" begin
		hits = query(corpus, cql"[pos='NOUN']")
		@test length(hits) > 0
		@test count(corpus, cql"[pos='NOUN']") == length(hits)

		fr_hits = query(corpus, cql"[pos='NOUN']"; component = "maupassant-fr")
		@test length(fr_hits) > 0
		@test length(fr_hits) < length(hits)
	end

	@testset "concordance" begin
		hits = query(corpus, cql"[pos='NOUN']")
		conc = concordance(hits; limit = 5)
		@test conc isa Concordance
		@test length(conc) == 5
		@test conc[1].match_text != ""
		@test conc[1].document != ""

		conc2 = concordance(corpus, cql"[pos='NOUN']"; limit = 3)
		@test length(conc2) == 3

		df = DataFrame(conc)
		@test nrow(df) == 5
	end

	@testset "frequency" begin
		hits = query(corpus, cql"[pos='ADJ'] [pos='NOUN']")
		freqs = frequency(hits)
		@test length(freqs) > 0
		@test freqs[1] isa NamedTuple
		@test haskey(freqs[1], :value)
		@test haskey(freqs[1], :count)
	end

	@testset "captures" begin
		hits = query(corpus, CQL("a:[pos='ADJ'] b:[pos='NOUN']"))
		@test length(hits) > 0

		names = captures(hits)
		@test names == ["a", "b"]

		spans_a = captures(hits, "a")
		@test spans_a[1] isa UnitRange{Int}
		@test length(spans_a) == length(hits)

		@test_throws KeyError captures(hits, "z")
	end

	@testset "extract — DataFrame" begin
		hits = query(corpus, cql"[pos='ADJ'] [pos='NOUN']")

		df = extract(hits, DataFrame,
			:word => join,
			:lemma => collect,
			:document,
			:width,
		)
		@test df isa DataFrame
		@test nrow(df) == length(hits)
		@test df.word[1] isa String
		@test df.lemma[1] isa Vector{String}
		@test length(df.lemma[1]) == 2
		@test df.document[1] isa String
		@test df.width[1] == 2
	end

	@testset "extract — capture lambdas" begin
		hits = query(corpus, CQL("a:[pos='ADJ'] b:[pos='NOUN']"))

		df = extract(hits, DataFrame,
			:word => join,
			(x -> first(x["a", :lemma])) => :adj_lemma,
			(x -> first(x["b", :lemma])) => :noun_lemma,
		)
		@test :adj_lemma in propertynames(df)
		@test :noun_lemma in propertynames(df)
		@test df.adj_lemma[1] isa String
	end

	@testset "extract — renamed columns" begin
		hits = query(corpus, cql"[pos='ADJ'] [pos='NOUN']")

		# todo: this is a bug in extract.jl, fix it
#		df = extract(hits, DataFrame,
#			(:word => join) => :matched_text,
#		)
#		@test :matched_text in propertynames(df)
	end

	@testset "extract — Vector" begin
		hits = query(corpus, cql"[pos='NOUN']")

		docs = extract(hits, Vector, :document)
		@test docs isa Vector{String}
		@test length(docs) == length(hits)

		words = extract(hits, Vector, :word => join)
		@test words isa Vector{String}
	end

	@testset "collocates and cooccurrences" begin
		hits = query(corpus, cql"[lemma='maison']"; component = "maupassant-fr")
		@test length(hits) > 0

		colls = collocates(hits; window = 5, layer = :lemma)
		@test length(colls) > 0
		@test haskey(colls[1], :token)
		@test haskey(colls[1], :position)
		@test haskey(colls[1], :count)

		coocc = Montre.cooccurrences(hits; window = 5, layer = :lemma)
		@test length(coocc) > 0
		@test haskey(coocc[1], :token)
		@test haskey(coocc[1], :count)
	end

	@testset "projection" begin
		fr_hits = query(corpus, cql"[pos='NOUN']"; component = "maupassant-fr")
		projected = project(fr_hits, "labse")
		@test projected isa HitList
		@test length(projected) > 0

		conc = concordance(projected; limit = 5)
		@test length(conc) > 0
	end

	@testset "tokens (UD nodes)" begin
		hits = query(corpus, cql"[pos='ADJ'] [pos='NOUN']")
		nodes = tokens(hits, 1)
		@test length(nodes) == 2
		@test nodes[1] isa UD.Node
	end

	@testset "CQL dispatch consistency" begin
		n_str = count(corpus, """[pos="NOUN"]""")
		n_cql = count(corpus, cql"[pos='NOUN']")
		@test n_str == n_cql
	end

	close(corpus)
end
