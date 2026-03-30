using Test
using Montre
using DataFrames
import Tables

@testset "Montre.jl" begin
	@testset "Hit basics" begin
		hit = Hit(10:14, 0, 3)
		@test first(hit.span) == 10
		@test last(hit.span) == 14
		@test length(hit.span) == 5
		@test hit.document_index == 0
		@test hit.sentence_index == 3
	end

	@testset "Hit show" begin
		hit = Hit(10:14, 0, 3)
		r = repr(hit)
		@test contains(r, "10:14")
		@test contains(r, "doc=0")
	end

	@testset "Concordance Tables.jl" begin
		line = ConcordanceLine("le vieux", "chat", "dormait", "poeme.conllu", 100)
		@test Tables.getcolumn(line, :match_text) == "chat"

		conc = Concordance([line])
		@test Tables.istable(typeof(conc))
		schema = Tables.schema(conc)
		@test schema.names == (:document, :position, :left, :match_text, :right)
	end

	@testset "show methods" begin
		@test repr(Component("fr", "fr", 100)) == "Component(\"fr\", fr, 100 tokens)"
		@test contains(repr(Alignment("labse", "fr", "en", "sentence", "sentence", true, 50)), "→")
	end

	@testset "CQL strings" begin
		q = cql"[pos='NOUN']"
		@test q isa CQL
		@test q.query == """[pos="NOUN"]"""

		q2 = cql"[pos='ADJ'] [pos='NOUN']"
		@test q2.query == """[pos="ADJ"] [pos="NOUN"]"""

		@test repr(q) == """cql"[pos='NOUN']" """[1:end-1]
	end

	@testset "spec parsing errors" begin
		@test_throws ErrorException Montre.parse_spec(:lemma)
		spec = Montre.parse_spec(:document)
		@test spec.name == :document
	end

	# ── integration tests (require a built corpus) ──

	corpus_path = get(ENV, "MONTRE_TEST_CORPUS", nothing)

	if corpus_path !== nothing
		@testset "corpus lifecycle" begin
			corpus = Montre.open(corpus_path)
			@test isopen(corpus)
			@test token_count(corpus) > 0
			close(corpus)
			@test !isopen(corpus)
		end

		@testset "query and iteration" begin
			Montre.open(corpus_path) do corpus
				hits = query(corpus, """[pos="NOUN"]""")
				@test length(hits) > 0
				@test hits[1] isa Hit
				@test hits[1].document_index isa Integer

				collected = collect(Iterators.take(hits, 3))
				@test length(collected) == 3
				@test all(h -> h isa Hit, collected)

				@test count(corpus, """[pos="NOUN"]""") == length(hits)
			end
		end

		@testset "document_name" begin
			Montre.open(corpus_path) do corpus
				hits = query(corpus, """[pos="NOUN"]""")
				length(hits) == 0 && return

				@test document_name(corpus, hits[1]) isa String
				@test document_name(hits, 1) isa String
				@test document_name(corpus, hits[1]) == document_name(hits, 1)
			end
		end

		@testset "captures" begin
			Montre.open(corpus_path) do corpus
				hits = query(corpus, CQL("a:[pos='ADJ'] b:[pos='NOUN']"))
				length(hits) == 0 && return

				@test captures(hits) == ["a", "b"]
				spans_a = captures(hits, "a")
				@test spans_a[1] isa UnitRange{Int}
				@test_throws KeyError captures(hits, "z")
			end
		end

		@testset "extract — layer => function" begin
			Montre.open(corpus_path) do corpus
				hits = query(corpus, """[pos="ADJ"] [pos="NOUN"]""")
				length(hits) == 0 && return

				df = extract(hits, DataFrame,
					:word => join,
					:lemma => first,
					:pos => collect,
				)
				@test df isa DataFrame
				@test nrow(df) == length(hits)
				@test df.word[1] isa String
				@test df.lemma[1] isa String
				@test df.pos[1] isa Vector{String}
				@test length(df.pos[1]) == 2
			end
		end

		@testset "extract — structural fields" begin
			Montre.open(corpus_path) do corpus
				hits = query(corpus, """[pos="NOUN"]""")
				length(hits) == 0 && return

				df = extract(hits, DataFrame, :document, :width, :sentence_index)
				@test df isa DataFrame
				@test nrow(df) == length(hits)
				@test df.document[1] isa String
				@test df.width[1] isa Int
			end
		end

		@testset "extract — lambda specs" begin
			Montre.open(corpus_path) do corpus
				hits = query(corpus, CQL("a:[pos='ADJ'] b:[pos='NOUN']"))
				length(hits) == 0 && return

				df = extract(hits, DataFrame,
					:word => join,
					(x -> first(x["a", :lemma])) => :adj_lemma,
					(x -> first(x["b", :lemma])) => :noun_lemma,
				)
				@test df isa DataFrame
				@test :adj_lemma in propertynames(df)
				@test :noun_lemma in propertynames(df)
			end
		end

		@testset "extract — renamed output" begin
			Montre.open(corpus_path) do corpus
				hits = query(corpus, """[pos="ADJ"] [pos="NOUN"]""")
				length(hits) == 0 && return

				df = extract(hits, DataFrame,
					:word => join => :matched_text,
					:lemma => join => :lemma_text,
				)
				@test :matched_text in propertynames(df)
				@test :lemma_text in propertynames(df)
			end
		end

		@testset "extract — Vector sink" begin
			Montre.open(corpus_path) do corpus
				hits = query(corpus, """[pos="NOUN"]""")
				length(hits) == 0 && return

				docs = extract(hits, Vector, :document)
				@test docs isa Vector{String}
				@test length(docs) == length(hits)

				words = extract(hits, Vector, :word => join)
				@test words isa Vector{String}
			end
		end

		@testset "frequency" begin
			Montre.open(corpus_path) do corpus
				hits = query(corpus, """[pos="ADJ"] [pos="NOUN"]""")
				length(hits) == 0 && return

				freqs = frequency(hits)
				@test freqs isa DataFrame
				@test :count in propertynames(freqs)
				@test freqs.count[1] >= freqs.count[end]
			end
		end

		@testset "concordance" begin
			Montre.open(corpus_path) do corpus
				conc = concordance(corpus, """[pos="NOUN"]"""; limit = 3)
				@test conc isa Concordance
				@test length(conc) <= 3
				@test conc[1].match_text != ""
			end
		end

		@testset "projection" begin
			corpus = Montre.open(corpus_path)
			if length(alignments(corpus)) > 0
				aligns = alignments(corpus)
				hits = query(corpus, """[pos="NOUN"]""")
				projected = project(corpus, hits, aligns[1].name)

				@test projected isa HitList
				@test length(projected) > 0
				@test projected[1] isa Hit
			end
			close(corpus)
		end

		@testset "CQL macro with corpus" begin
			Montre.open(corpus_path) do corpus
				hits_str = query(corpus, """[pos="NOUN"]""")
				hits_cql = query(corpus, cql"[pos='NOUN']")
				@test length(hits_cql) == length(hits_str)
			end
		end
	else
		@info "Skipping integration tests. Set MONTRE_TEST_CORPUS to a corpus path to enable."
	end
end
