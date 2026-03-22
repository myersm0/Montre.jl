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

# ---- what's in here? ----

corpus
components(corpus)     # now includes per-component token counts
alignments(corpus)     # now includes layer info, directionality, edge counts
layers(corpus)
features(corpus)       # decomposed morphological feature layers (feats.*)
span_layers(corpus)    # sentence, document, paragraph, etc.

# ---- vocabulary exploration ----

vocabulary(corpus, "pos")          # all POS tags in the corpus
length(vocabulary(corpus, "lemma"))   # how many distinct lemmas?

# ---- basic querying ----

hits = query(corpus, cql"[pos='NOUN']")
concordance(hits; limit=10)

pairs = query(corpus, cql"[pos='ADJ'] [pos='NOUN']")
frequency(pairs; by="word")

# ---- component-filtered queries ----

fr_nouns = frequency(corpus, cql"[pos='NOUN']"; by="lemma", component="maupassant-fr")
first(fr_nouns, 20)

en_nouns = frequency(corpus, cql"[pos='NOUN']"; by="lemma", component="maupassant-en")
first(en_nouns, 20)

# count without materializing
count(corpus, cql"[pos='VERB']"; component="maupassant-fr")

# ---- multi-attribute queries ----

ame = query(corpus, cql"[lemma='âme' & pos='NOUN']"; component="maupassant-fr")
concordance(ame; limit=10)

colors = query(corpus, cql"[lemma=/^(noir|blanc|rouge|bleu|vert)$/ & pos='ADJ']"; component="maupassant-fr")
frequency(colors; by="lemma")
concordance(colors; limit=10)

# ---- morphological features ----

# if the corpus was built with --decompose-feats:
# query(corpus, cql"[feats.Number='Plur' & feats.Gender='Fem']"; component="maupassant-fr")

# ---- alignment projection ----

result = project(ame, "labse")
result                     # shows projection diagnostics
result.projected           # unique target sentences
result.no_alignment        # source hits with no alignment edge
result.unmapped            # source hits not locatable in source component

texts(result)
concordance(result; limit=10)

# ---- collocates ----

collocates(ame; window=5, layer="lemma")

positional = collocates(ame; window=5, layer="lemma", positional=true)
first(positional, 30)

# ---- bulk annotation access ----

# annotations for a range of positions
hit = ame[1]
annotations(corpus, hit.span, "pos")
annotations(corpus, hit.span, "lemma")

# ---- DataFrames integration ----

using DataFrames

hits = query(corpus, cql"[pos='ADJ'] [pos='NOUN']")
df = DataFrame(hits)
df.text = texts(hits)
df.lemma = texts(hits; layer="lemma")

fr_conc = DataFrame(concordance(ame; limit=20))
en_conc = DataFrame(concordance(result; limit=20))

# ---- build a corpus from Julia ----

# single-component build:
# Montre.build("data/conllu/", "my-corpus/"; name="maupassant", decompose_feats=true)

# multi-component build from manifest:
# Montre.build("corpus.toml", "my-corpus/")

close(corpus)
