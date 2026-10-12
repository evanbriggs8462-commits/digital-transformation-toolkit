---
name: html-dashboard-layout
description: Build or review HTML dashboard structure, headers, KPI cards, close-status tables, responsive layouts, accessible colors, and loading or stale-data presentation. Use for dashboard styling and information hierarchy.
---

# HTML dashboard layout

## Start with the information contract

Inspect existing markup, brand tokens, permitted scope, KPI definitions, and serving environment before editing. Prefer the project's components; do not add a chart library for a handful of cards. For n8n-served HTML, consult `n8n-dashboard-serving` before assuming browser storage or navigation works.

Use this reading order: page header, period/scope filters, KPI summary, exception detail, supporting status table. Put “September 2026 monthly close,” selected BU/OU, target deadline, and “Data as of” near the heading. Distinguish source freshness from the time the browser last fetched data. A browser refresh must not imply the source refreshed.

Keep one `h1`, then logical `h2` sections. Use `header`, `main`, named `nav`, and an actual data `table`. Explain abbreviations on first use. Format numbers consistently; align numeric table columns right and keep identifiers as strings so leading zeros survive.

## Useful defaults

- KPI card: descriptive label, value, numerator/denominator, short definition, and explicit “View open items” link where drilling is supported. Separate closed count, overdue open count, and closed-late count.
- Table: `caption`, `thead`, `tbody`, column `th scope="col"`, and row headers where helpful. Show BU, OU, optional plant/task, state, owner, due time, completion time, and detail action only when permitted.
- Status badge: visible text plus a stable color. Use “Closed,” “Open,” “Overdue,” “Reopened,” and “Exempt”; never make color the only meaning. Keep explanatory labels beside icons.
- Keep actions above the table, with one clear primary action. Use a link for navigation and `button type="button"` for an in-page action. Avoid clickable `div` elements and nested controls inside clickable cards.

Example palette on white: primary `#1D4ED8`, text `#111827`, muted text `#4B5563`; Closed `#166534` on `#DCFCE7`; Open `#1E40AF` on `#DBEAFE`; Overdue `#991B1B` on `#FEE2E2`; Reopened `#854D0E` on `#FEF9C3`; Exempt `#374151` on `#F3F4F6`. Recheck actual contrast after any token change. Target at least 4.5:1 for ordinary text, 3:1 for large text, and visible control boundaries/focus indicators. Do not use decorative low-contrast gray for actionable content.

```css
.kpis {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(min(100%, 14rem), 1fr));
  gap: 1rem;
}
.table-scroll { overflow-x: auto; }
.number { text-align: right; font-variant-numeric: tabular-nums; }
:focus-visible { outline: 3px solid #1d4ed8; outline-offset: 3px; }
```

## Present every data state

Loading: preserve layout, mark the results region `aria-busy="true"`, and announce one concise status. Empty: distinguish no required scope from no rows matching filters. Error: retain clearly marked previous values only when their scope matches; show retry. Stale: display the source timestamp and freshness rule. Unauthorized: expose no hidden scope or row counts. Never replace unknown data with zero.

Verify at narrow widths and 200% zoom, with long OU labels and keyboard navigation. Check card counts against detail rows, heading order, focus visibility, and labels without relying on color. Deliver the changed components plus assumptions and checks performed.

## Sources

Checked 2026-10-12:
- [W3C use of color](https://www.w3.org/WAI/WCAG22/Understanding/use-of-color.html)
- [W3C minimum contrast](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html)
- [W3C table captions](https://www.w3.org/WAI/tutorials/tables/caption-summary/)
- [MDN button](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/button)
- [MDN grid columns](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/grid-template-columns)
