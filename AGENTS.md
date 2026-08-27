# PBIX Intake Lab agent contract

This contract governs the PBIX Intake Lab files at the repository root. The separate `databricks-agent-toolkit/` companion has its own nested `AGENTS.md`; agents working there must follow that narrower contract instead.

The PBIX Intake Lab performs one job: capture the complete semantic-model metadata from one exact Power BI Desktop PBIX and produce a deterministic handoff for Genie. It is read-only and local-only.

## Preconditions

- Power BI Desktop is open and its Data pane has finished loading.
- Tabular Editor 2 and DAX Studio were provisioned once outside normal runs.
- `config/tools.json` exists. If it does not and the user has explicitly authorized the one-time POC provisioning, the agent must run `Install-PbixIntakeTools.Once.ps1` itself from the user's normal non-elevated shell. Do not hand the routine installation step back to the user.
- If the user has not authorized software installation, or company policy requires prior approval, stop and request that authorization instead of installing.
- Never download, install, repair, update, or replace a tool during an intake run.

## Agent-owned POC provisioning

After the user explicitly authorizes the one-time POC installation, run this exact wrapper from the lab root:

```powershell
& "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -File .\Install-PbixIntakeTools.Once.ps1
```

The wrapper already supplies WinGet's `--silent`, `--disable-interactivity`, `--accept-source-agreements`, and `--accept-package-agreements` switches. Those switches silently accept the WinGet source and package-license agreements that the user authorized for the POC and prevent ordinary WinGet questions. Do not reconstruct the underlying WinGet commands, remove a verification step, launch either vendor installer manually, or ask the user to click through those agreement prompts.

Silent agreement acceptance is not silent security approval. The wrapper cannot approve a Windows UAC secure-desktop prompt, create a company-policy exception, or bypass application control. If any of those interrupts or blocks provisioning, stop, preserve `config/provisioning-logs/`, and report the exact failure for the user or IT. Never elevate, retry with machine scope, or weaken the pinned/hash/publisher checks.

Provisioning is complete only when the wrapper exits successfully, `config/tools.json` exists, and its final output confirms that both pinned tools passed validation. After that, proceed with intake and do not invoke the installer again as a recovery step.

## Run

When exactly one PBIX is open:

```powershell
& "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -File .\Invoke-PbixIntake.ps1
```

When more than one PBIX is open, supply the exact filename only:

```powershell
& "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -File .\Invoke-PbixIntake.ps1 -PbixName "Exact Report.pbix"
```

Do not supply a path. Do not use fuzzy matching. If identity cannot be proven from the Desktop process and its Analysis Services child, stop.

Follow `docs/DISCOVERY_PLAYBOOK.md` before asking the user for a filename or path. Exhaust Desktop Bridge, process-command-line, and window-title evidence, in that order; a missing preview bridge is not a blocker by itself.

## Command truth

- TE2 `-L` means connect to a local open Power BI Desktop model.
- TE2 `-S` means execute a C# script. It does not select a PBIX.
- TE2 `-B` writes a BIM metadata copy.
- TE2 `-TMDL` writes a TMDL metadata folder.
- TE2 `-D` deploys/saves and is forbidden.
- `dscmd --server` (`-s`) selects the server.
- `dscmd --file` (`-f`) reads a DAX query file.
- `dscmd --query` (`-q`) is inline DAX, not a query-file path.
- `dscmd.exe`, not `DaxStudio.exe`, is the automation executable.
- `dscmd` 3.6.0 is case-insensitive, but the supported 3.5.2 compatibility floor is not. Always use lowercase `csv`, `vpax`, and canonical lowercase long options.

The canonical runtime resolves `localhost:<verified-port>` plus the exact catalog first. It does not let an agent improvise native arguments.

## Acceptance

Trust a run only when all of these are true:

- `run.json` has `status: succeeded`, `result: PASS`, and `blockerCode: null`.
- `coverage.json` says `semanticModel: captured` and `reportLayer: not-collected`.
- `manifest.json` validates every published artifact by SHA-256.
- `semantic_model/model.bim` parses as JSON.
- the TMDL folder is nonempty and contains `.tmdl` files.
- `validation/dax_connection.csv` contains one `PbixIntakeConnection=OK` row.
- `GENIE_HANDOFF.md` exists and does not claim the report canvas was captured.

Exit code zero from TE2 or DAX Studio is not sufficient by itself.

## Boundaries

- Never invoke the run-once installer as an automatic recovery action. Provisioning requires an explicit one-time user/IT decision.
- Never use TE2 `-D` or any deploy, refresh, process, save, publish, or write command.
- Never execute arbitrary TE2 C# scripts.
- Never export model rows or query business data in the baseline workflow.
- VPAX must use `--donotreadstatsfromdata` and must retain TOM metadata.
- The report layer is deliberately out of scope. Pages, visuals, filters, slicers, bookmarks, and interactions must be supplied separately by the user.
- Raw BIM/TMDL can contain sensitive connection metadata. Keep raw artifacts internal. Give Genie the redacted normalized files and handoff unless raw access is explicitly approved.
- Never claim that semantic metadata alone recreates a complete PBIX.

## Failure behavior

Every attempt creates a unique run folder and a `run.json`, including failures. Return the exact `blockerCode`, message, and `nextAction`. Never reuse an older run's PASS.

Read `docs/FAILURE_KB.md` before troubleshooting. Source-maintainer instruction: if `tests/Invoke-AdversarialTests.ps1` is present, run it after changing argument construction, discovery, process handling, redaction, or output generation. Minimal runtime bundles intentionally omit source tests; do not download or recreate them during an intake.
