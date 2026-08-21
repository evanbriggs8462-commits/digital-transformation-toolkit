---
id: brain.prompt.question-routing
status: binding-template
scope: brain-aware-agent
audience: [ai-agent]
last_reviewed: 2026-08-20
---

# Question Routing and Completion Rules

## Router

Classify every request into one or more intents:

```text
ARTIFACT_DISCOVERY
MODEL_METADATA
NUMERIC_RESULT
VISUAL_EXPLANATION
SOURCE_DISCOVERY
RECONCILIATION
VARIANCE_DIAGNOSIS
GENIE_ENRICHMENT
CODE_GENERATION
DOCUMENTATION
```

## Routes

### Artifact discovery

```text
Registry exact/metadata search
→ FTS
→ relationship traversal
→ curated semantic similarity if needed
→ return trust state and evidence
```

### Model metadata

```text
Retrieve prior report profile
→ validate against current TE2 inventory
→ answer with current object definitions and drift
```

### Numeric result

```text
Select exact model
→ retrieve promoted/verified semantics
→ validate measure and filters through TE2
→ build read-only DAX
→ execute through dscmd wrapper
→ validate result artifact
→ return actual value
```

Returning only DAX is prohibited when local execution is available.

### Visual explanation

```text
Identify visual/page/report context from supplied filters or report definition
→ inspect measure and dependencies
→ reproduce known context through DAX
→ identify hidden/interactive context that remains unavailable
→ never invent filters
```

### Source discovery

```text
Parse M/source mappings
→ retrieve historical UC candidates
→ probe current accessible UC metadata
→ record live-validated or stale mappings
```

### Reconciliation

```text
Execute Power BI DAX control
→ execute equivalent Databricks SQL control
→ normalize filters, currency, UoM, and grain
→ compare in Python
→ drill residual by configured dimensions
→ return values and evidence
```

### Variance diagnosis

```text
Confirm comparable definitions
→ identify largest contributing dimension
→ recursively drill
→ test timing, grain, duplicates, missing keys, FX, UoM, and business exceptions
→ separate explained from unresolved variance
```

### Genie enrichment

```text
Retrieve scoped knowledge cards
→ retrieve Power BI semantics and source mappings
→ validate current UC candidates
→ compile problem packet
→ ask Genie for grain, joins, assumptions, SQL, and validation
→ compare Genie result to controls
```

### Code generation

If the user explicitly asks for code, return reusable code. Where safe and requested, test it in a disposable sandbox. Do not confuse code generation with a request for an actual business result.

## Final-answer contract for evaluated results

Include:

- result value/table;
- exact PBIX/model or source;
- measure/expression or query identity;
- filters and their source;
- currency/UoM/grain assumptions;
- execution and validation status;
- material unresolved context;
- provenance/evidence references.

## Clarification policy

Ask one precise clarification only after deterministic discovery and brain retrieval fail to resolve an ambiguity. Never ask the user for information that the environment can safely discover.

## Failure policy

Return a structured blocker:

```json
{
  "blockerCode": "AMBIGUOUS_MODEL",
  "retryable": false,
  "requiresIT": false,
  "nextAction": "Specify one of the exact open PBIX filenames",
  "evidence": ["Two candidate models passed discovery"]
}
```

Do not claim success because a process started.
