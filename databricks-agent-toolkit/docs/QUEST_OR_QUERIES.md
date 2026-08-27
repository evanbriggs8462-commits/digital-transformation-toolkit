# “Quest,” `queries`, SQL execution, and Genie

Checked against Databricks CLI **v1.14.0** on **2026-08-27**.

## The short answer

There is no core Databricks CLI command group named `quest`. Do not invent `databricks quest ...`.

The likely meanings are:

| User wording | Actual surface | What it does | What it does **not** do |
|---|---|---|---|
| “queries” | `databricks queries` | Creates, gets, lists, updates, or deletes saved Databricks SQL **query definitions** | It does not execute the saved SQL |
| “query history” | `databricks query-history list` | Reads execution history for SQL warehouses and serverless compute | It does not submit a statement |
| “run SQL” | `databricks api post /api/2.0/sql/statements` | Submits SQL to the Statement Execution API | It is not the `queries` CRUD surface |
| “ask the data” | `databricks genie ...` | Interacts with an existing Genie space/conversation and can produce query-backed answers | It is not deterministic saved-query CRUD |
| “Quest” or “erwin” | Quest Software products | Optional third-party data modeling, catalog, lineage, and governance integration | It is not built into the Databricks CLI |

Sources: [CLI command inventory](https://docs.databricks.com/aws/en/dev-tools/cli/commands), [`queries` reference](https://docs.databricks.com/aws/en/dev-tools/cli/reference/queries-commands), [`query-history` reference](https://docs.databricks.com/aws/en/dev-tools/cli/reference/query-history-commands), [Statement Execution API](https://docs.databricks.com/api/statement-execution/v1), and [`genie` reference](https://docs.databricks.com/aws/en/dev-tools/cli/reference/genie-commands).

## Agent resolution rule

Use surrounding intent before choosing a surface:

1. If the user wants to inventory or edit a saved SQL object, use `queries`.
2. If the user wants to inspect what ran, use `query-history`.
3. If the user supplied SQL and wants it executed, use Statement Execution after the read/write guard in `AGENT_PLAYBOOK.md`.
4. If the user asks a natural-language business question in a named Genie space, use `genie` and treat generated query execution and returned data as sensitive.
5. If the user explicitly names Quest Software, erwin Data Modeler, erwin Data Intelligence, or Quest Data Modeler, treat it as a separately licensed third-party integration. Do not install or configure it from this toolkit.
6. If none of those interpretations is supportable, ask one short clarification. Do not “try” a guessed command.

## `queries` is definition CRUD, not an executor

These are definition operations:

```powershell
databricks queries list --profile $DbxProfileName --output json
databricks queries get $QueryId --profile $DbxProfileName --output json
```

`create`, `update`, and `delete` mutate workspace objects and require explicit write authorization. The v1.14.0 `queries` group has no restore operation. Getting a query definition can expose SQL text, object names, and parameters; handle the output as workspace metadata.

Do not infer that a successful `queries get` or `queries update` means the SQL compiled or ran. Use [Statement Execution](https://docs.databricks.com/api/statement-execution/v1) for execution and inspect `status.state`, not just the HTTP status or process exit code.

## Genie is a separate conversational surface

The v1.14.0 `genie` group includes operations such as `list-spaces`, `get-space`, `ask`, `start-conversation`, message retrieval, attachment-query execution, and result download. Some operations only read configuration; others create conversations, execute a query attachment, or materialize results. Apply the same data-access and cost approval rules used for SQL.

Never substitute Genie for deterministic reconciliation. For repeatable validation, execute reviewed, parameterized SQL and preserve the statement ID and result manifest. Use Genie when the user wants the semantics of an existing Genie space and accepts its conversational behavior.

## Quest Software and erwin

Databricks documents [erwin Data Modeler by Quest](https://docs.databricks.com/aws/en/partners/data-governance/erwin) as a third-party partner integration for modeling and reverse engineering. It is not a Databricks CLI surface.

Quest products have their own licensing, installers, credentials, APIs, and approval boundaries. Their existence does not create a `quest` command in Databricks CLI. Add Quest/erwin automation only as a separately approved integration with its own primary documentation and tests.
