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

## what's in here?

corpus
components(corpus)
alignments(corpus)
layers(corpus)

## Basic querying

hits = query(corpus, cql"[pos='NOUN']")
concordance(hits; limit=10)

# adjective-noun pairs
pairs = query(corpus, cql"[pos='ADJ'] [pos='NOUN']")
frequency(corpus, cql"[pos='ADJ'] [pos='NOUN']"; by="word")

## component-filtered queries

fr_nouns = frequency(corpus, cql"[pos='NOUN']"; by="lemma", component="maupassant-fr")
first(fr_nouns, 20)

en_nouns = frequency(corpus, cql"[pos='NOUN']"; by="lemma", component="maupassant-en")
first(en_nouns, 20)

## multi-attribute queries

# find "âme" used as a noun
ame = query(corpus, cql"[lemma='âme' & pos='NOUN']"; component="maupassant-fr")
concordance(ame; limit=10)

# color adjectives via regex alternation
colors = query(corpus, cql"[lemma=/^(noir|blanc|rouge|bleu|vert)$/ & pos!='ADJ']"; component="maupassant-fr")
frequency(colors; by="lemma")
concordance(colors; limit=10)

## alignment projection

# query French, see the English translations
translated = project(ame, "labse")
concordance(translated; limit=10)

## collocates

# what words appear near "âme" in a ±5 token window?
collocates(ame; window=5, layer="lemma")

# positional distribution: where do collocates appear relative to "âme"?
positional = collocates(ame; window=5, layer="lemma", positional=true)
first(positional, 30)

## DataFrames integration

using DataFrames

fr_conc = DataFrame(concordance(ame; limit=20))
en_conc = DataFrame(concordance(translated; limit=20))

close(corpus)

