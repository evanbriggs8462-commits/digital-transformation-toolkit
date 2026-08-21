---
id: brain.security-scope
status: baseline
scope: generic-framework
audience: [ai-agent, developer]
last_reviewed: 2026-08-20
---

# Security and Scope

## Public framework versus populated brain

This repository may contain generic architecture, SAP/Power BI/Databricks reference knowledge, schemas, prompts, and sanitized examples.

A populated brain may contain employer-specific sessions, report metadata, Unity Catalog objects, custom SAP objects, business definitions, queries, and results. Keep that populated workspace in the approved local/team-controlled location rather than committing it to the generic public repository.

## Always excluded from indexing and model context

- `.env`
- `.databrickscfg`
- `auth.json`
- PAT/token files
- values beginning with known token prefixes such as `dapi`
- bearer or Authorization headers
- private keys
- passwords
- browser/session authentication data
- certificate private keys
- credential-bearing connection strings

When detected, store only:

```text
source path
secret category
redacted fingerprint or SHA-256
exclusion status
```

Never store or print the value.

## Credential boundary

The brain may know that an approved authentication profile exists, but not the credential itself.

```yaml
authenticationProfile: WORK_POC
availability: configured
secretValue: never-stored
```

Runtime adapters read credentials from the approved local environment. The AI model does not need direct access.

## Source preservation

Historical source folders are read-only during inventory. The brain writes only to its own workspace. Do not automatically rename, move, delete, or rewrite discovered files.

## Execution boundary

Historical code is not executed during harvesting. Execution requires one of:

- `PROMOTED` status;
- explicit current-task validation;
- a disposable sandbox with bounded permissions.

Never disable endpoint security, certificate validation, package integrity, or organizational policy. A policy block becomes a structured blocker, not an invitation to invent a bypass.

## Scope fields

Every knowledge object should carry:

- `scopeType`: generic, enterprise, team, report-family, project, restricted;
- `sensitivity`: public, internal, confidential, secret-excluded;
- `containsResultData`;
- `shareable`;
- `sourceUserOrSession`;
- `validationState`;
- `promotionStatus`.

## Business observations

SAP implementations are configurable. Store observations such as pricing subtotal meaning, cost timing, FX treatment, or partner derivation with explicit system/process scope and exceptions. Do not convert one implementation's behavior into a universal SAP fact.

## Live-system least privilege

- UC discovery returns only objects the identity can access.
- DAX executes against the selected local model.
- REST exports are timestamped and access-scoped.
- No central brain process should broaden a user's data authorization.

## Generated outputs

Runtime state, logs, model metadata, query outputs, and REST/UC snapshots should be written outside the shared release package. Apply team folder permissions and retention appropriate to their contents.
