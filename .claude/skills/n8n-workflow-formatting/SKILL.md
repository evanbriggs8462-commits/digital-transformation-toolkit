---
name: n8n-workflow-formatting
description: Format readable n8n workflows, node names, sticky notes, expressions, and sanitized handoffs. Use when cleaning a canvas, documenting business rules, preparing workflow JSON, or improving form and email presentation.
---

# Format n8n workflows

Make the workflow explain its business purpose without opening every node. Preserve behavior while changing layout or documentation.

## Name and arrange

Use action-and-object names such as `Verify actor`, `Load BU/OU permissions`, `Validate close period`, `Persist close event`, and `Queue notification`. Name branches by outcomes: `Authorized`, `Denied`, `Duplicate`, and `Failed`. Keep the main path left to right, exception paths visibly separate, and related steps inside descriptive notes or available canvas groups. Use `Tidy up workflow` where helpful, then inspect the arrangement.

Before renaming an existing node, find all name-based expressions such as `$('Load permissions')`. Update references consistently, preserve node IDs and connections, and verify downstream expressions. Avoid broad JSON reformatting that obscures the functional diff.

Group by responsibility: identity, validation, permissions, persistence, notifications, reporting. Use restrained note colors to distinguish those groups; document the legend and keep explicit headings so color is supplementary. Do not imply that canvas colors grant permission or change execution.

## Write useful notes

Use Markdown headings, lists, links, and inline code in Sticky Notes. Keep canvas text short. Add node Notes for non-obvious rules; enable `Display note in flow` selectively. Record why a rule exists rather than repeating the node's label.

Suggested original note content:

```markdown
## Close submission

- **Grain:** period + BU + OU; add task only if required.
- **Identity:** verified actor from approved authentication.
- **Permission:** approved scope table; deny unmatched actors.
- **Duplicate:** same request key returns prior result.
- **Notification:** sent after durable status change.
```

Include the real data owner, timezone, source contract link, and failure contact only when known. Keep secrets and personal records out of notes and examples.

## Format content and expressions

Use stable machine keys such as `period`, `bu`, `ou`, and `closed_at`; use human labels such as `Business unit`, `Operating unit`, and `Closed at` in the form/dashboard. Prefer ISO timestamps for storage and explicit local-time formatting for presentation. Represent missing values as null with a display label such as `Not submitted`; never replace missing numbers with zero unless the KPI contract permits it.

Build emails with a clear subject containing period and authorized scope, a short status statement, relevant timestamp/timezone, and an approved deep link. Escape interpolated values. Build structured JSON as objects rather than concatenated strings. Preserve distinctions between literal text, expression mode, Markdown notes, email HTML, and browser HTML: syntax that works in one is not guaranteed in the others.

## Deliver a handoff

List modified nodes, input/output contract, required credential names without values, assumptions, and a small synthetic example. Sanitize pinned data, credential identifiers/names, headers, URLs with tokens, internal contacts, and saved execution fragments before sharing an export. Verify JSON parsing and references; test the import only in an authorized environment. Label layout-only verification separately from business execution verification.

Read [references/formatting.md](references/formatting.md) for official formatting links and a compact handoff template.
