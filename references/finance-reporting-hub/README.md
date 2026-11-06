# Finance Reporting Hub — research and implementation reference

A compact reference for building a fast, professional finance report directory served from n8n and embedded in a Power BI Org app. Research and decisions recorded **November 6, 2026**. This public reference uses six fictional catalog entries; it contains no internal report inventory or operational data.

## Start here on your work PC

1. Read [the design guide](docs/design-guide.md) for the agreed direction and exact typography, color, and spacing recommendations.
2. On GitHub, select branch **`docs/finance-reporting-hub`**, then use **Code → Download ZIP**. Extract it, open **`references/finance-reporting-hub`**, and open **`demo/index.html`** in a browser. No Node installation, API key, external font, or internet connection is needed for the local demo.
3. Open **`examples/design-directions.html`** to compare compact tiles, a report index, and finance chapters.
4. Follow [the n8n and Power BI how-to](docs/n8n-powerbi-howto.md) to integrate a reviewed version.

GitHub's file viewer displays HTML source; download the file or clone the repository to run the demo. No GitHub Pages site or production n8n workflow is enabled by this repository.

## Current decision

Use a **compact report catalog**: report title, brief useful summary, finance topics, up to three useful tab names, and an Open report action when a destination is configured. Use Segoe UI with system fallbacks, readable 16px descriptions, a light background, and one restrained blue accent.

- Remove repeated owner, refresh, and “link coming soon” fields.
- Avoid inline card expansion and automatic report rearrangement.
- Do not reserve a permanent details panel for short content.
- Keep extended definitions and guidance in each report's own landing page.
- Group by finance purpose; retain familiar report names and searchable abbreviations.
- Use approved brand artwork where appropriate. Public Corning 175/brand research is included as a reference; no official logo is bundled or recreated here.

The earlier single-panel idea is retained in [the archived example](examples/archive/details-panel.html), clearly marked **superseded**. It is useful history, not the recommended implementation.

## Contents

| Path | Purpose |
| --- | --- |
| [docs/design-guide.md](docs/design-guide.md) | Design decisions, typography, palette, responsive layout, branding, content examples |
| [docs/research-sources.md](docs/research-sources.md) | Official source links, findings, and evidence boundaries |
| [docs/n8n-powerbi-howto.md](docs/n8n-powerbi-howto.md) | Local editing, HTML serving, Org app integration, sandbox restrictions |
| [docs/implementation-checklist.md](docs/implementation-checklist.md) | Implementation sequence, review checklist, coding-agent handoff |
| [data/catalog.example.json](data/catalog.example.json) | Six fictional finance-report examples for adapting privately |
| [data/catalog.schema.json](data/catalog.schema.json) | Machine-readable catalog structure |
| [src/](src/) | HTML template, CSS design tokens, plain JavaScript renderer |
| [demo/index.html](demo/index.html) | Built, self-contained starter with search, topic filtering, and three layouts |
| [examples/design-directions.html](examples/design-directions.html) | Standalone export of the three visual directions discussed |
| [examples/archive/details-panel.html](examples/archive/details-panel.html) | Superseded earlier concept |

## Edit and rebuild

Use Node.js 18+ only if you want to rebuild from separate source files. There are no npm dependencies to install. Run these commands from **`references/finance-reporting-hub`**, not the toolkit's root folder. The toolkit's Power BI model launcher is unrelated to this standalone reference.

```sh
npm run build
npm run check
npm test
```

Edit `src/styles.css` for appearance, `src/app.js` for interaction, and `data/catalog.example.json` for the example catalog. `npm run build` updates `demo/index.html`.

For real work URLs, keep a local catalog separate from the example:

```powershell
Copy-Item data/catalog.example.json data/catalog.local.json
node scripts/build.mjs data/catalog.local.json dist/index.html
```

`data/catalog.local.json` and `dist/` are git-ignored. Fill in validated absolute HTTPS report links, review the summaries, and use the resulting `dist/index.html` in your approved hosting/n8n workflow. Do not put credentials in any catalog.

The build embeds the JSON in the HTML, so the deployed page needs no separate JSON request. Searches and filters run locally and never invoke an AI model or query financial data.

## What is verified and what is a draft

- Source research is linked and dated; exact design dimensions are recommendations, not universal standards.
- All six fictional report destinations are `null`. The starter displays a single preview notice and does not manufacture clickable links.
- Names, descriptions, topics, and tab labels are illustrative. They do not describe or verify any organization's actual reports. Confirm real content in a private local catalog before use.
- Screenshots, real financial data, tokens, and private destination URLs are not included.
- Automated checks validate the catalog, destination scheme, script-safe JSON serialization, and JavaScript syntax.
- Browser appearance, keyboard behavior, zoom, and real Power BI/n8n navigation must still be verified in the target environment. The starter is not represented as a production deployment.

## Maintenance

Store each report's content once in JSON and generate every layout from the same record. Keep IDs stable when titles change. Use `descriptionStatus` for editorial review; it is not an access control or a claim of certification. Recheck linked vendor documentation before deploying against a different product version.

Third-party fonts, logos, and photography retain their own licenses and usage rules. This reference does not bundle those assets or change the host repository's license terms.
