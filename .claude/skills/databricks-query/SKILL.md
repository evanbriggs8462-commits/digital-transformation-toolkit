---
name: databricks-query
description: Discover and query Databricks with fresh schema evidence, bounded SQL, and verified results. Use for Databricks SQL, warehouse execution, landed SAP data, catalog discovery, schema errors, joins, and financial reconciliation; distinguish drafts from live execution.
---

# Query Databricks from evidence

Load the repository's [live contract](../../../databricks-agent-toolkit/AGENTS.md) before live work and its [execution guide](../../../databricks-agent-toolkit/docs/SQL_STATEMENT_EXECUTION.md) before submitting SQL. Reuse them within the session; reread when changed. These govern authorization and execution; this skill adds query discipline.

## Prove the target

1. Distinguish **SQL draft** from **live query**. Label unexecuted SQL explicitly; never invent results, successful commands, IDs, or row counts.
2. For live work, use the installed approved `databricks` CLI, its current `--help`, and the contract's preflight. Establish the explicit approved profile, workspace host, principal, exact warehouse ID, catalog, and schema. Never guess company identifiers or assume Unity Catalog write access.
3. Check the warehouse state using a read command. A query against stopped compute can start it automatically. Require authorization for that start; do not submit SQL to bypass the boundary. Do not install tools, authenticate, change profiles, or mutate resources without authorization.

## Discover only what the question needs

- Identify the metric, grain, entity/client/source-system scope, period, currency, and expected comparison first.
- Inspect targeted current metadata using `SHOW`, `DESCRIBE`, or filtered information-schema queries before writing business SQL. Verify each table, column, and type. A similar SAP name is a hypothesis, not proof.
- Treat missing metadata as **not visible to this principal**, not proof the object does not exist. Preserve the actual permission or resolution error.
- Inspect a small relevant slice when contents need verification. Use named columns, selective entity/date predicates, finite result limits, and `EXPLAIN` when scan cost is uncertain. `LIMIT` and API result limits do not guarantee a cheap scan. Avoid catalog-wide inventories and unrestricted `SELECT *`.

## Protect financial meaning

- Verify the landed physical grain separately from the expected SAP business key. Check source/client keys, CDC operation/version columns, deleted records, history, and freshness. Never use arbitrary `DISTINCT` or "latest row" logic to conceal unexplained duplicates.
- Prove join keys and cardinality on the scoped data. Include applicable source system/client, company, fiscal year, language, organizational, and validity keys. Compare counts and currency-specific totals before and after a join; expose unmatched rows and fanout.
- Preserve string IDs and leading zeros. Verify date encoding, zero/blank sentinels, timestamp type/timezone, decimal scale, currency/unit, and whether signs are already applied. Keep currencies separate unless an approved FX rule defines conversion. Use explicit half-open period boundaries.
- Reconcile to the agreed source of truth with identical filters and grain. State residuals and unresolved assumptions; metadata alone does not establish financial agreement.

## Execute and report honestly

`databricks queries` manages saved definitions; execute SQL through the contract's Statement Execution API path. Parameterize values, quote verified identifiers, poll real terminal state, consume intended result chunks, and report truncation. HTTP 200 or exit zero alone does not prove SQL success.

Read [SQL patterns](references/sql-patterns.md) only for syntax/validation needs. Use [the evidence template](references/evidence-template.md) for a compact sanitized record in an approved private location. Keep secrets, business rows, and internal mappings out of public Git and verbose chat.
