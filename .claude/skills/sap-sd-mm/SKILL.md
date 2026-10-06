---
name: sap-sd-mm
description: Reason about SAP ECC sales, delivery, billing, purchasing, invoice, and material-movement table families when querying landed data. Use for VBAK/VBAP/VBEP/VBFA, LIKP/LIPS, VBRK/VBRP, EKKO/EKPO/EKET/EKBE, RBKP/RSEG, MKPF/MSEG, backlog, shipments, and purchasing history.
---

# SAP SD and MM transactions

Read [sd-mm.md](references/sd-mm.md) only for the requested sales or procurement/movement family. Use typical ECC meanings to form hypotheses, then prove them against the actual schema and reporting logic.

1. Use `databricks-query` to identify and describe the landed source, client, extraction mode, source release, and required columns.
2. Select the business event: order, schedule line, delivery, goods movement, billing, purchasing, or incoming invoice. Do not equate shipment, billing, and recognized revenue.
3. State the fact grain. Include source/client and the full document/item/year or schedule/event identity appropriate to the family.
4. Profile header/item joins and every one-to-many child separately. Aggregate child facts to the requested grain before combining them, unless event-level detail is explicitly required.
5. Confirm document categories, cancellation/reversal/return/deletion/status rules, units, currency, and effective refresh before computing balances or backlog.
6. Trace document flow with observed reference fields/categories and verified item mappings. Do not equate identical-looking document numbers across SD, MM, and FI.
7. Reconcile quantities and monetary amounts independently. Show fanout and unmatched-reference counts; preserve unresolved business-rule differences.

Return the selected event, verified grain, status scope, units/currencies, and control evidence. For backlog or inventory at a past date, establish snapshot or movement/history coverage first; a current-state table does not by itself establish historical state.
