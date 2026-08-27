# Failure knowledge base

Every attempt writes `run.json`. A failure is actionable only when its `blockerCode`, message, and next action are preserved exactly.

The separate run-once installer writes `config/provisioning-logs/<run-id>/result.json` and bounded stdout/stderr logs. It never turns a provisioning failure into a runtime retry.

| Blocker code | Meaning | Safe next action |
| --- | --- | --- |
| `TOOLS_NOT_PROVISIONED` | `config/tools.json` does not exist | Run the one-time initializer with approved paths |
| `TOOL_MISSING` | A registered executable disappeared | Restore/reinstall it through the approved provisioning path, then reinitialize |
| `TOOL_CHANGED` | Path hash changed after provisioning | Review the update and rerun the initializer explicitly |
| `TOOL_DISTRIBUTION_CHANGED` | A registered runtime/configuration companion file changed, appeared, or disappeared | Review/reinstall the complete approved distribution, then reinitialize explicitly |
| `TOOL_IDENTITY_INVALID` | Filename/product identity is wrong | Select the genuine executable |
| `TOOL_SIGNATURE_INVALID` | Signature is absent, invalid, or from the wrong publisher | Stop and ask IT/vendor; do not bypass policy |
| `TOOL_VERSION_UNSUPPORTED` | Tool is older than the tested floor | Provision an approved supported version |
| `TOOL_RUNTIME_INCOMPLETE` | Harmless help smoke test fails | Reinstall the complete portable distribution; do not copy only the EXE |
| `TOOL_EXECUTION_BLOCKED` | App Control/AppLocker/EDR/policy blocked execution | Give the executable hash/publisher and logs to IT |
| `PBIX_NOT_OPEN` | No durable PBIX window is open | Open a PBIX and wait for its Data pane |
| `PBIX_TARGET_INVALID` | A path, switch-like value, wrong extension, or invalid basename was supplied | Supply one exact `.pbix` filename only |
| `PBIX_TARGET_NOT_FOUND` | Requested exact basename is not open | Use one of the names recorded in `run.json` |
| `PBIX_TARGET_AMBIGUOUS` | Several distinct PBIX files are open and no exact target was supplied | Rerun with `-PbixName` |
| `PBIX_TARGET_DUPLICATE` | The same basename is open in more than one Desktop process | Close one copy |
| `PBIX_TARGET_UNSAVED` | An untitled/unsaved model has no durable PBIX identity | Save it as PBIX first |
| `PBIX_MODEL_NOT_READY` | Desktop exists but its Analysis Services child/catalog/listener is not ready | Wait for the Data pane and retry once |
| `PBIX_IDENTITY_MISMATCH` | Desktop Bridge, window, PID, port, or catalog evidence conflicts | Stop, close stale Desktop instances, reopen the intended file |
| `PBIX_CONTEXT_AMBIGUOUS` | More than one AS child, listener, or catalog remains plausible | Close extra instances and retry |
| `TE2_ARGUMENT_CONTRACT_FAILED` | Generated TE2 arguments violate the fixed read-only grammar | Fix the argument builder; do not hand-edit the command |
| `READ_ONLY_GUARD_VIOLATION` | A deploy/write token such as `-D` appeared | Stop; extraction runs must never contain it |
| `TE2_TIMEOUT` | TE2 exceeded the bounded runtime | Confirm termination, wait for Desktop to finish loading, retry once |
| `TE2_EXECUTION_FAILED` | TE2 exited nonzero | Read the captured stdout/stderr and identity evidence |
| `MODEL_EXPORT_MISSING` | TE2 returned success without a new nonempty artifact | Treat as failure; never trust exit code alone |
| `MODEL_EXPORT_INVALID` | BIM is invalid JSON or TMDL is structurally empty | Preserve logs and rerun after model readiness is confirmed |
| `DAX_ARGUMENT_CONTRACT_FAILED` | Generated `dscmd` arguments confuse server/file/query modes | Fix the argument builder |
| `DAX_TIMEOUT` | `dscmd` exceeded the bound | Confirm termination and retry once |
| `DAX_CONNECTION_FAILED` | The fixed one-row query did not prove the selected model | Reopen/finish loading the target PBIX |
| `DAX_OUTPUT_INVALID` | Output is missing, duplicated, empty, or not the expected row | Preserve logs; do not publish the handoff |
| `REDACTION_FAILED` | A likely secret remains in an agent-facing artifact | Keep the run restricted and update redaction/review rules |
| `OUTPUT_NONDETERMINISTIC` | Same semantic input produced different canonical artifacts | Investigate ordering, locale, encoding, or volatile properties |
| `HANDOFF_OVERCLAIM` | Markdown claims the report layer or complete PBIX was captured | Correct the handoff and rerun validation |
| `RUN_ALREADY_ACTIVE` | Another intake owns the local mutex | Wait for that run to finish |
| `RUNTIME_PATH_INVALID` | A script-relative default resolved before `$PSScriptRoot` was available, or escaped the lab root | Resolve defaults after the `param` block and require absolute contained paths |
| `UNCLASSIFIED_FAILURE` | Failure was not mapped | Preserve the complete run folder and extend this catalog before retrying |

## Run-once provisioning failures

| Prefix/code | Meaning | Safe next action |
| --- | --- | --- |
| `PROVISION_ELEVATED_SESSION` | The wrapper was started from an administrator token | Close it and use a normal logged-in user shell |
| `PROVISION_USER_CONTEXT_INVALID` | The wrapper is running as SYSTEM | Run interactively as the intended user; WinGet does not support this path under SYSTEM |
| `PROVISION_OS_UNSUPPORTED` | Windows is not 64-bit | Use a supported 64-bit Windows device |
| `PROVISION_SHELL_UNSUPPORTED` | PowerShell is older than 5.1 | Use `powershell.exe` 5.1 or an approved newer host |
| `PROVISION_DOTNET_PREREQUISITE_MISSING` | .NET Framework 4.8 runtime release key is absent/old | Ask IT to provision the runtime; do not let the TE2 developer-pack dependency elevate |
| `WINGET_MISSING` | App Installer alias is unavailable | Ask IT to restore/update App Installer; do not hardcode a WindowsApps version path |
| `WINGET_IDENTITY_INVALID` | `winget.exe` is shadowed, its alias is not a reparse point, or Desktop App Installer identity cannot be corroborated | Stop and let IT repair App Installer/PATH; do not run the shadowing executable |
| `WINGET_CAPABILITY_MISSING` | Installed WinGet lacks one of the pinned safety flags | Update App Installer through the approved channel; do not drop the flag |
| `WINGET_SOURCE_IDENTITY_INVALID` | Source named `winget` is not the canonical Microsoft source | Stop and let IT repair source configuration |
| `WINGET_SOURCE_REFRESH_FAILED` | Explicit source update lacked a standalone `Done`, contained failure/cancellation/HRESULT evidence, or returned nonzero | Preserve logs and repair source access; do not install from cached metadata |
| `WINGET_TIMEOUT` | A source/package operation exceeded its bound | Read the logs and confirm no installer child remains before retrying |
| `WINGET_STEP_FAILED` | Source refresh, manifest resolution, or install returned an unaccepted code | Preserve the two logs; do not retry with machine scope, force, or ignored hashes |
| `WINGET_MANIFEST_CHANGED` | Same pinned version no longer exposes the audited URL/hash | Stop for a publishing/security review |
| `TOOL_MISSING_AFTER_INSTALL` | HKCU install evidence does not resolve exactly one executable | Inspect per-user uninstall entries and WinGet logs; do not guess a path |
| `TOOL_REGISTRATION_FAILED` | Installed binary failed identity/signature/hash/help registration | Preserve evidence and ask IT/vendor; do not bypass the check |

## Hallucinations to reject immediately

- `TabularEditor.exe "Report.pbix" ...` for a closed PBIX.
- TE2 `-S "Report.pbix"`; `-S` is script, not select.
- `dscmd -L "Report.pbix"`; `dscmd` uses `--server`.
- treating `dscmd vpax -l` as a local-PBIX selector; there it means Direct Lake mode.
- `dscmd ... -q query.dax`; `-q` is inline DAX, while `-f` reads a file.
- `DaxStudio.exe` for automation; use `dscmd.exe`.
- standardizing on uppercase `dscmd CSV` or `dscmd VPAX`; 3.6 is case-insensitive, but the supported 3.5.2 floor requires lowercase `csv` and `vpax`.
- `winget install TabularEditor.TabularEditor`; the exact TE2 package ID is `TabularEditor.TabularEditor.2`.
- omitting `--exact`, `--version`, `--source winget`, or `--scope user` from the run-once install.
- retrying a failed user install with `--scope machine`, `Start-Process -Verb RunAs`, `--force`, `--override`, or `--ignore-security-hash`.
- claiming `--disable-interactivity` can suppress an operating-system UAC prompt; it only disables WinGet prompts.
- copying only `dscmd.exe` out of the DAX Studio distribution.
- combining TE2 `-B` and `-TMDL` in one invocation.
- adding TE2 `-D`, `-E`, `-W`, or deployment options to an extraction.
- passing a full PBIX path where a Desktop filename is required.
- claiming a successful model connection proves page filters, slicers, bookmarks, or visual context.
- using `Join-Path $PSScriptRoot ...` as a parameter-default expression without testing Windows PowerShell 5.1; resolve script-relative defaults after `param`.
- treating Power BI's `TempSaves\~$*.pbix` child process and `Untitled` window as another user-open report.

## Shell/runtime traps proven in the sandbox

- `Start-Process -ArgumentList` does not preserve an array as native `argv`; without correct Windows quoting, spaces and `&` can split or change arguments.
- Windows PowerShell 5.1 may unwrap a zero- or one-element pipeline result. Use explicitly typed arrays before reading `.Count`.
- Windows PowerShell 5.1 reads UTF-8-without-BOM as the legacy ANSI code page unless `-Encoding UTF8` (or an explicit UTF-8 reader) is used.
- PowerShell 7.3 changed direct native argument passing. Do not let an agent switch launch strategies based on shell folklore; use the tested Windows quoting wrapper and inspect the child process exit code.
- WinGet does not refresh the current shell's `PATH` after an install. Resolve the per-user installation from HKCU/its install location and register the absolute executable path.
- WinGet can use cached source data after an automatic refresh warning, and some launcher paths can obscure a leaf failure behind exit zero. The run-once wrapper requires explicit source-update output containing a standalone `Done` and rejects failure, cancellation, or `0x8...` evidence even when the observed exit code is zero.
- A successful TE2/dscmd exit code is not a file-validity check. Parse BIM, require `.tmdl` files, validate the exact CSV row, and hash the artifacts.
- With several large Desktop models open, `dscmd vpax` can report a socket buffer/queue exhaustion error yet return exit zero and create no VPAX. The artifact guard correctly returns `DAX_OUTPUT_INVALID`; close only the extra, positively identified test PBIX processes and retry the selected model.
- Do not cache a Desktop port/catalog. Rediscover them from the selected PID and its current `msmdsrv` child every run.
