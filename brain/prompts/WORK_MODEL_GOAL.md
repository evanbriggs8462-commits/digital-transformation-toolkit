---
id: brain.prompt.work-model
status: reusable-prompt
scope: local-opencode-project
audience: [opencode-goal, coding-agent]
last_reviewed: 2026-08-20
---

# Work-Model `/goal`: Local Brain Harvest POC

Run this from the root of the approved OpenCode project folder.

```text
Build a cost-controlled, local-only project brain POC from this workspace and
recoverable OpenCode sessions associated with it.

Do not modify, rename, move, delete, or execute historical project artifacts.
Create all outputs under `.brain-poc/`.

PRECEDENCE

Read these repository files first:
- brain/AGENTS.md
- brain/manifest.yaml
- brain/schemas/brain.schema.json
- brain/sql/brain_registry.sql
- brain/reference/OPENCODE_ARTIFACT_HARVEST.md

SCOPE

- Current workspace and explicitly approved source roots only.
- Do not crawl the entire device.
- Source roots are read-only.
- Exclude `.git` objects, virtual environments, package caches, node_modules,
  binaries, temporary output, and secrets unless recording metadata only.

SECURITY

Never place secret values in logs, registries, prompts, or model context.
Exclude `.env`, `.databrickscfg`, `auth.json`, PAT/token values, Authorization
headers, private keys, passwords, and credential-bearing connection strings.
Record only path, category, redacted fingerprint/hash, and exclusion status.

COST AND MODEL POLICY

- Inspect installed OpenCode CLI help before assuming session/stat syntax.
- Capture usage before and after.
- Use deterministic shell/Python/PowerShell parsing first.
- No recursive agent trees.
- Maximum two concurrent model workers.
- Do not send exact duplicates or full raw sessions to a model.
- Classify no more than 30 representative artifacts in this run.
- Use the default fast model for the sample.
- Do not switch to a high-reasoning model without an explicit conflict queue.
- Stop before full-corpus LLM classification.

PHASE 1 — PREFLIGHT

Record workspace root, OS, PowerShell/Python/Git/OpenCode versions, safe shell
tools, current branch/commit, estimated file count/size, run ID, and resumable
state. A second run must skip unchanged hashes.

PHASE 2 — DETERMINISTIC INVENTORY

For relevant source/document/metadata files, collect:
- SHA-256 and paths;
- type, size, timestamps, and Git provenance;
- exact duplicates and probable version families;
- safe syntax results;
- imports, functions, classes, commands, inputs, and outputs;
- SQL/UC objects, joins, CTEs, and filters;
- DAX measures/tables/columns and filters;
- PBIX/PBIP names and Power Query M lineage;
- SAP tables, fields, T-codes, conditions, material types, currencies, units,
  plants, company codes, dates, and scenarios;
- secret-exclusion status.

Use size-aware sampling for large files and malformed/blank-first-row fallbacks.
Do not model-classify facts that deterministic parsers can extract.

PHASE 3 — SESSION RECOVERY

Inspect OpenCode help, enumerate recoverable sessions for this project, and
export them under `.brain-poc/raw-sessions/`. Exclude auth files.

Parse compact facts:
- objective and questions;
- user filters/assumptions;
- files and objects referenced;
- commands, exit codes, errors, and outputs;
- validation/control evidence;
- PBIX, DAX, SAP, UC, warehouse, and Genie references;
- later corrected or superseding work.

Separate USER_CLAIM, ASSISTANT_CLAIM, COMMAND_EVIDENCE, FILE_EVIDENCE,
VALIDATION_EVIDENCE, and LATER_SUCCESSFUL_USE. Link to artifact hashes.

PHASE 4 — REGISTRY AND TRUST

Create `.brain-poc/registry/brain.sqlite` from the supplied schema. Populate FTS
with compact redacted summaries. Add relationship edges and evidence-backed
trust assignments. Do not delete source files or promote work from model prose
alone.

PHASE 5 — 30-ARTIFACT SMOKE TEST

Select known/likely good, broken, stale, duplicate, business-context-heavy,
Power BI, Databricks, SAP, and ambiguous samples. Send only deterministic
summaries and minimal excerpts. Require compact JSON: purpose, project,
business process, inputs, outputs, rules, filters, systems, risks, likely state,
evidence, conflicts, missing context, and recommended validation.

Record model alias, input/output tokens, latency, reported cost, and corrected
hallucinations.

PHASE 6 — RETRIEVAL TEST

Benchmark exact identifiers, metadata filters, FTS, metadata-filtered FTS,
relationship traversal, and—only through an approved endpoint—curated summary
embeddings. Do not introduce a graph database. Score precision@5, reciprocal
rank, latency, trust compliance, explainability, and token cost.

PHASE 7 — OUTPUT

Create:
- `.brain-poc/state.json`
- `.brain-poc/logs/`
- `.brain-poc/registry/brain.sqlite`
- artifact/session/evidence/rule/relationship/trust JSONL exports
- inventory, session recovery, secret exclusion, trust, model smoke-test,
  retrieval benchmark, architecture, cost, and review-queue reports
- incremental scan and registry validation scripts

The review queue must contain no more than ten high-value human decisions.

STOP GATE

Stop after deterministic inventory, session harvest, registry creation,
30-artifact sample classification, and retrieval smoke test. Report measured
usage and forecast the full run. Do not begin full-corpus model classification.
```
