---
id: brain.roadmap
status: implementation-plan
scope: personal-poc
audience: [developer, ai-agent, analyst]
last_reviewed: 2026-08-20
---

# Implementation Sprints

The goal is to prove value in three focused sprints rather than building a platform before the corpus and retrieval needs are known.

## Sprint 0 — Freeze the runtime

Keep the tested RC2 Power BI runtime unchanged. Build the brain in a separate branch/workspace. Do not add experimental RAG, Databricks, or session-harvest logic to the first-user ZIP.

Exit criteria:

- known RC2 commit retained;
- brain workspace path selected;
- source roots approved read-only;
- secrets and outputs excluded;
- usage budget defined.

## Sprint 1 — Harvest and registry

Estimated effort: one focused evening.

Build:

- deterministic file inventory;
- SHA-256 and exact duplicates;
- size-aware parsers;
- syntax checks;
- probable version families;
- OpenCode session recovery;
- compact evidence extraction;
- SQLite registry and FTS5;
- trust-state proposals;
- no model classification beyond a small parser-assistance sample.

Expected output example:

```text
files scanned
relevant artifacts
exact duplicates/generated outputs
recoverable sessions
syntax failures
files with execution evidence
UC/Power BI/SAP object references
secret exclusions
high-value review queue
```

Stop if source mutation, secret exposure, or uncontrolled recursion occurs.

## Sprint 2 — Retrieval and curation

Estimated effort: one or two focused evenings.

Build:

- 20–30 artifact model bakeoff;
- artifact summaries and domain tags;
- evidence-backed trust ranking;
- version/supersession relationships;
- business knowledge cards;
- exact + FTS + relationship retrieval benchmarks;
- optional curated embedding test;
- report/source mapping cards;
- no automatic execution of historical code.

Use a high-reasoning model only for a small conflict/promotion queue.

Exit criteria:

- ten benchmark questions return relevant trusted results;
- BROKEN/SUPERSEDED assets do not outrank promoted work;
- cost per classified artifact measured;
- full-corpus forecast reviewed;
- vector search is accepted or rejected based on evidence.

## Sprint 3 — Beast-mode proof

Estimated effort: two or three focused sessions.

Prove one end-to-end loop:

```text
open PBIX
→ brain retrieval
→ TE2 validation
→ DAX control
→ M/UC source discovery
→ Databricks SQL control
→ Python reconciliation
→ enriched Genie follow-up
→ validated answer
```

Recommended cases:

1. SAP spool-to-Databricks SGM reconstruction.
2. Third-party sales/material cost timing.
3. ECC/S4 intercompany with missing partner or split billing.

Exit criteria:

- actual DAX and SQL values captured;
- equivalent filters/grain/currency/UoM documented;
- variance drilled through ordered dimensions;
- Genie packet materially improves source/SQL reasoning;
- reusable recipe promoted with evidence.

## Initial usage envelope

Target for the useful POC, not a hard promise:

```text
Input tokens:  1.5M–4M
Output tokens: 250k–700k
High-reasoning share: below 10–15%
Normal future question: prefer below ~20k total tokens
```

The deterministic harvest should consume little or no model usage. Measure configured model aliases rather than assuming name-to-price mappings.

## Stop gates

1. Deterministic inventory complete.
2. Twenty-to-thirty artifact benchmark complete; report usage.
3. First 100 deduplicated assets classified; forecast remaining cost.
4. Full classification only after approval.
5. Live SQL and Genie work only after secrets, target scope, and compute limits are confirmed.

## Compute discipline

LLM usage and Databricks compute are different meters.

For Databricks:

- inspect schema first;
- apply predicates early;
- use bounded samples;
- aggregate near the data;
- avoid repeatedly scanning unchanged data;
- record warehouse, duration, and result row counts;
- use Python for residual analysis, not unnecessary bulk extraction.

## Promotion path

```text
RAW
→ PARSED
→ RUNNABLE
→ VERIFIED
→ PROMOTION_CANDIDATE
→ PROMOTED
```

Promotion requires evidence, scope, assumptions, current-object validation, and a completion rule. Experimental success does not automatically change the shared runtime.

## Future backlog

Only after the POC proves value:

- incremental REST/UC snapshot automation;
- PBIR/report-layer parsing;
- curated vector index;
- structured lesson-candidate generation;
- shared-team knowledge promotion;
- GraphRAG if relational traversal is insufficient;
- governed Genie update automation;
- broader metadata extraction such as RLS, calculation groups, perspectives, and visual context.
