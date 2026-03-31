# core Montre.jl operations
#
# Engine-centric workflow: open a corpus, inspect it, query it,
# and work with results using built-in operations. No DataFrames needed.
#
# Uses the Maupassant parallel corpus artifact.

using Montre
using UniversalDependencies
using LazyArtifacts

corpus = Montre.open(artifact"maupassant_corpus")

# ── corpus overview ──

corpus
components(corpus)
alignments(corpus)
layers(corpus)
features(corpus)
span_layers(corpus)

# ── counting ──

token_count(corpus)
token_count(corpus; component = "maupassant-fr")
token_count(corpus; component = "maupassant-en")
token_count(corpus; component = "maupassant-fr", document = "allouma.conllu")

document_count(corpus)
document_count(corpus; component = "maupassant-fr")

sentence_count(corpus)
sentence_count(corpus; component = "maupassant-fr")
sentence_count(corpus; document = "allouma.conllu")

# ── vocabulary ──

vocabulary(corpus, :pos)
vocabulary(corpus, :lemma)

# ── querying ──

hits = query(corpus, cql"[pos='NOUN']")
length(hits)

count(corpus, cql"[pos='NOUN']")
count(corpus, cql"[pos='VERB']"; component = "maupassant-fr")

ame = query(corpus, cql"[lemma='âme' & pos='NOUN']"; component = "maupassant-fr")

colors = query(corpus, cql"[lemma=/^(noir|blanc|rouge|bleu|vert)$/ & pos='ADJ']"; component = "maupassant-fr")

# ── concordance ──

concordance(hits; limit = 10)
concordance(ame; limit = 10)
concordance(corpus, cql"[pos='ADJ'] [pos='NOUN']"; limit = 5)

# ── frequency ──

pairs = query(corpus, cql"[pos='ADJ'] [pos='NOUN']")
frequency(pairs)
frequency(pairs; by = :lemma)
frequency(colors; by = :lemma)

# ── collocates ──

collocates(ame; window = 5, layer = :lemma)
cooccurrences(ame; window = 5, layer = :lemma)

# ── labeled captures and global constraints ──

repeated = query(corpus,
	CQL("a:[pos='NOUN'] []{0,10} b:[pos='NOUN'] :: a.lemma = b.lemma");
	component = "maupassant-fr",
)

# todo: reconsider the API for this
captures(repeated)
captures(repeated, "a")

concordance(repeated; limit = 10)
frequency(repeated; by = :lemma)

# ── per-token annotation via UD nodes ──

nodes = tokens(ame, 1)
UD.form(nodes[1])
UD.upos(nodes[1])
UD.feats(nodes[1])

nodes = tokens(pairs, 42)
[UD.form(n) for n in nodes]
[UD.upos(n) for n in nodes]

# ── alignment projection ──

projected = project(ame, "labse")
projected
concordance(projected; limit = 10)
frequency(projected; by = :lemma)

# ── alignment edges ──

edge_data = edges(corpus, "labse")
first(edge_data, 5)

# ── building a corpus from Julia ──

# single-component build from a directory of CoNLL-U files:
# Montre.build("data/conllu/", "my-corpus/"; name = "maupassant", decompose_feats = true)

# multi-component build from a TOML manifest:
# Montre.build("corpus.toml", "my-corpus/")

close(corpus)
