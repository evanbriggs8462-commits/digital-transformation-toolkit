---
name: sap-fi-open-items
description: Reason about SAP ECC accounting documents and current or key-date open items using BKPF, BSEG, BSID, BSAD, BSIK, BSAK, BSIS, and BSAS. Use for FI joins, AR/AP, clearing dates, intercompany balances, currency/sign handling, or historical month-end reconstruction.
---

# SAP FI and open items

Read [fi-open-items.md](references/fi-open-items.md) for the selected document or open-item family. Treat it as typical ECC semantics, not proof of landed columns or completeness.

1. Treat `bsgeg` as a likely BSEG typo; confirm the actual table rather than querying an invented name.
2. Use `databricks-query` to verify object names, columns, types, source/client scope, refresh consistency, retention, and CDC state before generating SQL.
3. Select one representation for the financial fact. BKPF is a header, BSEG is entry-view detail, and the BS* indexes overlap those items. Do not stack all representations as additional transactions.
4. Preserve the complete FI document/item identity across source system, client, company code, fiscal year, document, and item. Do not join on BELNR alone.
5. Confirm date meaning, amount/currency pairing, and whether the extract already signs/scales amounts. Use the report's approved sign presentation; do not convert every credit to positive revenue automatically.
6. For historical open items, state `as_of_date` and `cutoff_exclusive = as_of_date + 1 day`. Consider both currently open and currently cleared populations, with normalized clearing dates and sufficient retained history.
7. Check duplicate keys, current/cleared overlap, join fanout, and control totals. Distinguish a latest-data key-date reconstruction from a historical snapshot.

Return the family, cutoff, retained-history limit, currencies, sign convention, special-G/L scope, and reconciliation evidence. Keep missing trading partners unresolved unless an evidenced mapping can assign them.
