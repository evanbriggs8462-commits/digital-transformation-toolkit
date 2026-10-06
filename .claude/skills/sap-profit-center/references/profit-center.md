# Typical ECC classic EC-PCA

Checked against public SAP documentation: 2026-10-06. Confirm real landed objects and DDIC fields. SAP extraction structures can expose transformed fields and aggregate records; they do not prove raw physical keys.

| Table | Expected contents | Grain and cautions |
| --- | --- | --- |
| GLPCA | Classic profit center actual line items, when line-item storage is configured | PCA document/posting row with technical/source identity and ledger/year/record-type/version context; verify full DDIC key and CDC grain |
| GLPCP | Classic profit center plan line items, when configured | Plan detail; do not treat as additional actuals |
| GLPCT | Classic PCA totals, including actual/plan and allocation record types | Totals across configured accounting dimensions, normally a fiscal-year row with period amount columns; not a FI document/item table |

Typical PCA field names include RCLNT, RLDNR, RRCTY, RVERS, RYEAR, RBUKRS, RPRCTR, RACCT, and DRCRK, but actual availability/naming must be observed. GLPCA often exposes DOCNR/DOCLN and separate REFDOCNR/REFRYEAR/REFDOCLN. Source reference identity is not the PCA document identity. Never assert that a short list such as DOCNR/DOCLN is the complete raw primary key.

GLPCT totals may also distinguish controlling area, transaction currency, partner company/profit center, functional area, origin object, debit/credit, valuation, and other dimensions. Profile the relevant fields before dropping them. A grouping at profit-center/account/year alone can collapse materially different populations.

## Record type, ledger, version

Standard classic PCA record types:

| RRCTY | Meaning |
| --- | --- |
| 0 | Ordinary actual |
| 1 | Ordinary plan |
| 2 | Actual assessment/distribution within PCA |
| 3 | Plan assessment/distribution within PCA |

Restrict to 0 alone only if the report excludes actual assessments/distributions. For a full actual result, establish whether 0 and 2 are required. Keep plan 1/3 and plan version separate. Actual version 000 is a common SAP example, not an instruction to hard-code the user's source. Likewise, establish ledger from metadata/configuration instead of copying 8A or 0L by habit.

## Periods and balances

- GLPCA uses posting year/period and dates for line-item questions. GLPCT normally carries period amount families such as TSL01...TSL16, HSL01...HSL16, KSL01...KSL16, and carryforward fields such as TSLVT/HSLVT/KSLVT. Inspect actual columns; a warehouse may already normalize them into period rows.
- Unpivot the selected currency family with an explicit column-to-period map after schema confirmation. Preserve carryforward separately. Do not join each wide totals row to all periods and repeat annual totals.
- Follow the actual fiscal variant and special-period scope. Period 001 need not mean January, and special periods are not ordinary extra calendar months.
- No GLPCA line items are generated for classic PCA balance carryforward; GLPCA alone cannot reproduce every beginning balance. SAP's PCA extractor guidance obtains carryforward from GLPCT with period 0.
- Periodic balance-sheet transfers in GLPCA can represent balances rather than ordinary movements (SAP extractor guidance identifies ACTIV = PRC4). Repeated transfer can replace prior rows. Establish transaction selection and CDC/deletion behavior before accumulating them.
- For a balance-sheet closing balance, validate carryforward plus relevant movements or transferred balances using the SAP report's logic. For period P&L, do not add balance carryforward by default.

## Currencies and signs

Standard extraction mapping distinguishes TSL transaction currency, HSL company-code/local currency (type 10), and KSL configured PCA currency (type 20, 30, or 90 depending on customizing). Do not label every KSL value USD or group currency without configuration. Confirm currency keys, decimal scaling, and any valuation view before aggregation.

DRCRK is a debit/credit classification, but PCA values may already carry signs. Never multiply all PCA credit values by -1 using BSEG SHKZG intuition. Inspect actual amounts and the approved extractor/report mapping, then reconcile credit, debit, and net totals. Preserve the distinction between accounting signs and a presentation that shows revenue positively.

## Reference joins and coverage

GLPCA may contain transferred FI/CO/SD/MM data, PCA-only allocations, and periodic balance-sheet transfers. Detail storage is configurable, so absence of GLPCA rows does not prove absence of GLPCT totals. Verify reference type/system/client/year/company/document/item before tracing to FI. Do not force every PCA row into a BSEG item or infer a universal one-to-one mapping.

In ECC New G/L and S/4HANA, profit-center reporting can instead use ledger-aware New G/L or universal-journal detail. Old classic-PCA objects may still exist without being the authoritative reporting source. Confirm activated components, actual release, and the report's source.

## Official sources

- [SAP data in Profit Center Accounting](https://help.sap.com/docs/SAP_ERP/02349a7c7b5445de83ceac3e9db8d90b/524ad953292a424de10000000a174cb4.html) explains totals and optional actual/plan detail storage.
- [SAP displaying totals records](https://help.sap.com/docs/SAP_ERP/02349a7c7b5445de83ceac3e9db8d90b/034cd953292a424de10000000a174cb4.html?version=6.17.latest) lists record types and accounting dimensions.
- [SAP PCA transaction-data extraction](https://help.sap.com/docs/BI_CONTENT_747/8283ab99b2f540c18afbe5cbb34501e3/4216883a-ddd0-4265-9884-7bb6e07eb7c0.html?version=7.47.22) documents currency-family and record-type mappings.
- [SAP PCA line-item extraction](https://help.sap.com/saphelp_scm70/helpdata/ru/5d/ac7d8082a27b438b026495593821b1/content.htm) describes references, aggregation, carryforward, and periodic-transfer exclusions.
- [SAP periodic balance-sheet line-item extraction](https://help.sap.com/saphelp_scm70/helpdata/ru/42/e77a8e0e2c6346a0be901408be8781/content.htm) distinguishes transferred balances from movements and explains replacement/deletion behavior.
