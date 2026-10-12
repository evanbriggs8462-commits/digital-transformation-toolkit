# Claude Code use

Checked: 2026-10-12. Source: [Anthropic Claude Code skills documentation](https://code.claude.com/docs/en/skills).

Place each complete skill folder at `.claude/skills/<name>/` in the project, or `~/.claude/skills/<name>/` for personal use. Keep `SKILL.md` and its references together. Keep the collection under one skills directory so the selector can discover each skill by name. The optional `agents/openai.yaml` file is ChatGPT UI metadata; Claude Code uses `SKILL.md` and supporting resources.

Invoke `/n8n-toolkit` to select guidance, `/n8n-api-cli` for commands, or `/html-dashboard-kpis` for metrics. Descriptions also support automatic selection. These instruction files do not provide an n8n connection, install an MCP server, set credentials, or modify Claude's permissions.

Keep stable project facts in the existing `CLAUDE.md`: actual environment, business timezone, approved endpoints, schema, permission source, KPI rules, and validation commands. Keep reusable procedures in these skills. Avoid adding the complete pack to `CLAUDE.md`.

Example requests:

- `/n8n-toolkit Build a monthly close tracker using our existing permissions table.`
- `/n8n-expressions-code Fix the linked items after this Code node; inspect the provided sample.`
- `/html-dashboard-interactions Make the completion card open its matching rows and preserve BU/OU filters.`
- `/n8n-security Review the data boundary before we connect this dashboard to production.`

Installation is a file-placement step in the user's Claude Code workspace. Configure n8n connectivity and approved credentials independently.
