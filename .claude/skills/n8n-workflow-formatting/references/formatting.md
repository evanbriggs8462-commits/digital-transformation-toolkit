# Workflow formatting reference

Checked: 2026-10-12.

Official sources:

- [Notes and documentation](https://docs.n8n.io/build/understand-workflows/workflow-components/add-notes-and-documentation.md): Sticky Notes use Markdown and can group nodes visually.
- [Work with nodes](https://docs.n8n.io/build/understand-workflows/workflow-components/work-with-nodes.md): node context menu and Settings expose layout and notes controls. Verify availability on the target version.

Suggested original handoff template:

```markdown
# Workflow handoff

Purpose: <business outcome>
Environment: <Cloud or self-hosted; observed version or unknown>
Changed nodes: <names and IDs>
Input contract: <fields, types, required/null rules>
Output contract: <success and failure fields>
Identity source: <verified source, never the token>
Authorization source: <table and server-side scope rule>
Grain and duplicate rule: <business key and request key>
Time policy: <UTC storage; agreed display timezone>
Notifications: <configured recipient rule; retry behavior>
Validation: <checks actually run and observed results>
Open assumptions: <unverified dependencies>
```

Treat the template as a documentation aid; keep actual credentials in the approved credential store and company-specific schema in the project contract.
