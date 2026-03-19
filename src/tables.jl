import Tables

# ---- HitList as table ----

Tables.istable(::Type{HitList}) = true
Tables.rowaccess(::Type{HitList}) = true
Tables.rows(hitlist::HitList) = hitlist

const hit_columns = (:start, :stop, :document_index, :sentence_index)
const hit_types = (Int, Int, Int, Int)

Tables.schema(::HitList) = Tables.Schema(hit_columns, hit_types)
Tables.columnnames(::Hit) = hit_columns

function Tables.getcolumn(hit::Hit, name::Symbol)
	name === :start && return first(hit.span)
	name === :stop && return last(hit.span)
	getfield(hit, name)
end

function Tables.getcolumn(hit::Hit, index::Int)
	Tables.getcolumn(hit, hit_columns[index])
end

Tables.getcolumn(hit::Hit, ::Type, col::Int, ::Symbol) = Tables.getcolumn(hit, col)

# ---- Concordance as table ----

Tables.istable(::Type{Concordance}) = true
Tables.rowaccess(::Type{Concordance}) = true
Tables.rows(conc::Concordance) = conc.lines

const concordance_columns = (:document, :position, :left, :match_text, :right)
const concordance_types = (String, Int, String, String, String)

Tables.schema(::Concordance) = Tables.Schema(concordance_columns, concordance_types)
Tables.columnnames(::ConcordanceLine) = concordance_columns

Tables.getcolumn(line::ConcordanceLine, name::Symbol) = getfield(line, name)
Tables.getcolumn(line::ConcordanceLine, index::Int) = getfield(line, concordance_columns[index])
Tables.getcolumn(line::ConcordanceLine, ::Type, col::Int, ::Symbol) = Tables.getcolumn(line, col)
