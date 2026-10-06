---
name: sap-profit-center
description: Reason about classic SAP ECC profit center accounting with GLPCA, GLPCT, and GLPCP. Use for KE5Z-style line items, actual versus plan totals, PCA allocations, partner profit centers, period amounts, carryforward, currencies, and reconciliation to FI or New G/L.
---

# SAP classic profit center accounting

Read [profit-center.md](references/profit-center.md) for the selected line-item or totals question. Use this for classic EC-PCA; first confirm whether the source actually uses classic PCA, New G/L, or S/4HANA universal journal.

1. Use `databricks-query` to confirm available tables, columns, release, client/source scope, extraction mode, and retained history.
2. Choose GLPCA detail or GLPCT totals deliberately. Do not union both as incremental transactions or join totals to detail before accounting for their different grains.
3. Inspect observed ledger, record type, version, fiscal year/period, company, account, profit-center, partner, valuation, and currency fields. Verify the complete key from DDIC/metadata and test uniqueness; document numbers alone are insufficient.
4. State whether actual allocations belong in the requested total. Standard record types distinguish ordinary actual, plan, actual allocations, and plan allocations.
5. Select exactly one approved amount/currency representation. Do not apply FI SHKZG logic to PCA amounts: inspect DRCRK and whether the amount is already signed.
6. Distinguish period movements, periodic balance-sheet transfers, and balance carryforward. Define balance versus P&L accumulation using fiscal configuration.
7. Reconcile at matching scope, grain, currency, period, record type, ledger, and version; explain remaining differences without inventing an FI/PCA one-to-one relationship.

Return source representation, amount basis, scoped dimensions, inclusion rules, and control-total evidence. Do not hard-code a PCA ledger, actual version, currency type, or organization mapping from an example.
