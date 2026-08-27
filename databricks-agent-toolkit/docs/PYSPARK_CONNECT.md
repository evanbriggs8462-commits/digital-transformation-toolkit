# PySpark development with Databricks Connect

Checked **2026-08-27**. This guide covers Databricks Connect for Python with Databricks Runtime 13.3 LTS and above.

Labels:

- **Databricks fact** — behavior from current Databricks documentation.
- **Toolkit rule** — the agent-safe engineering recommendation for this toolkit.

## What Databricks Connect is

**Databricks fact:** Databricks Connect is a client library that lets local Python code build Spark plans while execution occurs on Databricks compute. It is not a local Spark cluster and it does not connect to an arbitrary open-source Apache Spark server. See the [overview](https://docs.databricks.com/aws/en/dev-tools/databricks-connect/) and [requirements](https://docs.databricks.com/aws/en/dev-tools/databricks-connect/requirements).

Use it for interactive development, debugging, small contract tests, and applications that need the PySpark DataFrame API. Use SQL Statement Execution when the task is simply reviewed SQL on a warehouse; use Jobs/Bundles when the task is a deployable production workload.

## Compatibility gate

Before installation, prove all of the following:

1. The workspace has Unity Catalog enabled.
2. The selected compute is serverless or a cluster using Assigned or Shared access mode.
3. The compute's Databricks Runtime is greater than or equal to the Databricks Connect package version.
4. The local Python minor version is supported by that Connect/runtime series. If using Python UDFs, the local Python minor version must match the compute's Python minor version.
5. Authentication resolves to the intended workspace and principal.

**Databricks fact:** Serverless support begins with Databricks Connect 15.1. Version compatibility changes over time; use the live [compatibility table](https://docs.databricks.com/aws/en/dev-tools/databricks-connect/requirements), not a model's remembered matrix.

**Toolkit rule:** Record the runtime/serverless version, local Python version, Connect version, profile, host, and principal together. Do not “fix” a mismatch by upgrading only one side until the target compute is confirmed.

## One isolated virtual environment per target series

**Databricks fact:** Databricks strongly recommends a virtual environment. `databricks-connect` conflicts with the separately installed `pyspark` package; they must not coexist in one environment. Databricks recommends a Connect package in the matching `X.Y.*` series so the latest compatible patch is selected. See [installation](https://docs.databricks.com/aws/en/dev-tools/databricks-connect/python/install) and [conflicting PySpark installations](https://docs.databricks.com/aws/en/dev-tools/databricks-connect/python/troubleshooting).

### Preferred v1.14.0 CLI workflow

The `environments setup-local` command can create/update a `uv`-managed `.venv`, select compatible Python/Databricks Connect versions, and record constraints in `pyproject.toml`. It changes local project files, so preview first and inspect the diff:

```powershell
$DbxProfileName = "POC-DEV"

# Choose exactly one approved compute target.
databricks environments setup-local --serverless-version "<serverless-version>" `
    --profile $DbxProfileName `
    --dry-run
if ($LASTEXITCODE -ne 0) { throw "Could not calculate the local environment plan." }

# Run the same command without --dry-run only after approving its file/package changes.
```

Alternatives include `--cluster-id`, `--cluster-name`, or `--job-task <job-id>.<task-key>`. Do not select by a non-unique cluster name. The current syntax is in the [`environments` reference](https://docs.databricks.com/aws/en/dev-tools/cli/reference/environments-commands).

### Manual workflow

Use this only after reading the live compatibility table. `17.3.*` below is an example series, not a universal default:

```powershell
$DbxConnectSeries = "17.3.*"  # Replace with the approved series matching compute.

py -3.12 -m venv .venv
& .\.venv\Scripts\Activate.ps1
python -m pip uninstall -y pyspark
python -m pip install --upgrade pip
python -m pip install --upgrade "databricks-connect==$DbxConnectSeries"
python -m pip check
```

Commit dependency declarations/locks, not the `.venv`. If the project also tests with open-source PySpark locally, use a **different** virtual environment and accept that behavior may differ from Databricks Runtime.

## Authentication and compute selection

Use OAuth U2M for an attended developer and OAuth M2M for an unattended service principal. Keep credentials in unified authentication, not Python source.

For a cluster-backed profile that already contains `cluster_id`:

```python
from databricks.connect import DatabricksSession

spark = DatabricksSession.builder.profile("POC-DEV").getOrCreate()
```

For a profile configured for serverless compute with `serverless_compute_id = auto`:

```python
from databricks.connect import DatabricksSession

spark = DatabricksSession.builder.profile("POC-DEV").getOrCreate()
```

The [compute configuration reference](https://docs.databricks.com/aws/en/dev-tools/databricks-connect/cluster-config) also documents `DatabricksSession.builder.serverless()` and an SDK `Config` object when the compute ID is supplied separately.

**Toolkit rule:** Prefer an explicit named profile. Never use `builder.remote(token=...)`, embed a PAT, or add a client secret to code merely because those fields exist in the API.

Validate the environment and connection before running data logic:

```powershell
$DbxProfileName = "POC-DEV"
$PreviousDbxConfigProfile = $env:DATABRICKS_CONFIG_PROFILE
try {
    $env:DATABRICKS_CONFIG_PROFILE = $DbxProfileName
    databricks-connect test
    if ($LASTEXITCODE -ne 0) { throw "Databricks Connect validation failed." }
}
finally {
    $env:DATABRICKS_CONFIG_PROFILE = $PreviousDbxConfigProfile
}
```

Databricks Connect 14.3 and above also supports `DatabricksSession.builder.validateSession(True).getOrCreate()`.

## Split transformations from I/O

**Toolkit rule:** Make the transformation a pure DataFrame-to-DataFrame function. It should not choose a profile, read a table, write a table, start compute, call `collect()`/`toPandas()`, or fetch secrets. Put those effects in a thin entry point.

```python
# transforms/orders.py
from pyspark.sql import DataFrame, functions as F


def summarize_completed_orders(orders: DataFrame) -> DataFrame:
    """Return one deterministic row per customer; no reads, writes, or actions."""
    return (
        orders
        .where(F.col("status") == F.lit("COMPLETE"))
        .groupBy("customer_id")
        .agg(
            F.count("order_id").alias("order_count"),
            F.sum("amount").alias("completed_amount"),
        )
        .select("customer_id", "order_count", "completed_amount")
    )
```

```python
# jobs/orders_job.py
from transforms.orders import summarize_completed_orders


def run(spark, source_table: str, destination_table: str) -> None:
    source = spark.read.table(source_table)
    result = summarize_completed_orders(source)
    result.write.mode("overwrite").saveAsTable(destination_table)
```

The entry point's identifiers must come from approved configuration/allowlists, not unchecked user input. The write mode and destination require explicit authorization.

This split makes it possible to test schema and transformation behavior with tiny inputs without reading production tables or writing anything.

## Four-layer test strategy

### 1. Pure Python tests

Test parsing, configuration validation, identifier allowlists, and ordinary functions locally without Spark. These are fast and require no Databricks credentials.

### 2. Remote DataFrame contract tests

Create a few synthetic rows through a Databricks Connect session, apply the pure transform, and collect only the tiny expected result:

```python
from decimal import Decimal

from transforms.orders import summarize_completed_orders


def test_summarize_completed_orders(spark):
    source = spark.createDataFrame(
        [
            (1, 10, "COMPLETE", Decimal("12.50")),
            (2, 10, "CANCELED", Decimal("99.00")),
            (3, 20, "COMPLETE", Decimal("7.25")),
        ],
        "order_id long, customer_id long, status string, amount decimal(18,2)",
    )

    rows = {
        row.customer_id: (row.order_count, row.completed_amount)
        for row in summarize_completed_orders(source).collect()
    }

    assert rows == {
        10: (1, Decimal("12.50")),
        20: (1, Decimal("7.25")),
    }
```

The `spark` fixture should create one explicitly profiled `DatabricksSession`. Synthetic rows are still transmitted to remote compute; do not place real secrets or unapproved personal data in fixtures.

### 3. Read-only integration tests

Against a development catalog, validate that approved source objects exist, required columns/types are present, and bounded filters produce the expected contract. Avoid full-table `collect()` and `toPandas()`.

### 4. Authorized write/e2e tests

Use a dedicated temporary development schema, unique test-run identifiers, explicit cleanup scope, and data-owner approval. Validate before/after objects and never infer that an overwrite, merge, or cleanup is safe from a `dev` name alone.

Databricks documents both remote pytest use and workspace test tooling: [IDE extension pytest](https://docs.databricks.com/aws/en/dev-tools/vscode-ext/pytest) and [workspace unit tests](https://docs.databricks.com/aws/en/files/python-unit-tests).

## Important limitations

Review the live [Python limitations page](https://docs.databricks.com/aws/en/dev-tools/databricks-connect/python/limitations) for the exact Connect/runtime series. Current cross-version limitations include:

- no `DataFrame.display()` API;
- no Spark Context or RDD APIs;
- no libraries that require RDDs, Spark Context, or direct access to the Spark JVM;
- no Databricks Utilities for credentials, library management, notebook workflows, or widgets;
- `CREATE TABLE ... AS SELECT` is unsupported through this surface; Databricks documents using a DataFrame write instead;
- no changing log4j level through `SparkContext`;
- no distributed ML training;
- no automatic synchronization of the local development environment with remote compute.

There are also runtime-dependent limits for `foreachBatch`, pandas grouped operations, serverless UDF libraries, unresolved logical-plan size, and long-running queries. Do not generalize behavior proven on one runtime series to another.

## Common failures

| Symptom | Check |
|---|---|
| `UNAVAILABLE`, DNS, HTTP/2, or unknown connection error | Effective host, compute ID, compute availability, proxy/network path, profile |
| `stream corrupted`, class-not-found, Spark initialization errors | Remove the conflicting `pyspark` install and reinstall matching `databricks-connect` |
| Python serialization/UDF error | Match the local Python minor version to the runtime |
| Feature exists in a notebook but fails locally | Check the Databricks Connect limitations for that exact version |
| Windows “filename, directory name, or volume label syntax is incorrect” | The Connect environment path may contain spaces; use a path without spaces or the documented short-name workaround |
| Unexpected workspace/compute | Stop; inspect profile, host, principal, `cluster_id`, and ambient `DATABRICKS_*` variable names |

Do not respond to a compatibility error by installing another random PySpark/Connect version into the same environment. Re-prove the matrix, recreate the isolated environment, and rerun `databricks-connect test`.

Primary sources: [requirements](https://docs.databricks.com/aws/en/dev-tools/databricks-connect/requirements), [installation](https://docs.databricks.com/aws/en/dev-tools/databricks-connect/python/install), [compute configuration](https://docs.databricks.com/aws/en/dev-tools/databricks-connect/cluster-config), [limitations](https://docs.databricks.com/aws/en/dev-tools/databricks-connect/python/limitations), and [troubleshooting](https://docs.databricks.com/aws/en/dev-tools/databricks-connect/python/troubleshooting).
