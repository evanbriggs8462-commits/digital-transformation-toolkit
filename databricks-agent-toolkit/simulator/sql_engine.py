"""Small, deterministic, read-only SQL evaluator for the offline simulator."""

import json
import re
from decimal import Decimal, InvalidOperation


class SQLExecutionError(Exception):
    def __init__(self, code, message):
        Exception.__init__(self, message)
        self.code = code
        self.message = message


_DENIED = re.compile(
    r"\b(ALTER|CALL|COPY|CREATE|DELETE|DROP|GRANT|INSERT|MERGE|OPTIMIZE|"
    r"PUT|REFRESH|REMOVE|RESTORE|REVOKE|SET|TRUNCATE|UNDROP|UPDATE|USE|VACUUM)\b",
    re.IGNORECASE,
)
_ALLOWED_FIRST = {"SELECT", "SHOW", "DESCRIBE", "DESC", "EXPLAIN", "WITH", "VALUES"}
_PARAMETER = re.compile(r"(?<!:):([A-Za-z_][A-Za-z0-9_]*)")


def _code_only(sql):
    """Replace quoted text/comments with spaces while preserving token positions."""
    out = []
    i = 0
    mode = "code"
    while i < len(sql):
        c = sql[i]
        n = sql[i + 1] if i + 1 < len(sql) else ""
        if mode == "code":
            if c == "'":
                mode = "single"
                out.append(" ")
            elif c == '"':
                mode = "double"
                out.append(" ")
            elif c == "`":
                mode = "backtick"
                out.append(" ")
            elif c == "-" and n == "-":
                mode = "line_comment"
                out.extend((" ", " "))
                i += 1
            elif c == "/" and n == "*":
                mode = "block_comment"
                out.extend((" ", " "))
                i += 1
            else:
                out.append(c)
        elif mode == "single":
            out.append(" ")
            if c == "'" and n == "'":
                out.append(" ")
                i += 1
            elif c == "'":
                mode = "code"
        elif mode == "double":
            out.append(" ")
            if c == '"' and n == '"':
                out.append(" ")
                i += 1
            elif c == '"':
                mode = "code"
        elif mode == "backtick":
            out.append(" ")
            if c == "`":
                mode = "code"
        elif mode == "line_comment":
            out.append("\n" if c == "\n" else " ")
            if c == "\n":
                mode = "code"
        else:
            out.append(" ")
            if c == "*" and n == "/":
                out.append(" ")
                i += 1
                mode = "code"
        i += 1
    if mode in ("single", "double", "backtick", "block_comment"):
        raise SQLExecutionError("PARSE_SYNTAX_ERROR", "Unterminated quote or block comment.")
    return "".join(out)


def validate_read_only(sql):
    if not isinstance(sql, str) or not sql.strip():
        raise SQLExecutionError("INVALID_PARAMETER_VALUE", "statement must be a non-empty string")
    code = _code_only(sql)
    statements = [part for part in code.split(";") if part.strip()]
    if len(statements) != 1:
        raise SQLExecutionError("MULTI_STATEMENT_UNSUPPORTED", "Exactly one read-only SQL statement is allowed.")
    words = re.findall(r"[A-Za-z_]+", statements[0])
    if not words or words[0].upper() not in _ALLOWED_FIRST:
        first = words[0].upper() if words else "UNKNOWN"
        raise SQLExecutionError("READ_ONLY_VIOLATION", "Only read-only SQL is allowed; found %s." % first)
    denied = _DENIED.search(statements[0])
    if denied:
        raise SQLExecutionError(
            "READ_ONLY_VIOLATION",
            "SQL keyword %s is disabled by the simulator read-only policy." % denied.group(1).upper(),
        )
    return True


def normalize_parameters(raw_parameters, sql):
    if raw_parameters is None:
        raw_parameters = []
    if not isinstance(raw_parameters, list):
        raise SQLExecutionError("INVALID_PARAMETER_VALUE", "parameters must be an array")
    values = {}
    types = {}
    for item in raw_parameters:
        if not isinstance(item, dict) or not item.get("name"):
            raise SQLExecutionError("INVALID_PARAMETER_VALUE", "Each parameter needs a name and value.")
        name = str(item["name"])
        if name in values:
            raise SQLExecutionError("INVALID_PARAMETER_VALUE", "Duplicate named parameter: %s" % name)
        type_name = str(item.get("type", "STRING")).upper()
        value = item.get("value")
        values[name] = _convert_parameter(value, type_name, name)
        types[name] = type_name
    code = _code_only(sql)
    required = set(_PARAMETER.findall(code))
    missing = sorted(required.difference(values))
    if missing:
        raise SQLExecutionError(
            "UNBOUND_SQL_PARAMETER",
            "Missing named parameter(s): %s" % ", ".join(missing),
        )
    return values, types


def _convert_parameter(value, type_name, name):
    if value is None:
        return None
    try:
        if type_name in ("TINYINT", "SMALLINT", "INT", "INTEGER", "BIGINT", "LONG"):
            return int(value)
        if type_name in ("FLOAT", "DOUBLE"):
            return float(value)
        if type_name.startswith("DECIMAL"):
            return str(Decimal(str(value)))
        if type_name == "BOOLEAN":
            if isinstance(value, bool):
                return value
            text = str(value).lower()
            if text not in ("true", "false"):
                raise ValueError()
            return text == "true"
        if type_name in ("STRING", "DATE", "TIMESTAMP", "TIMESTAMP_NTZ", "BINARY"):
            return str(value)
    except (ValueError, TypeError, InvalidOperation):
        raise SQLExecutionError(
            "INVALID_PARAMETER_VALUE",
            "Value for parameter %s is not valid for %s." % (name, type_name),
        )
    raise SQLExecutionError("INVALID_PARAMETER_VALUE", "Unsupported parameter type: %s" % type_name)


def _split_csv(text):
    parts = []
    current = []
    depth = 0
    quote = None
    i = 0
    while i < len(text):
        c = text[i]
        if quote:
            current.append(c)
            if c == quote:
                if i + 1 < len(text) and text[i + 1] == quote:
                    current.append(text[i + 1])
                    i += 1
                else:
                    quote = None
        elif c in ("'", '"'):
            quote = c
            current.append(c)
        elif c == "(":
            depth += 1
            current.append(c)
        elif c == ")":
            depth -= 1
            current.append(c)
        elif c == "," and depth == 0:
            parts.append("".join(current).strip())
            current = []
        else:
            current.append(c)
        i += 1
    if current:
        parts.append("".join(current).strip())
    return parts


def _strip_identifier(value):
    return ".".join(part.strip().strip("`") for part in value.strip().split("."))


def _type_for_value(value, parameter_type=None):
    if parameter_type:
        base = parameter_type.split("(", 1)[0]
        return "INT" if base == "INTEGER" else base
    if value is None:
        return "STRING"
    if isinstance(value, bool):
        return "BOOLEAN"
    if isinstance(value, int):
        return "BIGINT"
    if isinstance(value, float):
        return "DOUBLE"
    return "STRING"


def _column(name, position, type_name, type_text=None):
    return {
        "name": name,
        "position": position,
        "type_name": type_name,
        "type_text": type_text or type_name.lower(),
    }


def _eval_scalar(expression, parameters, parameter_types):
    expression = expression.strip()
    alias_match = re.match(r"(?is)^(.*?)(?:\s+AS\s+|\s+)(`?[A-Za-z_][A-Za-z0-9_]*`?)$", expression)
    if alias_match:
        base = alias_match.group(1).strip()
        alias = alias_match.group(2).strip("`")
    else:
        base = expression
        alias = None
    if re.match(r"(?is)^current_user\s*\(\s*\)$", base):
        return alias or "current_user()", "agent@simulated.invalid", "STRING"
    if re.match(r"(?is)^current_catalog\s*\(\s*\)$", base):
        return alias or "current_catalog()", "main", "STRING"
    if re.match(r"(?is)^current_schema\s*\(\s*\)$", base):
        return alias or "current_schema()", "analytics", "STRING"
    pm = re.match(r"^:([A-Za-z_][A-Za-z0-9_]*)$", base)
    if pm:
        name = pm.group(1)
        return alias or name, parameters[name], _type_for_value(parameters[name], parameter_types[name])
    if re.match(r"^-?[0-9]+$", base):
        return alias or base, int(base), "BIGINT"
    if re.match(r"^-?[0-9]+\.[0-9]+$", base):
        return alias or base, float(base), "DOUBLE"
    if base.upper() in ("TRUE", "FALSE"):
        return alias or base.lower(), base.upper() == "TRUE", "BOOLEAN"
    if base.upper() == "NULL":
        return alias or "NULL", None, "STRING"
    if len(base) >= 2 and base[0] == "'" and base[-1] == "'":
        return alias or base, base[1:-1].replace("''", "'"), "STRING"
    raise SQLExecutionError("SIMULATOR_SQL_UNSUPPORTED", "Unsupported simulated SELECT expression: %s" % base)


def evaluate(sql, state, parameters, parameter_types):
    """Return (columns, rows) or raise a SQL execution failure."""
    validate_read_only(sql)
    if re.search(r"SIMULATE\s*:\s*FAIL", sql, re.IGNORECASE):
        raise SQLExecutionError("SIMULATED_EXECUTION_ERROR", "Requested deterministic simulated failure.")
    cleaned = re.sub(r"/\*.*?\*/", " ", sql, flags=re.DOTALL)
    cleaned = re.sub(r"--[^\r\n]*", " ", cleaned).strip().rstrip(";").strip()

    show_catalogs = re.match(r"(?is)^SHOW\s+CATALOGS\s*$", cleaned)
    if show_catalogs:
        rows = [[name] for name in sorted(state["catalogs"])]
        return [_column("catalog", 0, "STRING")], rows
    show_schemas = re.match(r"(?is)^SHOW\s+SCHEMAS(?:\s+(?:IN|FROM)\s+([`\w]+))?\s*$", cleaned)
    if show_schemas:
        catalog = _strip_identifier(show_schemas.group(1) or "main")
        rows = [[obj["name"]] for obj in state["schemas"].values() if obj["catalog_name"] == catalog]
        return [_column("databaseName", 0, "STRING")], sorted(rows)
    show_tables = re.match(r"(?is)^SHOW\s+TABLES(?:\s+(?:IN|FROM)\s+([`\w.]+))?\s*$", cleaned)
    if show_tables:
        schema = _strip_identifier(show_tables.group(1) or "main.analytics")
        rows = []
        for obj in state["tables"].values():
            if "%s.%s" % (obj["catalog_name"], obj["schema_name"]) == schema:
                rows.append([obj["schema_name"], obj["name"], False])
        cols = [_column("database", 0, "STRING"), _column("tableName", 1, "STRING"), _column("isTemporary", 2, "BOOLEAN")]
        return cols, sorted(rows)
    describe = re.match(r"(?is)^(?:DESCRIBE|DESC)(?:\s+TABLE)?\s+([`\w.]+)\s*$", cleaned)
    if describe:
        table_name = _strip_identifier(describe.group(1))
        table = state["tables"].get(table_name)
        if not table:
            raise SQLExecutionError("TABLE_OR_VIEW_NOT_FOUND", "Table or view not found: %s" % table_name)
        cols = [_column("col_name", 0, "STRING"), _column("data_type", 1, "STRING"), _column("comment", 2, "STRING")]
        return cols, [[c["name"], c["type_text"], c.get("comment")] for c in table["columns"]]
    if re.match(r"(?is)^EXPLAIN\b", cleaned):
        return [_column("plan", 0, "STRING")], [["Simulated read-only logical plan (no Spark execution)."]]
    if re.match(r"(?is)^WITH\b", cleaned):
        return [_column("simulated_result", 0, "STRING")], [["CTE accepted by read-only policy; offline evaluator returns a synthetic row."]]

    select_from = re.match(r"(?is)^SELECT\s+(.*?)\s+FROM\s+([`A-Za-z0-9_.]+)(.*)$", cleaned)
    if select_from:
        select_text = select_from.group(1).strip()
        table_name = _strip_identifier(select_from.group(2))
        tail = select_from.group(3)
        table = state["tables"].get(table_name)
        if not table:
            raise SQLExecutionError("TABLE_OR_VIEW_NOT_FOUND", "Table or view not found: %s" % table_name)
        source_columns = table["columns"]
        rows = [list(row) for row in state["table_rows"].get(table_name, [])]
        where = re.search(r"(?is)\bWHERE\s+(`?[A-Za-z_][A-Za-z0-9_]*`?)\s*=\s*(:[A-Za-z_][A-Za-z0-9_]*|'(?:''|[^'])*'|-?[0-9]+(?:\.[0-9]+)?)", tail)
        if where:
            col_name = where.group(1).strip("`")
            indexes = {col["name"].lower(): i for i, col in enumerate(source_columns)}
            if col_name.lower() not in indexes:
                raise SQLExecutionError("UNRESOLVED_COLUMN", "Column not found: %s" % col_name)
            token = where.group(2)
            if token.startswith(":"):
                wanted = parameters[token[1:]]
            elif token.startswith("'"):
                wanted = token[1:-1].replace("''", "'")
            elif "." in token:
                wanted = float(token)
            else:
                wanted = int(token)
            rows = [row for row in rows if row[indexes[col_name.lower()]] == wanted or str(row[indexes[col_name.lower()]]) == str(wanted)]
        count = re.match(r"(?is)^COUNT\s*\(\s*\*\s*\)(?:\s+AS\s+(`?[A-Za-z_][A-Za-z0-9_]*`?))?$", select_text)
        if count:
            alias = (count.group(1) or "count(1)").strip("`")
            return [_column(alias, 0, "BIGINT")], [[len(rows)]]
        if select_text == "*":
            columns = [dict(col) for col in source_columns]
        else:
            selected = _split_csv(select_text)
            index_by_name = {col["name"].lower(): i for i, col in enumerate(source_columns)}
            indexes = []
            columns = []
            for position, expression in enumerate(selected):
                match = re.match(r"(?is)^(`?[A-Za-z_][A-Za-z0-9_]*`?)(?:\s+AS\s+(`?[A-Za-z_][A-Za-z0-9_]*`?))?$", expression)
                if not match:
                    raise SQLExecutionError("SIMULATOR_SQL_UNSUPPORTED", "Only direct column projection is supported with FROM.")
                source_name = match.group(1).strip("`")
                if source_name.lower() not in index_by_name:
                    raise SQLExecutionError("UNRESOLVED_COLUMN", "Column not found: %s" % source_name)
                index = index_by_name[source_name.lower()]
                indexes.append(index)
                col = dict(source_columns[index])
                col["name"] = (match.group(2) or source_name).strip("`")
                col["position"] = position
                columns.append(col)
            rows = [[row[index] for index in indexes] for row in rows]
        limit = re.search(r"(?is)\bLIMIT\s+([0-9]+)\s*$", tail)
        if limit:
            rows = rows[: int(limit.group(1))]
        return columns, rows

    select_only = re.match(r"(?is)^SELECT\s+(.+)$", cleaned)
    if select_only:
        values = []
        columns = []
        for position, expression in enumerate(_split_csv(select_only.group(1))):
            name, value, type_name = _eval_scalar(expression, parameters, parameter_types)
            columns.append(_column(name, position, type_name))
            values.append(value)
        return columns, [values]
    if re.match(r"(?is)^VALUES\b", cleaned):
        return [_column("col1", 0, "STRING")], [["Simulated VALUES result"]]
    raise SQLExecutionError("SIMULATOR_SQL_UNSUPPORTED", "The statement is read-only but outside the simulator's small SQL subset.")


def truncate_rows(rows, row_limit, byte_limit):
    limited = list(rows)
    truncated = False
    if row_limit is not None and len(limited) > row_limit:
        limited = limited[:row_limit]
        truncated = True
    if byte_limit is not None:
        kept = []
        used = 0
        for row in limited:
            size = len(json.dumps(row, ensure_ascii=False, separators=(",", ":")).encode("utf-8"))
            if used + size > byte_limit:
                truncated = True
                break
            kept.append(row)
            used += size
        limited = kept
    return limited, truncated
