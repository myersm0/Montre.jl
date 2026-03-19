using Test
using Montre
import Tables

@testset "Montre.jl" begin
	@testset "types" begin
		hit = Hit(10:14, 0, 3)
		@test first(hit.span) == 10
		@test last(hit.span) == 14
		@test length(hit.span) == 5

		comp = Component("baudelaire-fr", "fr")
		@test comp.name == "baudelaire-fr"
		@test comp.language == "fr"

		align = Alignment("labse", "baudelaire-fr", "baudelaire-en")
		@test align.source == "baudelaire-fr"
		@test align.target == "baudelaire-en"

		line = ConcordanceLine("the dark", "night", "was cold", "doc1.conllu", 42)
		@test line.match_text == "night"
		@test line.position == 42
	end

	@testset "Tables.jl interface — Hit" begin
		hit = Hit(10:14, 2, 7)

		@test Tables.columnnames(hit) == (:start, :stop, :document_index, :sentence_index)
		@test Tables.getcolumn(hit, :start) == 10
		@test Tables.getcolumn(hit, :stop) == 14
		@test Tables.getcolumn(hit, :document_index) == 2
		@test Tables.getcolumn(hit, :sentence_index) == 7
		@test Tables.getcolumn(hit, 1) == 10
		@test Tables.getcolumn(hit, 4) == 7
	end

	@testset "Tables.jl interface — ConcordanceLine" begin
		line = ConcordanceLine("le vieux", "chat", "dormait", "poeme.conllu", 100)

		@test Tables.columnnames(line) == (:document, :position, :left, :match_text, :right)
		@test Tables.getcolumn(line, :document) == "poeme.conllu"
		@test Tables.getcolumn(line, :match_text) == "chat"
		@test Tables.getcolumn(line, 1) == "poeme.conllu"
		@test Tables.getcolumn(line, 3) == "le vieux"
		@test Tables.getcolumn(line, 5) == "dormait"

		conc = Concordance([line])
		@test Tables.istable(typeof(conc))
		@test Tables.rowaccess(typeof(conc))
		schema = Tables.schema(conc)
		@test schema.names == (:document, :position, :left, :match_text, :right)
		@test schema.types == (String, Int, String, String, String)
	end

	@testset "show methods" begin
		@test repr(Hit(10:14, 0, 0)) == "Hit(10:14)"
		@test repr(Component("fr", "fr")) == "Component(\"fr\", fr)"
		@test contains(repr(Alignment("labse", "fr", "en")), "→")
	end

	@testset "CQL strings" begin
		q = cql"[pos='NOUN']"
		@test q isa CQL
		@test q.query == """[pos="NOUN"]"""

		q2 = cql"[pos='ADJ'] [pos='NOUN']"
		@test q2.query == """[pos="ADJ"] [pos="NOUN"]"""

		q3 = cql"[word='\d+$']"
		@test q3.query == "[word=\"\\d+\$\"]"

		lemma = "fleur"
		q4 = CQL("[lemma='$(lemma)']")
		@test q4.query == """[lemma="fleur"]"""

		@test repr(q) == """cql"[pos='NOUN']" """[1:end-1]
	end

	# ---- integration tests (require a built corpus) ----

	corpus_path = get(ENV, "MONTRE_TEST_CORPUS", nothing)

	if corpus_path !== nothing
		@testset "corpus lifecycle" begin
			corpus = Montre.open(corpus_path)
			@test isopen(corpus)
			@test token_count(corpus) > 0
			close(corpus)
			@test !isopen(corpus)
		end

		@testset "do-block" begin
			Montre.open(corpus_path) do corpus
				@test isopen(corpus)
				@test token_count(corpus) > 0
			end
		end

		@testset "inspection" begin
			corpus = Montre.open(corpus_path)
			@test length(layers(corpus)) > 0
			@test length(documents(corpus)) > 0

			comps = components(corpus)
			@test length(comps) > 0
			@test comps[1] isa Component

			close(corpus)
		end

		@testset "query" begin
			corpus = Montre.open(corpus_path)

			hits = query(corpus, """[pos="NOUN"]""")
			@test length(hits) > 0
			@test hits[1] isa Hit
			@test first(hits[1].span) >= 0

			t = texts(hits)
			@test length(t) == length(hits)
			@test t[1] isa String

			@test span_text(corpus, hits[1]) isa String

			n = count(corpus, """[pos="NOUN"]""")
			@test n == length(hits)

			close(corpus)
		end

		@testset "concordance" begin
			corpus = Montre.open(corpus_path)

			conc = concordance(corpus, """[pos="NOUN"]"""; limit=3)
			@test conc isa Concordance
			@test length(conc) <= 3
			@test conc[1] isa ConcordanceLine
			@test conc[1].match_text != ""

			close(corpus)
		end

		@testset "frequency" begin
			corpus = Montre.open(corpus_path)

			freqs = frequency(corpus, """[pos="NOUN"]"""; by="lemma")
			@test length(freqs) > 0
			@test freqs[1].count >= freqs[end].count

			close(corpus)
		end

		@testset "iteration" begin
			corpus = Montre.open(corpus_path)
			hits = query(corpus, """[pos="NOUN"]""")

			collected = collect(Iterators.take(hits, 3))
			@test length(collected) == 3
			@test all(h -> h isa Hit, collected)

			close(corpus)
		end

		@testset "CQL macro with corpus" begin
			Montre.open(corpus_path) do corpus
				hits_str = query(corpus, """[pos="NOUN"]""")
				hits_cql = query(corpus, cql"[pos='NOUN']")
				@test length(hits_cql) == length(hits_str)

				@test length(concordance(corpus, cql"[pos='NOUN']"; limit=3)) <= 3
				@test count(corpus, cql"[pos='NOUN']") == length(hits_cql)
				@test length(frequency(corpus, cql"[pos='NOUN']")) > 0
			end
		end

		corpus = Montre.open(corpus_path)
		if length(alignments(corpus)) > 0
			@testset "projection" begin
				aligns = alignments(corpus)
				@test aligns[1] isa Alignment

				hits = query(corpus, """[pos="NOUN"]""")
				projected = project(corpus, hits, aligns[1].name)
				@test length(projected) > 0
				@test projected[1] isa Hit

				pt = texts(projected)
				@test length(pt) == length(projected)
			end
		end
		close(corpus)
	else
		@info "Skipping integration tests. Set MONTRE_TEST_CORPUS to a corpus path to enable."
	end
end
