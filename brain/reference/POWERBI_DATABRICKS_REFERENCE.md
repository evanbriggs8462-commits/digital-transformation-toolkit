---
id: brain.reference.powerbi-databricks
status: generic-reference
scope: local-powerbi-and-databricks
audience: [ai-agent, developer, analyst]
last_reviewed: 2026-08-20
---

# Power BI, Databricks, and Genie Reference

## 1. Tool responsibilities

```text
TE2              = what is in the semantic model?
DAX Studio/dscmd = what does the semantic model calculate?
PowerShell       = orchestration, timeout, logging, and validation
Databricks SQL   = what does the governed source calculate?
Python           = reconciliation, residual analysis, and evidence packaging
Genie            = workspace-aware natural-language and SQL reasoning
```

### TE2

Use for:

- tables and columns;
- hidden objects;
- measures and DAX definitions;
- relationships;
- partitions and M expressions;
- calculated columns/tables;
- semantic object descriptions and annotations.

### DAX Studio/dscmd

Use for actual evaluated results:

- dollar amounts;
- counts;
- percentages;
- measure values under filters;
- control totals;
- grouped result sets;
- DAX-versus-source comparison.

A numeric request is not complete when the agent merely prints a query while local execution is available.

## 2. Power BI execution flow

```text
Question
→ select exact open PBIX/PBIP
→ retrieve prior context
→ validate measure/filter objects through TE2
→ build read-only DAX
→ execute with dscmd
→ validate output
→ return result, filters, assumptions, and provenance
```

Power BI Desktop hosts an embedded Analysis Services model. Connection identity should be proven rather than guessed. Multiple open reports must require exact selection or deterministic matching.

## 3. Report-context limitation

DAX Studio can reproduce any filter context that is known and expressible in DAX. It does not automatically know every active report/page/visual filter, slicer state, bookmark, cross-selection, drillthrough context, Top N rule, or field-parameter state.

When the user asks about a visible number:

1. recover available report definition or supplied filters;
2. inspect the semantic measure;
3. reproduce the known context;
4. identify missing hidden/interactive context explicitly;
5. never invent filters.

PBIP/PBIR report definitions are promising sources for pages, visuals, configured fields, filters, bookmarks, and report structure. Desktop Bridge can support application identity and visual evidence where available, but preview APIs should be treated as optional observations rather than the sole control path.

## 4. Power Query M to Unity Catalog lineage

A common Databricks navigation pattern:

```powerquery
let
    Source = Databricks.Catalogs(
        "<workspace-host>",
        "/sql/1.0/warehouses/<warehouse-id>",
        [Catalog = null, Database = null, Implementation = "2.0"]
    ),
    Catalog = Source{[Name = "finance", Kind = "Database"]}[Data],
    Schema = Catalog{[Name = "commercial_gold", Kind = "Schema"]}[Data],
    Sales = Schema{[Name = "sales_detail", Kind = "Table"]}[Data]
in
    Sales
```

Deterministically extract:

```json
{
  "connector": "AzureDatabricks",
  "workspaceHost": "<redacted-or-approved>",
  "warehousePath": "/sql/1.0/warehouses/<id>",
  "implementation": "2.0",
  "catalog": "finance",
  "schema": "commercial_gold",
  "object": "sales_detail",
  "objectKind": "Table",
  "sourceConfidence": "exact_m_navigation"
}
```

Map common M steps:

| M operation | Brain fact |
|---|---|
| `Table.SelectRows` | filter predicates |
| `Table.SelectColumns` | projected fields |
| `Table.RenameColumns` | semantic aliases |
| `Table.TransformColumnTypes` | expected Power BI types |
| `Table.AddColumn` | business transformation |
| `Table.NestedJoin` / `Table.Join` | additional source relationship |
| `Table.ExpandTableColumn` | joined fields |
| `Table.Group` | aggregation and grain |
| `Value.NativeQuery` | native SQL-defined source |
| `Table.Buffer` | local evaluation/cache behavior to review |

Lineage confidence levels:

```text
exact_m_navigation
native_query_parsed
parameter_resolved
probable_from_name
unresolved_dynamic_expression
```

Never treat an old M-derived table path as current truth without validating live UC metadata.

## 5. Power BI REST observations

Store timestamped snapshots rather than mutating one current record:

```text
observations/powerbi/<timestamp>/
  workspaces.json
  reports.json
  semantic_models.json
  datasources.json
  refreshes.json
```

Useful fields include:

- workspace/report/model IDs and names;
- report-to-semantic-model relationship;
- datasource and gateway references;
- refresh status/duration;
- ownership, endorsement, and certification where accessible;
- modified timestamps;
- capacity/workspace context.

Use snapshots for drift detection:

- model moved or renamed;
- datasource changed;
- M source changed;
- measure/table count changed;
- refresh behavior changed;
- report/model disappeared or was replaced.

## 6. Unity Catalog probing

Use live accessible metadata to answer what currently exists. Preferred discovery surfaces include Unity Catalog information schema and approved SDK/REST queries.

Probe progressively:

1. current catalogs;
2. relevant schemas;
3. tables/views;
4. columns, types, and comments;
5. keys/constraints where available;
6. lineage or upstream/downstream evidence;
7. small bounded data-quality/control queries.

The user's authorization is the boundary. Discovery should not attempt to broaden access.

A historical brain entry such as `finance.gold.sales_v1` is a candidate. A current UC observation validates or supersedes it.

## 7. SQL-versus-DAX reconciliation

High-value loop:

```text
Power BI measure
→ TE2 dependency inspection
→ DAX execution
→ M/registry source mapping
→ live UC validation
→ SQL control
→ Python comparison
→ dimensional drill-down
```

A result packet should include:

- selected PBIX/model identity;
- DAX measure/expression;
- filters and filter source;
- DAX value and output hash;
- SQL text/hash and UC objects;
- SQL value;
- absolute and percentage variance;
- tolerance policy;
- drill dimensions;
- residual explanation;
- unresolved assumptions.

## 8. Databricks execution strategy

Use SQL for filtering and aggregation close to the data. Avoid downloading large raw tables to Python when a bounded SQL result can answer the question.

Use Python for:

- exact joins across result sets;
- tolerance logic;
- missing/duplicate keys;
- contribution decomposition;
- anomaly or residual clustering;
- fuzzy document matching;
- evidence and report generation.

Query controls:

- inspect schema before broad scans;
- use date/entity predicates early;
- use `LIMIT` or samples for reconnaissance;
- record warehouse, duration, and row counts;
- cache/reuse unchanged control results when safe;
- separate LLM token usage from Databricks DBU/warehouse usage.

## 9. Genie enrichment

The brain does not replace Genie. It supplies a stronger problem packet.

Genie packet inputs:

- exact objective;
- scoped business semantics;
- SAP objects and process clues;
- Power BI measure definitions and dependencies;
- M-derived source candidates;
- current accessible UC candidates;
- prior successful and failed approaches;
- required grain;
- filters and exclusions;
- known exceptions;
- expected controls;
- unresolved questions.

The enriched prompt should ask Genie to:

1. validate current sources and columns;
2. state grain and joins;
3. distinguish evidence from assumptions;
4. generate bounded SQL;
5. identify configuration-dependent logic;
6. define validation queries and expected comparisons.

Potential Genie improvements mined from Power BI include:

- table/column descriptions;
- business synonyms;
- approved join relationships;
- SQL expressions for business metrics;
- example questions and SQL;
- trusted-asset candidates;
- benchmark questions with validated controls;
- coverage gaps and feature ideas.

Do not automatically update a Genie space in the first POC. Generate recommendations, validate them, and promote only reviewed changes.

## 10. Genie quality loop

```text
Representative business question
→ current Genie response and generated SQL
→ classify failure
→ retrieve Power BI/SAP/business context
→ enrich prompt or semantic instruction
→ rerun Genie
→ compare SQL result to DAX/source control
→ record benchmark result
```

Useful failure labels:

```text
WRONG_TABLE
MISSING_JOIN
MISSING_BUSINESS_RULE
MISSING_SYNONYM
WRONG_GRAIN
WRONG_DATE_SEMANTICS
WRONG_FX_LOGIC
MISSING_FILTER
AMBIGUOUS_TERM
MISSING_TRUSTED_ASSET
CORRECT
```

## 11. Power BI Modeling MCP and authentication separation

Keep these jobs separate:

```text
Open local PBIX metadata/numbers
→ RC2 TE2 + dscmd; no Fabric SSO required

Workspace inventory/export
→ Power BI REST with approved authentication

Fabric semantic-model modeling/editing
→ official Power BI Modeling MCP with its supported authentication
```

A custom Python OAuth wrapper that waits indefinitely for a browser callback should not be the default architecture. Prefer direct invocation of the official MCP server where supported, capture stdout/stderr, set bounded timeouts, and inspect the installed version's help before relying on preview CLI flags.

Troubleshoot interactive auth by recording:

- exact launched command;
- process ID;
- stdout/stderr;
- tenant selection;
- redirect/callback URI;
- whether the browser launch occurred;
- timeout and exit behavior;
- official MCP logs.

Do not let an unbounded authentication process strand the agent.
