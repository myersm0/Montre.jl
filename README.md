# Montre

[![Build Status](https://github.com/myersm0/Montre.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/myersm0/Montre.jl/actions/workflows/CI.yml?query=branch%3Amain)

Julia bindings for [Montre](https://github.com/myersm0/montre), a lightweight but powerful, embeddable query engine for annotated and parallel corpora.

Montre.jl lets you query corpora using CQL (Corpus Query Language) directly from Julia, with no server, daemon, or external process. The query engine runs in-process via a Rust shared library.

## Status

**Early prototype.** The API is functional but subject to change.

## Installation

Set `MONTRE_ROOT` to the root of the montre Rust workspace (the directory containing `Cargo.toml`), then:

```julia
ENV["MONTRE_ROOT"] = expanduser("~/path/to/montre")
using Pkg
Pkg.develop(path="/path/to/Montre.jl")
Pkg.build("Montre")
```

This compiles `montre-ffi` and writes the shared library path for Julia to load at runtime.

## Usage

```julia
using Montre

corpus = Montre.open("./my-corpus")

# inspect
token_count(corpus)
layers(corpus)
documents(corpus)
components(corpus)
alignments(corpus)

# query
hits = query(corpus, """[pos="ADJ"] [pos="NOUN"]""")
span_text(corpus, hits[1])
texts(hits)

# concordance
concordance(corpus, """[lemma="fleur"]"""; context=5, limit=10)

# frequency
frequency(corpus, """[pos="NOUN"]"""; by="lemma")

# count without materializing hits
count(corpus, """[pos="VERB"]""")

# alignment projection
projected = project(corpus, hits, "my-alignment")
texts(projected)

close(corpus)
```

A `do`-block form is also available for automatic cleanup:

```julia
Montre.open("./my-corpus") do corpus
    hits = query(corpus, """[pos="NOUN"]""")
    println(length(hits), " hits")
end
```

## DataFrames integration

Query results implement the [Tables.jl](https://github.com/JuliaData/Tables.jl) interface:

```julia
using DataFrames

df = DataFrame(query(corpus, """[pos="ADJ"] [pos="NOUN"]"""))
df.text = texts(query(corpus, """[pos="ADJ"] [pos="NOUN"]"""))
```

Concordance results work the same way:

```julia
df = DataFrame(concordance(corpus, """[lemma="noir"]"""))
```

## API summary

**Corpus lifecycle:** `Montro.open`, `close`, `isopen`

**Inspection:** `token_count`, `layers`, `documents`, `components`, `alignments`, `annotation`, `span_text`

**Querying:** `query`, `count`, `texts`, `concordance`, `frequency`

**Parallel corpora:** `project`

## Requirements

- Julia 1.10+
- A montre corpus (built with `montre build` from CoNLL-U data)

## License

Apache-2.0
