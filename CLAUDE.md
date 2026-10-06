# Finance analysis workspace

Use `.claude/skills/` for task procedures. Load only the skill and reference needed for the current question; do not read the whole toolkit into context.

- Databricks SQL/discovery: use `databricks-query`. Follow `databricks-agent-toolkit/AGENTS.md` for live operations; that contract also applies when operating from this root.
- SAP semantics: choose `sap-materials`, `sap-fi-open-items`, `sap-profit-center`, or `sap-sd-mm`. Treat standard SAP descriptions as search hypotheses until the actual landed schema and grain are verified.
- Power BI intake: follow the root `AGENTS.md`. Its launcher rules concern PBIX work, not Databricks queries.
- Long investigations: use `finance-handoff` at a meaningful milestone, before changing topics, or before clearing context. Keep one active, concise handoff per session under ignored `.claude/state/`; save working SQL/code separately and reference paths.

Distinguish verified facts, hypotheses, unexecuted SQL, and live results. Never invent company mappings, model policy, catalog/table names, permissions, or successful executions. Use the existing approved company gateway and models; do not change authentication, routing, security controls, or budgets to optimize usage.

## Compaction instructions

Preserve the current objective; approved scope; verified table/column names and evidence references; grain and joins; fiscal/key-date, currency and sign decisions; exact unresolved error; failed approaches and why; changed files and validation status; and the next concrete action. Mark unknowns explicitly. Reference large SQL/results by local path instead of repeating them. Treat a saved compaction summary as a continuity aid whose facts require evidence, not a new source of truth. Do not include credentials or signed result URLs.
