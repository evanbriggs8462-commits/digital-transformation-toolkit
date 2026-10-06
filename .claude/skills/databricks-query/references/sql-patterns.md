# Bounded SQL patterns

These are **unexecuted templates**, not claims about available objects. Replace angle-bracket identifiers only with verified names. Bind named values using the Statement API `parameters` array. Quote each identifier segment separately with backticks; escape an embedded backtick by doubling it. Do not interpolate unchecked input. String values use parameters, not backticks.

## Targeted metadata

Submit each statement separately on an authorized warehouse:

```sql
SHOW TABLES IN `<catalog>`.`<schema>` LIKE '<exact_table_name>';
DESCRIBE TABLE `<catalog>`.`<schema>`.`<table>`;
```

For a Unity Catalog catalog, inspect columns without exporting business rows:

```sql
SELECT column_name, full_data_type, is_nullable
FROM `<catalog>`.information_schema.columns
WHERE table_schema = :schema_name AND table_name = :table_name
ORDER BY ordinal_position
LIMIT 100;
```

Information-schema relation names are stored in lowercase; bind the discovered metadata names. These results are privilege-filtered and may be incomplete. Revalidate saved mappings against current metadata before relying on them. For legacy metastores or unavailable information schema, use supported targeted `SHOW`/`DESCRIBE` instead.

## Scope before aggregation

Use this only after confirming columns, physical current-row semantics, and an approved date/entity slice:

```sql
SELECT `<business_key>`, COUNT(*) AS physical_rows
FROM `<catalog>`.`<schema>`.`<table>`
WHERE `<entity_column>` = :entity
  AND `<typed_date_column>` >= :start_date
  AND `<typed_date_column>` < :cutoff_exclusive
GROUP BY `<business_key>`
HAVING COUNT(*) > 1
ORDER BY physical_rows DESC
LIMIT 20;
```

Expand the key to all verified business-key components. This diagnoses scoped duplicate candidates; it neither proves global uniqueness nor chooses a CDC survivor. Aggregation can scan more data than it returns; check predicates/plan before execution. Reconcile an aggregate over the full approved scope, never sum a limited detail sample and call it the total.

## SAP raw date normalization

For a verified STRING `yyyyMMdd` SAP date column, normalize known empty sentinels before parsing:

```sql
SELECT CAST(try_to_timestamp(
         NULLIF(NULLIF(TRIM(`<raw_date_column>`), ''), '00000000'),
         'yyyyMMdd'
       ) AS DATE) AS normalized_date
FROM `<catalog>`.`<schema>`.`<table>`
WHERE `<scope_column>` = :scope
LIMIT 10;
```

Count malformed non-sentinel dates separately within the approved slice; `NULL` from tolerant parsing must not hide a data-quality problem. Do not apply this format to an already typed DATE/TIMESTAMP. Confirm available function/runtime support and session timezone before timestamp calculations.

## Statement request discipline

Use an explicit warehouse/catalog/schema and finite `row_limit`/`byte_limit`; use `wait_timeout: "0s"` with bounded polling for automation. For `:start_date`, bind `{"name":"start_date","value":"<ISO-date>","type":"DATE"}`. Use the actual installed CLI's supported request-file syntax. Never put tokens in JSON or shell arguments.

Preserve the returned statement ID, inspect `status.state`, and retrieve each intended chunk. Record `manifest.truncated`, fetched counts, and any SQL `LIMIT`. A complete limited sample remains a sample. On an ambiguous submit timeout, reconcile before resubmitting; do not duplicate remote execution. Follow the contract's authorization policy for cancellation.

## Official references

Checked 2026-10-06; documentation is syntax evidence, not workspace evidence.

- [SQL identifiers](https://docs.databricks.com/aws/en/sql/language-manual/sql-ref-identifiers)
- [Information-schema columns](https://docs.databricks.com/aws/en/sql/language-manual/information-schema/columns)
- [Information-schema tables](https://docs.databricks.com/aws/en/sql/language-manual/information-schema/tables)
- [Statement Execution API](https://docs.databricks.com/api/statement-execution/v1/statement-execution)
- [Warehouse automatic starts](https://docs.databricks.com/aws/en/compute/sql-warehouse)
- [Tolerant timestamp parsing](https://docs.databricks.com/aws/en/sql/language-manual/functions/try_to_timestamp)
