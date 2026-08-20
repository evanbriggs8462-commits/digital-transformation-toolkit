# Troubleshooting

Start with the durable runtime files. Do not guess from an agent narration such as `[running powershell]`.

```text
%LOCALAPPDATA%\DigitalTransformationToolkit\runtime\result.json
%LOCALAPPDATA%\DigitalTransformationToolkit\runtime\state.json
%LOCALAPPDATA%\DigitalTransformationToolkit\runtime\latest.log
```

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

At the beginning of every run, the launcher removes the prior `result.json`. Therefore an interrupted new run must not leave an old PASS as current evidence. Retry normally; do not reuse an earlier run's result. Accept success only when `state.json` and `result.json` share the same `runId` and satisfy the complete-run contract in the README.

## Security blocker

Do not work around explicit organization-policy blocks, disable endpoint security, disable certificate validation, or weaken package integrity checks. Report the exact installer/error text from `latest.log`.
