---
id: brain.architecture
status: design-foundation
scope: personal-poc
audience: [ai-agent, developer, architect]
last_reviewed: 2026-08-20
---

# Brain Architecture

## 1. Problem statement

A long-running analyst/developer workflow accumulates scripts, notebooks, metadata, chats, prompts, audit artifacts, and business exceptions. The files alone rarely show which version worked or why. Fresh AI sessions repeatedly rediscover filters, source mappings, and tool behavior, increasing ambiguity, latency, and token usage.

The brain converts accumulated work into a provenance-aware local knowledge and execution system.

## 2. System boundary

```text
                           ┌──────────────────────┐
User question ────────────▶│ Intent and task router│
                           └──────────┬───────────┘
                                      │
                           ┌──────────▼───────────┐
                           │ Trust-aware retrieval│
                           │ Gold → Silver → Bronze│
                           └──────────┬───────────┘
                                      │
                           ┌──────────▼───────────┐
                           │ Live validation      │
                           │ PBIX / UC / REST      │
                           └──────────┬───────────┘
                                      │
             ┌────────────────────────┼──────────────────────┐
             ▼                        ▼                      ▼
         TE2 metadata           DAX Studio             Databricks SQL
                                                          + Python
             └────────────────────────┬──────────────────────┘
                                      ▼
                           Validated result and evidence
```

The existing toolkit remains the deterministic Power BI runtime. The brain is an optional sidecar and should not destabilize the release ZIP.

## 3. Brain records

The registry stores:

- artifacts and all observed paths;
- exact duplicates and likely version families;
- sessions and compact session facts;
- execution and validation evidence;
- business-rule cards;
- SAP, Power BI, UC, and Genie object references;
- report profiles and source mappings;
- recipes and reconciliation profiles;
- live observations and drift;
- relationships among all records;
- trust assignments and explanations;
- model/token usage and retrieval benchmarks.

Every durable record has a stable ID, source provenance, observed/created time, scope, sensitivity, and validation state.

## 4. Artifact identity and versioning

Use SHA-256 as the immutable content identity. Paths are observations because the same content can appear in multiple locations.

```text
artifact ID = sha256(content)
artifact path = where that content was observed
version family = inferred relationship among similar artifacts
```

Do not infer authority from `final`, `fixed`, or modified time alone. Supersession requires evidence from Git history, sessions, execution, outputs, or an explicit curated decision.

## 5. Trust model

Trust is a lifecycle, not a single confidence score.

- `RAW`: discovered only.
- `PARSED`: deterministic metadata extracted.
- `LIKELY_USEFUL`: relevant but unvalidated.
- `NEEDS_CONTEXT`: missing business or environment information.
- `BROKEN`: syntax/runtime evidence shows failure.
- `RUNNABLE`: syntax/dependencies look viable; no trusted result yet.
- `VERIFIED`: execution and expected output were validated.
- `PROMOTION_CANDIDATE`: verified and apparently reusable.
- `PROMOTED`: curated for normal retrieval/execution.
- `SUPERSEDED`: replaced by a preferred asset.
- `ARCHIVED`: retained only for history.
- `RESTRICTED_SECRET`: content excluded from indexing/model use.

Trust assignments store evidence components. They are recalculable and reviewable.

## 6. Evidence model

Evidence types include:

```text
USER_CLAIM
ASSISTANT_CLAIM
COMMAND_EVIDENCE
FILE_EVIDENCE
VALIDATION_EVIDENCE
LATER_SUCCESSFUL_USE
GIT_PROVENANCE
LIVE_OBSERVATION
```

Strong evidence includes matched control totals, validated files/hashes, successful exit codes with relevant outputs, and later successful use. Assistant prose is weak evidence unless corroborated.

## 7. Retrieval architecture

Recommended starting architecture:

```text
SQLite metadata
+ FTS5 full-text search
+ relational relationship traversal
+ trust-aware ranking
```

Retrieval order:

1. Exact report, measure, field, table, file, T-code, or business identifier.
2. Structured filters such as domain, project, system, trust state, and observed date.
3. Promoted/verified report and business profiles.
4. Full-text search over compact redacted summaries and facts.
5. Multi-hop relationship traversal.
6. Curated embeddings when exact/FTS retrieval demonstrably misses useful fuzzy matches.
7. Raw corpus inspection for investigation only.

### Vector search

Useful for paraphrases and forgotten wording. Embed compact redacted summaries, not raw sessions, secrets, or every full script. Vector similarity identifies candidates; trust and provenance control use.

### GraphRAG

Do not begin with a graph database. Store relationships in SQLite and benchmark common multi-hop questions first. Adopt GraphRAG only if relationship density and query complexity justify the operational burden.

## 8. Bronze, Silver, Gold

### Bronze

Raw references, historical sessions, scripts, exports, and outputs. Immutable and not execution-eligible.

### Silver

Parsed facts, summaries, version relationships, object references, evidence, trust assignments, and searchable documents.

### Gold

Promoted recipes, report profiles, knowledge cards, source mappings, trusted controls, Genie problem packets, and reconciliation profiles.

## 9. Live observations and drift

Historical knowledge is retained. Current REST, M, TE2, or UC probes are timestamped observations.

```text
historical mapping + current observation → current interpretation
```

When a source changes, mark the old mapping stale or superseded; do not erase the evidence. Live observations should include source, collection method, timestamp, object identity, and optional previous snapshot.

## 10. Model routing and cost

Use models by role:

- **Scout:** inexpensive coding model for compact classification of parsed artifacts.
- **Curator:** moderate reasoning for grouping, business-rule extraction, and relationships.
- **Reviewer:** strongest reasoning only for conflicts, security, and promotion decisions.
- **Operator:** capable coding/reasoning model for validated execution and reconciliation.

Deterministic code performs file enumeration, hashing, exact duplicates, syntax parsing, import extraction, table/measure detection, and session normalization.

High reasoning should inspect a minority of the corpus. Persist checkpoints and process only changed hashes.

## 11. Task routing

```text
Metadata question
→ brain + TE2

Numeric Power BI question
→ brain + TE2 validation + dscmd

Databricks source question
→ brain + live UC metadata

Power BI-to-source reconciliation
→ DAX + SQL + Python

Unexplained variance
→ dimensional drill-down and evidence generation

Genie improvement
→ context compiler + live UC validation + benchmark loop
```

## 12. Reconciliation engine

A generic drill ladder:

```text
Grand total
→ period
→ legal entity/company
→ plant/profit center
→ account/product
→ customer/vendor
→ document/transaction
```

Databricks SQL should aggregate and filter close to the source. Python should handle comparison, tolerance, missing keys, duplicate keys, residual clustering, fuzzy matching, contribution analysis, and evidence packaging.

## 13. Genie context compiler

The compiler combines:

- user objective;
- scoped business semantics;
- relevant SAP objects;
- Power BI measures and M lineage;
- historical UC candidates;
- prior successful/failed approaches;
- required grain and filters;
- validation controls;
- unresolved questions.

It produces an evidence-backed problem packet and enriched prompt. Historical UC names are candidates only; Genie or a live UC probe must confirm current objects.

## 14. Learning loop

The personal POC may mine historical sessions. Future shared learning should prefer sanitized structured lesson artifacts over raw chat centralization.

```text
local success
→ lesson candidate
→ secret/result-data checks
→ validation
→ promotion
```

The reusable lesson should describe how to solve a problem, not expose restricted row-level results.

## 15. Current implementation status

Implemented and tested:

- RC2 Power BI runtime;
- exact multi-PBIX selection;
- TE2 metadata extraction;
- DAX Studio numerical execution;
- process timeouts and evidence artifacts.

Designed but requiring local corpus implementation:

- artifact/session scanner;
- SQLite registry;
- trust/version classification;
- M lineage parser;
- live REST/UC snapshots;
- Genie context compiler;
- DAX-versus-SQL reconciliation;
- retrieval benchmark and optional embeddings.
