# Databricks CLI agent playbook

Baseline: Databricks CLI **v1.14.0**; checked **2026-08-27**.

Labels used below:

- **Databricks fact** — behavior documented by Databricks.
- **Toolkit rule** — the conservative operating policy for an autonomous agent. It can be tightened by the organization, but must not be silently weakened.

## Non-negotiable rules

1. **Toolkit rule:** Never print, paste, persist, or transmit access tokens, client secrets, secret values, or signed result URLs. Never run `auth describe --sensitive`, `auth token`, or `secrets get-secret` as a discovery step. `auth env` is not a v1.14.0 command; do not invent it from older examples.
2. **Toolkit rule:** Select one named profile explicitly on every workspace/account command. Do not rely on `DEFAULT` or ambient shell state.
3. **Toolkit rule:** Prove the effective workspace host and principal before touching any target. Prove resource IDs again before a write.
4. **Toolkit rule:** Start read-only. A write, execution, deployment, compute start, permission change, secret change, or deletion requires scope-specific authorization.
5. **Toolkit rule:** Never use fuzzy name matching when names are duplicated. Resolve a name to an ID, present the identity evidence, then operate by ID.
6. **Toolkit rule:** Never treat exit code zero or HTTP 200 alone as business success. Parse the documented state/result and validate the intended artifact.
7. **Toolkit rule:** Do not retry a write merely because it timed out. Establish idempotency or reconcile remote state first.

## Safe decision tree

```text
What did the user request?
|
+-- Authentication setup only
|   +-- Interactive person -> OAuth U2M login; user completes browser flow
|   +-- Unattended automation -> IT-managed service principal + OAuth M2M
|
+-- Inventory, describe, list, get, validate, or plan
|   +-- Run identity/target preflight
|   +-- Use read-only command, JSON output, and complete pagination
|
+-- Execute SQL, a job, pipeline, Genie query, or start compute
|   +-- Confirm exact workspace, principal, compute, data scope, and cost boundary
|   +-- Prefer limits, parameters, dry-run/plan, and an idempotency mechanism
|
+-- Create, update, deploy, sync, upload, grant, put-secret, or edit
|   +-- Capture current state and diff/plan
|   +-- Require explicit authorization for that target and operation
|
+-- Delete, destroy, reset ACLs, revoke, stop shared compute, or expose a secret
    +-- Treat as destructive/high impact; require explicit confirmation
    +-- Re-read the exact target immediately before execution
```

Read-only does not mean harmless: metadata can reveal object names and SQL, queries can expose business data and incur compute cost, and list operations can be large.

## Authentication choice

**Databricks fact:** Databricks recommends OAuth. OAuth U2M is for attended user access; OAuth M2M with a service principal is for unattended processes. PAT authentication is supported as a legacy method. Unified authentication lets the CLI, SDKs, and Databricks Connect reuse profiles. See [CLI authentication](https://docs.databricks.com/aws/en/dev-tools/cli/authentication) and [unified authentication](https://docs.databricks.com/aws/en/dev-tools/auth/unified-auth).

**Toolkit rule:**

- POC or interactive agent session: use a named U2M profile created by the user's browser login.
- Scheduled/CI agent: use an IT-owned service principal with OAuth M2M and least privilege.
- Never ask a user to paste a token into chat or source code.
- Never put credentials in a command argument, JSON request file, Git repository, or Markdown.
- Do not create a PAT as a shortcut around OAuth or policy.

Interactive profile creation is a user-present action:

```powershell
databricks auth login --host "https://<workspace-host>" --profile "POC-DEV"
```

The browser sign-in/consent cannot be silently approved by an agent. For M2M, credential provisioning belongs to IT; this playbook deliberately contains no secret-bearing example.

## Identity and target preflight

Use variable names that do not overwrite PowerShell automatic variables such as `$PROFILE`.

```powershell
$DbxProfileName = "POC-DEV"
$ExpectedWorkspaceHost = "https://<workspace-host>"
$ExpectedPrincipal = "<expected-user-or-service-principal>"
$SqlWarehouseId = "<warehouse-id>"
$CatalogName = "<catalog-name>"

# Report names only, never environment-variable values.
Get-ChildItem Env:DATABRICKS_* | Select-Object -ExpandProperty Name

databricks version
if ($LASTEXITCODE -ne 0) { throw "Databricks CLI is unavailable." }

databricks auth profiles
if ($LASTEXITCODE -ne 0) { throw "Could not validate Databricks profiles." }

$AuthDescription = (& databricks auth describe --profile $DbxProfileName 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0) { throw "Authentication failed for the selected profile." }
if ($AuthDescription -notmatch [regex]::Escape($ExpectedWorkspaceHost)) {
    throw "Effective Databricks host does not match the approved workspace."
}

$CurrentPrincipal = (& databricks current-user me --profile $DbxProfileName --output json) |
    ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw "Could not resolve the effective principal." }
if ($CurrentPrincipal.userName -ne $ExpectedPrincipal -and $CurrentPrincipal.id -ne $ExpectedPrincipal) {
    throw "Effective principal does not match the approved identity."
}

$Warehouse = (& databricks warehouses get $SqlWarehouseId --profile $DbxProfileName --output json) |
    ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or $Warehouse.id -ne $SqlWarehouseId) {
    throw "SQL warehouse identity could not be proven."
}

$Catalog = (& databricks catalogs get $CatalogName --profile $DbxProfileName --output json) |
    ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or $Catalog.name -ne $CatalogName) {
    throw "Catalog identity could not be proven."
}
```

`auth describe` is intentionally used without `--sensitive`. Environment variables can influence unified authentication, so recording only their **names** and checking the effective host/principal prevents silent cross-workspace execution without leaking values.

For a schema or table, add an exact `schemas get <catalog>.<schema>` or `tables get <catalog>.<schema>.<table>` check. Before a permission change, also read the current grants/permissions and preserve the response as the rollback evidence.

## Read/write guardrails

| Class | Examples | Default agent action |
|---|---|---|
| Metadata read | `get`, `list`, `auth describe`, `current-user me`, `bundle validate`, `bundle plan` | Allowed after preflight; protect metadata and paginate |
| Data read / SQL | Statement Execution `SELECT`, Genie question, result download | Confirm authorized data scope, warehouse, cost, row/byte limits, and output location |
| Local mutation | `bundle init`, `aitools install`, `environments setup-local`, `ssh setup`, file download | Require authorization to change the working tree/user configuration; preview first where supported |
| Remote mutation | create/update/deploy/sync/import/upload, `jobs run-now`, warehouse start, Genie conversation creation | Require explicit target and operation authorization; capture plan/current state |
| Access/secret mutation | `permissions set/update`, `grants update`, `secrets put-*`, credential operations | Require IT/data-owner approval and least privilege; never expose values |
| Destructive/high impact | delete/destroy/reset/revoke, recursive `fs rm`, stopping shared compute | Require immediate explicit confirmation and exact target re-check |

`permissions set` replaces the object's existing direct ACL rather than merging it; prefer a reviewed `permissions update` only when that matches intent. `bundle destroy`, environment deletion, repository deletion, and recursive file removal are never cleanup assumptions.

## Command-selection map

| Need | Correct surface | Important distinction |
|---|---|---|
| Discover installed syntax | `databricks <group> <command> -h` | Installed help is the grammar authority |
| Call an uncovered REST endpoint | `databricks api get/post/...` | Keeps unified authentication; still obey endpoint semantics |
| Execute SQL | `api post /api/2.0/sql/statements` | `queries` does **not** execute SQL |
| Manage saved query definitions | `queries create/get/list/update/delete` | Definition CRUD only; v1.14.0 has no `restore` subcommand |
| Inspect executed queries | `query-history list` | History only |
| Deploy a project | `bundle validate`, `bundle plan`, then authorized `bundle deploy` | Prefer bundles for repeatable CI/CD resources |
| Inspect or run jobs | `jobs list/get/get-run`; authorized `run-now`/`submit` | Runs can incur cost and writes |
| Inspect Unity Catalog | `catalogs`, `schemas`, `tables`, `volumes`, `grants` | Creation/grants are separate write decisions |
| Move files | `fs`, `workspace`, or Unity Catalog Volumes as appropriate | A path prefix does not prove authorization |
| Ask natural-language questions | `genie` | Separate from deterministic SQL execution |
| Local PySpark development | Databricks Connect / `environments setup-local` | Not a local Spark cluster |

See `COMMAND_CATALOG.md` for the wider capability map.

## JSON input and Windows quoting

**Databricks fact:** Many CLI commands accept either inline JSON or `--json @<path>`. Global `--output json` emits machine-readable output. See [basic usage](https://docs.databricks.com/aws/en/dev-tools/cli/usage).

**Toolkit rule:** Use UTF-8 JSON request files for non-trivial bodies. Do not hand-escape nested JSON in PowerShell, use `Invoke-Expression`, or mix logs with stdout JSON.

Windows PowerShell 5.1 can remove embedded double quotes when a JSON string crosses the native-process boundary, turning valid JSON such as `{"name":"example"}` into an invalid argument. Treat that failure as a quoting problem, not an API/schema problem; use `--json '@request.json'` instead of trying more escape variants.

```powershell
$RequestPath = Join-Path $PWD "request.json"
$RequestObject = [ordered]@{
    name = "example"
    comment = "POC object"
}
$RequestJson = $RequestObject | ConvertTo-Json -Depth 20
[IO.File]::WriteAllText($RequestPath, $RequestJson, [Text.UTF8Encoding]::new($false))

$ResponseText = & databricks <group> <command> --profile $DbxProfileName --json "@$RequestPath" --output json
if ($LASTEXITCODE -ne 0) { throw "Databricks command failed." }
$Response = $ResponseText | ConvertFrom-Json
```

Never place a credential in the request object. If debug logs are required, write them to a protected file with `--log-file`, use the minimum useful log level, and inspect for sensitive content before sharing.

## Pagination: never invent one generic loop

**Databricks fact:** Pagination fields and flags differ by API. In CLI v1.14.0, generated typed list commands normally iterate pages internally and expose a visible `--limit` flag that caps the total rendered results. For example, `catalogs list -h` exposes `--limit`; it does not document `--max-results` or `--page-token`. Raw REST endpoints can instead return fields such as `next_page_token`. Some `jobs get` and `jobs get-run` responses paginate arrays nested inside one resource.

**Toolkit rule:**

1. Check the installed command's `-h`; do not copy pagination flags from a different command or API.
2. For typed CLI list commands, let the CLI iterator complete. Omit `--limit` for a complete inventory, or use a declared finite `--limit` when a sample is intentional.
3. Parse the actual JSON shape returned by that command; do not guess an items-array name.
4. For raw `databricks api` calls, follow the endpoint's documented token and request field exactly. Stop only when the next token is absent or empty, and fail on a repeated token.
5. Verify nested-array pagination separately for commands such as `jobs get` and `jobs get-run`; one top-level object does not prove its child arrays are complete.

Bounded typed-CLI example:

```powershell
$CatalogText = & databricks catalogs list `
    --profile $DbxProfileName `
    --output json `
    --limit 100
if ($LASTEXITCODE -ne 0) { throw "Catalog listing failed." }
$CatalogSample = $CatalogText | ConvertFrom-Json
```

This is deliberately a sample capped at 100 results, not evidence of a complete catalog inventory.

## Retry and reconciliation policy

**Databricks fact:** Official Databricks clients, including the CLI, retry transient failures automatically. For direct REST clients, the current [error reference](https://docs.databricks.com/api/workspace/errors) says:

- `503 TEMPORARILY_UNAVAILABLE`: retry with exponential backoff; honor `RetryInfo.retry_delay` as a minimum.
- `429 RESOURCE_EXHAUSTED`: may be quota exhaustion; retry only when known to be short-term throttling.
- `504 DEADLINE_EXCEEDED`: the operation may already have completed; do not blindly retry.
- `500 INTERNAL_ERROR`: capture `request_id` and contact support rather than looping.
- `409 ABORTED`: retry the whole application-level transaction, not one request in isolation.
- Other `4xx`: fix authentication, authorization, parameters, or resource state; unchanged retry will not help.
- Edge/proxy `429` or `503` responses without a Databricks error object are generally transient and can be retried with backoff.

**Toolkit rule:** Let the CLI perform its built-in retry. Do not wrap it in an infinite retry loop. For additional orchestration retries, cap attempts and elapsed time, add jitter, and retry only idempotent reads or writes with a documented idempotency token. After an ambiguous write result, `get`/`list` the exact resource and reconcile before deciding what to do.

## Completion evidence

An agent may claim success only after recording:

- CLI version and selected profile name (never credentials).
- Effective host and principal confirmation.
- Exact resource IDs and approved operation class.
- Command exit status plus documented remote terminal state.
- Pagination completion or a declared, intentional page limit.
- For a write: before state, plan/diff, after state, and idempotency/reconciliation evidence.
- For SQL: statement ID, terminal state, manifest/truncation status, and protected artifact location—not result data in chat.

Primary references: [CLI commands](https://docs.databricks.com/aws/en/dev-tools/cli/commands), [`auth` commands](https://docs.databricks.com/aws/en/dev-tools/cli/reference/auth-commands), [profiles](https://docs.databricks.com/aws/en/dev-tools/cli/profiles), [CLI usage](https://docs.databricks.com/aws/en/dev-tools/cli/usage), and [REST errors](https://docs.databricks.com/api/workspace/errors).
