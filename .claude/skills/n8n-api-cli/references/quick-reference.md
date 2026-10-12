# Official n8n API, CLI, and MCP references

Checked: 2026-10-12. Commands are examples; they were researched, not executed against a user's instance.

- [Public API authentication](https://docs.n8n.io/connect/n8n-api/authentication.md): `X-N8N-API-KEY`; API roots use `/api/v1`; free-trial exclusion; key expiration; Enterprise scopes versus non-Enterprise full account capability.
- [Pagination](https://docs.n8n.io/connect/n8n-api/pagination.md): default 100, maximum 250; body contains `.data` and `.nextCursor`; send cursor for following pages and retain authentication.
- [Endpoint reference](https://docs.n8n.io/connect/n8n-api/api-reference.md): verify request/response schemas for the actual operation rather than constructing writes from full GET responses.
- [Server CLI](https://docs.n8n.io/deploy/host-n8n/configure-n8n/use-the-command-line.md): export/import command reference; `--backup` is not a full instance backup. Consult restart requirements and current import-trigger caveats before modifying a running instance.
- [Remote connections and n8n CLI](https://docs.n8n.io/connect/): follow the current remote-CLI instructions; inspect the local installation rather than assuming the Server CLI binary is the remote client.
- [Instance-level MCP](https://docs.n8n.io/connect/connect-to-n8n-mcp-server.md): execution plus building/editing workflows from n8n 2.13.0. Exposed workflow visibility and user permissions apply. `execute_workflow` defaults to the production/published version; manual mode can use the current draft. Settings layout documented from 2.33.0 differs from older versions.
- [MCP tool reference](https://docs.n8n.io/connect/connect-to-n8n-mcp-server/mcp-server-tools-reference.md): compare current documented tools with actual connected-tool discovery. A workflow-specific MCP Server Trigger node exposes only that workflow's tools.

- [n8n 2.0 changes](https://docs.n8n.io/changelog/v20-breaking-changes.md): activation terminology changed to publication; Code-node environment access and runner behavior changed. Inspect migration guidance before carrying old snippets into n8n 2.x.

Security choices such as a protected curl header file, avoiding shell tracing, and minimizing payloads are engineering guidance. Never publish n8n API keys into browser dashboard code.
