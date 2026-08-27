# Databricks agent toolkit contract

This directory is a separate companion to the PBIX Intake Lab. It gives an agent a credential-free Databricks-like CLI sandbox and an official-source operating guide. It is not Databricks, Spark, Photon, Unity Catalog enforcement, or proof that a command will succeed in a real workspace.

## Choose the lane first

- Use the simulator unless the user explicitly asks for a live Databricks action.
- Simulator commands start with `./databricks-sim.ps1`. They never call the network, read `.databrickscfg`, inspect `DATABRICKS_*` variables, or invoke a real `databricks` executable.
- Live commands start with `databricks`. Do not silently substitute the simulator for a requested live validation, and do not silently substitute a live workspace for a simulation.
- Do not install the real CLI, authenticate, create a profile, or use a stored profile unless the user has authorized that state change.

## Simulator workflow

From this directory:

```powershell
& .\databricks-sim.ps1 version
& .\databricks-sim.ps1 current-user me -o json
& .\databricks-sim.ps1 warehouses list -o json
& .\databricks-sim.ps1 api post /api/2.0/sql/statements --json '@examples/statement-parameterized.json' -o json
```

Use `sim reset` before a deterministic scenario. State belongs only under the ignored local simulator state directory. Never copy real hosts, tokens, client secrets, signed URLs, data, or configuration profiles into fixtures.

Simulator success proves request shape, orchestration, polling, chunk traversal, cancellation, parsing, and failure handling only. It does not prove Spark SQL semantics, workspace permissions, data correctness, performance, cost, or cloud behavior.

## Live preflight

Before any live command:

1. Run `databricks version`. CLI `1.0.0+` is GA; the documentation snapshot was checked against `1.14.0`. Runtime `--help` is authoritative when the installed version differs.
2. Require an explicit profile. Do not rely on `DEFAULT`, environment precedence, or a bundle-selected profile for agent automation.
3. Use `databricks auth profiles` and `databricks current-user me -p <profile> -o json` to prove the resolved identity. Never run or log `databricks auth token`.
4. Resolve the exact target IDs with read commands: warehouse, job, catalog/schema/table, bundle target, or workspace path. Names alone are not enough when duplicates or environments exist.
5. State the intended action, target, expected mutation/cost, and rollback or stop condition before a write.

Prefer OAuth U2M for attended user work and a least-privilege service principal with OAuth M2M or workload identity federation for unattended automation. PATs are legacy. Never place credentials in commands, JSON bodies, source files, logs, query tags, or chat.

## Command truth

- `databricks queries` manages saved query definitions. It does not execute SQL.
- Execute warehouse SQL through `databricks api post /api/2.0/sql/statements --json '@request.json'` in PowerShell, or a supported connector/SDK.
- Use named SQL parameters (`:name`) and the request `parameters` array. The Statement Execution API does not support positional `?` markers.
- Use `-o json` for machine parsing and `--json '@file.json'` for complex request bodies in PowerShell. Avoid inline shell JSON.
- Treat `next_page_token`, `next_chunk_internal_link`, `next_chunk_index`, and `manifest.truncated` as control flow, not decoration.
- An HTTP-accepted SQL request can still have `status.state: FAILED`. Success requires a terminal `SUCCEEDED` state and complete intended results.
- A cancel response means the request was received; poll until a terminal state.
- Never attach Databricks authorization headers to Statement API external-result URLs, and never log those signed URLs.
- Use Unity Catalog volumes for governed non-tabular files. DBFS root and mounts are deprecated; `dbfs:/Volumes/...` is the reserved volume namespace, not legacy DBFS root.

## Authorization boundary

Read-only discovery is allowed when live access is explicitly in scope: `list`, `get`, `get-effective`, query history, statement status, and bounded SELECT/SHOW/DESCRIBE/EXPLAIN queries.

Require explicit user authorization for actions that create cost or change state, including starting compute, triggering or canceling runs, creating/updating saved queries, uploading/syncing files, bundle deploy/run, and SQL DDL or DML.

Require a separate explicit confirmation naming the exact target for destructive or access-changing actions, including permanent delete, `bundle destroy`, workspace/fs recursive delete, secret deletion, grants/permissions changes, warehouse/cluster/job deletion, token revocation, and production deployment. Never use `permissions set` when an incremental `update` is intended; `set` replaces direct ACLs.

## SQL execution defaults

- Read-only unless a write was explicitly approved.
- Require warehouse ID, profile, catalog, and schema for noninteractive live execution.
- Default to finite `row_limit` and `byte_limit`; surface truncation.
- For automation, use `wait_timeout: "0s"`, bounded polling with jitter, a local deadline, and cancel-then-poll on interruption.
- Persist the statement ID and a sanitized audit record. Query tags may contain an environment, tool version, and opaque run ID only.
- Retry only safe reads and documented transient errors. Never blindly retry DDL/DML or an ambiguous timeout.

## Development and verification

Run the offline suite with an available Python 3.9+ interpreter:

```powershell
& .\databricks-sim.ps1 sim self-test
```

Refresh the ignored live documentation cache only when internet access is intended:

```powershell
& .\databricks-sim.ps1 docs sync
```

Read `docs/AGENT_PLAYBOOK.md` before live work and `docs/SQL_STATEMENT_EXECUTION.md` before executing SQL. If “Quest” appears in a request, consult `docs/QUEST_OR_QUERIES.md`; it is not a core CLI command.
