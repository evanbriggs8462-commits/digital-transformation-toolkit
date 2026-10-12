# Monthly-close fixture cases

Synthetic examples, not production data or organizational policy.

## Canonical case

Period `2026-09`; grain `period + BU + OU`. Five approved required items, A–E. Deadline `2026-10-02T17:00:00-04:00` in `America/New_York`, equivalent to `2026-10-02T21:00:00Z`. Snapshot `asOf=2026-10-03T14:00:00Z`. All items have distinct BU/OU tuple keys and are permitted to this viewer.

| Item | Accepted events/state at asOf | Treatment |
| --- | --- | --- |
| A | Closed at `2026-10-02T20:00:00Z`; same event delivered twice | Closed once, on time |
| B | Closed at `2026-10-02T22:00:00Z` | Closed once, late |
| C | Closed, then reopened at `2026-10-03T12:00:00Z` | Open, reopened, overdue |
| D | No submission | Open, overdue |
| E | Approved exemption effective before asOf | Exempt, outside denominator |

Expected eligible required = 4; closed = 2; completion = 50.0%; currently closed on time = 1; on-time/all-required = 25.0%; closed late = 1; overdue open = 2; reopened = 1; exempt = 1. Closed + open must equal eligible required. Reopened is a subset of open, so do not add it again to total items.

## Edge cases

- Earlier snapshot before C's reopening selects C's previous state and excludes the future reopening event.
- A sixth unsolicited submission outside approved required scope neither increases denominator nor numerator; record a quality exception.
- No eligible required items yields completion `null` and label `N/A`, with the reason “No required items in this scope.”
- Denied OU requested through a direct URL returns no unauthorized rows or totals; server policy may reject the request outright.
- Two BUs with 1/1 and 1/9 closed yield global completion 2/10 = 20.0%, not mean-of-percentages 55.6%.
- Due date-only input requires an approved timezone and cutoff conversion; daylight-saving changes must not use a hard-coded UTC offset.
- Changing period leaves identical BU/OU identifiers isolated through the composite grain key.

When reopening, exemptions, or deadline rules differ locally, change both the metric contract and expected fixtures together.
