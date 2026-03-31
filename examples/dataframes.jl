# DataFrame workflows with Montre
#
# Extract structured data from query results into DataFrames,
# then analyze with DataFramesMeta. Shows capture lambdas,
# vector-valued columns, flatten, cross-tabs, and projection.
#
# Uses the Maupassant parallel corpus artifact.

using Montre
using DataFrames
using DataFramesMeta
using LazyArtifacts

corpus = Montre.open(artifact"maupassant_corpus")


# ════════════════════════════════════════════════════════════
# Example 1: noun coordination — a:[pos="NOUN"] [lemma="et"] b:[pos="NOUN"]
# ════════════════════════════════════════════════════════════

pairs = query(corpus, CQL("a:[pos='NOUN'] [lemma='et'] b:[pos='NOUN']"); component = "maupassant-fr")

# ── extract capture content into columns ──

df = extract(pairs, DataFrame,
	(x -> first(x["a", :lemma])) => :left,
	(x -> first(x["b", :lemma])) => :right,
	:document,
)

# ── most common pairings ──

@chain df begin
	@rtransform(:pair = :left * " et " * :right)
	groupby(:pair)
	@combine(:count = length(:pair))
	@orderby(-:count)
	first(20)
end

# ── are pairings symmetric? normalize order ──

@chain df begin
	@rtransform(:canonical = join(sort([:left, :right]), " et "))
	groupby(:canonical)
	@combine(:count = length(:canonical))
	@orderby(-:count)
	first(20)
end

# ── which stories use the most coordinated noun pairs? ──

@chain df begin
	groupby(:document)
	@combine(:count = length(:document))
	@orderby(-:count)
	first(10)
end

# ── project to English: how does the translator render these pairs? ──

en = project(pairs, "labse")
en_df = extract(en, DataFrame, :word => join, :document)
first(en_df, 20)


# ════════════════════════════════════════════════════════════
# Example 2: singular → plural echo within a sentence
#
# a:[pos="NOUN" & feats.Number="Sing"]
#   gap:[]{0,15}
# b:[pos="NOUN" & feats.Number="Plur"]
#   :: a.lemma = b.lemma within s
# ════════════════════════════════════════════════════════════

echoes = query(corpus,
	CQL("a:[pos='NOUN' & feats.Number='Sing'] gap:[]{0,15} b:[pos='NOUN' & feats.Number='Plur'] within s :: a.lemma = b.lemma");
	component = "maupassant-fr",
)

# ── which nouns do this? ──

df = extract(echoes, DataFrame,
	(x -> first(x["a", :lemma])) => :lemma,
	(x -> first(x["a", :word])) => :singular,
	(x -> first(x["b", :word])) => :plural,
	:width,
	:document,
)

@chain df begin
	groupby(:lemma)
	@combine(:count = length(:lemma))
	@orderby(-:count)
	first(20)
end

# ── how far apart are they? ──

@chain df begin
	groupby(:width)
	@combine(:count = length(:width))
	@orderby(:width)
end

# ── what fills the gap between singular and plural? ──

gap_df = extract(echoes, DataFrame,
	(x -> first(x["a", :lemma])) => :lemma,
	(x -> x["gap", :word]) => :gap_words,
	(x -> x["gap", :pos]) => :gap_pos,
)
exploded = flatten(gap_df, [:gap_words, :gap_pos])

@chain exploded begin
	groupby(:gap_pos)
	@combine(:count = length(:gap_pos))
	@orderby(-:count)
end

@chain exploded begin
	groupby([:lemma, :gap_words])
	@combine(:count = length(:gap_words))
	@orderby(-:count)
	first(30)
end

# ── cross-tab: lemmas × gap widths ──

counts = combine(groupby(df, [:lemma, :width]), nrow => :count)
unstack(counts, :lemma, :width, :count; fill = 0)

# ── project to English: does the translator preserve the echo? ──

en_echoes = project(echoes, "labse")
en_df = extract(en_echoes, DataFrame, :word => join, :document)
first(en_df, 20)

concordance(en_echoes; limit = 10)


# ════════════════════════════════════════════════════════════
# Example 3: basic extract patterns
# ════════════════════════════════════════════════════════════

hits = query(corpus, cql"[pos='ADJ'] [pos='NOUN']")

# ── layer reductions: join, first, collect ──

extract(hits, DataFrame,
	:word => join,
	:lemma => first,
	:pos => collect,
	:document,
	:width,
)

# ── single column, no DataFrame overhead ──

extract(hits, Vector, :word => join)
extract(hits, Vector, :document)

# ── concordance to DataFrame via Tables.jl ──

DataFrame(concordance(hits; limit = 20))

close(corpus)
