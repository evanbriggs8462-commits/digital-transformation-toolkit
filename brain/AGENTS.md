---
id: brain.agent-contract
status: binding
scope: brain-sidecar
audience: [ai-agent]
last_reviewed: 2026-08-20
---

# Brain Agent Contract

This file governs AI agents operating the brain framework or a populated local brain workspace.

## Startup

1. Read `brain/manifest.yaml` first.
2. Load only the documents relevant to the current task.
3. Do not read the entire historical corpus into context.
4. Determine whether the request is metadata, numeric calculation, reconciliation, code generation, artifact discovery, or Genie enrichment.
5. Check current runtime capabilities before planning execution.

## Source precedence

Use evidence in this order:

1. Current live system observation for the exact object and time.
2. Current validated runtime result.
3. `PROMOTED` knowledge.
4. `VERIFIED` knowledge.
5. `RUNNABLE` candidates with explicit validation required.
6. `NEEDS_CONTEXT`, `PARSED`, or `RAW` material for investigation only.

Never automatically execute `BROKEN`, `SUPERSEDED`, `ARCHIVED`, or `RESTRICTED_SECRET` assets.

## Trust states

Supported states:

```text
RAW
PARSED
LIKELY_USEFUL
NEEDS_CONTEXT
BROKEN
RUNNABLE
VERIFIED
PROMOTION_CANDIDATE
PROMOTED
SUPERSEDED
ARCHIVED
RESTRICTED_SECRET
```

Trust must be supported by provenance and evidence. A filename containing `final`, a model confidence score, or an assistant statement that something worked is insufficient.

## Evidence ranking

Prefer:

1. Matched control total or explicit validation.
2. Expected output created and independently verified.
3. Successful process exit code with relevant output.
4. Subsequent successful use.
5. User confirmation.
6. Assistant claim without supporting evidence.

Label claims and inferences. Do not present them as verified facts.

## Numeric and calculation requests

When the user asks for a value, amount, count, percentage, trend, variance, reconciliation, or other evaluated result, do not finish by merely suggesting DAX, SQL, or Python code when execution is available.

Required flow:

1. Identify the exact PBIX/PBIP or data target.
2. Retrieve relevant promoted/verified context.
3. Validate measures, fields, filters, and source objects against the live environment.
4. Construct a read-only query.
5. Execute through the approved wrapper.
6. Wait for termination.
7. Validate the output artifact.
8. Return the actual result with model/source, expression, filters, assumptions, and provenance.

Only return unexecuted code as completion when the user explicitly asks for code, execution capability is unavailable, target selection is ambiguous, or required filter context cannot be determined.

Do not instruct the user to paste generated code manually into DAX Studio or Databricks when an approved local execution path exists.

## Tool routing

```text
Model structure or definitions
→ TE2 metadata

Actual Power BI values
→ TE2 validation + DAX Studio/dscmd

Current catalog/schema/table metadata
→ Unity Catalog information schema or approved REST/SDK probe

Source control total
→ Databricks SQL

Variance diagnosis or fuzzy matching
→ Databricks SQL + Python

Natural-language workspace resolution
→ evidence-backed Genie problem packet

Historical artifact question
→ registry + full-text + relationships + trust ranking
```

PowerShell coordinates processes and validates outputs. It is not the numerical calculation engine.

## Live validation

Historical context is a candidate plan, not current truth.

- Validate old Power BI measure names against current TE2 metadata.
- Validate old UC object names against live accessible metadata.
- Validate stored report/source mappings against current M or REST observations.
- Record drift instead of overwriting history.
- Refuse to guess when two reports or objects remain ambiguous.

## Retrieval order

1. Exact identifiers and metadata filters.
2. Promoted report/business profiles.
3. SQLite full-text search.
4. Relationship traversal.
5. Curated vector similarity if enabled.
6. Raw corpus inspection only for unresolved investigations.

Semantic similarity finds candidates. It does not authorize execution.

## Cost discipline

- Hash, enumerate, parse, and deduplicate without a model.
- Never send exact duplicates to a model.
- Summarize sessions deterministically before reasoning.
- Use inexpensive models for bulk tagging.
- Escalate conflicts and promotion candidates to a stronger model.
- Persist checkpoints and skip unchanged files.
- Record input tokens, output tokens, latency, and reported cost where available.
- Stop at configured usage gates.

## Security

Never read into model context, emit, embed, or store secret values from:

- `.env`
- `.databrickscfg`
- `auth.json`
- PAT/token files
- Authorization headers
- private keys
- credential-bearing connection strings
- browser/session authentication

Store only path, category, redacted fingerprint/hash, and exclusion status.

## Business knowledge discipline

SAP and finance implementations are configurable. Store company/report observations as scoped claims, not universal truths.

A knowledge card must include:

- claim;
- system/process scope;
- evidence;
- filters and assumptions;
- validation state;
- exceptions;
- conflicts;
- permitted use: execution, analysis context, or Genie enrichment.

## Completion evidence

Do not declare success because a process launched. Success requires the expected validated result or artifact. On failure, report a structured blocker, whether it is retryable, whether IT/admin action is required, and the next safe action.
