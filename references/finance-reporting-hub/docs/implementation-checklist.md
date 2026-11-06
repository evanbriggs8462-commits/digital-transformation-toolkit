# Implementation and handoff checklist

This checklist translates the agreed design into reviewable work. It is a plan and validation guide; it does not mean the page has been deployed or tested inside the user's Power BI tenant.

## Agreed scope

- [ ] The page helps users choose and open a report.
- [ ] Each report has a title, a brief useful description, relevant topics, and optional representative tab labels.
- [ ] Owner, refresh, and “link coming soon” fields are absent from the landing-page presentation.
- [ ] Long methodology and warning text remain in the reports' own landing pages.
- [ ] Only a caveat that materially changes report selection remains in the brief summary.
- [ ] Compact tiles are the default design; a report index or finance-chapter view is optional.
- [ ] There is no permanent description panel consuming a column and no multi-card expansion that rearranges neighbors.

## Content and catalog

- [ ] Use one source record per report and stable unique IDs.
- [ ] Confirm names against the actual reports; retain familiar names in the title or summary if display names change. The starter has no separate alias field.
- [ ] Replace circular descriptions such as “Revenue reporting” with a verified purpose.
- [ ] Distinguish similarly named reports, such as monthly trends versus transaction details.
- [ ] Confirm which reports cover Revenue, Inventory, COGS, Scrap, OPEX, Close, and Receivables before assigning those tags.
- [ ] Allow several tags per report while displaying the report once in results.
- [ ] Search titles, summaries, categories, topics, and verified key tabs; include familiar abbreviations in that searchable text.
- [ ] Use a single topic selection initially; apply the search within that topic and make clearing filters obvious.
- [ ] Confirm key-tab names instead of inventing them from topic names.
- [ ] Validate JSON structure, duplicate IDs, required text, and destination protocols before publishing.
- [ ] Keep screenshots, credentials, private operational data, and actual sensitive links out of public examples.

## Visual layout

- [ ] Align the left edge of the title, filters, and report collection.
- [ ] Use Segoe UI/system fallbacks, or one deliberately hosted alternative, consistently.
- [ ] Start with a 28/36 px hub title, 18/24 px report titles, 16/24 px descriptions, 14/20 px controls, and 13/18 px secondary labels.
- [ ] Use the proposed high-contrast palette as a starting point; do not call it an official Corning palette.
- [ ] Keep the header compact and the introductory sentence short.
- [ ] Use roughly 24 px desktop outer padding, 16 px narrow padding, 16 px grid gaps, and 16–20 px tile padding.
- [ ] Adapt the column count to the actual embedded content width. Do not force three columns simply because the monitor is wide.
- [ ] Keep tiles equal height within a row through layout and concise content, not clipping or rigid pixel heights.
- [ ] Align destination actions consistently and avoid large empty areas under short descriptions.
- [ ] Use restrained rectangular tiles with small corner radii and subtle borders.
- [ ] Keep passive labels visually different from interactive filters and links.
- [ ] Reserve yellow for a meaningful caution; remove the large blanket warning box.
- [ ] Use only an approved Corning/175 asset, in its original proportions with the required clear space.
- [ ] Place any photograph or decorative fiber motif in the header, keeping text and reports on clear surfaces.

## Navigation and interaction

- [ ] Report titles/actions have one clear destination, rather than competing expand and open behaviors.
- [ ] Do not place nested links or buttons inside a single clickable card link.
- [ ] A key-tab label is interactive only when its direct destination is verified.
- [ ] Show external/new-tab behavior accurately where relevant.
- [ ] A click does not unexpectedly reorder or enlarge other reports.
- [ ] Filtering preserves a stable report order and shows an honest empty state.
- [ ] Keyboard users can reach and operate search, filters, and report destinations.
- [ ] Focus is clearly visible; hover is not the only way to discover an action or essential description.
- [ ] Use native headings, labels, lists, buttons, and links appropriately.
- [ ] Announce changed result counts politely without announcing every item or stealing focus.
- [ ] Respect reduced-motion preferences; use restrained state transitions rather than decorative animation.

## Embedded environment and serving

- [ ] `demo/index.html` works as a standalone local reference using the README's setup instructions.
- [ ] `data/catalog.example.json` remains illustrative until destinations and content are verified.
- [ ] The generated HTML is served through a GET route that does not send messages or modify business records.
- [ ] The n8n response is one assembled HTML document, with a deliberate HTML content type and success/error responses.
- [ ] The Power BI link uses the production webhook URL, not a test URL.
- [ ] The required workflow activation/publication state is confirmed on the installed n8n version.
- [ ] All necessary resource and report URLs are absolute.
- [ ] Search and filters work without accessing the parent window or local storage.
- [ ] No browser-delivered document contains shared credentials or service secrets.
- [ ] The HTML host's authentication and the reports' permissions are tested separately.
- [ ] Static tag filtering is never treated as role-based access control.
- [ ] The Microsoft external-content notice is accounted for as host-controlled space.
- [ ] No change to Org app sharing, audience membership, notification settings, or live deployment is made as an accidental side effect of styling work.

## Useful manual checks

| Check | Expected result |
|---|---|
| Open the hub with Power BI navigation expanded | Readable type; no clipped tiles or horizontal page scrolling |
| Collapse navigation | The report collection uses the extra width cleanly |
| Test narrow, medium, and wide iframe widths | Sensible one/two/three-column behavior where space permits |
| Enlarge text to 200% | No lost text or controls |
| Check 320 CSS-pixel equivalent width | Ordinary content reflows without needing two-directional scrolling |
| Use the longest title and summary | Wrapping remains readable; action alignment remains coherent |
| Search a familiar abbreviation | Correct report is found using its title or other searchable catalog text |
| Search text with no matches | Clear empty state with a way to reset |
| Choose Revenue, then search a reconciliation name | Topic and search combine predictably |
| Use only keyboard navigation | Controls and destinations remain understandable and operable |
| Open each destination as an intended viewer | Correct report/page and expected authentication behavior |
| Try an unauthorized destination | Power BI enforces the user's actual access |
| Disable/block an optional image or web font | The directory remains readable and functional |
| Measure first load and subsequent filters | Filters update locally and do not create a workflow run per click |

These checks are targets for the final implementation. A local prototype passing them does not establish tenant-specific embedding, authentication, or report-link behavior.

## Quick usability review

Ask a few representative finance users to complete concrete tasks without coaching:

1. Find the report for monthly revenue trends.
2. Find the operating-expenses-versus-budget report.
3. Find the report that contains inventory information.
4. Explain, from the tile, when the margin-analysis report would be useful.

Record where they hesitate, choose the wrong report, miss a filter, or need a definition. Improve titles, descriptions, and grouping before adding more UI. Use the exact available reports for these tasks rather than assuming the illustrative catalog is complete.

## Handoff prompt for a coding assistant on the work PC

Copy this prompt into the existing coding session after opening `references/finance-reporting-hub` on branch `docs/finance-reporting-hub` and making the actual source files available. Paths in the prompt are relative to that reference folder:

```text
Improve our existing n8n-served Finance Reporting Hub using this repository as the design reference.

Read README.md, docs/design-guide.md, docs/n8n-powerbi-howto.md, and
docs/implementation-checklist.md. Inspect the current HTML, JSON catalog, and
n8n serving configuration before editing. Do not guess private URLs, report
definitions, or acronym meanings.

Build a compact directory: report title, concise purpose, relevant finance
topics, two or three verified key tabs when useful, and a clear report link.
Remove owner, refresh, and "link coming soon" from the page. Keep detailed
guidance in the reports themselves. Do not add a permanent details panel or
inline card expansion that rearranges other reports.

Use the documented type scale, readable contrast, compact header, consistent
spacing, and responsive tiles. Work from the actual Power BI iframe width.
Keep descriptions readable and let layouts grow at zoom instead of clipping.
Use one JSON catalog for all views, with local search and topic filtering.

Retain existing authentication, authorization, and verified destinations.
Use absolute URLs and respect n8n's sandboxed iframe limitations. Do not place
secrets in the browser or assume access to the parent window/localStorage.
Use supplied approved brand artwork; do not recreate a Corning logo.

Show the proposed changes locally, validate catalog and link handling, check
keyboard and narrow/zoomed layouts, and document which embedded-environment
checks remain. Do not publish the workflow, change sharing/audiences, or send
notifications unless that action is separately requested in this session.
```

## Source references

- [Microsoft Fluent typography](https://fluent2.microsoft.design/typography)
- [USWDS card guidance](https://designsystem.digital.gov/components/card/)
- [WCAG minimum contrast](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html)
- [WCAG resize text](https://www.w3.org/WAI/WCAG22/Understanding/resize-text.html)
- [WCAG reflow](https://www.w3.org/WAI/WCAG22/Understanding/reflow.html)
- [n8n Respond to Webhook](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.respondtowebhook/)
- [Microsoft Org app guidance](https://learn.microsoft.com/en-us/power-bi/explore-reports/org-app-items)

For the full research trail and the distinction between standards and design choices, see [research-sources.md](research-sources.md).
