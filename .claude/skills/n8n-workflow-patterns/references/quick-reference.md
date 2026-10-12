# Official n8n workflow references

Checked: 2026-10-12. Treat the connected instance's version and actual node schema as authoritative for available controls.

- [Edit Fields (Set)](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.set/): Manual Mapping or JSON Output; input retention and binary retention are configurable.
- [If](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.if/): inspect the installed comparison options and type conversions.
- [Switch](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.switch/): inspect output and fallback rules rather than assuming single-match routing.
- [Merge](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.merge/): Append concatenates; Combine supports Matching Fields, Position, or All Possible Combinations. More than two inputs and SQL Query require n8n 1.49.0+. Legacy v0 execution-order behavior differs around If/Merge.
- [Execute Sub-workflow](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.executeworkflow/): modes are once with all items or once per item; choose whether to wait for completion.
- [Wait](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.wait/): resumptions include intervals, specified time, webhook, and form. Webhook resume URLs are generated per execution and support authentication. See this page's time-based section for server-time caveats; do not assume Wait follows the Schedule Trigger timezone rules.
- [Schedule Trigger](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.scheduletrigger/): workflow timezone takes precedence over instance timezone; workflow must be saved and published. Cloud tries the owner's timezone, then GMT; set an explicit workflow timezone.
- [Pin and mock data](https://docs.n8n.io/build/work-with-data/pin-and-mock-data.md): development fixtures and pinned outputs; unavailable for production executions.
- [Add notes and documentation](https://docs.n8n.io/build/understand-workflows/workflow-components/add-notes-and-documentation.md): Sticky Notes use CommonMark Markdown, can sit behind nodes, and offer preset/custom colors.
- [Data Tables](https://docs.n8n.io/build/work-with-data/data-tables.md): default aggregate storage is currently 200 MiB, with warnings at 80%. Self-hosted override: `N8N_DATA_TABLES_MAX_SIZE_BYTES`. Project members can access project tables by default; Admins and Owner can see all users' tables. Direct access from Code-node built-ins is unsupported. Node, UI, and `/datatables` API access are documented; inspect instance version and permissions before selecting an operation.

Engineering guidance in the skill, including key choice, duplicate checks, database selection, and naming conventions, is design advice rather than a claim of built-in n8n transactional or row-level guarantees.
