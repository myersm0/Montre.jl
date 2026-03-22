# Montre.jl

[![Build Status](https://github.com/myersm0/Montre.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/myersm0/Montre.jl/actions/workflows/CI.yml?query=branch%3Amain)

Julia bindings for **[montre]**(https://github.com/myersm0/montre), a fast, embeddable query engine for annotated and parallel corpora.

Montre.jl lets you analyze linguistic corpora using CQL-like queries directly from Julia, without any server, daemon, or external process. The query engine runs in-process via a Rust shared library.

## Status

**Early prototype.** The API is functional but subject to change.

## Installation

Install the montre engine:

```bash
curl -fsSL https://raw.githubusercontent.com/myersm0/montre/main/install.sh | sh
```

Then in Julia, set `MONTRE_ROOT` to the montre Rust workspace root and build:

```julia
ENV["MONTRE_ROOT"] = expanduser("~/path/to/montre")
using Pkg
Pkg.develop(path="path/to/Montre.jl")
Pkg.build("Montre")
```

## Quick start

```julia
using Montre

corpus = Montre.open("./my-corpus")

hits = query(corpus, cql"[pos='ADJ'] [pos='NOUN']")
concordance(hits; limit=10)
frequency(hits; by="lemma")

close(corpus)
```

## Usage

### Inspecting a corpus

```julia
corpus = Montre.open("./my-corpus")

token_count(corpus)
layers(corpus)           # annotation layers: word, lemma, pos, ...
features(corpus)         # decomposed morphological features: feats.Number, feats.Gender, ...
documents(corpus)
components(corpus)       # subcorpora with per-component token counts
alignments(corpus)       # alignment relations with layer info and edge counts
span_layers(corpus)      # sentence, document, paragraph, ...
vocabulary(corpus, "pos")  # all distinct values for a layer
```

### Querying

```julia
hits = query(corpus, cql"[pos='ADJ'] [pos='NOUN']")
texts(hits)
texts(hits; layer="lemma")

# restrict to a specific component
hits = query(corpus, cql"[pos='NOUN']"; component="maupassant-fr")

# multi-attribute queries
hits = query(corpus, cql"[lemma='être' & pos='VERB']")

# regex alternation
hits = query(corpus, cql"[lemma=/^(noir|blanc|rouge)$/]")

# count without materializing hits
count(corpus, cql"[pos='VERB']"; component="maupassant-fr")
```

### Concordance

`concordance` returns a KWIC (Key Word In Context) display that adapts to your terminal width:

```julia
concordance(corpus, cql"[lemma='âme']"; context=5, limit=10)
```

```
allouma.conllu     les coins sombres de l' âme . -- Mais les femmes
allouma.conllu  nous appartenaient corps… âme . Je lui dis :
```

Since `HitList` knows its corpus, you can also write:

```julia
hits = query(corpus, cql"[lemma='âme']")
concordance(hits)
```

### Frequency

```julia
frequency(corpus, cql"[pos='NOUN']"; by="lemma", component="maupassant-fr")

hits = query(corpus, cql"[pos='ADJ'] [pos='NOUN']")
frequency(hits; by="word")
```

### Collocates

Find words that co-occur with your query target within a context window:

```julia
collocates(corpus, cql"[lemma='âme']"; window=5, layer="lemma")
```

With `positional=true`, results include relative position (negative = left of match, positive = right):

```julia
collocates(hits; window=5, layer="lemma", positional=true)
```

### Alignment projection

Query one language and see the aligned translations:

```julia
ame = query(corpus, cql"[lemma='âme']"; component="maupassant-fr")
result = project(ame, "labse")

result.projected       # unique target sentences
result.no_alignment    # source hits with no alignment edge
result.unmapped        # source hits not locatable in source component

texts(result)
concordance(result)
```

### Bulk annotation access

Extract annotations for a range of token positions:

```julia
hit = hits[1]
annotations(corpus, hit.span, "pos")
annotations(corpus, hit.span, "lemma")
```

### Building corpora

Build corpora from Julia without the CLI:

```julia
Montre.build("data/conllu/", "my-corpus/"; name="maupassant", decompose_feats=true)
Montre.build("corpus.toml", "my-corpus/")   # multi-component from TOML manifest
```

### Resource management

A `do`-block form is available for automatic cleanup:

```julia
Montre.open("./my-corpus") do corpus
    hits = query(corpus, cql"[pos='NOUN']")
    println(length(hits), " hits")
end
```

## CQL query strings

The `cql"..."` string macro avoids escaping. Use single quotes for attribute values — the macro converts them to double quotes:

```julia
query(corpus, cql"[pos='NOUN']")
query(corpus, cql"[lemma='être' & pos='VERB']")
query(corpus, cql"[lemma=/^(bleu|blanc)$/]")
query(corpus, cql"[word='\d+$']")   # backslash and $ passed through literally
```

For dynamic queries with interpolation, use the `CQL()` constructor:

```julia
lemma = "fleur"
query(corpus, CQL("[lemma='$(lemma)']"))
```

Plain strings with triple-quoting also work:

```julia
query(corpus, """[pos="NOUN"]""")
```

## DataFrames integration

Query results and concordances implement the [Tables.jl](https://github.com/JuliaData/Tables.jl) interface:

```julia
using DataFrames

hits = query(corpus, cql"[pos='ADJ'] [pos='NOUN']")
df = DataFrame(hits)
df.text = texts(hits)
df.lemma = texts(hits; layer="lemma")
```

```julia
df = DataFrame(concordance(corpus, cql"[lemma='âme']"))
```

## How it works

`query` runs the CQL query in the Rust engine and returns a `HitList` — a handle to a fully materialized result set on the Rust side. The hit positions (start, stop, document, sentence) are available immediately with minimal overhead.

Text and annotation data (word forms, lemmas, POS tags) are fetched on demand when you call `texts`, `concordance`, `frequency`, or `collocates`. Each of these makes a single bulk FFI call, so the cost is one round-trip per operation, not per hit.

`project` returns a `ProjectionResult` containing the target-side hits plus diagnostic counts showing how many source hits mapped successfully, how many had no alignment edge, and how many couldn't be located in the source component.

`close(corpus)` frees the Rust-side resources. If you forget, Julia's garbage collector will clean up eventually, but `do`-blocks or explicit `close` are preferred.

## API summary

**Corpus lifecycle:** `Montre.open`, `close`, `isopen`, `Montre.build`

**Inspection:** `token_count`, `layers`, `features`, `documents`, `components`, `alignments`, `span_layers`, `vocabulary`, `annotation`, `annotations`, `span_text`

**Querying:** `query`, `count`, `texts`, `concordance`, `frequency`, `collocates`

**Parallel corpora:** `project`

**CQL helpers:** `cql"..."`, `CQL()`

## Requirements

- Julia 1.10+
- Montre engine ([install](https://github.com/myersm0/montre))
- A montre corpus (built with `montre build` or `Montre.build`)

## License

Apache-2.0
