import Tables

# ---- Concordance ----

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
