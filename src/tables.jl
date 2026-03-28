import Tables

Tables.istable(::Type{Concordance}) = true
Tables.rowaccess(::Type{Concordance}) = true
Tables.rows(conc::Concordance) = conc.lines

const _concordance_columns = (:document, :position, :left, :match_text, :right)
const _concordance_types = (String, Int, String, String, String)

Tables.schema(::Concordance) = Tables.Schema(_concordance_columns, _concordance_types)
Tables.columnnames(::ConcordanceLine) = _concordance_columns

Tables.getcolumn(line::ConcordanceLine, name::Symbol) = getfield(line, name)
Tables.getcolumn(line::ConcordanceLine, index::Int) = getfield(line, _concordance_columns[index])
Tables.getcolumn(line::ConcordanceLine, ::Type, col::Int, ::Symbol) = Tables.getcolumn(line, col)
