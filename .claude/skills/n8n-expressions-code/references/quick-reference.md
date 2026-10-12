# Official n8n expression and Code references

Checked: 2026-10-12.

- [Data structure](https://docs.n8n.io/build/work-with-data/understand-n8ns-data-structure.md): data moves as an array of items, normally with a `json` object and optionally binary data. Code can auto-wrap some output shapes, but explicit items are clearer for reusable examples.
- [Code node](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.code/): default Run Once for All Items versus Run Once for Each Item; JavaScript support; Cloud cannot import arbitrary npm libraries; self-hosted library import needs configuration. Use HTTP Request and appropriate file nodes for those operations.
- [Node input reference](https://docs.n8n.io/build/work-with-data/transform-data/expression-reference/nodeinputdata.md): `$input.all()`, `.first()`, `.item`, and `.last()`.
- [Node output reference](https://docs.n8n.io/build/work-with-data/transform-data/expression-reference/nodeoutputdata.md): `$('Node').item`, `.first()`, `.all()`, `.isExecuted`, and `.itemMatching(index)` have different meanings. All/first may take branch and run indexes; choose those explicitly in loops when needed.
- [Preserving linking in the Code node](https://docs.n8n.io/build/work-with-data/reference-data/link-data-items/preserving-linking-in-the-code-node.md): newly returned items can need `pairedItem` to preserve provenance, especially with multiple inputs.
- [Item linking for node creators](https://docs.n8n.io/build/work-with-data/reference-data/link-data-items/item-linking-for-node-creators.md): linkage objects use `item` and optional `input`; consult for more complex mappings.
- [Work with dates and times](https://docs.n8n.io/build/work-with-data/handle-special-data-types/work-with-dates-and-times.md): dates pass as strings; Luxon is recommended and honors n8n timezone context; `$now` and `$today` are Luxon values in JavaScript. Parse known formats instead of assuming a timestamp type.
- [Expressions](https://docs.n8n.io/code/expressions/): parameter expressions and the expressions editor are distinct from raw Code-node JavaScript.

Snippets in this skill are small original examples, not a universal schema for every trigger. Inspect the real trigger data and reject missing required fields before side effects. JavaScript null handling and numeric checks are programming guidance.
