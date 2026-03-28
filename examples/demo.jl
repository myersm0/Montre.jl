# Montre.jl demo: querying a parallel literary corpus
#
# This script assumes a multi-component corpus with French and English
# components and sentence-level alignments, such as the Isosceles
# Maupassant parallel corpus.
#
# Adjust the corpus path, component names, and alignment name to match
# your data.

using Montre
using UniversalDependencies

corpus_path = expanduser("~/path/to/your-corpus")
corpus = Montre.open(corpus_path)

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
token_count(corpus; document = "allouma.conllu")
token_count(corpus; component = "maupassant-fr", document = "allouma.conllu")

document_count(corpus)
document_count(corpus; component = "maupassant-fr")

sentence_count(corpus)
sentence_count(corpus; component = "maupassant-fr")
sentence_count(corpus; document = "allouma.conllu")

component_count(corpus)

# ── vocabulary ──

vocabulary(corpus, :pos)
vocabulary(corpus, :lemma; top = 20)

# ── basic querying ──

# TODO: should be able to do indexing and iteration on HitList
hits = query(corpus, cql"[pos='NOUN']")
concordance(hits; limit = 10)

pairs = query(corpus, cql"[pos='ADJ'] [pos='NOUN']")
frequency(pairs; by = :word)

# ── component-filtered queries ──

fr_nouns = frequency(corpus, cql"[pos='NOUN']"; by = :lemma, component = "maupassant-fr")

en_nouns = frequency(corpus, cql"[pos='NOUN']"; by = :lemma, component = "maupassant-en")

count(corpus, cql"[pos='VERB']"; component = "maupassant-fr")

# ── multi-attribute queries ──

ame = query(corpus, cql"[lemma='âme' & pos='NOUN']"; component = "maupassant-fr")
concordance(ame; limit = 10)

colors = query(corpus, cql"[lemma=/^(noir|blanc|rouge|bleu|vert)$/ & pos='ADJ']"; component = "maupassant-fr")
frequency(colors; by = :lemma)
concordance(colors; limit = 10)

# ── labeled captures and global constraints ──

repeated = query(corpus, CQL("a:[pos='NOUN'] []{0,10} b:[pos='NOUN'] :: a.lemma = b.lemma"); component = "maupassant-fr")

# inspect a single hit as UD nodes
nodes = tokens(repeated, 42)
UD.form(nodes[1])
UD.upos(nodes[1])
UD.feats(nodes[1])

# render as a CoNLL-U table
render(TableStyle(), nodes)

# bulk column extraction
column(repeated, :lemma)
column(repeated, "a", :lemma)
frequency(repeated; by = :lemma)
concordance(repeated; limit = 10)

# captures
captures(repeated)
# TODO: this returns integer ranges which are not useful to user:
captures(repeated, "a")

# ── alignment projection ──

# TODO: this returns a ProjectionResult, which doesn't have any getindex methods.
# Also consider unifying HitList and ProjectionResult — they share the same interaction pattern 
# (indexing, iteration, column, captures, frequency, collocates, concordance). 
# Options: common abstract supertype, or just store diagnostics as optional fields on HitList 
# (projection results are hits with extra metadata)
result = project(ame, "labse")
result
result.projected
result.no_alignment
result.unmapped

column(result, :word)
concordance(result; limit = 10)

# ── alignment edges ──

alignment_data = edges(corpus, "labse")
first(alignment_data, 5)

# ── collocates ──

collocates(ame; window = 5, layer = :lemma)

positional = collocates(ame; window = 5, layer = :lemma, positional = true)
first(positional, 30)

# ── per-token annotation via UD nodes ──

nodes = tokens(ame, 1)
[UD.upos(n) for n in nodes]
[UD.lemma(n) for n in nodes]
UD.feats(nodes[1])

# ── DataFrames integration ──

using DataFrames

fr_conc = DataFrame(concordance(ame; limit = 20))
en_conc = DataFrame(concordance(result; limit = 20))

# ── build a corpus from Julia ──

# single-component build:
# Montre.build("data/conllu/", "my-corpus/"; name="maupassant", decompose_feats=true)

# multi-component build from manifest:
# Montre.build("corpus.toml", "my-corpus/")

close(corpus)
