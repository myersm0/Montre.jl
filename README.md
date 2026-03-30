# Montre.jl

[![Build Status](https://github.com/myersm0/Montre.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/myersm0/Montre.jl/actions/workflows/CI.yml?query=branch%3Amain)

Julia bindings for **[montre](https://github.com/myersm0/montre)**, a fast, embeddable query engine for annotated and parallel corpora.

Montre.jl lets you analyze linguistic corpora using CQL queries directly from Julia, without any server, daemon, or external process. The query engine runs in-process via a Rust shared library.

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
using DataFrames

corpus = Montre.open("./my-corpus")

hits = query(corpus, cql"[pos='ADJ'] [pos='NOUN']")
concordance(hits; limit = 10)

close(corpus)
```

## Inspecting a corpus

```julia
corpus = Montre.open("./my-corpus")

token_count(corpus)
layers(corpus)            # annotation layers: word, lemma, pos, ...
features(corpus)          # decomposed morphological features: feats.Number, feats.Gender, ...
documents(corpus)
components(corpus)        # subcorpora with per-component token counts
alignments(corpus)        # alignment relations with layer info and edge counts
span_layers(corpus)       # sentence, document, paragraph, ...
vocabulary(corpus, :pos)
```

Counting with filters:

```julia
token_count(corpus; component = "maupassant-fr")
token_count(corpus; document = "la-parure.conllu")
document_count(corpus; component = "maupassant-fr")
sentence_count(corpus; component = "maupassant-fr")
count(corpus, cql"[pos='VERB']"; component = "maupassant-fr")
```

## Querying

```julia
hits = query(corpus, cql"[pos='ADJ'] [pos='NOUN']")
hits = query(corpus, cql"[pos='NOUN']"; component = "maupassant-fr")
hits = query(corpus, cql"[lemma='être' & pos='VERB']")
hits = query(corpus, cql"[lemma=/^(noir|blanc|rouge)$/]")
```

`HitList` is an `AbstractVector{Hit}`. A `Hit` itself, however, is opaque to the user. 


## Extracting data

`extract` is the bridge between corpus results and DataFrames. It takes a `HitList`, a sink type, and column specs describing what to extract and how to reduce each span to a value:

```julia
using DataFrames

hits = query(corpus, cql"[pos='ADJ'] [pos='NOUN']")

extract(
    hits, DataFrame,
    :word => join,          # concatenate tokens: "petit chat"
    :lemma => first,        # first token's lemma: "petit"
    :pos => collect,        # keep as vector: ["ADJ", "NOUN"]
    :document,              # structural field, included as-is
    :width,                 # number of tokens in the match
)
```

Spec forms:

| Form | Meaning |
|------|---------|
| `:word => collect` | Fetch layer, apply function, auto-name column `:word` |
| `:word => collect => :text` | Same, but name the column `:text` |
| `(x -> ...) => :name` | Lambda with explicit column name |
| `:document` | Structural field (`:document`, `:width`, `:start`, `:stop`, `:sentence_index`) |

Bare annotation layers (e.g. `:lemma` without a function) are not allowed — you must specify how to reduce a multi-token span to a value.

For a single column without DataFrame overhead:

```julia
extract(hits, Vector, :word => join)    # Vector{String}
```

## Labeled captures

CQL labels mark subspans within a match. Access them through the lambda form in `extract`:

```julia
pairs = query(corpus, CQL("a:[pos='NOUN'] [lemma='et'] b:[pos='NOUN']"))

extract(
    pairs, DataFrame,
    (x -> first(x["a", :lemma])) => :left,
    (x -> first(x["b", :lemma])) => :right,
    :document,
)
```

Labels can also capture variable-length spans, including gaps between anchors:

```julia
hits = query(corpus,
    CQL("a:[pos='NOUN' & feats.Number='Sing'] gap:[]{0,15} b:[pos='NOUN' & feats.Number='Plur'] :: a.lemma = b.lemma within s");
    component = "maupassant-fr",
)

extract(
    hits, DataFrame,
    (x -> first(x["a", :lemma])) => :lemma,
    (x -> x["gap", :word]) => :gap_words,
    (x -> x["gap", :pos]) => :gap_pos,
    :width,
)
```

On a `Hit` object, captures are accessible by name:

```julia
hit = echoes[1]
hit["a"]               # UnitRange for the capture span
hit["b"]
haskey(hit, "gap")     # true
keys(hit)              # ["a", "gap", "b"]
```

## DataFrames workflows

`extract` produces standard DataFrames that work with [DataFramesMeta.jl](https://github.com/JuliaData/DataFramesMeta.jl) and the rest of the ecosystem:

```julia
using DataFramesMeta

hits = query(corpus, CQL("a:[pos='NOUN'] [lemma='et'] b:[pos='NOUN']"); component = "maupassant-fr")

df = extract(
    hits, DataFrame,
    (x -> first(x["a", :lemma])) => :left,
    (x -> first(x["b", :lemma])) => :right,
    :document,
)

# most common pairings
@chain df begin
    @rtransform(:pair = :left * " et " * :right)
    groupby(:pair)
    @combine(:count = length(:pair))
    @orderby(-:count)
    first(20)
end

# which stories use the most coordinated noun pairs?
@chain df begin
    groupby(:document)
    @combine(:count = length(:document))
    @orderby(-:count)
    first(10)
end
```

Vector-valued columns from `collect` can be expanded with `flatten`:

```julia
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
```

## Concordance

```julia
concordance(corpus, cql"[lemma='âme']"; context = 5, limit = 10)
concordance(hits; limit = 20)
```

```
allouma.conllu     les coins sombres de l' âme . -- Mais les femmes
allouma.conllu  nous appartenaient corps… âme . Je lui dis :
```

Concordances implement Tables.jl, so `DataFrame(concordance(hits))` works directly.

## Frequency

```julia
frequency(hits)                         # by joined word text, default
frequency(hits; by = :lemma => join)    # by joined lemma
frequency(hits; by = :pos => collect)   # by POS sequence
```

## Collocates

```julia
collocates(hits; window = 5, layer = :lemma)
collocates(hits; window = 5, layer = :lemma, positional = true)
```

## Alignment projection

Query one language and see the aligned translations:

```julia
ame = query(corpus, cql"[lemma='âme']"; component = "maupassant-fr")
projected = project(ame, "labse")

projected isa HitList      # true
is_projection(projected)   # true
projected.projected        # number of projected hits
projected.unmapped         # source hits not locatable
projected.no_alignment     # source hits with no alignment edge

concordance(projected; limit = 10)
extract(projected, DataFrame, :word => join, :document)
```

## CQL query strings

The `cql"..."` string macro avoids escaping. Use single quotes for attribute values — the macro converts them to double quotes:

```julia
query(corpus, cql"[pos='NOUN']")
query(corpus, cql"[lemma='être' & pos='VERB']")
query(corpus, cql"[lemma=/^(bleu|blanc)$/]")
```

For dynamic queries with interpolation, use the `CQL()` constructor:

```julia
lemma = "fleur"
query(corpus, CQL("[lemma='$(lemma)']"))
```

## Building corpora

Build corpora from Julia without the CLI:

```julia
Montre.build("data/conllu/", "my-corpus/"; name = "maupassant", decompose_feats = true)
Montre.build("corpus.toml", "my-corpus/")
```

## Resource management

```julia
Montre.open("./my-corpus") do corpus
    hits = query(corpus, cql"[pos='NOUN']")
    println(length(hits), " hits")
end
```

## How it works

`query` runs the CQL query in the Rust engine and returns a `HitList` — a Julia `AbstractVector{Hit}` backed by a fully materialized result set on the Rust side. Hit positions, document indices, and capture spans are extracted in bulk via the FFI immediately after the query.

`extract` is the bridge between the engine and DataFrames. Each column spec describes which layer or structural field to fetch and how to reduce a multi-token span to a per-hit value. Layer data is fetched from the Rust forward index on demand — only the layers you ask for are touched.

`project` returns a `HitList` with additional diagnostic fields (`projected`, `unmapped`, `no_alignment`). All the same operations — `extract`, `concordance`, `frequency`, `collocates` — work identically on projected results.

`close(corpus)` frees the Rust-side resources. Julia's garbage collector will clean up eventually, but `do`-blocks or explicit `close` are preferred.

## Requirements

- Julia 1.10+
- Montre engine ([install](https://github.com/myersm0/montre))
- A montre corpus (built with `montre build` or `Montre.build`)

## License

Apache-2.0
