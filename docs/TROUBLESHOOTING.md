# Troubleshooting

Start with the durable runtime files. Do not guess from an agent narration such as `[running powershell]`.

```text
%LOCALAPPDATA%\DigitalTransformationToolkit\runtime\result.json
%LOCALAPPDATA%\DigitalTransformationToolkit\runtime\state.json
%LOCALAPPDATA%\DigitalTransformationToolkit\runtime\latest.log
```

## Schema-v2 recovery contract

Read the four top-level fields `blockerCode`, `retryable`, `requiresIT`, and `nextAction` from both `state.json` and `result.json`. On running and successful states their defaults are `null`, `false`, `false`, and `null`, respectively. The existing `lastError` and `blocker` fields remain the human-readable details.

- `blockerCode` is the stable failure identifier to preserve in diagnostics.
- `retryable: true` permits exactly one automatic rerun, and only after completing `nextAction`.
- `requiresIT: true` means stop and escalate with the exact blocker; do not rerun or attempt a workaround.
- `nextAction` is the safe prerequisite for the one permitted rerun or the action to report to the user or IT.

If `retryable` is false, stop. If one permitted rerun also fails, stop and report the fields from the newest matching `state.json` and `result.json`. Never loop, remove Mark-of-the-Web, change execution policy, bypass endpoint controls, or provide credentials.

Two safety exceptions deliberately do not produce a normal matching pair. A concurrent invocation exits `2` without touching the active run's shared files; do not interpret those files as the rejected invocation's result. If `result.json` itself is locked, `RESULT_INVALIDATION_FAILED` may leave that older file in place, but the new failed `state.json` has a different `runId`, so the old result is non-authoritative and must be preserved only as failure evidence.

## Choose the correct setup mode

- Metadata or model-structure task: run `START_HERE.ps1 -SkipDaxStudio`.
- Calculation or DAX-query task: run `START_HERE.ps1 -RequireDaxStudio`, and continue only when the completed result has `capabilities.daxQueries: true`.
- Unclear or mixed task: run `START_HERE.ps1` with neither switch as best effort, then inspect `capabilities.daxQueries` before attempting DAX.

## Browser or SharePoint download is blocked before startup

An unsigned downloaded ZIP can retain Mark-of-the-Web after extraction. Under `RemoteSigned` or stricter policy, PowerShell may reject `START_HERE.ps1` before the runtime can write diagnostics.

Do not unblock files or change execution policy. Record the exact PowerShell error and report the package as not rollout-ready until it is signed by a trusted publisher or delivered through an approved trusted channel. If any UAC prompt appears, cancel it and mark the run failed.

## No PBIX open

`Result: PASS` with `status: ready-no-model` means the workstation is ready but no Power BI Desktop PBIX was available. Open the PBIX, wait for it to finish loading, and run `START_HERE.ps1` again.

## Multiple PBIX files open

The launcher will list the open filenames and stop rather than guess. Pass the exact open filename only, including `.pbix`; do not pass a full path. A wrong or ambiguous filename must fail rather than fall back to another open model:

```powershell
powershell.exe -NoProfile -File .\START_HERE.ps1 -PbixName "Exact File.pbix"
```

## Tabular Editor 2 not found

The launcher checks PATH, common Program Files locations, LocalAppData, and WinGet package folders before installing anything. If still missing, it attempts:

```text
winget install --id TabularEditor.TabularEditor.2 --exact --source winget --scope user --silent --disable-interactivity --version 2.28.0 --accept-source-agreements --accept-package-agreements
```

The official TE2 WinGet manifest packages the portable ZIP and declares the .NET Framework 4.6 Developer Pack as a dependency. The launcher first verifies a compatible .NET Framework 4.6+ runtime, then uses `--skip-dependencies` to avoid the Developer Pack/elevation path. If the runtime cannot be confirmed, setup stops; it does not launch the normal dependency installer. Explicit organizational-policy blocks also stop the workflow.

## DAX Studio not found

Core metadata extraction can still succeed using TE2. DAX Studio is required only for `run_dax_query_any_model.ps1`. To make it mandatory during bootstrap, run:

```powershell
powershell.exe -NoProfile -File .\START_HERE.ps1 -RequireDaxStudio
```

## TE2 filename connection fails

This is expected on some Desktop setups. Discovery is layered: optional Desktop Bridge file/PID evidence, TE2 local filename, Power BI/Analysis Services process mapping, `msmdsrv.port.txt`, and finally a listener-by-process port probe. The runtime refuses ambiguous matches. If all routes fail, the error preserves the failed connection evidence.

## TE2 appears to hang

The canonical TE2 wrapper waits for the WinForms process to actually finish and applies a timeout. Diagnostics are written into the inventory output directory as `_te2_stdout.log` and `_te2_stderr.log`.

## Git error in a shared folder

Git is not required in SharePoint/download mode. If you see a Git-clean error, check whether the process environment has `TOOLKIT_ENFORCE_GIT_CLEAN=1`; that setting is intended only for development checkouts.

## Broken or stale output

A successful run requires all six CSVs, exact expected headers, readable CSV content, hashes, and a manifest with `status: succeeded`. The launcher does not reuse old artifacts as proof of success.

At the beginning of every run, the launcher removes the prior `result.json`. Therefore an interrupted new run must not leave an old PASS as current evidence. Do not reuse an earlier run's result. Accept success only when `state.json` and `result.json` share the same `runId` and satisfy the complete-run contract in the README. Rerun only when `retryable: true`, perform the stated `nextAction`, and rerun no more than once.

## Security blocker

Do not work around explicit organization-policy blocks, disable endpoint security, disable certificate validation, or weaken package integrity checks. Report the exact installer/error text from `latest.log`.
