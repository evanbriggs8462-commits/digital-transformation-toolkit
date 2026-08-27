# Open-PBIX discovery playbook

This is the order an agent must use. Do not start by asking the user to retype a path, and do not spend tokens guessing spelling.

## Evidence chain

For every `PBIDesktop.exe` process, collect all available name evidence:

1. **Desktop Bridge** `application.state.get/v1`: current file path, unsaved state, and owning Desktop PID.
2. **Process command line**: a quoted `.pbix` argument and owning Desktop PID. This is a fallback when the preview bridge is missing or not ready.
3. **Window title**: convert the durable title to a `.pbix` basename. Ignore blank and `Untitled` startup windows.

Never fuzzy-match these values. If two available routes for one PID resolve to different basenames, return `PBIX_IDENTITY_MISMATCH`. If the routes agree, record all of them and the chosen source. If only one route is available, continue with that evidence; do not give up merely because Desktop Bridge is absent.

Ignore Power BI's internal recovery/conversion children as selectable reports. In observed multi-open testing, Desktop spawned an additional `PBIDesktop.exe` with an `Untitled` window and a command-line PBIX under `Power BI Desktop ...\TempSaves\~$...pbix`. A `~$` basename, a `TempSaves` path, or equivalent temporary-recovery evidence is diagnostic process noise, not a fourth user report.

After selecting one exact Desktop PID:

4. Find the `msmdsrv.exe` whose `ParentProcessId` is that Desktop PID.
5. Read the model workspace from that process's `-s "...\Data"` command-line argument.
6. Resolve the port from both the live TCP listener owned by that exact `msmdsrv` PID and `msmdsrv.port.txt`.
7. Use the live PID-owned listener when a stale port file disagrees, and record the conflict/source. Never reuse a cached port.
8. Require exactly one current `*.db.xml` in that workspace and read its Database ID as the catalog. Do not select "newest" among several files and do not substitute a guessed database name.
9. Connect TE2 and `dscmd` with the resulting explicit `localhost:<port>` plus catalog.

## Multiple reports

- Zero durable targets: `PBIX_NOT_OPEN`.
- One target and no name supplied: select it.
- More than one distinct basename and no name supplied: `PBIX_TARGET_AMBIGUOUS`, with all discovered names/PIDs in `run.json`.
- Exact requested basename not present: `PBIX_TARGET_NOT_FOUND`; show the discovered names, but do not autocorrect.
- Same basename in two Desktop PIDs: `PBIX_TARGET_DUPLICATE`; close one copy.
- Exact name present once: select its PID, even when other PBIXs are open.

A full path supplied by a user is rejected as `PBIX_TARGET_INVALID`; the runtime accepts a basename because identity comes from the already-open Desktop process, not from opening or rewriting a closed package.

## Readiness versus discovery

During startup, the command line may already identify the intended PBIX while its window still says `Untitled` and no Analysis Services child exists. That is not "file not found." Preserve the discovered name and return `PBIX_MODEL_NOT_READY` with the instruction to wait for the Data pane.

## Agent stop rule

Ask the user for help only after the run has emitted a classified blocker and the recorded evidence cannot distinguish the target. The next question should cite the exact discovered names/PIDs or conflict; never ask an open-ended "where is the PBIX?" question first.
