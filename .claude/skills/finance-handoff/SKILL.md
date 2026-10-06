---
name: finance-handoff
description: Save a short local checkpoint for a lengthy Databricks or SAP finance investigation before compaction, switching tasks, or starting a fresh session. Preserve verified findings, decisions, failed approaches, and the next action without copying the conversation or query results.
---

# Finance investigation handoff

Use this when an investigation has accumulated useful findings that would be expensive to rediscover. Keep interactive problem solving in the current conversation; this skill records its working state.

1. Read [the handoff template](template.md). Read the current session's existing handoff if one exists; update it rather than append a diary.
2. Write `.claude/state/sessions/${CLAUDE_SESSION_ID}/HANDOFF.md`. The session ID must contain only letters, digits, `_`, and `-`; never substitute user-supplied paths. Reject symlinks or junctions in the destination. If the local path is unavailable, report the blocker instead of writing elsewhere.
3. Use 300–600 words at most; a routine checkpoint should be much shorter. Use fewer than 80 lines. Preserve the current objective, accepted constraints, verified facts with evidence references, decisions and reasons, disproved approaches, unresolved questions, and the next 1–3 actions.
4. Record exact verified table identifiers, grain and join keys, filters, cutoff/date rules, currency/sign conventions, and SQL/notebook/file references when they matter. Label assumptions separately. An earlier model answer or automatic compaction summary is not proof of a schema or financial result. Include the verification date or run ID when available.
5. Link to existing local artifacts instead of copying code, schemas, logs, or tool output. Do not include credentials, access tokens, connection strings, personal data, or business rows. Keep only metadata and concise reconciliation aggregates needed for continuation and permitted by the organization's policy. Never commit or push local state; `.gitignore` is a convenience, not a substitute for checking a diff.
6. Do not rerun a query merely to write the handoff. If evidence is missing, mark it unverified and record the smallest verification needed.
7. Tell the user the saved path and one suggested continuation:
   - Continuing the same investigation: `/compact Preserve verified findings, decisions, failed approaches, evidence references, open questions, and the next action.`
   - Starting a new conversation: `/clear`, then ask Claude to read that exact `HANDOFF.md` path and continue its next action.

Saving Markdown does not reduce the active context by itself. `/compact` replaces older conversation history with a summary; `/clear` starts with fresh context. Preserve important unresolved work before either command.

The optional `PostCompact` hook saves the built-in summary as `COMPACTION.md`, with no additional model request. That is a recovery snapshot, not this reviewed handoff. Do not load summaries or handoffs from other sessions unless the user selects one.

Read [hook setup notes](references/hook-notes.md) only when configuring or troubleshooting automatic snapshots.
