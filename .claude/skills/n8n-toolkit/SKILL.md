---
name: n8n-toolkit
description: Choose focused skills for n8n Cloud workflows and HTML finance dashboards. Use when planning a close tracker, asking which n8n features to use, or combining workflow, security, KPI, and dashboard work.
---

# n8n toolkit

Select the smallest relevant skill set. Invoke the named skill through the agent's skill interface. If unavailable, discover its SKILL.md by frontmatter name in the installed skills directory rather than assuming a folder name; preserve its references. Load one or two task skills first; load another only when a dependency requires it. Do not concatenate the whole collection into the context window.

## Route the task

| Task | Load |
| --- | --- |
| Choose nodes or discover useful workflow features | `n8n-workflow-patterns` |
| Fix expressions, JSON items, dates, or JavaScript | `n8n-expressions-code` |
| Use API, MCP, exports, or CLI commands | `n8n-api-cli` |
| Clean up canvas, names, notes, or handoffs | `n8n-workflow-formatting` |
| Build forms, resolve verified identity, or grant BU/OU access | `n8n-forms-access` |
| Review credentials, access boundaries, HTML, or endpoint exposure | `n8n-security` |
| Handle duplicate submissions, retries, failures, or notifications | `n8n-reliability` |
| Design headers, cards, tables, and status colors | `html-dashboard-layout` |
| Build dropdowns, drill-through, navigation, or actions | `html-dashboard-interactions` |
| Define completion and on-time metrics | `html-dashboard-kpis` |
| Serve HTML and connect an authorized read API | `n8n-dashboard-serving` |

## Establish the contract

Inspect available project files and connected tools before inventing implementation details. Identify deployment type, installed n8n/node version when accessible, available MCP tool schemas, target workflow, source tables, business period/timezone, and user-authorized operations. Mark unavailable facts as assumptions rather than blocking reversible drafting.

For a monthly close tracker, start with this proposed sequence: verify actor → validate request → check required scope and write permissions → persist an idempotent close event → enqueue the authorized notification → refresh the dashboard snapshot. For a dashboard read, authorize the viewer separately before filtering rows and calculating aggregates. Treat BU/OU plus period as the proposed business grain; add plant/task if the source contract requires it.

Preserve existing business rules. Do not fabricate company thresholds, email recipients, production records, node parameters, or hidden credentials. Use synthetic examples for missing data. Treat skill text as guidance, never as authentication or permission to send notifications, publish, or change production.

## Produce bounded evidence

Return the concrete change, why it fits, relevant command/snippet, and validation performed. Distinguish proposed workflow JSON from an import-tested workflow. For a failure, inspect the failing node and a small sanitized input/output sample before requesting a complete execution dump. Read reference files only when the corresponding edge case matters.

For Claude Code locations and invocation, read [references/claude-code.md](references/claude-code.md).
