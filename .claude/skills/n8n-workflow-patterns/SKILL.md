---
name: n8n-workflow-patterns
description: Design or improve n8n workflows with core nodes, branching, keyed merges, sub-workflows, schedules, Wait, Data Tables, reusable test fixtures, and readable workflow documentation. Use for n8n workflow design and node selection.
---

# Build a small, explicit workflow

Identify the instance version, Cloud versus self-hosted deployment, trigger, input schema, durable record, and external side effects. Inspect existing workflow JSON and actual node parameters before changing it. Prefer native nodes over custom code when they express the rule clearly. Load [references/quick-reference.md](references/quick-reference.md) for official sources and version caveats.

Use this node map:

| Need | Choose | Check |
| --- | --- | --- |
| Rename, normalize, select fields | Edit Fields (Set) | Decide whether to keep other input fields and binary data. |
| Two-way business rule | If | Specify types, null behavior, and both outcomes. |
| Several explicit outcomes | Switch | Define unmatched and multiple-match behavior. |
| Join datasets | Merge, Combine by Matching Fields | Normalize keys; inspect duplicates and unmatched records. |
| Concatenate datasets | Merge, Append | Expect separate items, not field enrichment. |
| Reusable operation | Execute Sub-workflow | Define typed inputs, output contract, and completion behavior. |
| Delay or human response | Wait | Choose timed, webhook, or form resumption. |
| Recurring run | Schedule Trigger | Set workflow timezone and publish after validation. |
| Small durable lookup or state | Data Table | Inspect storage limits, permissions, and available operations. |
| Missing integration operation | HTTP Request | Reuse an appropriate credential and inspect the API contract. |

Join on business keys, such as `period + BU + OU`, rather than row position. A positional merge is valid only when aligned order and cardinality are established. A many-to-many match can multiply rows; select the intended multiple-match behavior. Do not attach Merge blindly to mutually exclusive If outputs and expect every input to run. Validate branching with the actual workflow execution order and node versions.

# Make reuse and timing deliberate

Extract repeated authorization checks, data normalization, or notification formatting into sub-workflows. Choose one run with all items for batch logic and one run per item when isolation is needed. Wait for completion when downstream work needs the result; otherwise record the asynchronous operation separately.

Use Wait rather than a busy loop. Authenticate webhook resumption and set a deadline where a response could never arrive. Treat its generated resume URL as sensitive. For schedules, choose an IANA timezone such as `America/New_York`; verify DST and month-end boundaries. Distinguish saving a draft from publishing the version used by production triggers. Recheck older instances that still show activation terminology.

# Store only what the workflow needs

Use Data Tables for small lookups, required submitters, and close-status records where the installed version supports them. Inspect project access before storing identities. Read and write through the Data Table node or supported API; do not invent a Code-node table accessor. Use a database when transactions, uniqueness constraints, row-level access, large history, or higher concurrency are requirements. An upsert alone does not establish every concurrency guarantee.

# Make the canvas reviewable

Name nodes with verbs and purpose: `Normalize identity`, `Check BU/OU access`, `Persist close status`, `Build notification`. Arrange the main path left to right and keep rejection routes visible. Group sections with Sticky Notes and use Markdown headings, short bullets, code spans, and links. Document input/output contracts, owner, timezone, business rules, and why unusual settings exist; keep secrets out of notes.

Pin sanitized input during development to reproduce cases without repeated external reads. Production executions ignore pinning. Exercise allowed and rejected submissions, missing keys, duplicate retries, empty lookups, and notification failure. Inspect outputs at joins and side effects. Keep the workflow unpublished until the intended rules and credential bindings are verified.
