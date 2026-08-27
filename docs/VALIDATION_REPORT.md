# Validation report

Validated on 2026-08-26 with:

- Power BI Desktop Store app `2.157.879.0`
- signed Tabular Editor 2 `2.28.0` (`2.28.9557.26801` file version)
- signed DAX Studio `dscmd` `3.6.0.1243` (plus compatibility evidence from `3.5.2.1205`)
- WinGet `1.29.290`
- Windows PowerShell 5.1

## POC operator-contract update (2026-08-27)

The agent instructions now make the authorized one-time POC provision an agent-owned step. They explicitly document that the audited wrapper supplies `--silent`, `--disable-interactivity`, `--accept-source-agreements`, and `--accept-package-agreements`; none of those options can approve UAC or override company policy. Regression assertions now require both agreement-acceptance flags in every pinned package command. The complete offline adversarial suite was rerun after this update: **33/33 PASS**.

## One-time provisioning

The run-once wrapper completed from a non-elevated user session with no machine-scope or elevation fallback:

- canonical WinGet source identity and explicit refresh: PASS
- exact TE2 2.28.0 x86 user-portable selection: PASS
- exact DAX Studio 3.6.0 x64 `/CURRENTUSER` selection: PASS
- installed executable version, pinned SHA-256, and Authenticode publisher checks: PASS
- bounded TE2 and `dscmd` help smoke tests: PASS
- runtime dependency registration: 26 TE2 files and 179 current `dscmd` files
- complete registration recheck: PASS in approximately 3.1 seconds

Every provisioning attempt that can create its configured evidence directory has its own `config/provisioning-logs/<run-id>/result.json`; host/user preflight failures are recorded there before WinGet is invoked. Tool steps also retain stdout/stderr logs. This is unique per-run evidence, not immutable storage.

## Automated contract tests

- Adversarial suite: **33/33 PASS**
- Live discovery matrix: **7/7 PASS**
- Artifact-manifest hash recheck on the final DAX 3.6.0 export: **29/29 PASS**

The live matrix observed three durable PBIX identities concurrently. Two visible test reports exposed all three discovery routes; the user's background report exposed Desktop Bridge evidence but no usable command-line/window filename and was correctly excluded only from fallback-route equality. The matrix proved:

1. Desktop Bridge plus corroborating command-line/window evidence;
2. Desktop Bridge disabled, forcing command-line/window fallback;
3. Desktop Bridge and command-line discovery disabled, forcing window-title fallback;
4. exact-name selection and no-name ambiguity;
5. misspelling rejection without fuzzy correction;
6. selected Desktop PID to its own `msmdsrv` PID, live listener, port, and catalog mapping;
7. exclusion of Power BI internal `TempSaves\~$*.pbix` identities.

## End-to-end semantic exports

| PBIX | Tables | Columns | Measures | Relationships | Result |
| --- | ---: | ---: | ---: | ---: | --- |
| `Revenue Opportunities.pbix` | 9 | 69 | 6 | 6 | PASS on DAX 3.6.0, including metadata-only VPAX |
| `AdventureWorks Sales.pbix` | 10 | 62 | 20 | 9 | PASS on the supported DAX 3.5.2 floor |
| `Sales & Returns Sample v201912.pbix` | 18 | 86 | 58 | 9 | PASS on the supported DAX 3.5.2 floor, including spaces and `&` |

The final Revenue run (`20260826T204434034Z_f6b8d61f76b9`) used the schema-2 dependency registration and produced valid BIM, nonempty TMDL, a one-row `PbixIntakeConnection=OK` CSV, metadata-only VPAX, redacted normalized JSON, scope coverage, a deterministic Genie handoff, logs, identity/command evidence, and a 29-file manifest with zero hash mismatches.

A repeated Revenue run produced byte-identical:

- `semantic_model/model.bim`
- every TMDL file
- `normalized/model.redacted.json`
- `GENIE_HANDOFF.md`

`coverage.json` intentionally differed when VPAX was requested in one run and skipped in the other.

## Expected negative runs

- Several distinct open PBIXs with no exact name: `PBIX_TARGET_AMBIGUOUS`
- Deliberate `Revenue Opportunites.pbix` misspelling: `PBIX_TARGET_NOT_FOUND`
- Duplicate open `AdventureWorks Sales.pbix` basenames: `PBIX_TARGET_DUPLICATE`
- Loading/untitled sample windows: fallback route withheld until durable identity evidence appeared
- Concurrent intake attempt: `RUN_ALREADY_ACTIVE`
- Exit-zero fake tool with no artifact: `MODEL_EXPORT_MISSING`
- Changed companion DLL: `TOOL_DISTRIBUTION_CHANGED`
- WinGet source output containing failure/HRESULT with exit zero: `WINGET_SOURCE_REFRESH_FAILED`
- Five concurrently loaded Desktop models exhausted the VPAX socket buffer/queue; `dscmd` returned zero but produced no file, and the run correctly stopped as `DAX_OUTPUT_INVALID`
- Bounded fake tool over timeout: categorized timeout with confirmed direct-process termination

Each negative attempt retained a blocker code, stage, message, next action, and the evidence known at failure time. After the VPAX resource failure, only positively identified lab sample processes were closed; the clean retry passed.

## Real regressions found and fixed during sandboxing

- `dscmd` 3.5.2 rejected uppercase `CSV`; lowercase grammar now works on both 3.5.2 and case-insensitive 3.6.0.
- `Start-Process -ArgumentList` split paths/values containing spaces until a Windows command-line quoting routine was added.
- Windows PowerShell 5.1 unrolled empty/singleton collections and raised missing `.Count` errors until arrays were typed explicitly.
- `$PSScriptRoot` was empty in script parameter-default expressions; defaults now resolve after `param`.
- Generic-list serialization produced `Argument types do not match`; results now convert explicitly to object arrays.
- UTF-8-without-BOM JSON was decoded as ANSI by PowerShell 5.1, corrupting a signer subject; all owned UTF-8 reads are explicit.
- Power BI spawned a hidden/temporary `TempSaves\~$...pbix` Desktop/model pair; discovery now excludes it.
- A PowerShell backslash/character literal broke manifest creation after all exports had succeeded; manifest path normalization is now tested.
- Bridge-only background reports caused an impossible window-fallback comparison; fallback tests now compare only targets that actually expose that route while retaining those reports as valid Bridge targets.
- WinGet source refresh could look successful at a launcher boundary while leaf output said `Failed`; source output is now parsed fail-closed.
- Executable-only hashes left companion DLL drift undetected; the schema-2 registration now validates the runtime-critical dependency set.

## Scope boundary

These tests validate semantic-model intake only. The report layer - pages, visuals, layout, filters, slicers, bookmarks, and interactions - was deliberately not collected and cannot be reconstructed from this handoff alone.
