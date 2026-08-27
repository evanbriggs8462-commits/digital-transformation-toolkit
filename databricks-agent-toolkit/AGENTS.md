# Databricks live-agent contract

This directory is a live-only companion to the PBIX Intake Lab. When a user asks to inspect or operate Databricks through the CLI or REST API, invoke the real approved `databricks` CLI. Explicitly approved PySpark execution may use a real Databricks Connect session. Never use a mock, emulator, fabricated response, cached command output, or documentation example as evidence that an action ran.

## Non-negotiable execution rule

- Requested CLI or API work is complete only after the real `databricks` command returns fresh evidence from the intended workspace. Approved PySpark work is complete only after the intended remote Databricks Connect session returns fresh execution evidence.
- If the CLI is missing, the approved profile is unavailable, authentication fails, the network is blocked, permissions are insufficient, compute is unavailable, or the target cannot be resolved, stop and report the exact command, exit code, and sanitized error.
- Never manufacture a successful result, resource ID, row count, terminal state, or validation claim.
- Never quietly downgrade a requested live validation into a syntax review or documentation answer. Clearly label those as unexecuted if that is all that can be done.
- Documentation sync is not Databricks execution and cannot satisfy a live request.

## Authority boundary

Do not install or upgrade the CLI, authenticate, create or alter profiles, start compute, or make a workspace change unless the user has authorized that action. Do not infer permission for a write merely because read access works.

Read-only discovery is allowed when live Databricks access is in scope: `list`, `get`, `get-effective`, query history, statement status, and bounded `SELECT`, `SHOW`, `DESCRIBE`, or `EXPLAIN` queries.

Require explicit user authorization for actions that create cost or change state, including starting compute, triggering or canceling runs, creating or updating saved queries, uploading or syncing files, bundle deploy/run, and SQL DDL or DML.

Require separate confirmation naming the exact target before permanent deletion, `bundle destroy`, recursive workspace/file deletion, secret deletion, grants or permission changes, warehouse/cluster/job deletion, token revocation, or production deployment. Prefer incremental permission `update`; `set` replaces direct ACLs.

## Live preflight

Before a live operation:

1. Run `databricks version`. Runtime `--help` is authoritative for the installed version.
2. Run `databricks auth profiles`; require an explicitly selected approved profile.
3. Run `databricks current-user me --profile <profile> --output json` to prove the resolved principal. Never run or log `databricks auth token`.
4. Establish the workspace host without exposing credentials, then resolve exact target IDs with read commands.
5. For a mutation, state the action, target, expected cost or state change, and rollback or stop condition before executing.

Prefer OAuth U2M for attended user work and a least-privilege service principal with OAuth M2M or workload identity federation for unattended automation. Never place credentials in commands, request bodies, source files, logs, query tags, or chat.

## Command truth

- `databricks queries` manages saved query definitions. It does not execute SQL.
- Execute warehouse SQL through `databricks api post /api/2.0/sql/statements --profile <profile> --json '@request.json' --output json`.
- In Windows PowerShell, use a request file and the quoted `--json '@request.json'` form. Avoid complex inline shell JSON.
- Use named SQL parameters such as `:name` with the API `parameters` array. Do not assume positional `?` markers work.
- Treat `next_page_token`, `next_chunk_internal_link`, `next_chunk_index`, and `manifest.truncated` as control flow.
- An HTTP-accepted request can still end in `FAILED`. Success requires the real terminal `SUCCEEDED` state and all intended results.
- A cancellation acknowledgement is not a terminal state; continue polling.
- Never attach Databricks authorization headers to Statement API external-result URLs, and never log signed URLs.
- `Quest` is not a core Databricks CLI command. If that word appears, consult `docs/QUEST_OR_QUERIES.md` and resolve whether the user means queries, Genie, or another product.

## SQL execution defaults

- Read-only unless a write was explicitly approved.
- Require a profile, warehouse ID, catalog, and schema for noninteractive SQL.
- Set finite `row_limit` and `byte_limit`, and report truncation.
- For automation, use `wait_timeout: "0s"`, bounded polling with jitter, a local deadline, and cancel-then-poll on interruption.
- Persist the statement ID and a sanitized audit record. Query tags may contain an environment, tool version, and opaque run ID only.
- Retry only idempotent reads and documented transient errors. Never blindly retry DDL, DML, or an ambiguous timeout.

## Completion evidence

For each live action, preserve enough sanitized evidence to distinguish execution from advice:

- CLI version and explicit profile name
- resolved workspace host and authenticated principal
- exact command family and target resource IDs
- process exit code or HTTP status
- returned operation or statement ID, when the action creates one
- real terminal state, when asynchronous, and a bounded result summary

Read `docs/AGENT_PLAYBOOK.md` before live work and `docs/SQL_STATEMENT_EXECUTION.md` before executing SQL. With an already-approved Python 3.9+ interpreter that has working HTTPS support, the official-source cache can optionally be checked with `python .\scripts\sync_official_docs.py --check-only`; it is reference maintenance only. Do not install or repair Python for this task.
