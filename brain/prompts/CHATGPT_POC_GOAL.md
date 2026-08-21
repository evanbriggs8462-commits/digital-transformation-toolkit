---
id: brain.prompt.chatgpt-poc
status: reusable-prompt
scope: uploaded-sandbox-corpus
audience: [chatgpt-goal]
last_reviewed: 2026-08-20
---

# ChatGPT `/goal`: Brain Framework POC

Paste the following into a ChatGPT goal after attaching a representative ZIP of project files and any available session exports.

```text
Build and validate a cost-controlled proof of concept for a searchable,
evidence-aware Finance and Digital Transformation Brain.

This is a ChatGPT sandbox POC, not the final work-device implementation. Use
only attached/project files. Do not claim access to unseen local files or live
systems.

OBJECTIVE

Prove schemas, trust rules, deterministic parsing, retrieval methods, cost
controls, and Genie-context enrichment on a representative corpus containing
SQL, Python, PowerShell, DAX, TE2 scripts, notebooks, metadata, sprint notes,
audits, session exports, successful work, failed attempts, and stale versions.

The POC must answer:
- what exists;
- which version has evidence of working;
- which business rules and filters were established;
- which SAP, Power BI, and UC objects are connected;
- which assets are safe to execute versus context-only;
- whether FTS, embeddings, relationship traversal, or GraphRAG add measurable
  value.

SAFETY

- Treat every supplied source file as immutable.
- Create outputs only in a separate sandbox directory.
- Do not execute historical business SQL, DAX, PowerShell, Python, notebooks,
  or downloaded binaries.
- Do not connect to Databricks, Power BI, GitHub, SharePoint, or Genie.
- Detect and exclude secrets before model processing.
- Never print or index values from `.env`, `.databrickscfg`, `auth.json`, PATs,
  Authorization headers, private keys, passwords, or credential-bearing
  connection strings.
- Record only secret path, category, redacted fingerprint/hash, and exclusion.

COST POLICY

- Deterministic Python/parsing/hashing before model reasoning.
- Deduplicate before model processing.
- Do not send full raw sessions, logs, duplicate files, or whole long files
  unless required.
- Enrich no more than 30 representative artifacts with the model.
- Deep-review no more than five conflicting version families.
- Stop before full-corpus LLM classification.
- Estimate future work-model input/output tokens and compute costs even if
  ChatGPT does not expose exact billing.

PHASES

1. Inventory every supplied file or explicitly exclude it.
2. Compute SHA-256, type, size, provenance, duplicate groups, probable version
   families, syntax status, imports, functions, referenced SAP/Power BI/UC
   objects, hard-coded filters, inputs, outputs, and secret-exclusion status.
3. Parse supplied OpenCode sessions into compact facts. Separate user claims,
   assistant claims, command evidence, file evidence, validation evidence, and
   later successful use. Link facts to artifact hashes where possible.
4. Create a SQLite registry using the repository's `brain/sql/brain_registry.sql`
   and validate FTS5 search.
5. Assign evidence-backed trust states: RAW, PARSED, LIKELY_USEFUL,
   NEEDS_CONTEXT, BROKEN, RUNNABLE, VERIFIED, PROMOTION_CANDIDATE, PROMOTED,
   SUPERSEDED, ARCHIVED, RESTRICTED_SECRET.
6. Create relationship edges such as DUPLICATE_OF, SUPERSEDES,
   CREATED_IN_SESSION, EXECUTED_IN_SESSION, FAILED_IN_SESSION, VALIDATED_BY,
   READS_FROM, USES_SAP_OBJECT, USES_UC_OBJECT, RELATES_TO_PBIX,
   IMPLEMENTS_BUSINESS_RULE, and ENRICHES_GENIE_PROMPT.
7. Classify no more than 30 representative artifacts using compact structured
   outputs and the minimum relevant excerpts.
8. Create scoped business-knowledge cards for discovered concepts. Never turn
   one implementation observation into a universal SAP fact.
9. Benchmark exact metadata, filename search, SQLite FTS, metadata-filtered FTS,
   relationship traversal, curated vector search if available, and hybrid
   retrieval. Recommend GraphRAG only if simple relationship traversal fails on
   important multi-hop questions.
10. Build at least two Genie problem packets that distinguish verified facts,
    hypotheses, historical UC candidates, required grain, failed approaches,
    open questions, and validation controls.
11. Forecast Lean, Balanced, and Aggressive implementation usage, including LLM
    tokens, embeddings, and Databricks warehouse compute.
12. Generate a concise `WORK_MODEL_GOAL.md` for the real local implementation.

BENCHMARK QUESTIONS

- Find the strongest SAP spool-to-Databricks migration work.
- Find SGM, UoM, custom pricing-condition, pricing-subtotal, freight, and net
  invoice-value logic.
- Find third-party cost, GR/IR timing, valuation, and material-price logic.
- Find balance-sheet versus income-statement FX rules.
- Find ECC/S4 intercompany logic involving split billing, multiple profit
  centers, or missing partner evidence.
- Find the verified TE2 metadata and DAX Studio numerical workflow.
- Find Databricks SQL API, UC probing, and warehouse execution code.
- Distinguish validated scripts from failed or superseded versions.
- Recover filters and assumptions from prior sessions.
- Find artifacts that generated validated dollar/control totals.

DELIVERABLES

- brain_poc_report.md
- brain_poc_registry.sqlite
- artifacts.jsonl
- session_facts.jsonl
- execution_evidence.jsonl
- business_knowledge_cards.jsonl
- relationships.jsonl
- trust_rankings.csv
- duplicate_families.json
- model_sample_results.json
- retrieval_benchmark.md
- genie_context_compiler_examples.md
- cost_and_token_forecast.md
- architecture_recommendation.md
- WORK_MODEL_GOAL.md
- reusable deterministic scripts
- ZIP of all POC outputs

ACCEPTANCE

- Sources unchanged.
- Every file inventoried or excluded.
- Secrets excluded before model use.
- Duplicates and version families identified.
- Sessions converted to compact evidence.
- SQLite and FTS validated.
- Model sample limited to 30.
- Retrieval methods compared empirically.
- At least two Genie packets produced.
- No historical business code or remote system executed.
- Final report clearly distinguishes verified evidence, claims, inference, and
  unresolved ambiguity.

Do not return only a plan. Execute the safe POC and create the deliverables.
```
