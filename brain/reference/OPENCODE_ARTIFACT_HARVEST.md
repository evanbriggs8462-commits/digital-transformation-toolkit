---
id: brain.reference.opencode-harvest
status: implementation-guide
scope: local-read-only-corpus
audience: [ai-agent, developer]
last_reviewed: 2026-08-20
---

# OpenCode Artifact and Session Harvest

## 1. Objective

Convert a scoped collection of project folders and recoverable OpenCode sessions into a searchable evidence registry without manually reviewing every script and without spending high-reasoning tokens on deterministic work.

## 2. Scope discipline

- Start at approved project roots, not the entire device.
- Keep historical source folders read-only.
- Write only under a dedicated brain workspace.
- Exclude package caches, virtual environments, `node_modules`, binaries, and runtime noise unless metadata is needed.
- Record large-file size and row-count metadata before deciding on full scans.
- Use randomized/multi-position samples when the first rows may be blank, null, malformed, or unrepresentative.

## 3. Relevant files

Common inputs:

```text
.ps1 .psm1 .py .sql .dax .csx .cs .ipynb
.md .txt .json .jsonl .yaml .yml .toml .csv
.patch .bundle metadata exports and audit evidence
```

For binaries or unsupported formats, record path, hash, size, type, and provenance only.

## 4. Deterministic inventory

For every artifact collect:

- SHA-256;
- canonical and relative path;
- size and timestamps;
- extension and inferred type;
- Git branch/commit/status where available;
- exact duplicate group;
- probable version family;
- syntax parse result;
- imports/functions/classes;
- referenced files and outputs;
- SQL/UC objects, joins, filters, and CTEs;
- DAX measures/tables/columns and filters;
- PowerShell commands and executable dependencies;
- Python packages and entry points;
- PBIX/PBIP names;
- SAP tables, fields, T-codes, conditions, material types, and business terms;
- possible secret exclusion.

Do not use a model to calculate hashes, enumerate files, locate exact strings, or parse obvious static structure.

## 5. Version-family detection

Use multiple signals:

- normalized filename tokens;
- content hash and near-duplicate similarity;
- shared imports/tables/functions;
- Git history;
- session references;
- generated outputs;
- explicit supersession notes.

Never select authority based only on names like `final`, `fixed`, or `REAL`.

## 6. OpenCode session recovery

Inspect the installed OpenCode CLI help before assuming syntax because versions can differ. Where supported, use session-list, export, and usage/stat commands to recover sessions associated with the scoped project.

Store raw exports in a restricted Bronze folder. Do not send complete raw sessions to a model.

Parse compact facts:

- session ID/date/project;
- user objective and business question;
- supplied filters and assumptions;
- files read/created/modified;
- commands and tool calls;
- exit codes and errors;
- output artifacts;
- validation results;
- PBIX/PBIP names;
- DAX measures;
- SAP and UC objects;
- Genie prompts/responses;
- references to corrected or superseding work.

Classify facts:

```text
USER_CLAIM
ASSISTANT_CLAIM
COMMAND_EVIDENCE
FILE_EVIDENCE
VALIDATION_EVIDENCE
LATER_SUCCESSFUL_USE
```

Link session facts to exact artifact hashes whenever possible.

## 7. Trust assignment

Automatic rules can propose states but should preserve evidence.

Examples:

| Evidence | Candidate state |
|---|---|
| Exact duplicate | duplicate relationship |
| Syntax failure | BROKEN |
| Repeated failed execution | BROKEN |
| Later validated replacement | SUPERSEDED |
| Syntax pass, no run evidence | RUNNABLE |
| Successful run + expected output | VERIFIED |
| Successful run + control total + reuse | PROMOTION_CANDIDATE |
| Secret detected | RESTRICTED_SECRET |

Nothing is deleted automatically.

## 8. Model usage strategy

### Scout

Use a fast inexpensive coding model for compact classification of deterministic summaries.

### Curator

Use moderate reasoning for project grouping, business-rule extraction, and relationship suggestions.

### Reviewer

Use high reasoning only for:

- conflicting implementations;
- promotion candidates;
- material business-rule disagreements;
- security concerns;
- high-value assets without reliable evidence.

### Operator

Use a capable coding/reasoning model to execute promoted recipes and validate outputs.

The alias name alone does not prove capability. Benchmark the actual configured endpoints on a representative sample.

## 9. Cost gates

Recommended stop gates:

```text
Stage 1: deterministic scan only
Stage 2: classify 20–30 representative artifacts
STOP and report tokens/cost/accuracy
Stage 3: classify first 100 deduplicated assets
STOP and forecast full corpus
Stage 4: full classification only after approval
```

Suggested initial POC limits:

- no more than two concurrent model workers;
- no recursive subagent trees;
- high-reasoning escalation below 10–15% of the corpus;
- compact JSON outputs;
- no unchanged artifact reprocessing;
- no exact duplicates sent to a model;
- raw logs and sessions summarized first.

Track:

- input/output tokens;
- reported cost or equivalent cost;
- latency;
- artifacts processed;
- classifications corrected;
- hallucination rate;
- cost per useful classified artifact.

## 10. Retrieval bakeoff

Benchmark:

1. exact identifiers;
2. filename/path search;
3. SQLite FTS5;
4. metadata-filtered FTS;
5. relational relationship traversal;
6. curated vector search;
7. hybrid FTS/vector;
8. graph-assisted retrieval.

Use known-answer questions and score precision@5, reciprocal rank, trust-state compliance, latency, token volume, and explainability.

Vector search should index compact redacted summaries. It should not index raw credentials, full session transcripts, or every full script.

## 11. Output shape

The first harvest should produce:

```text
brain-workspace/
  state.json
  logs/
  registry/brain.sqlite
  exports/artifacts.jsonl
  exports/session_facts.jsonl
  exports/execution_evidence.jsonl
  exports/business_rules.jsonl
  exports/relationships.jsonl
  exports/trust_assignments.jsonl
  reports/inventory_summary.md
  reports/session_recovery_report.md
  reports/retrieval_benchmark.md
  reports/review_queue.md
```

The review queue should contain no more than ten high-value questions for the human owner.

## 12. What the first harvest must not do

- execute discovered business scripts;
- connect to remote systems unless explicitly entering the live-validation phase;
- automatically delete or consolidate source files;
- label artifacts verified from prose alone;
- build a graph database because GraphRAG sounds advanced;
- classify the entire corpus before sample cost/quality results are known.
