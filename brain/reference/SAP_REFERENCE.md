---
id: brain.reference.sap
status: generic-reference
scope: cross-implementation
audience: [ai-agent, developer, analyst]
last_reviewed: 2026-08-20
---

# SAP Reference for Artifact Discovery and Reasoning

This document supplies candidate-generation priors for agents searching scripts, CSVs, Databricks schemas, Power BI metadata, and session history. SAP is highly configurable. Validate all mappings against the relevant ECC/S/4 environment and landed-data design.

## 1. Naming and key conventions

Common patterns:

- Header and item tables frequently form a one-to-many hierarchy.
- `MANDT` is the client in many classic tables.
- Keys that appear numeric are commonly character or NUMC identifiers and must preserve leading zeroes.
- Header identifiers often end in `...NR`; item positions often end in `...POS`, `...EI`, or similar.
- Custom objects commonly begin with `Z` or `Y`, but their semantics are implementation-specific.
- Change documents often use `CDHDR` and `CDPOS`.
- Text tables often end in `T` or include a language key such as `SPRAS`, but do not infer joins from naming alone.

## 2. FI accounting hierarchy

```text
BKPF — accounting document header
  └── BSEG — accounting line items
       └── BSET — tax detail where applicable
```

Typical classic document key:

```text
MANDT + BUKRS + BELNR + GJAHR
```

Line-item key adds:

```text
BUZEI
```

Important fields often encountered:

- `BUKRS` company code
- `BELNR` accounting document
- `GJAHR` fiscal year
- `BUZEI` line item
- `BUDAT` posting date
- `BLDAT` document date
- `AUGDT` clearing date
- `AUGBL` clearing document
- `HKONT` G/L account
- `KUNNR` customer
- `LIFNR` vendor
- `WRBTR` amount in document currency
- `DMBTR` amount in local currency
- `WAERS` document currency
- `VBUND` trading partner
- `ZUONR` assignment
- `XBLNR` reference
- `SGTXT` line-item text

Open/cleared item families in ECC commonly include:

```text
Customer: BSID (open), BSAD (cleared)
Vendor:   BSIK (open), BSAK (cleared)
G/L:      BSIS (open), BSAS (cleared)
```

S/4 introduces the Universal Journal:

```text
ACDOCA — primary universal-journal line-item surface
BKPF   — accounting header remains relevant
BSEG   — remains relevant for source/open-item and selected compatibility purposes
```

Do not assume a direct ECC query remains the preferred S/4 semantic source. Prefer the environment's governed views or released CDS semantics where available.

## 3. SD order-to-cash hierarchy

```text
VBAK — sales document header
  └── VBAP — sales document items
       └── VBEP — schedule lines

VBKD — business data
VBPA — partner functions
VBFA — document flow

LIKP — delivery header
  └── LIPS — delivery items

VBRK — billing header
  └── VBRP — billing items
```

Common keys:

```text
VBELN — sales/delivery/billing document depending on table
POSNR — item position
ETENR — schedule-line number
```

Frequent analytical fields:

- document type and category;
- sales organization, distribution channel, division;
- sold-to, ship-to, payer, bill-to;
- material, plant, storage location;
- billed quantity and sales unit;
- net value and document currency;
- pricing document number;
- reference/predecessor document;
- profit center and controlling assignment.

Pricing persistence differs by generation:

```text
ECC: KONV is commonly encountered for pricing conditions.
S/4: PRCD_ELEMENTS is the primary persistence surface.
```

Pricing subtotals such as `KZWI1` through `KZWI6` are configuration-dependent. Never assign a universal business meaning such as revenue, freight, or margin without validating the pricing procedure and condition configuration.

## 4. MM procure-to-pay hierarchy

```text
EBAN — purchase requisitions

EKKO — purchase-order header
  └── EKPO — purchase-order items
       ├── EKET — schedule lines
       ├── EKKN — account assignments
       └── EKBE — purchasing history

RBKP — invoice header
  └── RSEG — invoice items
```

Common keys:

```text
EBELN — purchasing document
EBELP — purchasing item
ETENR — schedule line where relevant
```

Material documents:

```text
ECC: MKPF header + MSEG items
S/4: MATDOC and governed/released semantic surfaces
```

Important business relationships include:

- purchase order → goods receipt;
- purchase order → invoice receipt;
- GR/IR timing;
- account assignment;
- material valuation and standard price;
- third-party sales links between SD and MM.

## 5. Material master and units

```text
MARA — general material
MARC — material by plant
MARD — storage-location data
MBEW — valuation
MAKT — descriptions
MARM — alternate units and conversion
```

Related unit/currency configuration may include `T006`-family unit semantics and `TCUR*`-family exchange-rate/currency behavior.

Important material concepts:

- material type;
- base unit of measure;
- alternate UoM numerator/denominator;
- valuation area;
- price-control indicator;
- standard price or moving-average price;
- plant-specific procurement/planning settings.

## 6. DDIC-to-lake type policy

When authoritative DDIC metadata is unavailable, prefer all-string Bronze ingestion and explicit Silver conversion.

| SAP type | Bronze | Curated | Rule |
|---|---|---|---|
| CHAR | STRING | STRING | Preserve semantic text and padding where relevant. |
| NUMC | STRING | STRING | Never infer integer; preserve leading zeroes. |
| CLNT | STRING | STRING | Client identifier. |
| CUKY | STRING | STRING | Currency key. |
| UNIT | STRING | STRING | Unit key. |
| DATS | STRING | DATE | Normalize blanks and `00000000` to null first. |
| TIMS | STRING | TIME/timestamp derivative | Preserve raw `HHMMSS`. |
| CURR | DECIMAL | DECIMAL(p,s) | Retain currency-reference field. |
| QUAN | DECIMAL | DECIMAL(p,s) | Retain unit-reference field. |
| DEC | DECIMAL | DECIMAL(p,s) | Avoid floating-point loss. |
| FLTP | DOUBLE | DOUBLE | Use only when source is truly floating point. |
| INT1/2/4 | INTEGER | INTEGER | Genuine integer semantics. |

Hard rules:

```text
NUMC is not a number for analytical ingestion.
CURR without its currency key is incomplete.
QUAN without its unit key is incomplete.
```

Currency display may require decimal-place configuration such as `TCURX`. Unit conversion may require `MARM` and unit configuration. Preserve raw values and reference keys so adjustments remain reproducible.

## 7. CSV and schema handling

For uncertain SAP CSV extracts:

1. Read the header and sample rows as strings.
2. Preserve original column names and raw values.
3. Record delimiter, encoding, quote behavior, and row count.
4. Treat blank initial rows and malformed first records as possible export artifacts.
5. Use a fallback sampler across the file rather than assuming the first row is representative.
6. Validate leading zeroes, decimal separators, dates, and amount/unit pairs.
7. Materialize curated typed columns separately from raw columns.
8. Record the transformation schema and rejected-row count.

Large files should use size-aware inspection: metadata and sampled scans first, full scans only when required for reconciliation or quality assurance.

## 8. Month-end open-item reconstruction

A generic key-date pattern:

```text
BUDAT < cutoff_exclusive
AND (
  item is uncleared
  OR AUGDT >= cutoff_exclusive
)
```

Additional safeguards:

- normalize blank/null/`00000000` clearing dates;
- do not remove prior-year items solely because fiscal year is old;
- distinguish reporting cutoff from source-state/as-of timestamp;
- document retained-history limitations explicitly;
- deduplicate open and cleared source unions at the accounting-item key.

## 9. Intercompany evidence graph

Do not reduce intercompany classification to one field.

Candidate evidence hierarchy:

```text
VBUND when populated and trustworthy
→ customer/vendor master partner mapping
→ company-code/legal-entity mapping
→ SD billing/document flow
→ MM purchasing/invoice flow
→ FI references and clearing relationships
→ assignment/reference/text evidence
→ amount/currency/date consistency
→ reciprocal-entity evidence
```

Important complications:

- missing `VBUND` does not prove external activity;
- split billing can create one-to-many relationships;
- multiple profit centers can appear in one cross-company process;
- reciprocal postings may differ in document number, posting date, or currency;
- ECC and S/4 persistence and derivation can differ;
- partner assignment can be inferred at customer/vendor or process level when line-level partner is absent.

Reconciliation should answer three distinct questions:

1. Is the item intercompany, and who is the partner entity?
2. Which reciprocal posting or transaction group does it belong to?
3. Does the group financially reconcile within the stated tolerance and FX policy?

## 10. Sales gross margin and pricing reasoning

Treat the following as investigation patterns rather than universal facts:

- a custom condition such as `ZBO3` may represent only one pricing component;
- a configured pricing subtotal may include freight or other adders not present in that condition;
- a Power BI measure such as a net-value-invoice metric may embody adjustments not obvious from raw billing fields;
- billed quantity and cost may require explicit UoM normalization;
- margin logic must specify transaction currency, local currency, reporting currency, and FX date/rate type.

A robust reconstruction packet should identify:

- business metric definition;
- billing-item grain;
- pricing procedure and relevant conditions/subtotals;
- quantity and UoM conversion;
- revenue and cost components;
- freight and adjustment treatment;
- FX policy;
- exclusions and document types;
- legacy spool and Power BI control totals.

## 11. Third-party sales and cost timing

In third-party processes, billing-side cost may not fully represent later procurement, goods receipt, invoice receipt, material valuation, or standard-cost effects. For affected material/process classes:

- trace SD order/billing to purchasing documents;
- inspect PO history and GR/IR timing;
- inspect valuation and price-control behavior;
- distinguish estimated, billed, received, invoiced, and revalued cost;
- document whether material types or price-control methods require a separate price-update process.

Do not assert that a missing direct receipt link means cost is unavailable. It means the evidence path must broaden across SD, MM, FI, and valuation.

## 12. FX reasoning

Never apply one generic FX rule to all finance metrics. Capture:

- transaction/document currency;
- local/company currency;
- group/reporting currency;
- rate type;
- rate date;
- balance-sheet versus income-statement policy;
- actual versus budget/forecast policy;
- whether translation occurs at transaction, period-average, or closing rate;
- rounding and currency decimal conventions.

A reconciliation must state which policy each side used before treating an FX difference as a data-quality defect.
