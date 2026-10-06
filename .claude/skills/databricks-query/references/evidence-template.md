# Private query evidence template

Copy only to an approved private project location. Never commit real internal metadata or results to a public repository. Keep identifiers sanitized when sharing; omit credentials and signed URLs entirely.

```markdown
## Query evidence
- Status: draft-unexecuted | blocked | executed
- Observed at: <UTC timestamp>
- CLI version / approved profile: <verified>
- Workspace / principal / warehouse ID / state: <verified>
- Catalog.schema.table / required columns and types: <verified>
- Metadata evidence: <command/statement ID; time; artifact pointer>
- Metric / business grain / physical grain / source-client keys: <verified or unresolved>
- Entity / period / timezone / currency-unit / sign / CDC policy: <scope>
- SQL and bound parameters: <private artifact pointer>
- Command / exit code or HTTP status / statement ID / terminal state: <fresh evidence>
- Intended scope / SQL LIMIT / API limits / chunks and rows fetched / truncated: <facts>
- Join match, duplicate, fanout checks / source-of-truth reconciliation: <scoped evidence>
- Unknowns / residual / exact blocker / next step: <concise>
```

Update facts only from observed evidence. Preserve failed hypotheses as failed; do not transform a draft, stale mapping, sample count, or old successful run into fresh validation.
