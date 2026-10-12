---
name: html-dashboard-interactions
description: Implement dashboard dropdowns, dependent filters, KPI drill-through, breadcrumbs, back navigation, sorting, refresh buttons, keyboard focus, and asynchronous result states. Use when dashboard controls or navigation must work consistently.
---

# HTML dashboard interactions

## Establish one state model

Inspect the current router and host before choosing navigation. Model `period`, `bu`, `ou`, optional `plant/task`, `status`, `sort`, `page`, and `snapshotId` explicitly. Filters describe the view; server-side authorization decides what may be returned. A hidden dropdown option is not access control.

Use native labelled `select` controls first. Native controls provide established keyboard behavior; custom comboboxes require a complete interaction pattern. Give each control a visible `label` associated through `for` and `id`. Avoid using placeholders as labels.

Dependency rule: period changes refresh its allowed scope; BU changes recompute OU and clear an invalid OU; OU changes clear invalid plant/task. Changing any row filter resets pagination to the first page. Use explicit “All permitted OUs,” never an ambiguous blank. Disable unavailable controls and explain why. Keep focus on the changed control; announce updated result count without moving focus on every filter change.

Choose immediate updates for fast local data or an “Apply filters” button for expensive requests. A reset action restores documented defaults and resets dependent filters, status, sort, and page together. Do not unexpectedly change the accounting period.

## Make drill-through reversible

KPI drill-through must use the exact predicate that produced the card and retain period, authorized scope, and snapshot/as-of context. “Open 12” should open those 12 records, not all open records across periods. Label the action “View 12 open items.” Include a breadcrumb with a labelled `nav` and `aria-current="page"` on the current page. Provide “Back to summary,” restoring filters, sort, pagination, and scroll/focus position.

For a separately hosted page, use the existing router or `URLSearchParams` with History API and a `popstate` handler. Initialize the first history entry with `replaceState`. Put only nonsecret, nonsensitive view state in the URL; never tokens or personal data. For n8n's sandboxed HTML response, use in-frame application state or verified absolute navigation; do not assume top-level History API access works.

```js
// A separately hosted dashboard with an existing validated state.
const detailUrl = new URL("/close/detail", location.origin);
const query = new URLSearchParams();
for (const key of ["period", "bu", "ou", "snapshotId"])
  if (state[key]) query.set(key, state[key]);
query.set("status", "open");
detailUrl.search = query.toString();
openItemsLink.href = detailUrl.href;
```

## Handle asynchronous updates and actions

Cancel obsolete requests with `AbortController` or ignore results using a request sequence number. Compare response scope/snapshot to the current request before rendering. Mark results busy and keep a pre-existing `role="status"` region for concise updates. Distinguish loading, empty, failed, expired session, and stale snapshots. Never leave old-period cards looking current while a new period loads.

Use buttons for Refresh, Apply, Reset, and other actions. Set a meaningful pending label, prevent double submission, and restore focus after completion. Sorting uses a header button and `aria-sort` on the active header. Focus the detail heading after intentional route changes; return focus to the activating card/link on back. Render server text with `textContent`, not raw `innerHTML`.

Verify cascading reset, quick repeated filter changes, back/forward behavior, denied scope, empty results, keyboard use, and card-to-detail count equality. Report host assumptions and observed checks.

## Sources

Checked 2026-10-12:
- [MDN select](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/select)
- [MDN URLSearchParams](https://developer.mozilla.org/en-US/docs/Web/API/URLSearchParams)
- [MDN History API](https://developer.mozilla.org/en-US/docs/Web/API/History_API/Working_with_the_History_API)
- [W3C breadcrumbs](https://www.w3.org/WAI/ARIA/apg/patterns/breadcrumb/)
- [W3C status messages](https://www.w3.org/WAI/WCAG22/Understanding/status-messages.html)
- [MDN AbortController](https://developer.mozilla.org/en-US/docs/Web/API/AbortController)
- [MDN textContent](https://developer.mozilla.org/en-US/docs/Web/API/Node/textContent)
