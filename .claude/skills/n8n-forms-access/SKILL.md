---
name: n8n-forms-access
description: Build or review n8n forms, trusted submitter identity, required-user lookups, and BU/OU permissions for monthly close submissions and dashboard access. Use when a form collects company email, uses SSO, or restricts plant and organizational scope.
---

# n8n forms and access

Treat the close tracker as an authenticated application. Make identity, permission checks, period validation, and persistence explicit before designing form styling. Read [sources](references/sources.md) when checking version-dependent options.

## Establish trusted identity

Inspect the installed n8n Cloud version, Form Trigger node version, available authentication options, and project permissions. Current documentation lists **n8n User Auth**, **Basic Auth**, and **None**; confirm availability in the user's instance.

For provisioned n8n users, use **n8n User Auth** and retain **Include User in Output**. Consider **Require Workflow Execute Permission** if project execution permission should be an additional restriction. Inspect a sanitized execution to locate the authenticated user metadata; do not invent its JSON path or substitute a similarly named form field.

Distinguish n8n instance SSO from arbitrary external form authentication. SSO configured for n8n can authenticate users signing into that instance, but an unauthenticated webhook or form does not inherit verified company identity merely because SSO exists.

For a company portal using an external identity provider, authenticate at a trusted backend or gateway. Verify token signature, allowed algorithm, issuer, audience, expiration, and tenant as required by that provider. Pass a server-validated identity to n8n over an authenticated upstream connection. Strip and replace incoming identity headers at the gateway, and prevent direct callers from bypassing it. Treat typed email, query parameters, hidden fields, and client-supplied headers as untrusted input. A shared Basic Auth password identifies possession of that password; it does not prove which employee submitted.

## Authorize each operation

Use separate server-side checks for submission writes and dashboard reads. Define permission records such as:

```text
principal_id | email | active | bu | ou | can_submit | can_view
```

Use an immutable identity ID where available; retain canonical email for existing lookup compatibility. Normalize documented identifiers without changing their meaning: trim surrounding whitespace, compare email consistently, and preserve leading zeros in BU/OU codes.

For a write, require an active user, an allowed BU/OU pair, an open reporting period, and an allowed status transition. For a read, restrict returned rows, KPI denominators, dropdown options, drill-through details, and CSV exports to approved scope. A dropdown containing only allowed plants improves usability; repeat the permission check after submission. Deny access when a lookup is missing, ambiguous, unavailable, or malformed.

## Assemble the submission path

Use this order:

1. Authenticate and extract trusted identity.
2. Validate field types, sizes, status values, and period format.
3. Lookup the active user and BU/OU permission.
4. Resolve the authoritative period and expected close requirement.
5. Persist an idempotent close event and notification intent.
6. Return a receipt; dispatch notifications separately.

Set `submitted_at` on the server; do not accept a browser clock as the audit timestamp. Resolve recipient addresses from maintained routing data rather than accepting arbitrary recipient fields.

## Format and verify the form

Use stable field names such as `period`, `bu`, `ou`, `status`, and `comment`. Add explicit labels, a clear period header, required fields, helpful placeholders, and a confirmation containing the saved receipt ID. Use Custom Form Styling for CSS. Native Custom HTML is sanitized; do not assume embedded scripts, buttons, or inputs will survive. Use a separate authenticated dashboard for richer interactive controls.

Use the Test URL while developing; publish and use the Production URL for real submissions. Test verified identity, forged email, altered BU/OU, inactive users, closed periods, and forbidden dashboard drill-through. Return generic denial responses without disclosing unrelated user or permission records.
