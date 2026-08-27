# Security position: provisioning versus intake

## Short answer

- **No**: using `winget` itself is not inherently improper.
- **Yes**: silently accepting ordinary WinGet source and package-license agreements can be appropriate after the user explicitly authorizes the POC; the audited wrapper does this with WinGet's documented agreement flags.
- **No**: silent agreement acceptance does not grant or elevate Windows permissions.
- **Yes**: a script whose purpose is to suppress, evade, auto-accept, or work around an expected UAC or company approval prompt is likely to be challenged by security reviewers.
- **No**: copying selected functions from an unpinned Git repository is not automatically safer. That creates a private fork whose provenance, review history, dependencies, and updates must be maintained.
- **Yes**: a one-time, exact user-scope WinGet install followed by hash-and-publisher registration is a defensible design when it has the approval applicable to the device: explicit user POC authorization where permitted, or prior organizational approval where policy requires it.

The lab therefore keeps package-manager and download code in one visibly named `Install-PbixIntakeTools.Once.ps1` entry point. After explicit POC authorization, the agent runs that wrapper with silent installer mode, disabled WinGet interaction, and automatic acceptance of the source and package agreements. The normal intake path has no package-manager, download, elevation, execution-policy, Mark-of-the-Web, repair, or self-update code.

## Defensible control story

Provision TE2 and DAX Studio once, outside the repeated workflow. The run-once wrapper uses the canonical Microsoft WinGet source, exact package IDs and versions, user scope, vendor release URLs, WinGet installer-hash verification, and post-install executable verification. The owner or IT may instead use the organization's normal software channel or a reviewed portable archive. The lab then registers only:

- the absolute executable path;
- the product and file version;
- Authenticode status and publisher;
- the exact executable SHA-256 hash;
- hashes for the runtime-critical companion/configuration dependency set.

Every intake revalidates those values. A mismatch stops the run; the runtime never tries to repair it. This is strong drift/tamper evidence for ordinary operations, but a per-user installation and its evidence are writable by a process already running as that same user. Protected IT deployment plus application control is required if hostile same-user code is in scope. The provisioning wrapper refuses an elevated shell and has no machine-scope fallback. It does not hide or bypass UAC; if policy interrupts the supported user-scope transaction, the safe result is failure plus evidence for IT.

## Why TE2 skips one manifest dependency

TE2 2.28.0's source targets .NET Framework 4.8, but its current WinGet manifest declares the machine-scoped .NET Framework 4.6 Developer Pack. Installing that build-time developer pack is unnecessary for this runtime and is the part most likely to request elevation. The wrapper first reads the official .NET Framework runtime release key and requires 4.8 or later, then uses `--skip-dependencies` only for TE2. WinGet still verifies the TE2 archive hash, and the wrapper verifies the installed signed executable and runs it with `/?`.

## Honest UAC statement

DAX Studio's manifest has a user installer that supplies `/CURRENTUSER`, and the vendor says that mode requires no administrator rights. The same manifest declares `ElevationRequirement: elevatesSelf`, so no wrapper can promise that Windows or enterprise controls will never display UAC. `--disable-interactivity` affects WinGet prompts, not the secure desktop. The lab makes the non-admin selection explicit and never retries with broader rights.

## If source functions are vendored

Vendoring a small subset can reduce runtime surface area, but only when all of these are true:

1. source is pinned to an immutable commit and its license is retained;
2. the exact copied files and transitive dependencies are reviewed;
3. changes are recorded as a patch and covered by tests;
4. the local fork has an explicit update and vulnerability-review owner;
5. the code does not acquire credentials, elevate, install, or modify policy.

This lab avoids that maintenance obligation: it uses a small local PowerShell harness and invokes the signed vendor binaries through a fixed read-only argument grammar.

## Approval request language

> Request approval for one-time, current-user provisioning of pinned Tabular Editor 2 2.28.0 and DAX Studio 3.6.0 through the canonical WinGet community source. Provisioning preserves WinGet's installer hash validation, verifies the signed installed executables and their registered runtime dependency sets, records unique per-run evidence, requests no machine scope, and has no elevation fallback. Normal operation is local, non-elevated, read-only, and network-free. It revalidates publisher and SHA-256 on every run, connects only to the Analysis Services child of the selected local Power BI Desktop process, and exports semantic-model metadata. The normal runtime cannot deploy, save, refresh, publish, install, update, or collect report data.

For the initial POC, the user may explicitly authorize the agent to supply WinGet's documented `--silent`, `--disable-interactivity`, `--accept-source-agreements`, and `--accept-package-agreements` options. This removes routine package-manager prompts only. It does not approve UAC, override application control, grant administrative rights, or represent IT approval. The POC evidence is then supplied to management and IT for a broader-deployment decision.
