# Power BI Agent Runtime

This folder is intended to be copied from SharePoint/shared storage and handed to an agent. The teammate should not need to configure ports, paths, TE2, DAX Studio, Git, or metadata export manually.

## Release status: unsigned validation candidate

This package is an unsigned release candidate for local validation only. A ZIP downloaded through a browser or SharePoint may carry Mark-of-the-Web (`ZoneId=3`). Under `RemoteSigned` or a stricter PowerShell policy, Windows can block `START_HERE.ps1` before toolkit code runs.

Do not remove Mark-of-the-Web, change execution policy, or bypass endpoint controls. Production rollout requires trusted Authenticode signing and a successful re-test from a browser-downloaded, Mark-of-the-Web-tagged ZIP.

The supported workflow must not display a UAC prompt. If one appears, cancel it and mark the test failed.

## User experience

1. Open the Power BI Desktop report you want to work with.
2. Give the agent this folder (or open the folder as its workspace).
3. Ask the Power BI question.

The agent contract tells it to run `START_HERE.ps1`, which discovers/repairs the local environment, detects the open PBIX, extracts and validates semantic-model metadata, and records durable diagnostics if anything fails.

## What the runtime knows

- **Model structure and logic:** tables, measures, columns, relationships, partitions, M/shared expressions — extracted read-only with Tabular Editor 2.
- **Calculated model results:** DAX Studio can execute DAX queries against the resolved open model when a calculation or validation is needed.
- **Desktop identity:** discovery is layered. The runtime can use the Power BI Desktop Bridge (preview) as optional exact file/PID evidence, then native filename and Analysis Services process/port fallbacks. It refuses ambiguous model selection.

## Important report-layer boundary

A PBIX semantic model does not by itself reveal every active report/page/visual filter, slicer selection, bookmark, or visual interaction. DAX Studio can reproduce a filter context only when that context is known and expressed in DAX. The agent must use PBIR/PBIP report definitions or explicit user/report context when available and must not invent missing visual filters.

## Zero-touch tool setup

The supported bootstrap does not require an administrator credential prompt. Compatible existing tools are reused. Missing TE2 is installed only through a user-scope, silent WinGet portable path after the required .NET runtime is verified, with a hash-pinned official portable ZIP fallback. Missing DAX Studio is installed from its official portable release under `%LOCALAPPDATA%`. The runtime does not attempt an elevated dependency or machine-wide install.

Repeated setup runs reuse validated portable tools and regenerate `.env` idempotently. Concurrent launcher runs are rejected instead of racing over shared runtime state. Tool executables are checked for minimum version and trusted Authenticode publisher before use.

## Runtime outputs

Environment/run state is written under:

```text
%LOCALAPPDATA%\DigitalTransformationToolkit\runtime
```

Validated model evidence is written under:

```text
%USERPROFILE%\PowerBI-Evidence
```

A SharePoint release built with `package_manifest.json` validates its runtime files by SHA-256 and does not require Git.

## Accepting a completed extraction

Do not accept console output alone. A metadata-extraction run is successful only when:

- `state.json` and `result.json` exist and have the same `runId`;
- `state.json` has `status: succeeded` and `stage: complete`;
- `result.json` has `result: PASS`, `status: complete`, and `exitCode: 0`;
- `inventory_manifest.json` has `status: succeeded` and a nonempty `toolkitCommit`; and
- the manifest validates exactly these six artifacts: `tables.csv`, `measures.csv`, `columns.csv`, `relationships.csv`, `partitions.csv`, and `expressions.csv`.

`ready-no-model` proves setup readiness only; it is not proof of PBIX extraction.

## Scope

The default workflow is read-only. It does not publish, deploy, refresh, or save changes back to Power BI.
