---
name: n8n-api-cli
description: Inspect and manage n8n through its public REST API, available MCP tools, or the appropriate remote versus self-hosted Server CLI. Use for API authentication, pagination, safe workflow export/import, CLI discovery, and tool-capability checks.
---

# Select the available control surface

Identify deployment, installed version, instance URL, user permissions, and intended action. Prefer a connected n8n tool whose current schema covers the request. Discover the available MCP tools and read their schemas; do not invent method names, arguments, node-validation tools, or capabilities from remembered third-party MCP packages. Distinguish instance-level MCP from a workflow's MCP Server Trigger node.

Consult [references/quick-reference.md](references/quick-reference.md) for official sources and commands. Keep searches narrow: workflow names/IDs, a small execution window, or selected nodes. Avoid loading all execution payloads or entire credential inventories for a simple lookup.

# Use the public API correctly

Use the versioned public API root, commonly `https://INSTANCE/api/v1`; preserve a configured self-hosted base path. Authenticate every page with `X-N8N-API-KEY`. Treat `/rest/...` as an internal UI interface rather than a supported substitute for the public contract. Inspect the current endpoint schema before writes and strip read-only response fields where the write schema excludes them.

The public API is unavailable during the Cloud free trial. Enterprise API keys can have scopes; use the minimum needed. Non-Enterprise keys have the account's full resources/capabilities, so constrain the owning account and protect the key. Set expiry and revoke credentials when no longer needed.

Read workflows with a protected header file supplied outside the repository by the user's secret-management setup. Its content must include the API-key header; restrict filesystem access to it. Never insert plaintext keys into commands, workflow exports, HTML, logs, or Git. Avoid verbose curl output and shell tracing.

```bash
curl --fail-with-body --silent --show-error \
  --header "@${N8N_AUTH_HEADER_FILE}" \
  --header 'Accept: application/json' \
  --get "${N8N_API_BASE%/}/workflows" \
  --data-urlencode 'limit=100'
```

Aggregate response `.data`, then request the next page using URL-encoded `.nextCursor` in the `cursor` query parameter until absent/empty. Keep filters unchanged. The documented default limit is 100 and maximum 250; verify endpoint-specific exceptions. Limit stored responses to the data actually needed and redact sensitive node parameters.

# Distinguish two CLIs

The **Server CLI** ships with self-hosted n8n, runs on its host/container, directly accesses the database, and bypasses normal access controls. It is not a remote management client for n8n Cloud. Inspect help in the installed binary before using version-dependent flags:

```bash
n8n export:workflow --help
n8n import:workflow --help
n8n export:workflow --id=WORKFLOW_ID --output=workflow.json
n8n export:workflow --backup --output=backups/latest/
n8n import:workflow --input=workflow.json
```

Treat import as a write: matching exported IDs can overwrite existing workflows. Remove/change IDs only when intentionally creating copies; review credential bindings and sub-workflow references. Export drafts versus published versions deliberately. Back up before replacing workflows. Never use decrypted credential export for ordinary version control.

The separate **remote n8n CLI** uses the API and can manage reachable Cloud or self-hosted instances within permissions. Inspect its installed package/version and own help; do not interchange its syntax with Server CLI syntax.

# Verify the result

Read the target back after an authorized mutation and compare relevant nodes, connections, settings, and credential references. Import/save is distinct from publication. In n8n 2.x, use the installed publish/unpublish model; old `update:workflow` activation commands are deprecated. Confirm which draft/published version MCP execution or an API action will use before starting any workflow with side effects.
