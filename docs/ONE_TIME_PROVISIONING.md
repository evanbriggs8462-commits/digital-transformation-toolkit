# One-time tool provisioning

The intake runtime never installs software. Provision the two tools once, register their exact binaries, and then run all PBIX captures offline from that fixed registration.

## Standard agent-run POC path

Once the user explicitly authorizes the one-time POC installation, the agent—not the user—runs this exact command from the lab root in the user's normal, non-elevated Windows session:

```powershell
& "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -File .\Install-PbixIntakeTools.Once.ps1
```

The wrapper is deliberately pinned to:

| Tool | WinGet ID | Version | Scope | Architecture | Installer |
| --- | --- | --- | --- | --- | --- |
| Tabular Editor 2 | `TabularEditor.TabularEditor.2` | `2.28.0` | user | x86 | portable ZIP |
| DAX Studio | `DaxStudio.DaxStudio` | `3.6.0` | user | x64 | Inno `/CURRENTUSER` |

It performs this fixed sequence:

1. Requires 64-bit Windows, PowerShell 5.1 or later, a logged-in user token, and a non-elevated process.
2. Requires `winget.exe` to resolve through the current user's App Installer alias, verifies that alias is a reparse point, and corroborates the Microsoft Desktop App Installer package identity. It never trusts an earlier PATH entry or hardcodes a versioned WindowsApps path.
3. Verifies that source `winget` is the canonical Microsoft source and requires a successful source refresh. A stale-cache fallback is not accepted.
4. Checks that the local WinGet client exposes every safety option used by the wrapper.
5. Requires .NET Framework 4.8 (`Release >= 528040`). TE2 2.28 targets 4.8, although its current WinGet manifest incorrectly names the machine-scoped .NET 4.6 Developer Pack. Only after the runtime check does the TE2 command use `--skip-dependencies`.
6. Resolves the exact package ID, version, source, user scope, architecture, and installer type. It compares WinGet's displayed installer URL and SHA-256 with the audited values before installation.
7. Runs each install separately with `--silent`, `--disable-interactivity`, and the two agreement-acceptance flags. It never retries without user scope.
8. Resolves the resulting HKCU installation, verifies exact product version, executable SHA-256, Authenticode validity, and expected publisher, then runs bounded help smoke tests.
9. Records hashes for TE2's distribution and DAX `dscmd`'s launcher/config, directly probed managed dependencies, current x64 native dependency, and current UI-culture resources. Every intake checks that set before execution.
10. Writes `config/tools.json` and unique per-run evidence under ignored `config/provisioning-logs/`.

After a previously successful provision, an explicitly authorized repeat verification is idempotent: WinGet may report that no update applies, but the wrapper still accepts the result only after the pinned executable passes every independent check. This is not an automatic recovery path. After any UAC, policy, timeout, or installation failure, preserve the evidence and wait for renewed user or IT direction before rerunning it.

### Silent acceptance contract

The wrapper, not an improvised agent command, supplies all four noninteractive switches:

| Switch | What the POC authorizes |
| --- | --- |
| `--silent` | Requests the selected vendor installer's silent mode. |
| `--disable-interactivity` | Prevents ordinary WinGet questions and makes an unanswered WinGet interaction fail. |
| `--accept-source-agreements` | Accepts the canonical WinGet source agreement on the user's behalf. |
| `--accept-package-agreements` | Accepts the pinned third-party package-license terms on the user's behalf. |

The user does not need to paste commands or click through those WinGet agreements. The agent must wait for the wrapper, inspect its exit status, and confirm that `config/tools.json` records both validated tools before starting an intake.

These flags do not grant Windows permissions. They cannot answer a UAC secure-desktop prompt, approve an application-control exception, or override organizational policy. A prompt or policy block is a fail-closed handoff to the user or IT, never a reason to elevate or loosen the command.

### POC-to-IT handoff

1. The user explicitly authorizes the one-time POC installation and agreement acceptance.
2. The agent runs the wrapper silently and retains its unique `config/provisioning-logs/` evidence.
3. The agent runs a representative PBIX intake and retains the successful run manifest and Genie handoff.
4. The user demonstrates the result and control boundaries to the boss.
5. IT reviews the pinned versions, package manifests, hashes, publishers, evidence, and approval request before broader deployment.

A successful POC proves that the workflow works on the test device; it does not itself constitute IT approval.

## UAC and company policy

This is a supported current-user installation path, not a UAC bypass:

- the wrapper refuses to run from an elevated token;
- every install contains `--scope user`;
- there is no `Start-Process -Verb RunAs`, machine-scope retry, `--force`, `--override`, or `--ignore-security-hash` path;
- TE2 is a user-portable app whose executable requests `asInvoker`;
- DAX Studio's user manifest supplies `/CURRENTUSER`, which its vendor documents as not requiring administrator rights.

WinGet nevertheless labels the DAX installer `elevatesSelf`. `--disable-interactivity` disables WinGet questions; it cannot suppress an operating-system UAC prompt or override App Control. If Windows or enterprise policy prompts or blocks the transaction, cancel it and give IT the evidence rather than trying another scope.

The agreement flags accept the WinGet source and vendor package terms without a WinGet prompt. The user's explicit POC authorization is the trigger for the agent to use them. An organization that requires separate legal or IT approval of those terms must provide it before this file is run.

## IT-provisioned alternative

If software is already deployed through the company channel, do not run WinGet. Register the exact executables instead:

```powershell
& "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -File .\Initialize-PbixIntakeLab.ps1 `
  -Te2Path "C:\approved\TabularEditor.exe" `
  -DscmdPath "C:\approved\DAX Studio\dscmd.exe"
```

Do not copy only `dscmd.exe`; it depends on the companion files in the DAX Studio distribution. Request a publisher or exact-hash allow rule, not a broad allow rule for a user-writable directory. Do not remove Mark-of-the-Web, lower execution policy, or bypass App Control.

Per-user installs remain writable by the same Windows user. The dependency manifest reliably detects accidental drift and ordinary replacement before a run; it is not a security boundary against a hostile process already running as that user, because such a process can alter both programs and user-owned registration evidence. IT deployment under protected `Program Files` plus application control is the stronger option when that threat model matters.

## Shell contract

The canonical outer command and the wrapper's initializer call both use the explicit System32 Windows PowerShell path. The file uses syntax supported by Windows PowerShell 5.1 and does not rely on PowerShell 7.3 native-argument behavior. Every process launched directly by the wrapper is time-bounded, its actual exit code is checked, and its paths use the lab's Windows command-line quoting routine. A timeout can terminate the direct WinGet process before an installer descendant exits, so the safe next action is to inspect the process/log evidence and confirm no installer child remains before retrying.

See `PUBLISHING_AUDIT_2026-08-26.md` for release/manifests and `SECURITY_POSITION.md` for the approval case.
