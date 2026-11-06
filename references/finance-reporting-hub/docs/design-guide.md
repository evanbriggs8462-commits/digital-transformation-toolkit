# Finance Reporting Hub design guide

Research and decisions reviewed **November 6, 2026**. This guide captures the current design direction for an n8n-served HTML directory embedded in a Power BI Org app. The exact pixel values and palette below are implementation starting points, not Microsoft or Corning requirements. Normative accessibility constraints are identified separately.

## Purpose and current scope

Help a finance user quickly identify the right report and open it. Each entry should explain what a report covers without duplicating the report's own introduction or technical documentation.

Keep these fields visible:

1. Recognizable report title.
2. One useful sentence, normally about 15–25 words.
3. One or two relevant finance topics.
4. Two or three representative tab names when they help distinguish the report.
5. One clear action to open the report.

Remove repeated owner, refresh, and “link coming soon” fields. Remove repetitive “Power BI report” badges when that describes almost every item. Retain external-destination behavior only when users need it to understand what clicking will do. A consequential scope distinction can stay in the summary; detailed caveats belong in the destination report.

### Superseded interaction decision

An earlier proposal used a permanent right-hand details panel because the cards contained long guidance. **That is no longer the recommendation.** Once the content is shortened, a permanent panel consumes width and adds an unnecessary click. The current default shows the useful summary and tabs directly in the tile. It has no inline expanding cards and no details panel. Selecting one report should not move unrelated reports around the page.

## Layout options

| Direction | Structure | Suitable use |
|---|---|---|
| **Compact tiles — recommended default** | Equal-width rectangular entries in a responsive grid | Balances visual appeal and brief report explanations |
| Report index | Aligned vertical rows with title, summary, topics, and destination | Efficient for frequent users and long report names; optional view from the same catalog |
| Finance chapters | Topic headings with compact report entries underneath | Useful when people primarily browse by finance question |

Use lightly rounded rectangles. Circles, hexagons, masonry layouts, and uneven bento blocks consume reading space or imply differences in importance. This is a contextual design judgment, not a universal scientific rule. Express the brand through a restrained header, clear typography, and consistent interaction.

For an entry with one destination, use one semantic link. If individual tabs also navigate, place separate links inside a non-clickable container; never nest links. Passive topic or tab labels should not look like interactive buttons. Actual topic filters must be buttons with visible selected states.

## Typography

**Recommended family:** Segoe UI with native system fallbacks. It fits beside Power BI and avoids a font download when already installed. Inter is a strong optional alternative if a consistent custom font across platforms is important enough to justify hosting and testing a font asset. No source establishes one universally best font for this task.

```css
font-family: "Segoe UI", system-ui, -apple-system,
             BlinkMacSystemFont, Arial, sans-serif;
```

| Element | Size / line height | Weight |
|---|---:|---:|
| Finance Reporting Hub heading | 28 / 36 px | 600 |
| Introductory sentence | 16 / 24 px | 400 |
| Report title | 18 / 24 px | 600 |
| Report description | 16 / 24 px | 400 |
| Filter and action label | 14 / 20 px | 500–600 |
| Topic and tab label | 13 / 18 px | 500 |

These values deliberately give descriptions more room than a dense administrative interface. Microsoft Fluent's web ramp includes 14/20 body, 16/22 subtitle, and 28/36 title sizes; the chosen 16/24 descriptions are a recommendation for this directory.

Keep the heading left-aligned with filters and entries. Use one font family, regular sentence case, and a limited number of weights. Gain density by removing repeated content and excessive padding rather than reducing essential text to 10–12 px. Avoid justified text and all-capital descriptions.

If using Inter, host an approved WOFF2 asset and test its loading strategy. Font swaps can change text dimensions and shift layout. Referencing an installed system font in CSS is different from copying proprietary font files to a server.

## Color and visual hierarchy

When reviewing photographs of an interface, glare, camera processing, scaling, and monitor settings prevent exact color or font measurement. Inspect the actual CSS and rendered page instead.

The following are **proposed interface tokens, not official Corning digital brand specifications**:

| Role | Color | Notes |
|---|---|---|
| Page | `#F7F9FC` | Near-white background |
| Tile | `#FFFFFF` | Plain surface for readable descriptions |
| Main text | `#172B4D` | Approximately 14.10:1 contrast on white |
| Description text | `#526173` | Approximately 6.33:1 contrast on white |
| Action / selection | `#0F5BA7` | Approximately 6.83:1 contrast on white |
| Selected-topic surface | `#EAF2FC` | Approximately 6.05:1 with the blue text above |
| Decorative divider | `#DCE4EE` | Do not use as the sole essential control boundary |

Use blue for actions, selection, and a restrained brand accent. Keep passive topics and tab labels neutral. Reserve yellow for consequential cautions; a large yellow block around ordinary documentation attracts attention away from choosing a report. Avoid assigning a different color to every report tab unless those colors encode a defined, consistent meaning.

At WCAG AA, ordinary text requires at least **4.5:1** contrast; qualifying large text requires **3:1**. Semibold styling alone does not make a small title qualify as large text. Preserve visible keyboard focus and do not rely on color alone to communicate selection.

## Responsive sizing and use of width

Design against the available iframe viewport, not physical monitor resolution. Power BI navigation and application chrome reduce the area available to the directory. Ordinary media queries inside an iframe respond to its viewport; container queries are useful for components within that page.

Starting values:

- 24 px outer padding on desktop; 16 px when narrow.
- 16 px grid gaps.
- Approximately 300–320 px minimum comfortable tile width.
- Three columns only when all three fit comfortably; otherwise two or one.
- 16–20 px tile padding and 6–8 px corner radius.
- A compact masthead, approximately 88–112 px where the content permits; allow natural growth when text wraps.
- Full available width, with an optional 1440–1600 px cap only on very wide views.

Align the header, filters, and collection to the same container. Use equal heights within each grid row and align the final action with flexible layout, such as `margin-top: auto`. Do not set rigid heights or clip essential descriptions to force uniformity. Keep normal reading order; avoid masonry or dense grid packing that visually reorders items.

The content must remain usable when enlarged. WCAG reflow requires ordinary vertically scrolling content to work at a width equivalent to **320 CSS px** without two-dimensional scrolling. Test zoom, long names, and increased text spacing rather than merely checking a default desktop screenshot.

## Categories, tags, and search

Make finance purpose the main organizing dimension. Candidate topics are P&L, Revenue, Inventory, Cost of goods sold, Scrap, Operating expenses, Close and controls, and Receivables. Only expose categories supported by the actual catalog.

Store a primary category plus secondary tags. A revenue reconciliation can match both Revenue and Close without creating duplicate entries. Start with one selected topic at a time. Search narrows that result set using titles, familiar abbreviations, summaries, tags, and tab names. Show a result count and a helpful empty state.

If a grouped chapter layout is used, place each report under its primary category and let secondary tags support search. Do not duplicate the same destination in every section. Keep delivery technology such as “linked tool” secondary to the finance task.

## Writing the entries

Write the sentence that answers: **What question should I use this report to answer?**

The following are fictional writing examples, not descriptions of internal reports.

| Vague wording | More useful fictional example |
|---|---|
| Spend report | Compare operating expenses with budget by department. |
| Revenue view | Review revenue trends by month and product category. |
| Inventory report | Review stock balances and aging by location. |
| Margin analysis | Compare gross margin trends by product group. |
| Close status | Track completion of month-end activities by team. |

“Reporting tool” and “Link to the dashboard” do not add enough information. Confirm ambiguous abbreviations and scope instead of inventing definitions. Explicitly distinguish similarly named destinations, such as a monthly trend report and a transaction-detail report.

Use a few representative tab labels, such as Overview, Trends, or Details, only when those names exist in the actual destination. The bundled fictional catalog uses illustrative tab labels. If real tab names are not known, set the required `keyTabs` array to `[]`; the renderer omits the tab-label line instead of publishing a placeholder.

## Corning identity and imagery

This section records publicly available brand research as an optional reference. The generic examples contain no official logo or internal brand asset.

An approved Corning 175 asset can sit at the upper right of the masthead while the hub title remains dominant. Use the supplied artwork at its original proportions and maintain the required clear space. Corning's public logo guidance prohibits recreating, stretching, adorning, or modifying the logo. Use the organization's approved internal asset and applicable brand rules; do not fabricate an anniversary mark.

A single optical-fiber photograph cropped into a small header area, or a subtle fiber-inspired line motif, can add identity. Keep the report collection on an opaque plain surface. Avoid detailed photography behind text, background video, and parallax for this directory.

Corning's public Image Bank permits use of its listed photographs with credit to Corning Incorporated. Public visibility of an image elsewhere on the anniversary campaign does not automatically establish the same reuse terms. Specify image dimensions to reserve its space and use a compressed asset. Make anniversary artwork replaceable after the campaign year.

## Acceptance checks

- Verify the actual Org app with navigation expanded and collapsed.
- Test narrow layout, long report names, enlarged text, and keyboard navigation.
- Confirm filters preserve readable titles and announce the result count.
- Confirm every destination and its new-tab behavior in the actual embedded environment.
- Ensure report and tab labels match their destinations.
- Keep directory response time separate from report load/query performance.
- Ask a few colleagues to locate specific reports without assistance; record where wording or grouping causes hesitation.

See [research-sources.md](research-sources.md) for primary sources and the distinction between documented behavior and proposed design choices.
