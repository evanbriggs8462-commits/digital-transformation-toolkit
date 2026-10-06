---
name: sap-materials
description: Reason about SAP ECC material master tables and their expected contents when querying landed SAP data, including MARA, MARC, MAKT, MARM, MARD, MBEW, and MVKE. Use for material attributes, plant assignments, descriptions, units, stock, valuation, and ambiguous material-table names.
---

# SAP material master

Read [materials.md](references/materials.md) only for the requested material family. Treat the reference as typical ECC semantics, never proof of a Databricks object, field, key, or company rule.

1. Resolve ambiguous names from available metadata. `maram` is unresolved; suggest MARA/MARC/MAKT and check MARM if units are intended. Do not silently rewrite it.
2. Identify the actual catalog/schema/table, source system, client, extraction mode, and source release. Use `databricks-query` for schema confirmation and bounded queries.
3. Describe the selected tables before writing SQL. Inspect only relevant columns. Confirm whether CDC contains current rows, historical versions, tombstones, or duplicated snapshots.
4. State the required grain: material, material/plant, material/language, material/unit, material/storage location, material/valuation area/type, or material/sales area.
5. Join within the same source system and client where present. Prove the dimension is unique at the intended grain before attaching it to transactions; record row and amount changes after the join.
6. Preserve identifiers as strings, including leading zeros. Normalize only with an explicit, consistent mapping on both sides.
7. Keep stock snapshots distinct from movements and historical stock. Keep valuation area distinct from company code and plant until configuration confirms their relationship.

Return the selected family, observed grain, relevant unit/currency, schema evidence, and any unresolved assumption. Do not infer internal BU/OU/product mappings from SAP field names alone.
