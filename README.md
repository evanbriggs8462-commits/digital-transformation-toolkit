# PBIX Intake Lab

PBIX Intake Lab is a deliberately small, read-only Windows harness for repeatedly capturing a Power BI Desktop semantic model and creating a Genie-ready handoff.

It is designed for unlimited *repetition*, not an unbounded process: every individual tool call has a timeout, every attempt gets its own evidence folder, and one failed experiment cannot silently become the next run's result.

It does not install tools during a run, modify the open model, extract report pages or visuals, publish, refresh, or move data. The old zero-touch deployment machinery is preserved on the `rc-1.2.0-rc.2` branch and is not part of this lab.

## One-time provisioning

For an explicitly authorized POC, the agent should run the audited WinGet entry point once from the user's normal, non-elevated Windows shell:

```powershell
& "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -File .\Install-PbixIntakeTools.Once.ps1
```

It pins and installs:

- Tabular Editor 2 `2.28.0` from `TabularEditor.TabularEditor.2`.
- DAX Studio `3.6.0` from `DaxStudio.DaxStudio`.

The script requires the canonical WinGet community source, parses an explicit successful refresh, selects only user-scope installers, retains WinGet hash enforcement, verifies the pinned installer metadata, validates the installed executable hashes and Authenticode publishers, and registers the runtime-critical dependency sets in `config/tools.json`. It has no machine-scope, `RunAs`, force, hash-ignore, or elevation fallback.

No routine installer interaction is expected. The wrapper itself passes `--silent`, `--disable-interactivity`, `--accept-source-agreements`, and `--accept-package-agreements`, so the agent accepts the WinGet source and package-license terms covered by the user's POC authorization and WinGet does not ask ordinary confirmation questions. The agent must use the wrapper as-is instead of improvising direct WinGet or vendor-installer commands.

If IT already provisioned approved binaries, register those exact paths instead:

```powershell
& "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -File .\Initialize-PbixIntakeLab.ps1 `
  -Te2Path "C:\approved\TabularEditor.exe" `
  -DscmdPath "C:\approved\dscmd.exe"
```

The initializer itself never downloads or installs anything. Every intake revalidates the recorded path, version, publisher, executable SHA-256, and registered dependency hashes. Provisioning is never invoked by `Invoke-PbixIntake.ps1`.

The run-once path is designed to avoid elevation, not to bypass it. DAX Studio officially supports a current-user install without admin rights, but its WinGet manifest still declares `elevatesSelf`; Windows or company policy can therefore still interrupt or block installation. Silent agreement acceptance cannot approve UAC or override company policy. Stop and use the IT path if that happens. See `docs/ONE_TIME_PROVISIONING.md` and `docs/PUBLISHING_AUDIT_2026-08-26.md`.

For the POC, retain the wrapper's unique provisioning evidence and a successful intake result for the boss demonstration. Treat that as proof of function and controls, not as company approval. Submit the evidence and the approval language in `docs/SECURITY_POSITION.md` to IT before broader deployment.

## Intake

Open a PBIX in Power BI Desktop, wait for the model to load, and run:

```powershell
& "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -File .\Invoke-PbixIntake.ps1
```

If several reports are open:

```powershell
& "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -File .\Invoke-PbixIntake.ps1 -PbixName "Exact Report.pbix"
```

Successful runs contain `run.json`, `GENIE_HANDOFF.md`, `coverage.json`, `manifest.json`, `identity.json`, complete BIM/TMDL metadata, normalized redacted JSON, a DAX connection proof, optional metadata-only VPAX, and bounded tool logs.

`model.bim` and TMDL are the semantic-model sources of truth. Normalized files and `GENIE_HANDOFF.md` are redacted navigation artifacts for an agent.

## Honest coverage

The lab captures semantic metadata: tables, columns, measures, DAX, relationships, partitions, M/shared expressions, data-source definitions, calculation groups, hierarchies, roles, perspectives, translations, annotations, and model settings represented in TOM/TMDL.

It does not capture the Power BI report canvas. Users must separately provide page/visual/filter/slicer context to Genie. See `docs/KNOWLEDGE_BASE.md` for the exact boundary.

## Tests

Run the offline adversarial suite:

```powershell
& "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -File .\tests\Invoke-AdversarialTests.ps1
```

Download the pinned Microsoft PBIX corpus explicitly for live tests:

```powershell
& "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -File .\tests\Get-OfficialPbixSamples.ps1
```

Samples are not bundled with the lab.

See `docs/TEST_CORPUS.md` for pinned Microsoft sample hashes and `docs/SECURITY_POSITION.md` for the one-time provisioning control story.

For first-run target reliability, `docs/DISCOVERY_PLAYBOOK.md` defines the bridge -> command line -> window title -> Desktop PID -> model PID -> port -> catalog evidence chain and the exact stop conditions.

`docs/VALIDATION_REPORT.md` records the adversarial failures and live three-PBIX results used to accept this build.
