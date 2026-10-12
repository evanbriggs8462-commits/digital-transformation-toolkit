# n8n workflow and dashboard workspace

Use `.claude/skills/n8n-toolkit/SKILL.md` to select the relevant task skill. Load one or two skills initially and read detailed references only when needed. See `docs/N8N_CLAUDE_SKILLS.md` for the skill map and examples.

Inspect actual n8n deployment, node versions, input/output schema, and connected MCP tool schemas before constructing changes. Keep company-specific identity sources, BU/OU permissions, period rules, recipients, and KPI definitions grounded in approved project data. Treat missing facts as explicit assumptions.

Keep read and write authorization server-side. Never place n8n management keys in browser HTML or use a submitted email as verified identity. Preserve item grain, audit history, idempotency, and snapshot consistency. Distinguish proposed code and synthetic verification from observed live results.

For Power BI runtime tasks, follow root `AGENTS.md` and its launcher contract. These n8n skills do not change Power BI runtime behavior.
