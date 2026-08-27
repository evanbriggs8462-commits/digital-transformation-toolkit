# Databricks Agent Toolkit

Databricks Agent Toolkit gives coding agents two deliberately separate lanes:

1. an offline, credential-free CLI simulator for practicing command selection, JSON bodies, SQL Statement Execution polling, chunks, cancellation, and failure handling;
2. a current official-source playbook for operating the real Databricks CLI, SQL APIs, saved queries, jobs, Unity Catalog, bundles, files, Genie, and Databricks Connect/PySpark.

It does not emulate Spark, Photon, cloud IAM, Unity Catalog enforcement, or performance. The simulator validates agent orchestration, not Databricks correctness.

## Quick start

```powershell
Set-Location .\databricks-agent-toolkit
& .\databricks-sim.ps1 version
& .\databricks-sim.ps1 quickstart
& .\databricks-sim.ps1 sim reset
& .\databricks-sim.ps1 catalogs list -o json
& .\databricks-sim.ps1 api post /api/2.0/sql/statements --json '@examples/statement-parameterized.json' -o json
```

The wrapper locates an available Python 3.9+ interpreter. It never resolves or calls a real `databricks` binary.
On Windows PowerShell, use the quoted `--json '@file.json'` form shown above for request bodies; complex inline JSON can lose its embedded quotes at the native-process boundary.

## What is modeled

- CLI-style JSON/text output and global `-o/--output`, `-p/--profile`, and `-t/--target` flags
- current user and safe simulated profiles
- warehouses, clusters, jobs/runs, saved queries, and query history
- Unity Catalog catalogs, schemas, tables, and volumes
- workspace and volume file listings
- exact `databricks api` paths for SQL Statement Execution
- named parameters, async status transitions, result chunks, truncation, cancellation, execution failures, and external-link handling
- deterministic local state and reset

## Live Databricks

The real CLI is intentionally not bundled. As of 2026-08-27, the current official release is `1.14.0`, and CLI `1.0.0+` is GA. Install and authenticate it only through your approved process. Databricks recommends OAuth over PATs and now provides official coding-agent skills through `databricks aitools`.

For attended access:

```powershell
databricks auth login --host <workspace-url>
databricks auth profiles
databricks current-user me -p <profile> -o json
```

For coding-agent guidance after your organization approves the CLI and skill installation:

```powershell
databricks aitools install --agents codex --scope project
```

Do not run `auth token` in logged automation. Do not assume a profile, workspace, warehouse, catalog, or production target.

## Documentation layout

- `AGENTS.md`: mandatory safety and execution contract
- `docs/AGENT_PLAYBOOK.md`: live-agent decision flow and command patterns
- `docs/COMMAND_CATALOG.md`: which surface to use for each Databricks task
- `docs/SQL_STATEMENT_EXECUTION.md`: SQL API request, polling, chunk, cancel, and error contract
- `docs/PYSPARK_CONNECT.md`: Databricks Connect and local PySpark boundaries
- `docs/QUEST_OR_QUERIES.md`: saved queries, Genie, and the possible Quest ambiguity
- `docs/OFFICIAL_SOURCES.md`: official links and freshness record
- `references/official_sources.json`: machine-readable source index

Run `databricks-sim.ps1 docs sync` to fetch a fresh, ignored local text cache from the official links. Source summaries remain checked in; downloaded documentation does not.

## Tests

```powershell
& .\databricks-sim.ps1 sim self-test
```

The suite must pass without network access, a Databricks CLI installation, profiles, or credentials.
