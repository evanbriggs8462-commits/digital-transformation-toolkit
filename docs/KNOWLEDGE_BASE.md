# PBIX semantic-intake knowledge base

## Scope

The lab captures the semantic model loaded inside Power BI Desktop. It does not reverse-engineer the closed PBIX package and does not capture the report canvas.

### Captured through BIM/TMDL/TOM

- model compatibility, culture, annotations, and settings
- data sources and connection metadata, with redacted agent copies
- tables, hidden state, descriptions, lineage tags, storage behavior
- columns, source columns, calculated columns, data types, formats, categories, sort-by, keys
- measures, DAX, format strings, dynamic format strings, folders, KPIs
- calculation groups and calculation items
- hierarchies and levels
- relationships, direction, active state, cardinality, security filtering behavior
- partitions, storage modes, M/SQL source expressions, incremental-refresh metadata
- shared expressions/parameters and query groups represented by TOM
- roles and row/object-level security expressions; principal membership is not promised
- perspectives, cultures, translations, and annotations

TMDL is the canonical readable artifact. BIM is retained as a full JSON snapshot that the normalizer can process.

### Deliberately not captured

- pages, visuals, layout, visual field bindings, themes
- report/page/visual filters and slicer selections
- visual interactions, bookmarks, navigation, drillthrough, tooltip pages
- cached/imported business rows
- credentials or refresh secrets
- Power BI service permissions, gateways, schedules, endorsements, or lineage outside the local model

Users may supply report-layer context separately to Genie. The handoff must never infer it.

## Run sequence

1. Enumerate Power BI Desktop processes. Ignore a blank/`Untitled` window only when no durable Desktop Bridge or command-line PBIX identity exists for that PID.
2. Select one exact PBIX basename; fail on zero, multiple, duplicate, path, or fuzzy matches.
3. Correlate the Desktop PID to its `msmdsrv.exe` child.
4. Resolve the live listener and exact catalog from that process's workspace.
5. Revalidate the registered TE2 and DAX Studio paths, executable/dependency hashes, versions, and Authenticode publishers.
6. Export BIM and TMDL in separate bounded TE2 processes. No C# script and no deploy switch are used.
7. Parse BIM, create deterministic sorted inventories, and redact sensitive literals from agent-facing copies.
8. Run one fixed DAX connection query and create VPAX with data-statistic scans disabled.
9. Validate files, scan published agent artifacts for secrets/overclaims, hash everything, then publish `GENIE_HANDOFF.md`.

## Identity rules

- A PBIX name is a filename only.
- Omitted `.pbix` is normalized once; all matching is exact and case-insensitive.
- Two open copies with the same basename are ambiguous even if their directories differ.
- Window-title evidence is weaker than Desktop Bridge exact-path/PID evidence.
- Internal Analysis Services database names are not PBIX identity and are never used as a fuzzy fallback.
- Ports and catalogs are rediscovered every run. They are never cached.
- A port is trusted only when it belongs to the selected Desktop process's Analysis Services child.

## Determinism

- Each run writes into a new uniquely named directory.
- Normalized arrays use ordinal name ordering.
- Agent files use UTF-8 without BOM and LF newlines.
- Timestamps and machine-specific paths stay in `run.json`, `identity.json`, and `manifest.json`; they are excluded from the semantic handoff.
- An unchanged model should produce identical normalized artifacts and `GENIE_HANDOFF.md`.

## Security and privacy

- Tool provisioning is separate from runtime and occurs once.
- Normal runs have no network, download, install, update, repair, or privilege-elevation path.
- Raw BIM/TMDL may expose server names, paths, M source text, and accidentally embedded secrets. Treat raw artifacts as internal restricted evidence.
- Normalized files redact common password, token, API-key, SAS, account-key, bearer-token, Databricks PAT, GitHub token, and OpenAI key forms.
- If the final scan still detects a likely secret, the run fails and no Genie handoff is authoritative.
- VPAX uses `--donotreadstatsfromdata`; it retains TOM metadata but avoids distinct-count data scans.

## Genie handoff

`GENIE_HANDOFF.md` is a routing and reconstruction guide, not the only source of truth. Genie should read `coverage.json`, then the normalized inventories, then raw TMDL only when access is approved.

For Genie Code, the handoff can be supplied alongside the artifact tree or adapted into `AGENTS.md`. For a Genie Agent, translate the semantic definitions into Unity Catalog descriptions, joins, SQL expressions, metric views, and verified example SQL rather than pasting one giant Markdown block.

## Public test corpus

`tests/Get-OfficialPbixSamples.ps1` downloads only files pinned to an immutable commit in Microsoft's MIT-licensed `powerbi-desktop-samples` repository. Each corpus entry records its source URL, expected SHA-256, size, license, and purpose. Samples are test inputs and are not bundled in releases.
