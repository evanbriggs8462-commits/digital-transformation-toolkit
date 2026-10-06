# Typical ECC SD and MM families

Checked against public SAP documentation: 2026-10-06. Grains are expected business identities inside one source/client, not complete certified physical keys. Verify DDIC, actual landed columns, CDC current-state rules, and the source release.

## Sales and distribution

| Table | Expected contents | Typical business grain |
| --- | --- | --- |
| VBAK / VBAP | Sales-document header / item | VBELN / VBELN, POSNR |
| VBEP | Sales schedule lines: dates and quantities | VBELN, POSNR, ETENR |
| VBPA | Partners by document/item, role, and potentially partner counter | Finer than document alone; verify full partner identity |
| VBKD | Business data at header/default or item level | Document/item scope; header defaults commonly use POSNR = 000000 |
| VBFA | Preceding/subsequent document-flow relationships | Document/item relationship plus categories/technical dimensions |
| LIKP / LIPS | Delivery header / item | VBELN / VBELN, POSNR |
| VBRK / VBRP | Billing-document header / item | VBELN / VBELN, POSNR |
| VBUK / VBUP | ECC header / item status | Document / document,item; confirm release-specific availability |
| KONV | ECC document pricing conditions | Pricing document/item/step/counter; verify full key |

VBAK can contain different sales document categories, not only ordinary customer orders. Choose document type/category explicitly. Likewise VBRK/VBRP can contain credit memos, cancellations, and other billing types.

One order item may have several schedule lines, deliveries, billing items, partners, and conditions. Joining these children directly creates products of their cardinalities. Reduce each child to the approved target grain or preserve event-level links separately. Do not sum header NETWR once for every joined item.

VBPA requires the selected partner role, item/header scope, and fallback logic; sold-to, ship-to, bill-to, and payer differ. VBKD also requires deliberate item-versus-header default logic. Never resolve a many-row partner/business-data join with arbitrary MAX or DISTINCT.

VBFA traces document flow using preceding and subsequent documents/items and document categories. Delivery and billing item references may help, but item splits, partial documents, and order-related versus delivery-related billing prevent universal number equality. Confirm every relevant mapping. FI reference keys need their own origin/type/year/company handling.

Backlog requires an approved definition: ordered versus confirmed versus delivered/open quantity, rejection/completion rules, blocks, requested/confirmed dates, and valuation basis. A simple order quantity minus billing quantity is not a universal backlog rule. Current schedule/status data cannot reconstruct every historical backlog without snapshots/change history.

Goods issue is a logistics event; delivery creation is not proof of shipment. Billing is not automatically recognized revenue. Select actual goods-issue/posting dates and financial recognition logic appropriate to the requested report. Preserve cancellation/return behavior.

## Purchasing, incoming invoices, inventory movements

| Table | Expected contents | Typical business grain |
| --- | --- | --- |
| EKKO / EKPO | Purchasing-document header / item | EBELN / EBELN, EBELP |
| EKET | Purchasing schedule lines | EBELN, EBELP, ETENR |
| EKBE | Purchasing-document history: receipts, invoice events, reversals, and related categories | Multiple history events per PO item; verify full event identity, including category/year/document/item and account-assignment scope |
| EKKN | Purchasing account assignments | PO item plus assignment counter; can be multiple rows |
| RBKP / RSEG | Logistics incoming-invoice header / items | BELNR, GJAHR / BELNR, GJAHR, BUZEI |
| MKPF / MSEG | ECC material-document header / items | MBLNR, MJAHR / MBLNR, MJAHR, ZEILE |

EKKO includes purchasing categories beyond ordinary purchase orders. Scope categories/document types, deletion/completion flags, and return items according to the report. Purchase orders are commitments, distinct from received inventory, invoiced amount, and cash paid.

EKBE is event history, not one record per PO item. Separate goods-receipt and invoice-receipt event categories before aggregation. Confirm category and debit/credit semantics, reversals/returns, units, currency, and account assignment. EKET and EKKN are independent children; joining both to EKBE without controlling grain can multiply amounts.

MKPF/MSEG keys include material-document year. MSEG movement type BWART, quantity/unit, SHKZG, stock category, and reversal/reference fields must be verified. Do not count every positive quantity as a receipt or discard every reversed original without considering its reversal and dates. Identify both legs of transfers and distinguish organizational movement from net external inventory change.

Preserve base, entry, sales, order, and pricing units separately. Use verified material conversion factors only where needed. Verify price-unit denominators and currency decimals; do not aggregate unrelated units/currencies or apply conversion twice.

## ECC versus S/4HANA

In S/4HANA material-document persistence moves to MATDOC, with compatibility access for MKPF/MSEG and affected stock structures. Physical replication of old names may not equal redirected application reads. Pricing and status storage also change by release (for example PRCD_ELEMENTS versus classic KONV). Determine the actual release and extraction contract before choosing objects. Do not query presumed MATDOC/ACDOCA merely because the warehouse uses Databricks.

## Official sources

- [SAP sales orders and shipments replication](https://help.sap.com/docs/CARAB/23629a03333840199de513280b74f738/7c6354e2520741c08fbe87b405211cab.html?version=6.0.2) identifies the sales-document family.
- [SAP source-table names and meanings](https://help.sap.com/docs/signavio-process-insights/business-content-reference/source-tables-for-performance-indicator-data-in-on-premise-source-systems) lists standard table families. Confirm actual release-specific definitions.
- [SAP purchasing replication tables](https://help.sap.com/docs/CARAB/55c14d85842b4275afda2af381a7ab71/51bc645550663b01e10000000a44538d.html?version=5.0) identifies header, item, schedule, and history tables.
- [SAP purchasing item data](https://help.sap.com/docs/BI_CONTENT_757/45e4eda3753c458ead20c81f77c55921/e2487053bbe77c1ee10000000a174cb4.html) separates PO item, schedule, and history views; extractor columns are not raw-column guarantees.
- [SAP material-document quantity/sign interpretation](https://help.sap.com/docs/sap-responsible-design-and-production/user-guide-sap-rdp/material-documents-rdp) distinguishes positive raw quantity from signed movement and reversal context.
- [SAP S/4HANA material-document archiving](https://help.sap.com/docs/SAP_S4HANA_ON-PREMISE/8308e6d301d54584a33cd04a9861bc52/75bcb6531de6b64ce10000000a174cb4.html) describes MATDOC and compatibility access.
