# n8n and HTML dashboard skills for Claude Code

The twelve skills in `.claude/skills/` provide concise, task-specific guidance for n8n workflows and monthly-close dashboards. Platform details were checked against official documentation on 2026-10-12; verify the connected instance's current node versions and available tools before applying version-specific options.

## Use

Open this repository as the Claude Code project. Invoke `/n8n-toolkit` to select guidance, or invoke a specific skill. Keep each complete folder and its `references/` together. For personal use, copy the twelve folders into `~/.claude/skills/`; preserve any existing skills with matching names instead of overwriting them blindly.

The collection provides instructions. Configure n8n connectivity and approved credentials independently. Skill invocation does not authorize production writes, email sends, publication, or changes to security settings.

## Skill map

| Skill | Coverage |
| --- | --- |
| [n8n-toolkit](../.claude/skills/n8n-toolkit/SKILL.md) | Select relevant workflow and dashboard skills. |
| [n8n-workflow-patterns](../.claude/skills/n8n-workflow-patterns/SKILL.md) | Core nodes, branching, keyed joins, sub-workflows, Wait, schedules, pinning, and Data Tables. |
| [n8n-expressions-code](../.claude/skills/n8n-expressions-code/SKILL.md) | Expressions, JSON items, Code modes, linking, nulls, numbers, and timezones. |
| [n8n-api-cli](../.claude/skills/n8n-api-cli/SKILL.md) | Public API, MCP discovery, pagination, exports/imports, and Cloud versus Server CLI. |
| [n8n-workflow-formatting](../.claude/skills/n8n-workflow-formatting/SKILL.md) | Canvas organization, node names, Markdown notes, content formatting, and handoffs. |
| [n8n-forms-access](../.claude/skills/n8n-forms-access/SKILL.md) | Verified identity, required users, BU/OU read/write permissions, and forms. |
| [n8n-security](../.claude/skills/n8n-security/SKILL.md) | Credentials, endpoint access, safe HTML, CSP, CORS, CSRF, and prompt injection. |
| [n8n-reliability](../.claude/skills/n8n-reliability/SKILL.md) | Idempotency, concurrent updates, audit records, email outboxes, retries, and errors. |
| [html-dashboard-layout](../.claude/skills/html-dashboard-layout/SKILL.md) | Headers, KPI cards, tables, responsive layout, accessible status colors, and data states. |
| [html-dashboard-interactions](../.claude/skills/html-dashboard-interactions/SKILL.md) | Dropdowns, filters, drill-through, breadcrumbs, buttons, back navigation, and focus. |
| [html-dashboard-kpis](../.claude/skills/html-dashboard-kpis/SKILL.md) | Completion/on-time rates, approved denominators, duplicates, reopened/exempt/late items, and snapshots. |
| [n8n-dashboard-serving](../.claude/skills/n8n-dashboard-serving/SKILL.md) | Hosting choices, iframe limitations, authenticated JSON, scoped caching, and load. |

## Example requests

```text
/n8n-toolkit Review our monthly close workflow and select the relevant guidance.
/n8n-expressions-code Fix this transformation while preserving item linkage.
/n8n-forms-access Review how this form verifies identity and checks BU/OU access.
/html-dashboard-kpis Define completion and on-time metrics from our approved scope table.
/html-dashboard-interactions Make KPI drill-through preserve filters and snapshot context.
/n8n-security Review the browser-facing data boundary before connecting production.
```

## Close-tracker defaults

Treat `period + BU + OU` as a proposed item grain, adding plant/task where the actual requirements demand it. Calculate KPIs from approved required scope, verified viewer permissions, and the same data snapshot used by detail views. Preserve established close policies instead of inventing thresholds or reopening rules. Distinguish saved close status from email delivery status.

For Power BI work, follow the existing root `AGENTS.md`. Its runtime launcher applies to Power BI tasks; publishing or reading these n8n instruction files does not require a PBIX extraction run.

## Validation

All twelve skill frontmatters and nine relative reference links were validated. Independent synthetic walkthroughs covered spoofed form identity, duplicate retries, uncertain email acceptance, reopened items, exemptions, accurate KPI denominators, and card-to-detail reconciliation. These checks do not validate a live company n8n deployment.
