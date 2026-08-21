---
id: brain.prompt.genie-context-compiler
status: reusable-template
scope: databricks-genie-enrichment
audience: [ai-agent]
last_reviewed: 2026-08-20
---

# Genie Context Compiler

## Purpose

Transform a vague business question into a scoped, evidence-backed problem packet that helps Databricks Genie use its live workspace knowledge without forcing Genie to rediscover prior SAP, Power BI, and reporting semantics.

## Inputs

- user objective;
- relevant promoted/verified knowledge cards;
- unresolved hypotheses;
- current or historical Power BI measures and dependencies;
- Power Query M source mappings;
- current accessible UC metadata when available;
- relevant SAP objects and process hierarchy;
- prior successful SQL/Python;
- failed approaches to avoid;
- filters, required grain, currency/UoM/FX policy;
- validation controls and expected comparisons.

## Output packet

```json
{
  "recordType": "genieProblemPacket",
  "id": "genie.<run-id>",
  "objective": "...",
  "businessProcess": "...",
  "systems": ["SAP ECC", "Power BI", "Databricks"],
  "knownSemantics": ["verified fact with evidence"],
  "hypotheses": ["configuration-dependent item to test"],
  "powerBiObjects": ["[Measure]", "Table[Column]"],
  "sapObjects": ["VBRK", "VBRP", "pricing elements"],
  "candidateUcObjects": ["historical candidate; validate live"],
  "filters": {},
  "requiredGrain": "billing item",
  "failedApproaches": [],
  "openQuestions": [],
  "validationControls": [],
  "prompt": "final enriched prompt",
  "provenance": []
}
```

## Compilation rules

1. Distinguish verified semantics from hypotheses.
2. Do not assert that historical UC objects still exist.
3. Do not expose credentials or restricted row-level results.
4. State required grain and join expectations.
5. State filter, currency, UoM, and FX policies.
6. Include failed approaches when they prevent repeated mistakes.
7. Ask Genie to identify current sources and explicitly document assumptions.
8. Request bounded SQL and validation queries.
9. Do not treat Genie's generated SQL as verified until executed and reconciled.

## Generic prompt template

```text
Objective
---------
<precise business result or migration objective>

Known validated semantics
-------------------------
- <fact, scope, evidence>

Configuration-dependent hypotheses
----------------------------------
- <hypothesis to test, not a fact>

Power BI evidence
-----------------
- Measures: <measure names and compact definitions>
- Dimensions/filters: <fields and filter semantics>
- Source lineage: <M-derived historical candidates>

SAP/process evidence
--------------------
- Relevant domains/tables: <FI/SD/MM/material/pricing candidates>
- Required grain: <document, item, period, etc.>
- Known exceptions: <timing, missing partner, split billing, FX, UoM>

Unity Catalog candidates
------------------------
- <candidate objects from historical work or live probe>
These are candidates and must be validated against current accessible UC.

Failed approaches to avoid
--------------------------
- <failed or superseded logic and why>

What Genie should do
--------------------
1. Identify the best current UC tables/views and required columns.
2. State the grain of every source and the final result.
3. Explain joins and possible fan-out/duplication risk.
4. Distinguish verified workspace semantics from assumptions.
5. Generate bounded SQL with explicit filters.
6. Provide control queries and expected validation dimensions.
7. Flag any logic requiring SAP configuration or business-owner confirmation.

Validation
----------
- Compare to: <legacy spool, evaluated DAX, known control>
- Tolerance: <absolute and percentage>
- Drill dimensions: <ordered list>
```

## Example topic: SGM

Include pricing-procedure scope, custom condition versus subtotal composition, freight/adders, billed quantity/UoM, cost source and timing, FX policy, Power BI measure dependencies, and legacy spool control.

## Example topic: intercompany

Include partner-evidence hierarchy, missing VBUND possibility, customer/vendor mapping, split billing, multiple profit centers, reciprocal document grouping, key-date open-item logic, currency, and separate classification/reconciliation confidence.

## Genie improvement outputs

Beyond a one-time prompt, compile candidates for:

- descriptions and synonyms;
- approved joins;
- SQL expressions;
- example questions;
- trusted assets;
- benchmark questions;
- coverage gaps;
- feature ideas;
- concepts that are not ready for Genie because the source reconstruction is unverified.
