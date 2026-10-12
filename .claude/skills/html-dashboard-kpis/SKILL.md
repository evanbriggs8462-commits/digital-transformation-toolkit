---
name: html-dashboard-kpis
description: Define and verify monthly-close completion, on-time, late, overdue, and exempt KPIs at period + BU + OU grain. Use for dashboard calculation contracts, denominator handling, event deduplication, reopened items, timestamps, and drill-through reconciliation.
---

# HTML dashboard KPI contracts

## Define the contract before calculating

Inspect the required-scope table, event history, permissions, period calendar, and existing close policy. The following rules are proposed defaults, not accounting policy. Preserve established definitions and document any unresolved choice.

Default item grain is `(period, BU, OU)`. Add plant or task only if separately required; never count both OU and its task rows as equal items in the same denominator. Keep identifiers as strings and use a tuple/structured key. Define period format, calendar timezone, deadline boundary, exemption authority, reopening behavior, and snapshot/as-of rule.

The denominator comes from the approved required-scope snapshot for the period, intersected with the viewer's permitted scope and selected organizational filters. Remove approved exemptions; display their count and reason separately. Missing submissions remain open. Never derive requirements from submissions, recipient lists, or the current directory of users. Status/search filters narrow detail rows but must not silently redefine a summary denominator.

## Compute one canonical item state

- Deduplicate repeated events by a stable event/idempotency ID. Retries do not create additional required items or completions.
- Select the last accepted event at or before `asOf` using an authoritative revision/sequence and deterministic tie rule. Timestamps alone may collide.
- A reopened item currently counts as open; a historical “closed once” event does not count as current completion. Retain history for audit.
- A completed item is closed-late when its effective latest completion exceeds the agreed deadline. An open item is overdue when `asOf` exceeds that deadline. Keep closed-late and overdue-open separate.
- An exempt item is excluded only through an approved, effective exemption. An unapproved claim does not remove requirements.
- Invalid/missing timestamps or conflicting revisions are data-quality exceptions; do not guess their on-time status.

Suggested cards: Closed, Required eligible, Completion %, On-time %, Overdue open, Reopened, Closed late, and Exempt. Define on-time as currently closed by deadline divided by all eligible required items. If the organization instead measures on-time among completed items, use that explicit label and denominator.

```js
const completion = requiredCount === 0 ? null : closedCount / requiredCount;
const label = completion === null ? "N/A" :
  new Intl.NumberFormat("en-US", {
    style: "percent", minimumFractionDigits: 1, maximumFractionDigits: 1
  }).format(completion);
// Show the accompanying counts, e.g. "2 of 4 required items".
```

Keep full precision internally; round only presentation. Never show 0% or 100% for a zero denominator. Flag impossible states such as closed > required instead of clamping. Aggregate ratios from summed counts, not averages of BU percentages. Display the grain beside aggregate cards when ambiguity exists.

## Keep time and detail consistent

Store instants as ISO timestamps with offsets/UTC; display in the documented IANA business timezone. Interpret a date-only deadline using that business timezone and an explicit cutoff rule. Distinguish `asOf`, source `generatedAt`, and client fetch time. A drill-through uses the same snapshot and canonical states as its card; use counts before pagination.

Review [fixture cases](references/kpi-fixtures.md) before implementation. Verify duplicates, reopening, exemptions, zero requirements, unauthorized scope, period isolation, and unequal BU sizes. Deliver a concise metric contract, computation changes, fixture results, and unresolved policy decisions. Avoid claiming a mock fixture validates the production source.

## Sources

Checked 2026-10-12:
- [MDN Intl.DateTimeFormat](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Intl/DateTimeFormat)
- [MDN Intl.NumberFormat](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Intl/NumberFormat)

Business rules above are implementation recommendations requiring an approved local close policy.
