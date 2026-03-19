# Montre

[![Build Status](https://github.com/myersm0/Montre.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/myersm0/Montre.jl/actions/workflows/CI.yml?query=branch%3Amain)

Julia bindings for [Montre](https://github.com/myersm0/montre), a fast, embeddable query engine for annotated and parallel corpora.

Montre.jl lets you query corpora using CQL (Corpus Query Language) directly from Julia, with no server, daemon, or external process. The query engine runs in-process via a Rust shared library.

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
frequency(corpus, cql"[pos='NOUN']"; by="lemma")

close(corpus)
```

## Usage

### Inspecting a corpus

```julia
corpus = Montre.open("./my-corpus")

token_count(corpus)
layers(corpus)        # available annotation layers: word, lemma, pos, ...
documents(corpus)
components(corpus)
alignments(corpus)
```

### Querying

```julia
hits = query(corpus, cql"[pos='ADJ'] [pos='NOUN']")
span_text(corpus, hits[1])
texts(hits)

# restrict to a specific component
hits = query(corpus, cql"[pos='NOUN']"; component="baudelaire-fr")

# count without materializing hits
count(corpus, cql"[pos='VERB']")
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
frequency(corpus, cql"[pos='NOUN']"; by="lemma")
frequency(corpus, cql"[pos='NOUN']"; by="lemma", component="baudelaire-fr")
```

### Collocates

Find words that co-occur with your query target within a context window:

```julia
collocates(corpus, cql"[lemma='âme']"; window=5, layer="lemma")
```

With `positional=true`, results include relative position (negative = left of match, positive = right), enabling distributional analysis:

```julia
collocates(corpus, cql"[lemma='âme']"; window=5, layer="lemma", positional=true)
```

### Alignment projection

Query one language and see the aligned translations:

```julia
hits = query(corpus, cql"[lemma='âme']"; component="maupassant-fr")
translated = project(hits, "labse")
texts(translated)
concordance(translated)
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
query(corpus, cql"[lemma=/^(bleu|blanc|rouge)$/]")
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
```

```julia
df = DataFrame(concordance(corpus, cql"[lemma='âme']"))
```

## How it works

`query` runs the CQL query in the Rust engine and returns a `HitList` — a handle to a fully materialized result set on the Rust side. The hit positions (start, stop, document, sentence) are available immediately with minimal overhead.

Text and annotation data (word forms, lemmas, POS tags) are fetched on demand when you call `texts`, `concordance`, `frequency`, or `collocates`. Each of these makes a single bulk FFI call, so the cost is one round-trip per operation, not per hit.

`close(corpus)` frees the Rust-side resources. If you forget, Julia's garbage collector will clean up eventually, but `do`-blocks or explicit `close` are preferred.

## API summary

**Corpus lifecycle:** `Montre.open`, `close`, `isopen`

**Inspection:** `token_count`, `layers`, `documents`, `components`, `alignments`, `annotation`, `span_text`

**Querying:** `query`, `count`, `texts`, `concordance`, `frequency`, `collocates`

**Parallel corpora:** `project`

**CQL helpers:** `cql"..."`, `CQL()`

## Requirements

- Julia 1.10+
- Montre engine ([install](https://github.com/myersm0/montre))
- A montre corpus (built with `montre build` from CoNLL-U data)

## License

MIT
