# Typical ECC FI and open-item semantics

Checked against public SAP documentation: 2026-10-06. Confirm base-table versus extractor/view identity and actual columns before SQL. Expected identity is not an assertion of a landed table's physical primary key.

| Family | Expected contents | Identity inside one source/client |
| --- | --- | --- |
| BKPF | FI accounting-document header; document dates, type, status, currency, reversal/reference information | BUKRS, BELNR, GJAHR |
| BSEG | FI accounting-document entry-view items; account/customer/vendor, amounts, debit/credit, clearing and assignment fields | BUKRS, BELNR, GJAHR, BUZEI |
| BSID / BSAD | Customer items: currently open / currently cleared | FI item identity; customer/special-G/L fields are also important |
| BSIK / BSAK | Vendor items: currently open / currently cleared | FI item identity; vendor/special-G/L fields are also important |
| BSIS / BSAS | G/L line-item indexes: open / cleared populations | FI item identity; confirm account line-item/open-item configuration and coverage |

Include actual source-system and client columns where present. A raw ECC BSEG query normally needs BKPF for header dates; a replicated view may already carry those dates. Confirm rather than assuming BUDAT is in every BSEG object. Extractor documentation may display denormalized header fields or derived columns under a BSEG origin.

## Dates and clearing

- BUDAT is posting date; BLDAT is document date; CPUDT is entry date. They answer different questions. Use fiscal-year/period configuration for fiscal comparisons rather than deriving GJAHR from the calendar year.
- AUGDT is clearing date; AUGBL is clearing document number. Normalize blank, `00000000`, null, and actual typed-date representations before comparing dates. Preserve invalid values as exceptions instead of silently treating them as open.
- For an inclusive date D, set `cutoff_exclusive = D + 1 day`. The usual ECC historical-open predicate is `BUDAT < cutoff_exclusive AND (AUGDT IS NULL OR AUGDT >= cutoff_exclusive)`, after valid initial dates have been normalized to null.
- This includes an item cleared after D; an item cleared on D is closed at that day's end. Document the boundary explicitly.
- Apply that predicate to a consistent current union of open and cleared indexes, or an independently validated complete item source. `BSID` or `BSIK` alone cannot retrieve every item that was open in the past.
- Current/cleared overlap can result from inconsistent refreshes or CDC history. Resolve using the authoritative current-state/load contract; never discard financial conflicts with arbitrary DISTINCT or ROW_NUMBER ordering.
- Do not restrict historical open items to recent GJAHR values merely to speed up the query: old-year items can remain open. If retention forces a restriction, report incomplete coverage and quantify it where possible.
- Most recent clearing fields do not necessarily recover prior clearing/reset history. Backdated postings, reversals, clearing resets, archives, and inconsistent extracts can make a latest-data reconstruction differ from the report actually observed on D. Use dated snapshots/change history when that distinction matters.

## Amounts, currencies, and signs

- WRBTR is normally document-currency amount; DMBTR is company-code local-currency amount. Verify document currency (normally BKPF-WAERS or the chosen index/view) and local currency (commonly T001-WAERS), plus additional-currency fields/configuration if used.
- Standard SHKZG uses `S` debit and `H` credit. For raw unsigned conventional amounts, an accounting debit-positive signed amount uses `S => amount`, `H => -amount`. Confirm negative-posting XNEGP semantics and existing extract transforms before applying a rule; do not double-sign.
- Presenting AP as positive liability or revenue as positive is a separate report convention. Keep that decision explicit and reconcile to an approved control.
- Confirm whether raw SAP currency decimals were already externalized. TCURX affects currency precision; do not scale a normalized Databricks amount again. FX also needs rate type/date/direction, TCURR/TCURF factors, and approved conversion semantics.
- UMSKZ special-G/L items, noted/statistical items, account type, reversals, and posting status require an explicit report scope. Ordinary customer account type is `D`, vendor is `K`; verify extraction mappings rather than copying a tutorial constant.

## Partners and source version

VBUND is a trading-partner company identifier where available, not automatically a BUKRS. Customer/vendor, document origin, and partner fields can be blank or differently populated. Use evidenced configuration to map them; do not infer a reciprocal entity from account numbers or free text alone.

ECC entry view, ECC New G/L (for example FAGLFLEXA), classic PCA, and S/4HANA universal journal are distinct representations. In S/4HANA BSEG still exists for relevant entry-view postings; ACDOCA has ledger-aware detail and can differ in coverage/grain. Some old index/totals names are compatibility views. Do not assume BSEG was universally replaced or join BSEG BUZEI to ACDOCA DOCLN without a verified mapping.

## Official sources

- [SAP Customer Line Items](https://help.sap.com/docs/SAP_ERP/44d76b07aa8e45899a2e83923c3d11ba/3de289f60f954bffa97273355f857fe6.html?version=6.06.latest) describes BSID/BSAD.
- [SAP Vendor Line Items](https://help.sap.com/docs/SAP_ERP/44d76b07aa8e45899a2e83923c3d11ba/2fe299a861d14dd4ad13380d271749e2.html?version=6.06.latest) describes BSIK/BSAK.
- [SAP KBA 2457349](https://userapps.support.sap.com/sap/support/knowledge/en/2457349) confirms cleared items can appear in an open-at-key-date selection; its full content may require support access.
- [SAP General Ledger Accounting line-item extraction](https://help.sap.com/docs/SAP_ERP/29e1b7170a344430b27643ca050d4247/883c36861f874739a916df63ab6d7ca0.html?version=6.18.latest) distinguishes entry versus ledger views; its extract structure is not a raw-column guarantee.
- [SAP debit/credit API field semantics](https://help.sap.com/docs/SAP_S4HANA_ON-PREMISE/91af7f8d3acd47da90d33aaacfcd0d59/65002458360e1f60e10000000a44147b.html) documents S/H meanings.
- [SAP currency conversion](https://help.sap.com/docs/signavio-process-intelligence/accelerators/currency-conversion) describes currency precision and conversion factors.
- [SAP S/4HANA 2025 simplification list](https://help.sap.com/doc/0df2ffddebab40cf9338488b2f18dc41/2025.latest/en-US/SIMPL_OP2025.pdf) documents release-specific persistence changes; verify the actual installed release.
