# Closeboard — n8n closing dashboard

A responsive, self-contained dashboard based on the supplied closing-scorecard and workflow screenshots. No external fonts, libraries, CDN requests, credentials or LLM calls. It replaces the reporting interface; your existing submission workflow remains responsible for business logic.

## Preview

Open **dashboard.html** in a desktop browser. It works offline and shows clearly marked illustrative data, not extracted financial results. Try September / August, BU and ERP filters, status filtering, search, pagination, an entity detail dialog, and CSV export. At narrow widths the layout stacks and the scorecard scrolls horizontally.

To customize the design, edit `dashboard.html`, then run `python3 build_package.py` to regenerate the n8n Code-node file and ZIP. Existing sample payload edits are preserved. No Python or build process is needed inside n8n; paste the generated JavaScript directly.

## Validation performed

Tested the standalone dashboard in Chromium at desktop and 390px mobile widths, including calculations, scope-preserving filters, pagination, details, CSV download, live-format sample input and empty scopes. Rendering and filtering also passed inside a sandboxed iframe. Renderer tests checked the verified-identity contract, duplicate guards, invalid closed timestamps and script-injection escaping. These checks do not test your company's actual SSO, n8n Cloud instance or permission tables.

Optional regression tests: install Node.js and Playwright in your development environment, install its Chromium browser, then run `node tests/check.cjs`. Tests create temporary local QA files; they make no changes to your company systems.

## Serve it through n8n Cloud

Create a separate **GET** dashboard workflow:

1. Webhook: choose a production path such as `closing-dashboard`; set response mode to **Using Respond to Webhook Node**.
2. Authenticate this request using your approved authentication integration. Do not assume a Webhook inherits the Form Trigger's n8n User Auth or SSO. The verified subject must come from a validated token/session or approved trusted auth integration, never a URL parameter, email field or unverified header. Keep auth secrets on the server. A plain public webhook is not ready for company data.
3. Query dashboard viewing permissions and retrieve ONLY rows the viewer may see. Viewing scope can differ from the user's close/reopen permissions. Apply permission filtering on the server before passing data to the renderer; the browser filters are convenience controls only.
4. Prepare **one input item** with the JSON shape in **sample-payload.json**. Replace every illustrative identity, URL, record and timestamp. Set `viewer.authenticated` to true ONLY after verification. This field is an internal contract, not an authentication mechanism. Never wire an incoming webhook body directly into this renderer. Aggregate permitted records into `rows`, including empty `[]` for an authorized user with no records.
5. Add a **Code** node in JavaScript, **Run Once for All Items**. Paste the entire content of **n8n-render-dashboard.code.js**. It contains the full template; no file imports or HTML node are needed.
6. Add **Respond to Webhook**, response type **Text**, body expression `{{ $json.html }}`. Set `Content-Type: text/html; charset=utf-8` and `Cache-Control: private, no-store`. Publish the workflow and use the production URL behind your approved authentication.

The renderer deliberately rejects missing verified identity, invalid dates/statuses, missing required flags and duplicate item IDs within a period. It renders only explicitly selected fields, keeping hidden workflow credentials out of the page. It does not implement your authentication integration, permission query or data-source adapter because these were not supplied.

## Payload fields

| Field | Meaning |
|---|---|
| `generatedAt` | Snapshot timestamp, ISO 8601 with Z or numeric UTC offset. Use server time when data is retrieved. |
| `defaultPeriod` | Default close period, `YYYY-MM`; should match an available period. |
| `timeZone` | Display timezone, e.g. `America/New_York`. Store timestamp inputs with timezone offsets. |
| `dashboardUrl` | Absolute HTTPS production dashboard URL from server configuration. Enables full-page manual refresh. Omit to hide refresh. |
| `formUrl` | Absolute HTTPS closing form URL from server configuration. Omit to hide the submit action. |
| `viewer` | Verified server-side identity: `authenticated`, `id`, display `name`, and a permitted-scope label. |
| `rows` | All permitted required/nonrequired current-state items for the periods to display. |

Each row needs string `id`, `period`, `bu`, `ou`, `entity`, `erp`, and `status`; boolean `required`; and `targetAt`. `status` is exactly `open`, `closed`, or `reopened`. Closed rows need `closedAt`. Optional fields: `taskType`, `owner`, `closedBy`.

Keep `id` unique per period and stable through reopen/resubmit. If an OU has several separate closing tasks, give each task its own ID. Do not send an event log as status rows; this dashboard expects one current-state item per required closure. Keep append-only close/reopen history in your existing backend if needed.

## Calculation rules

- Completion = currently closed required items / all required items in the selected period, BU and ERP scope. Zero required items displays an em dash, not 100%.
- Seed all required period items before submissions start; unsubmitted OUs must remain in the denominator.
- Status and search narrow the scorecard and CSV only. Summary cards, ERP progress and attention list follow period/BU/ERP scope, so searching for a closed site does not falsely turn overall completion into 100%.
- Reopened items are incomplete. A past close timestamp is not shown as the current close when reopened.
- Overdue = open/reopened with a target strictly earlier than the server snapshot timestamp.
- Closed timing = `(targetAt - closedAt) / 1 hour`: positive is early, negative is late. Exactly on target counts as on time.
- The attention panel lists the five oldest overdue targets in scope. The full overdue set is available through the status filter.
- The page is a snapshot. Clock-based calculations use `generatedAt`, so all displayed data has a consistent as-of time. Refresh requests a new page and snapshot.

## n8n iframe behavior

n8n wraps webhook HTML in a sandboxed iframe. This implementation makes no background API calls, assumes no browser storage, and uses a configured absolute dashboard URL with a user-clicked `_top` link for refresh. Internal filtering runs entirely in the page. Test refresh through your company's actual SSO integration; it must authenticate the new request as well.

Browser-side CSV export works in a normal browser preview. Your n8n sandbox or company browser policy may block downloads. For guaranteed production export, provide a separate authenticated workflow returning permitted records as a CSV attachment. No token or n8n API key should be embedded in this page.

## Before monthly rollout

Verify one controller's allowed scope and another controller's denied scope; verify leadership's read scope separately. Check open, reopened, closed, late and exempt records; ensure required records with no submissions appear. Test your Cloud plan's peak concurrency with dashboard reads and a closing submission at the same time. This package is a tested rendering implementation, not a validation of your unknown production auth, tables or Cloud capacity.

## References

- https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.respondtowebhook
- https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.html
- https://docs.n8n.io/deploy/use-n8n-cloud/understand-concurrency

The dashboard is read-only. The Submit closing link opens your existing form rather than introducing a second implementation of close/reopen authorization.
