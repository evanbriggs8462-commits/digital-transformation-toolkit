---
name: n8n-dashboard-serving
description: Choose and implement n8n-backed dashboard serving using Webhook/Respond to Webhook HTML or a separately hosted UI with authenticated JSON endpoints. Use for iframe limitations, read snapshots, permission-aware caching, deployment checks, and keeping secrets out of browsers.
---

# n8n dashboard serving

## Choose the delivery boundary

Inspect n8n version, Cloud/self-hosted deployment, identity gateway, storage, permissions, and expected close-day concurrency. Treat n8n as the workflow backend; do not invent a general BI/dashboard node. Its workflow execution statistics are different from a business close dashboard.

For a small preview, a GET Webhook can authenticate, load permitted data, assemble one HTML document, and return it through Respond to Webhook. For a durable company dashboard with SSO, routing, assets, and frequent reads, prefer a separately hosted UI behind the company identity gateway. Its backend can call private n8n endpoints or an approved read store. Choose based on actual hosting constraints; do not claim monthly use alone proves production readiness.

Separate read from write: GET returns a snapshot and performs no submission/email action. POST validates and persists close transitions; use idempotency keys and concurrency/version checks. Apply CSRF defenses when cookie authentication is used. Notifications follow successful persistence and need their own retry/deduplication behavior.

## Configure the n8n response deliberately

Set Webhook **Respond** to **Using 'Respond to Webhook' node**. In Respond to Webhook, use **Text** for HTML (default `Content-Type: text/html`) or **JSON** for the data contract. Assemble one envelope before responding: the response node executes once using its first input item. Make successful, denied, and invalid-input branches reach a deliberate response; an unfinished response path can otherwise return an unintended success.

Since n8n 1.103.0, HTML webhook responses render in a sandboxed iframe. Top-level window/localStorage access fails; original authentication headers are unavailable inside the iframe; relative URLs do not work. Use absolute resource/form/API URLs. Validate browser behavior on the deployed version. Prefer self-contained read-only HTML or separately hosted session-aware UI. If issuing an embedded token is unavoidable, make it short-lived, narrowly scoped, revocable where supported, and never a long-lived n8n API/admin key.

## Secure reads and manage load

The Webhook supports Basic, Header, or JWT authentication; choose credentials compatible with the server boundary. A browser must never contain a shared service secret. Prefer verified SSO claims at a trusted backend that privately authenticates to n8n. Never trust a submitted email/header as proof of user identity.

Validate period and filters, resolve permitted BU/OU scope server-side, then fetch and aggregate. Authorize again for detail/export/write endpoints. CORS does not authenticate a caller; restrict origins and test preflight behavior rather than assuming the setting covers every browser request.

Use a durable read snapshot refreshed after successful changes or on a schedule. Cache by tenant, period, permitted-scope fingerprint/permission version, filters, and snapshot version. Do not reuse one user's filtered response for another. Invalidate after accepted writes and permission changes. Avoid shared CDN caching of personal finance data; use private server caching and appropriate response headers.

```json
{
  "period": "2026-09",
  "snapshotId": "fixture-v1",
  "asOf": "2026-10-03T14:00:00Z",
  "generatedAt": "2026-10-03T14:00:05Z",
  "timezone": "America/New_York",
  "scope": { "bu": "01", "ou": "001" },
  "kpis": { "required": 4, "closed": 2 },
  "rows": []
}
```

Verify production versus test webhook URL, identity rejection, denied direct URL, JSON/HTML content type, stale snapshots, iframe requests, and close-day concurrent read latency. Report measured limits and serving assumptions; do not publish, change authentication, or mutate live close data just to test.

## Sources

Checked 2026-10-12:
- [n8n Respond to Webhook](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.respondtowebhook/)
- [n8n Webhook](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.webhook/)

Caching, identity-gateway separation, and the example contract are architectural recommendations.
