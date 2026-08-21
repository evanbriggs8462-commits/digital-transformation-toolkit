---
id: brain.overview
status: design-foundation
scope: personal-poc
audience: [ai-agent, developer, analyst]
last_reviewed: 2026-08-20
---

# Digital Transformation Brain

The brain is a private, local-first sidecar for the existing Power BI toolkit. It stores reusable technical knowledge, business semantics, artifact provenance, execution evidence, source mappings, and live-system observations so a fresh AI session does not have to rediscover prior work or guess which script is trustworthy.

The brain is **not** a replacement for the tested runtime. The separation is intentional:

```text
17-file toolkit   = deterministic hands
brain sidecar     = memory, retrieval, planning, and trust
live systems      = current source of truth
AI model          = reasoning and orchestration
```

## Primary outcomes

A brain-aware agent should be able to answer:

1. What relevant work already exists?
2. Which version worked, and what evidence proves it?
3. Which business filters and assumptions were established previously?
4. Which SAP, Power BI, Databricks, and Genie objects are related?
5. Which artifacts are safe to execute?
6. Which artifacts should only be used as contextual evidence?
7. What must be checked against the live PBIX or Unity Catalog before use?
8. Which execution path is appropriate: TE2, DAX Studio, Databricks SQL, Python, Genie, or a combination?
9. What actual number or reconciliation result was produced?
10. What remains ambiguous?

## Core operating model

```text
User question
   ↓
Intent classification
   ↓
Trust-aware brain retrieval
   ↓
Validate retrieved context against the live environment
   ↓
Select deterministic tools
   ↓
Execute and validate
   ↓
Return value + filters + assumptions + provenance
```

The historical brain provides candidate context. It never silently overrides the live model or live catalog.

## Knowledge layers

### Bronze: raw references

- Historical scripts and notebooks
- OpenCode session exports
- Sprint notes and implementation briefs
- Metadata exports
- Generated results and logs
- Failed and abandoned experiments

Bronze assets are never executed automatically.

### Silver: parsed and linked facts

- File hashes and version families
- Syntax status
- Imports, tables, measures, filters, and dependencies
- Session facts and command evidence
- Business-rule candidates
- Power BI-to-Databricks source mappings
- Relationship edges
- Trust-state assignments

### Gold: validated knowledge

- Promoted recipes
- Verified queries
- Report profiles
- Reconciliation profiles
- Approved business definitions
- Validated SAP/Power BI/Databricks mappings
- Genie context templates and benchmark questions

Normal questions search Gold first, then Silver. Bronze is consulted only when investigating or curating.

## Current integration boundary

The brain does not need to be included in the first-user ZIP. The tested RC2 runtime remains small and deterministic. The personal brain can live beside it on the development workstation and call the runtime when needed.

```text
DigitalTransformationToolkit/
brain-workspace/
  registry/
  observations/
  recipes/
  reports/
  runtime/
```

The populated brain may contain internal business context and should remain in the approved local/team scope. This repository contains the generic framework, schemas, reference knowledge, examples, and prompts needed to build it.

## Non-negotiable principles

- Deterministic parsing before model reasoning.
- Exact hashes and provenance before semantic similarity.
- Live-system validation before execution.
- Evidence-based trust states rather than filenames or model confidence.
- Actual numerical requests must execute when local capability is available.
- Assistant claims are not proof of success.
- Secrets are excluded before indexing or model processing.
- No historical script is executed until explicitly promoted or directly validated for the current task.
- Vector search and GraphRAG are optional techniques, not default architecture.
- Expensive reasoning is reserved for conflicts, promotion candidates, and unexplained variances.

## Recommended implementation order

1. Scoped read-only file inventory.
2. Secret exclusion and exact deduplication.
3. OpenCode session recovery and compact fact extraction.
4. SQLite registry and full-text search.
5. Trust-state and provenance rules.
6. Relationship traversal.
7. Model classification on a representative sample.
8. Curated embeddings only if benchmarked value is material.
9. Power BI M lineage extraction.
10. Live UC observations and Genie context compilation.
11. DAX-versus-SQL reconciliation.

## Directory guide

- `AGENTS.md` — binding behavior for agents operating the brain.
- `manifest.yaml` — machine-readable map of the knowledge pack.
- `architecture.md` — system design, trust model, retrieval, and model routing.
- `reference/` — durable technical reference knowledge.
- `schemas/` — machine-readable record contracts.
- `sql/` — SQLite registry schema.
- `examples/` — generic scoped knowledge cards and reconciliation profiles.
- `prompts/` — ChatGPT, work-model, question-routing, and Genie prompts.
- `roadmap/` — implementation sprints and cost gates.
- `security/` — secret exclusion and scope boundaries.

## Definition of done for the first POC

The first POC is useful when it can:

- inventory the scoped corpus without changing it;
- recover and parse available sessions;
- identify duplicate/version families;
- distinguish evidence-backed assets from claims;
- answer ten benchmark retrieval questions;
- produce no more than ten high-value review decisions;
- generate at least two evidence-backed Genie problem packets;
- forecast full indexing cost from measured sample usage;
- stop before an uncontrolled full-corpus model pass.
