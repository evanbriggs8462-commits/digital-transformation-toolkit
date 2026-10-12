---
name: n8n-security
description: Secure n8n Cloud workflows and HTML dashboard endpoints with least-privilege credentials, server-side authorization, safe HTML rendering, CSRF protection, controlled CORS, and prompt-injection boundaries. Use when handling company identity, financial status, secrets, or browser-facing APIs.
---

# n8n security

Identify the application's entry points, trusted identity source, sensitive data, credential owners, and side effects. Read [sources](references/sources.md) for platform-specific details. Apply controls to form submissions, dashboard JSON, drill-through, exports, notification routing, and administrative tooling.

## Protect identity and privileges

Authenticate callers before processing business data. Treat a typed email or identity header as unverified unless a trusted authenticated gateway validates identity, strips and replaces that header, and prevents direct upstream bypass. When available and configured, native Form Trigger **n8n User Auth** provides authenticated n8n user output. Keep BU/OU read and write permissions in deterministic server-side checks; hiding a button or filtering a browser table does not enforce access.

Use deny-by-default behavior on missing identity, lookup errors, and unknown scope. Do not use Webhook **Only Run If** as an authorization boundary: current documentation states expression evaluation errors allow the request through.

## Keep secrets server-side

Use n8n credential objects and approved secret management rather than literals in workflow JSON, Code nodes, HTML, screenshots, or Git. Prefer service accounts with the minimum required downstream permissions. Separate development and production credentials; rotate exposed secrets and set supported expirations.

Keep `X-N8N-API-KEY` out of the dashboard browser, local storage, query strings, and downloadable files. The n8n management API operates on workflows and instance resources; use an authenticated application endpoint returning scoped business data for dashboard consumers. Enterprise API keys support scopes; current non-Enterprise keys inherit full account capabilities. Verify plan support before assuming a key can be read-only.

Review project membership and workflow sharing because workflow editors may use the credentials attached to shared workflows. Restrict Data Tables containing permissions or recipient mappings to an appropriate project.

## Render untrusted data safely

Use text sinks for comments, organization names, submitter labels, and API values:

```js
const label = document.createElement('span');
label.textContent = row.comment ?? '';
container.replaceChildren(label);
```

Do not concatenate untrusted content into `innerHTML`, script blocks, style rules, or event attributes. If rich HTML is required, sanitize it with a maintained sanitizer and an explicit allowlist. Validate URL scheme and destination before creating links; reject `javascript:` URLs. Keep CSS class selection within a fixed status map.

Configure a dashboard-specific Content Security Policy at its actual host or gateway, with explicit script and connection sources. Treat CSP as an additional defense, not a replacement for safe rendering. Test n8n webhook HTML's sandboxed iframe behavior; do not assume parent-window storage, authentication headers, or relative URLs work inside it.

## Control requests and downstream tools

Keep reads on GET and state changes on POST/PATCH/DELETE. For cookie-authenticated state changes, validate CSRF tokens and origin as appropriate; use Secure, HttpOnly, and appropriate SameSite cookie settings. Restrict CORS origins, but continue authenticating and authorizing every request: CORS constrains browser access and is not authentication.

Validate schemas, lengths, enumerations, dates, and scope identifiers. Parameterize SQL. Allowlist outbound destinations rather than letting a form supply arbitrary HTTP Request URLs. Keep TLS certificate verification enabled. Bound payload sizes and rate-limit costly endpoints at the authenticated gateway.

Treat email bodies, comments, webpages, retrieved documents, and tool outputs as untrusted data for Claude or workflow AI agents. Keep credentials, permission decisions, KPI arithmetic, and notification recipients outside model discretion. Give agents narrow tools and validate every proposed tool call deterministically.

Log receipt IDs, actor IDs, scope, outcomes, and timing; omit secrets and unnecessary sensitive content. Verify unauthorized reads/writes, forged headers, malicious HTML, missing CSRF tokens, and direct gateway-bypass attempts.
