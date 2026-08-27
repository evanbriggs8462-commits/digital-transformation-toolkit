# Databricks Agent Toolkit

This is a live-only instruction set for coding agents that operate Databricks through the official CLI. The CLI's `databricks api` command is the required path for uncovered REST endpoints. Explicitly approved PySpark work may use a real Databricks Connect session. The toolkit contains no emulator, mock workspace, synthetic execution path, bundled CLI, installer, credentials, or fake-success fallback.

An agent may claim that a CLI or API action ran only when the real `databricks` command returned evidence from the intended workspace. An approved PySpark action requires fresh evidence from the intended remote Databricks Connect session. If the required live surface, approved profile, authentication, network, permissions, compute, or target is unavailable, the agent must report the exact blocker. It must never replace execution with invented output.

## Ownership and prerequisites

The user or IT installs and approves the Databricks CLI and grants access. This toolkit does not install software or create credentials. An agent must not install the CLI, sign in, create a profile, or expose a token unless the user has explicitly authorized that action.

Before live work, identify an approved profile and run:

```powershell
databricks version
databricks auth profiles
databricks auth describe --profile <profile>
databricks current-user me --profile <profile> --output json
```

The agent must record the installed CLI version, selected profile name, resolved workspace host, authenticated principal, and any target IDs needed for the requested action. Resolve only relevant targets with exact or intentionally bounded reads. Secrets and token values must never be printed or logged.

## Real execution contract

- Use `databricks` for every requested CLI or API operation; there is no local substitute. Use Databricks Connect only for explicitly approved PySpark execution against a proven remote workspace and compute target.
- Use an explicit `--profile` on live commands. Do not silently rely on `DEFAULT`, environment precedence, or a bundle-selected target.
- Resolve real resource IDs before acting. Do not invent hosts, warehouse IDs, job IDs, catalogs, schemas, tables, paths, or statement IDs.
- Treat a nonzero process exit, API error, permission denial, unreachable host, missing target, and expired authentication as failures—not partial success.
- For asynchronous work, poll the real resource to a terminal state. An accepted request is not proof of successful completion.
- Report the command or operation, exit status, target identity, and—when the action produces them—the returned resource ID and terminal state, while redacting secrets and signed URLs.
- Keep reads bounded. Require authorization before compute starts, writes, deployments, DDL/DML, or other state changes, and exact-target confirmation before destructive or access-changing operations.

## SQL execution

`databricks queries` manages saved query definitions; it does not run SQL. Execute warehouse SQL through the Statement Execution API, for example:

```powershell
databricks api post /api/2.0/sql/statements --profile <profile> --json '@request.json' --output json
```

Build `request.json` for the real, discovered warehouse and approved catalog/schema. On Windows PowerShell, prefer the quoted `--json '@request.json'` form because inline JSON is easy to corrupt at the native-process boundary. Poll the returned statement ID until a terminal state, traverse every intended result chunk, and surface truncation or failure.

## Documentation layout

- `AGENTS.md`: mandatory live-execution and safety contract
- `docs/AGENT_PLAYBOOK.md`: live-agent decision flow and command patterns
- `docs/COMMAND_CATALOG.md`: which official surface to use for each task
- `docs/SQL_STATEMENT_EXECUTION.md`: SQL request, polling, chunks, cancellation, and errors
- `docs/PYSPARK_CONNECT.md`: Databricks Connect and local PySpark boundaries
- `docs/QUEST_OR_QUERIES.md`: saved queries, Genie, and the possible Quest ambiguity
- `docs/OFFICIAL_SOURCES.md`: official links and freshness record
- `references/official_sources.json`: machine-readable source index

Optional maintainer task: from the toolkit directory, an already-approved Python 3.9+ interpreter with working HTTPS support can check or refresh the ignored documentation cache from the indexed official URLs:

```powershell
python .\scripts\sync_official_docs.py --check-only
python .\scripts\sync_official_docs.py
```

That script fetches documentation only. It does not connect to a Databricks workspace or prove that any Databricks command ran.
Do not install or repair Python just for this optional cache. The checked-in source index and summaries remain usable without it.
