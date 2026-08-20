# Agent Contract

This folder is a self-contained Power BI runtime delivered from a shared folder. Do not assume Git is installed or that the user understands PowerShell, ports, Tabular Editor, or DAX Studio.

## Always start here

For setup, discovery, or first use, run and wait for:

```powershell
powershell.exe -NoProfile -File .\START_HERE.ps1
```

If the exact open PBIX filename is already known, `-PbixName "<FILE>.pbix"` is allowed. Supply a filename only, not a path. Never substitute a similar name or fall back to another open model. Do not recreate winget installs, `.env` edits, Power BI instance discovery, port probing, or TE2 invocation yourself.

Console `Result: PASS` is not sufficient. For metadata extraction, accept success only when `state.json` and `result.json` have the same `runId`; state is `succeeded` at stage `complete`; result is `PASS` with status `complete` and exit code `0`; and `inventory_manifest.json` reports `status: succeeded`, a nonempty `toolkitCommit`, and exactly six existing validated artifacts. `ready-no-model` proves setup readiness only. A new run clears the prior result, so an interrupted run is safe to retry but must never inherit an old PASS.

## Task router

Choose tools by the question, not by habit:

- **TE2 / model inventory** — use for model structure and logic: tables, columns, measures and their expressions, relationships, partitions, Power Query/M, shared expressions, hidden objects, and model metadata.
- **DAX Studio / `dscmd`** — use when the user wants a calculated answer from the model: totals, reconciliations, filtered results, measure evaluation, comparisons, validation queries, or a result set. Run `START_HERE.ps1` first so DAX Studio and the correct Desktop model connection are known.
- **Report context** — page filters, visual filters, slicer state, interactions, bookmarks, and what a specific visual is showing are report-layer context. Do not infer these from semantic-model metadata. If PBIR/PBIP report definitions are available, inspect them. If Desktop Bridge is available, its exact file/PID state may be used as discovery evidence; screenshots are optional preview evidence, not a source of hidden filter semantics. Otherwise use only filters/context explicitly supplied by the user.

DAX Studio can calculate under any filter context that can be expressed in DAX, but the agent must not silently invent missing page/visual filters. Translate explicit user/report context into the DAX query, then validate the result.

## Canonical wrappers

Use these only after the launcher has prepared the environment:

- `powershell\run_model_inventory.ps1`
- `powershell\run_dax_query_any_model.ps1`
- `powershell\test_toolkit_setup.ps1`

For a non-test DAX query, write the generated query under the configured evidence/output area, not inside the toolkit. Preserve the query and its manifest as evidence.

## Discovery and ambiguity

The runtime uses layered discovery and must prefer stronger evidence when available: Desktop Bridge exact file/PID, native filename connection, Power BI process/Analysis Services mapping, `msmdsrv.port.txt`, then listener-by-process fallback. If evidence remains ambiguous, do not guess a port, model ID, PBIX, or filter context.

If multiple PBIX files are open, use one of the exact names returned by the launcher. If the user named a report, select only an unambiguous matching target.

## Boundaries

- Metadata extraction is read-only.
- Do not publish, deploy, refresh, process, or save a semantic model unless the user explicitly requests a separate write workflow.
- Do not request or print credentials, API keys, tokens, or secrets.
- Do not disable UAC, endpoint security, certificate validation, package-integrity checks, or organizational policy.
- Zero-touch setup must not require UAC credentials. TE2 uses only a verified user-scope portable WinGet path or a hash-pinned official portable ZIP. DAX Studio uses its official portable ZIP under LOCALAPPDATA. `-NoProfile`, silent mode, and agreement acceptance are noninteractive options, not privilege escalation.
- This unsigned RC may be blocked when a browser/SharePoint ZIP carries Mark-of-the-Web. Do not unblock files or lower execution policy; report that as a release blocker.
- No supported path displays UAC. If a UAC prompt appears, cancel it and mark the test failed.

## Failure handling

Read these before troubleshooting or improvising:

- `%LOCALAPPDATA%\DigitalTransformationToolkit\runtime\result.json`
- `%LOCALAPPDATA%\DigitalTransformationToolkit\runtime\state.json`
- `%LOCALAPPDATA%\DigitalTransformationToolkit\runtime\latest.log`

Return the exact blocker. Do not claim success from a launched process, an old artifact, or an unverified CSV.
