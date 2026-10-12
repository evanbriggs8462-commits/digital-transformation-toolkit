# Sources

Checked 2026-10-12.

- [n8n API authentication](https://docs.n8n.io/connect/n8n-api/authentication.md): API header, Enterprise scopes, non-Enterprise key capabilities.
- [n8n Webhook](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.webhook): authentication, CORS, fail-open `Only Run If` errors, sandboxed HTML responses.
- [n8n Workflow sharing](https://docs.n8n.io/workflows/sharing/): editors can use credentials attached to shared workflows.
- [OWASP Authorization](https://cheatsheetseries.owasp.org/cheatsheets/Authorization_Cheat_Sheet.html): least privilege and request authorization.
- [OWASP XSS prevention](https://cheatsheetseries.owasp.org/cheatsheets/Cross_Site_Scripting_Prevention_Cheat_Sheet.html): text sinks, sanitization, URL handling, CSP defense in depth.
- [OWASP CSRF prevention](https://cheatsheetseries.owasp.org/cheatsheets/Cross-Site_Request_Forgery_Prevention_Cheat_Sheet.html): tokens, origin validation, SameSite limitations.
- [OWASP prompt-injection prevention](https://cheatsheetseries.owasp.org/cheatsheets/LLM_Prompt_Injection_Prevention_Cheat_Sheet.html): indirect injection and deterministic tool permission boundaries.

Gateway, endpoint, and dashboard recommendations are application design guidance; they do not imply that n8n Cloud supplies a custom reverse proxy or automatically enforces business permissions.
