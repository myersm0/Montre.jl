# Montre.jl demo: querying a parallel literary corpus
#
# This script assumes a multi-component corpus with French and English
# components and sentence-level alignments, such as the Isosceles
# Maupassant parallel corpus.
#
# Adjust the corpus path, component names, and alignment name to match
# your data.

using Montre

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

vocabulary(corpus, "pos")
vocabulary(corpus, "lemma"; top = 20)

# ── basic querying ──

hits = query(corpus, cql"[pos='NOUN']")
concordance(hits; limit = 10)

pairs = query(corpus, cql"[pos='ADJ'] [pos='NOUN']")
frequency(pairs; by = "word")

# ── component-filtered queries ──

fr_nouns = frequency(corpus, cql"[pos='NOUN']"; by = "lemma", component = "maupassant-fr")
first(fr_nouns, 20)

en_nouns = frequency(corpus, cql"[pos='NOUN']"; by = "lemma", component = "maupassant-en")
first(en_nouns, 20)

count(corpus, cql"[pos='VERB']"; component = "maupassant-fr")

# ── multi-attribute queries ──

ame = query(corpus, cql"[lemma='âme' & pos='NOUN']"; component = "maupassant-fr")
concordance(ame; limit = 10)

colors = query(corpus, cql"[lemma=/^(noir|blanc|rouge|bleu|vert)$/ & pos='ADJ']"; component = "maupassant-fr")
frequency(colors; by = "lemma")
concordance(colors; limit = 10)

# ── labeled captures and global constraints ──

repeated = query(corpus, CQL("a:[pos='NOUN'] []{0,10} b:[pos='NOUN'] :: a.lemma = b.lemma"); component = "maupassant-fr")
hit = repeated[1]
hit["a"]               # span of the first noun
hit["b"]               # span of the repeated noun
haskey(hit, "a")       # true
keys(hit)              # ["a", "b"]

span_text(corpus, hit["a"]; layer = "lemma")
span_text(corpus, hit["b"]; layer = "lemma")

# ── alignment projection ──

result = project(ame, "labse")
result
result.projected
result.no_alignment
result.unmapped

texts(result)
concordance(result; limit = 10)

# ── alignment edges ──

alignment_data = edges(corpus, "labse")
first(alignment_data, 5)

# ── collocates ──

collocates(ame; window = 5, layer = "lemma")

positional = collocates(ame; window = 5, layer = "lemma", positional = true)
first(positional, 30)

# ── bulk annotation access ──

hit = ame[1]
annotations(corpus, hit.span, "pos")
annotations(corpus, hit.span, "lemma")

# ── DataFrames integration ──

using DataFrames

hits = query(corpus, cql"[pos='ADJ'] [pos='NOUN']")
df = DataFrame(hits)
df.text = texts(hits)
df.lemma = texts(hits; layer = "lemma")

fr_conc = DataFrame(concordance(ame; limit = 20))
en_conc = DataFrame(concordance(result; limit = 20))

# ── build a corpus from Julia ──

# single-component build:
# Montre.build("data/conllu/", "my-corpus/"; name="maupassant", decompose_feats=true)

# multi-component build from manifest:
# Montre.build("corpus.toml", "my-corpus/")

close(corpus)
