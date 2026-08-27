# SQL Statement Execution API

Checked **2026-08-27** against the GA [Statement Execution API](https://docs.databricks.com/api/statement-execution/v1) and Databricks CLI **v1.14.0**.

Use this surface to execute SQL on a Databricks SQL warehouse. The CLI `queries` group manages saved query definitions; it does not execute them.

## Endpoint grammar

| Operation | Method and path | Success interpretation |
|---|---|---|
| Submit | `POST /api/2.0/sql/statements` | Request accepted; inspect `status.state` |
| Poll/get first result chunk | `GET /api/2.0/sql/statements/{statement_id}` | Inspect state; `SUCCEEDED` includes manifest and first chunk |
| Fetch a result chunk | `GET /api/2.0/sql/statements/{statement_id}/result/chunks/{chunk_index}` | Process returned chunk and its next pointer |
| Request cancellation | `POST /api/2.0/sql/statements/{statement_id}/cancel` | Empty response means cancel was received; continue polling |

The executing principal needs `CAN USE` on the selected warehouse plus privileges on every referenced data object. Only the principal that executes the statement can fetch its results. Use the `sql` API scope where scoped OAuth is configured.

## Submit request contract

Required fields:

- `statement`: one SQL statement; maximum text size **16 MiB**.
- `warehouse_id`: the SQL warehouse ID, not its display name and not a cluster ID.

Optional fields most useful to an agent:

| Field | Contract |
|---|---|
| `catalog` | Default catalog, analogous to `USE CATALOG` |
| `schema` | Default schema, analogous to `USE SCHEMA` |
| `parameters` | Named marker values; details below |
| `row_limit` | Result limit that also makes `manifest.truncated` report trimming |
| `byte_limit` | Result-size limit based on Databricks' internal representation |
| `format` | `JSON_ARRAY` (default), `ARROW_STREAM`, or `CSV` |
| `disposition` | `INLINE` (default) or `EXTERNAL_LINKS` |
| `wait_timeout` | `0s` for immediate asynchronous return, or `5s` through `50s`; default `10s` |
| `on_wait_timeout` | `CONTINUE` (default) or `CANCEL` when `wait_timeout` is nonzero |
| `query_tags` | Public Preview attribution/filtering tags; at most 20 are retained |

Format/disposition combinations:

- `INLINE` supports `JSON_ARRAY` only.
- `EXTERNAL_LINKS` supports `JSON_ARRAY`, `ARROW_STREAM`, and `CSV`.
- `JSON_ARRAY` values are strings or JSON `null`, even when the SQL column is numeric/date typed. Use `manifest.schema.columns` to recover types.
- With external CSV, only the first result chunk contains the header row.
- Format and disposition cannot be changed after submission for a statement ID.

## Parameter grammar

Use a named marker such as `:minimum_amount` and one matching object in `parameters`:

```json
{
  "statement": "SELECT order_id FROM orders WHERE amount >= :minimum_amount AND order_date >= :start_date",
  "parameters": [
    { "name": "minimum_amount", "value": "100.00", "type": "DECIMAL(18,2)" },
    { "name": "start_date", "value": "2026-01-01", "type": "DATE" }
  ]
}
```

Exact rules:

- Positional `?` parameters are not supported by the Statement Execution API.
- `name` is required. `value` is represented as a string.
- Omit `value`, or set it to JSON `null`, to pass SQL `NULL`.
- If `type` is omitted, it defaults to `STRING`.
- A supplied value must be castable to the supplied SQL type.
- Complex parameter types such as `ARRAY`, `MAP`, and `STRUCT` are not supported.
- Parameter markers represent literal values, not catalog/schema/table names or SQL syntax. Select identifiers from an approved allowlist; never concatenate unchecked user text into SQL.

Databricks [strongly recommends parameterized statements](https://docs.databricks.com/aws/en/dev-tools/sql-execution-tutorial) to reduce SQL-injection risk.

## State machine and failure truth

`status.state` has these values:

```text
PENDING -> RUNNING -> SUCCEEDED
                   -> FAILED
                   -> CANCELED
SUCCEEDED          -> CLOSED
```

- `PENDING`: waiting for a warehouse.
- `RUNNING`: execution in progress.
- `SUCCEEDED`: execution succeeded and result data can be fetched.
- `FAILED`: execution failed; read `status.error.error_code` and `status.error.message`.
- `CANCELED`: explicit cancellation or timeout with `on_wait_timeout=CANCEL`.
- `CLOSED`: execution succeeded but the result is no longer fetchable.

A warehouse-side SQL failure can return **HTTP 200** with `status.state=FAILED`. Therefore a zero CLI exit code is not proof that the SQL succeeded. A cancel response is `{}` and only acknowledges receipt; poll until a terminal state.

After a statement has spent at least 12 hours in a terminal state, it can be removed and subsequent status calls return HTTP 404. A status call can take up to about five seconds to reflect the latest state.

## Result limits and chunks

### Inline

- Designed for small, predictable results up to **25 MiB**.
- If the result exceeds 25 MiB, execution is aborted and no result set is available.
- The first chunk is returned by submit/get when the state is `SUCCEEDED`.
- Follow `result.next_chunk_index` or the opaque `result.next_chunk_internal_link`. Absence means no more chunks.

### External links

- Designed for larger results and supports fetching up to **100 GiB**.
- If `byte_limit` is omitted, `EXTERNAL_LINKS` applies a default 100 GiB byte limit.
- Each result link expires in **15 minutes or less**; the response includes `expiration`.
- Chunks can be resolved/fetched more than once and in parallel while valid. Calling the authenticated chunk endpoint obtains a current link.
- A signed external URL embeds temporary credentials. Treat the full URL as a secret: never print, log, commit, or send it to another service.
- **Never send a Databricks `Authorization` header when downloading an external link.** The signed URL already authorizes the storage download.

For both modes, inspect `manifest.truncated`. `true` means `row_limit` or `byte_limit` trimmed the result. Byte counts use internal representations and need not equal the final file/JSON byte size.

## Safe PowerShell submit and poll

This example delegates OAuth handling to `databricks api`; it does not extract a token. It is intentionally a bounded, read-only sample query. Replace placeholders only after completing the preflight in `AGENT_PLAYBOOK.md`.

```powershell
$DbxProfileName = "POC-DEV"
$SqlWarehouseId = "<warehouse-id>"
$RequestPath = Join-Path $PWD "sql-statement.request.json"

$Request = [ordered]@{
    warehouse_id   = $SqlWarehouseId
    catalog        = "samples"
    schema         = "tpch"
    statement      = "SELECT l_orderkey, l_extendedprice FROM lineitem WHERE l_extendedprice >= :minimum_price"
    parameters     = @(
        [ordered]@{ name = "minimum_price"; value = "60000"; type = "DECIMAL(18,2)" }
    )
    row_limit       = 100
    byte_limit      = 1048576
    format          = "JSON_ARRAY"
    disposition     = "INLINE"
    wait_timeout    = "10s"
    on_wait_timeout = "CONTINUE"
}

$RequestJson = $Request | ConvertTo-Json -Depth 20
[IO.File]::WriteAllText($RequestPath, $RequestJson, [Text.UTF8Encoding]::new($false))

$ResponseText = & databricks api post "/api/2.0/sql/statements" `
    --profile $DbxProfileName `
    --json "@$RequestPath" `
    --output json
if ($LASTEXITCODE -ne 0) { throw "Statement submission request failed." }

$Response = $ResponseText | ConvertFrom-Json
if (-not $Response.statement_id) { throw "No statement_id was returned." }
$StatementId = [string]$Response.statement_id

$PollDeadline = [DateTimeOffset]::UtcNow.AddMinutes(5)
while (@("PENDING", "RUNNING") -contains [string]$Response.status.state) {
    if ([DateTimeOffset]::UtcNow -ge $PollDeadline) {
        throw "Polling deadline reached for statement $StatementId; execution may still be running. Reconcile before canceling or retrying."
    }
    Start-Sleep -Seconds 2
    $ResponseText = & databricks api get "/api/2.0/sql/statements/$StatementId" `
        --profile $DbxProfileName `
        --output json
    if ($LASTEXITCODE -ne 0) { throw "Statement status request failed for $StatementId." }
    $Response = $ResponseText | ConvertFrom-Json
}

switch ([string]$Response.status.state) {
    "SUCCEEDED" { }
    "FAILED"    { throw "SQL failed: $($Response.status.error.error_code): $($Response.status.error.message)" }
    "CANCELED"  { throw "SQL statement was canceled." }
    "CLOSED"    { throw "SQL result is closed and cannot be fetched." }
    default      { throw "Unknown statement state: $($Response.status.state)" }
}

if ($Response.manifest.truncated -eq $true) {
    throw "Result was truncated by row_limit or byte_limit."
}
```

The request file contains SQL and object names, but no credential. It can still be sensitive metadata; keep it out of Git unless intentionally sanitized.

## Fetch every inline chunk

Process each chunk as it arrives instead of accumulating an unbounded result in memory:

```powershell
$CurrentChunk = $Response.result
while ($null -ne $CurrentChunk) {
    foreach ($Row in @($CurrentChunk.data_array)) {
        # Validate and write the row to an approved protected artifact here.
        # Do not print business rows to the agent transcript.
    }

    $HasNext = $CurrentChunk.PSObject.Properties.Name -contains "next_chunk_index"
    if (-not $HasNext) { break }

    $NextChunkIndex = [int]$CurrentChunk.next_chunk_index
    $ChunkText = & databricks api get "/api/2.0/sql/statements/$StatementId/result/chunks/$NextChunkIndex" `
        --profile $DbxProfileName `
        --output json
    if ($LASTEXITCODE -ne 0) { throw "Failed to fetch chunk $NextChunkIndex." }
    $CurrentChunk = $ChunkText | ConvertFrom-Json
}
```

Also compare processed chunk/row counts with `manifest.total_chunk_count` and `manifest.total_row_count`. Do not silently accept a partial artifact.

## Fetch external-link chunks without credential leakage

Submit with `disposition=EXTERNAL_LINKS` and `format=CSV` or `ARROW_STREAM` when a reviewed use case genuinely needs a large extract. The following loop never sends an authorization header to storage and never displays the signed URL:

```powershell
$ProtectedOutputDirectory = "<approved-protected-output-directory>"
$CurrentResult = $Response.result
$DownloadedChunkCount = 0

while ($null -ne $CurrentResult) {
    $Links = @($CurrentResult.external_links)
    if ($Links.Count -eq 0) { throw "No external link was returned for a result chunk." }

    foreach ($Link in $Links) {
        if ([DateTimeOffset]::Parse([string]$Link.expiration) -le [DateTimeOffset]::UtcNow) {
            throw "External result link expired; request a fresh link through the authenticated chunk endpoint."
        }

        $ChunkPath = Join-Path $ProtectedOutputDirectory ("chunk-{0:D6}.bin" -f [int]$Link.chunk_index)

        # Intentionally no Authorization header and no verbose logging.
        Invoke-WebRequest -Uri ([string]$Link.external_link) -OutFile $ChunkPath -UseBasicParsing
        if (-not (Test-Path -LiteralPath $ChunkPath)) { throw "External chunk download did not produce a file." }
        $DownloadedChunkCount++
    }

    $LastLink = $Links[-1]
    $HasNext = $LastLink.PSObject.Properties.Name -contains "next_chunk_index"
    if (-not $HasNext) { break }

    $NextChunkIndex = [int]$LastLink.next_chunk_index
    $ChunkMetadataText = & databricks api get "/api/2.0/sql/statements/$StatementId/result/chunks/$NextChunkIndex" `
        --profile $DbxProfileName `
        --output json
    if ($LASTEXITCODE -ne 0) { throw "Failed to resolve external chunk $NextChunkIndex." }
    $CurrentResult = $ChunkMetadataText | ConvertFrom-Json
}

if ($DownloadedChunkCount -ne [int]$Response.manifest.total_chunk_count) {
    throw "External result is incomplete."
}
```

Use a file extension matching the selected format (`.csv`, Arrow stream file convention, or `.json`) in production code, and validate each artifact before claiming completion. Protect query results according to the underlying data classification.

## Cancellation

Cancellation is a separate, authorized action when a statement is still `PENDING` or `RUNNING`:

```powershell
$CancelText = & databricks api post "/api/2.0/sql/statements/$StatementId/cancel" `
    --profile $DbxProfileName `
    --json "{}" `
    --output json
if ($LASTEXITCODE -ne 0) { throw "Cancellation request failed." }

# Do not claim canceled yet. Poll GET until CANCELED or another terminal state.
```

Do not cancel automatically merely because the local poll deadline elapsed unless the user authorized that policy. A timeout can leave remote execution running.

## Retry policy

The Databricks CLI already retries transient transport failures. Do not add an infinite wrapper. A statement submission is not safe to repeat after an ambiguous timeout because the first submission may have succeeded. Preserve the returned statement ID; if none was received, use approved query-history/reconciliation logic rather than immediately submitting the SQL again. Follow the exact [REST error guidance](https://docs.databricks.com/api/workspace/errors) summarized in `AGENT_PLAYBOOK.md`.

Primary sources: [API reference](https://docs.databricks.com/api/statement-execution/v1), [official tutorial](https://docs.databricks.com/aws/en/dev-tools/sql-execution-tutorial), and [API errors](https://docs.databricks.com/api/workspace/errors).
