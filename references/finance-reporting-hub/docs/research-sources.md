# Research sources and evidence

Reviewed **November 6, 2026**. These are primary documentation and official brand sources consulted for the design. Links may change as the products evolve. This document summarizes findings rather than reproducing the source material.

## Typography and font delivery

1. **[Microsoft Fluent typography](https://fluent2.microsoft.design/typography)** — Segoe UI is the web type-ramp default, with platform-native font behavior. The web ramp includes 14/20 px body, 16/22 px subtitle, and 28/36 px title styles. Our 18/24 report titles and 16/24 descriptions are contextual design choices, not mandated Fluent tokens.
2. **[Fluent Text guidance](https://fluent2.microsoft.design/components/web/react/core/text/usage)** — Supports consistent typeface and alignment choices. The recommendation to align the hub heading with its content follows this broader system approach.
3. **[Inter, from its creator](https://rsms.me/inter/)** — Documents the font's text/display optical designs, small-text features, variable weights, and open-source licensing. A suitable alternative; no claim that it is universally superior to Segoe UI.
4. **[web.dev: font best practices](https://web.dev/articles/font-best-practices)** — Downloaded fonts can delay text and produce layout shifts when their dimensions differ from a fallback. Supports considering an installed system stack for this small embedded directory.
5. **[Microsoft font FAQ](https://learn.microsoft.com/en-us/typography/fonts/font-faq)** — Distinguishes referencing installed fonts from distributing font files. Do not copy Windows font files to web hosting merely because a CSS font family is permitted.

## Layout and content patterns

6. **[USWDS Card](https://designsystem.digital.gov/components/card/)** — Cards summarize related content and act as entry points to fuller information. Guidance favors actionable entries, simple styling, and removal of repeated content. Supports dropping repeated owner/refresh/type labels and keeping report documentation at its destination.
7. **[Fluent Card](https://fluent2.microsoft.design/components/web/react/core/card/usage/)** — Documents card layout and action patterns. Supports restrained tiles and a clear distinction between one whole-surface action and multiple explicit actions.
8. **[Fluent List](https://fluent2.microsoft.design/components/web/react/core/list/usage)** — Lists support scanning and accessing independent repeated items. A report directory does not automatically require a table or data grid.
9. **[Fluent Layout](https://fluent2.microsoft.design/layout)** — Consistent spacing, alignment, and responsive reflow establish relationships. Our exact padding, gap, radius, and maximum-width proposals are project choices.
10. **[Fluent Drawer](https://fluent2.microsoft.design/components/web/react/core/drawer/usage)** — Supports side-by-side supplemental information when useful. This informed an earlier details-panel concept. That concept was superseded when the scope became brief summaries and key tabs already visible in each entry.
11. **[MDN: CSS container queries](https://developer.mozilla.org/en-US/docs/Web/CSS/Guides/Containment/Container_queries)** — Components can adapt to their container size. An iframe's own viewport is also relevant to its internal media queries. Do not base embedded layout solely on the monitor resolution.

## Accessibility constraints

12. **[WCAG 2.2: contrast minimum](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html)** — Ordinary text requires at least 4.5:1 contrast at AA; qualifying large text requires 3:1. Ratios in the design guide were calculated for the proposed colors, not sampled from photographs.
13. **[WCAG 2.2: resize text](https://www.w3.org/WAI/WCAG22/Understanding/resize-text.html)** — Text must be resizable to 200% without lost content or functionality, subject to the criterion's scope.
14. **[WCAG 2.2: reflow](https://www.w3.org/WAI/WCAG22/Understanding/reflow.html)** — Ordinary vertical content should retain information and functionality at 320 CSS px without requiring two-dimensional scrolling.
15. **[WCAG 2.2: text spacing](https://www.w3.org/WAI/WCAG22/Understanding/text-spacing.html)** — Content must tolerate specified user spacing overrides. This does not prescribe one default line height for every interface.
16. **[WCAG 2.2: target size minimum](https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html)** — The AA criterion uses 24×24 CSS px with exceptions. Our preference for approximately 40–44 px practical filter/button heights is a usability recommendation, not a claim that AA always mandates 44 px.

## Org app and n8n behavior

17. **[Microsoft: get started with Org apps](https://learn.microsoft.com/en-us/power-bi/explore-reports/org-app-items)** — Documents overview pages, navigation ordering, audiences, and app-page sharing. The first navigation item is the landing experience. Native overview content can reflect audience visibility; a manually authored HTML directory does not automatically inherit that filtering.
18. **[Microsoft: organizing content with Org apps](https://learn.microsoft.com/en-us/fabric/iq/plan/resources/how-to-create-org-apps)** — Documents Add → Link and opening a URL within the app or in a new browser tab, plus Share → Link to this app page.
19. **[n8n: Respond to Webhook](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.respondtowebhook/)** — Text responses send HTML by default. Since n8n 1.103.0, HTML webhook responses are wrapped in a sandboxed iframe; top-level window/local-storage assumptions fail and absolute URLs are needed. The response node runs once using its first incoming item.
20. **[n8n: Webhook](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.webhook/)** — Reference for configuring the trigger and response mode. Test against the deployment's actual version and production URL.
21. **[MDN: same-origin policy](https://developer.mozilla.org/en-US/docs/Web/Security/Same-origin_policy)** — Explains why an embedded external page cannot freely access or restyle the parent application's interface. A Microsoft external-content notice belongs to the host interface, separately from the HTML directory's own guidance boxes.
22. **[MDN: CSP frame-ancestors](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/frame-ancestors)** — Hosting policies can permit or block embedding. A page being reachable at a URL does not by itself prove that it will work inside an Org app.

## Corning identity and imagery

23. **[175 Years of Corning](https://www.corning.com/richmedia/corning-175)** — Official anniversary campaign and visual reference. Use existing approved artwork rather than inventing a logo from the campaign theme.
24. **[Corning logo usage](https://www.corning.com/worldwide/en/about-us/news-events/resources/corning-incorporated-logo-usage.html)** — Requires supplied artwork, prohibits alterations/typesetting, lists permitted logo color formats, and defines clear space. PMS 301 is specified for blue logo use; this document does not invent an official digital hex conversion.
25. **[Corning Image Bank](https://www.corning.com/worldwide/en/about-us/news-events/resources/image-bank.html)** — Its listed photographs are available for public use with credit to Corning Incorporated. This is not a blanket license for every image on other Corning pages.
26. **[Optical Communications image category](https://www.corning.com/worldwide/en/about-us/news-events/resources/image-bank/optical-communications.html)** — Relevant starting point for a restrained header photograph.

## Evidence boundaries

Additional implementation comparisons: [Power BI buttons](https://learn.microsoft.com/en-us/power-bi/create-reports/desktop-buttons) documents native button actions; [Python visuals](https://learn.microsoft.com/en-gb/power-bi/connect-data/desktop-python-visuals) documents that the rendered image is not interactive; [Power Apps visual](https://learn.microsoft.com/en-us/power-apps/maker/canvas-apps/powerapps-custom-visual) documents canvas-app integration and separate app sharing; [Power Automate visual](https://learn.microsoft.com/en-us/power-bi/create-reports/power-bi-automate-visual) documents a button-triggered flow. Their suitability for this directory is a design recommendation.

- The six example reports are fictional. Their names, descriptions, topics, and tab labels do not establish an organization's actual report inventory, scope, destinations, or authorization behavior.
- No source establishes a universal best font, mandatory card shape, or a guarantee that the proposed redesign is faster than the existing app.
- Compact tiles, the proposed palette, the type scale, local filtering, and the exact spacing values are recommendations to validate in the real environment.
- Search and category filtering are presentation features, not access control. Destination permissions continue to matter.
- Directory performance and report query/render performance are separate measurements.
