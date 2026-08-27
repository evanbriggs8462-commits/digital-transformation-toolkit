# Official Databricks sources

Checked: **2026-08-27**
CLI baseline: **Databricks CLI v1.14.0**, released 2026-08-26. The release is immutable and signed in the official `databricks/cli` repository.

This toolkit uses primary documentation maintained by Databricks and the official Databricks GitHub organization. Re-check command help and these pages after changing the CLI version. Databricks CLI versions `1.0.0` and above are GA, but individual command groups can still carry Preview or Beta labels.

## CLI baseline and behavior

- [Databricks CLI v1.14.0 release](https://github.com/databricks/cli/releases/tag/v1.14.0)
- [Databricks CLI overview and release types](https://docs.databricks.com/aws/en/dev-tools/cli/)
- [Install or update the CLI](https://docs.databricks.com/aws/en/dev-tools/cli/install)
- [Complete CLI command inventory](https://docs.databricks.com/aws/en/dev-tools/cli/commands)
- [Basic CLI usage, JSON input, and JSON output](https://docs.databricks.com/aws/en/dev-tools/cli/usage)
- [CLI troubleshooting and structured logs](https://docs.databricks.com/aws/en/dev-tools/cli/troubleshooting)
- [Raw REST calls through `databricks api`](https://docs.databricks.com/aws/en/dev-tools/cli/reference/api-commands)
- [REST API errors and retry semantics](https://docs.databricks.com/api/workspace/errors)

## Authentication and target identity

- [Authentication for the Databricks CLI](https://docs.databricks.com/aws/en/dev-tools/cli/authentication)
- [`auth` command reference](https://docs.databricks.com/aws/en/dev-tools/cli/reference/auth-commands)
- [CLI configuration profiles](https://docs.databricks.com/aws/en/dev-tools/cli/profiles)
- [Databricks configuration profiles](https://docs.databricks.com/aws/en/dev-tools/auth/config-profiles)
- [Databricks unified authentication](https://docs.databricks.com/aws/en/dev-tools/auth/unified-auth)
- [Unified-authentication environment variables and fields](https://docs.databricks.com/aws/en/dev-tools/auth/env-vars)
- [OAuth user-to-machine authorization](https://docs.databricks.com/aws/en/dev-tools/auth/oauth-u2m)
- [OAuth machine-to-machine authorization](https://docs.databricks.com/aws/en/dev-tools/auth/oauth-m2m)
- [`current-user` command reference](https://docs.databricks.com/aws/en/dev-tools/cli/reference/current-user-commands)

## SQL and query surfaces

- [Statement Execution API reference](https://docs.databricks.com/api/statement-execution/v1)
- [Statement Execution API tutorial](https://docs.databricks.com/aws/en/dev-tools/sql-execution-tutorial)
- [Databricks REST API reference and rate limits](https://docs.databricks.com/api/workspace/)
- [API scopes](https://docs.databricks.com/api/workspace/scopes)
- [`warehouses` command reference](https://docs.databricks.com/aws/en/dev-tools/cli/reference/warehouses-commands)
- [`queries` command reference](https://docs.databricks.com/aws/en/dev-tools/cli/reference/queries-commands)
- [`query-history` command reference](https://docs.databricks.com/aws/en/dev-tools/cli/reference/query-history-commands)
- [`genie` command reference](https://docs.databricks.com/aws/en/dev-tools/cli/reference/genie-commands)

## Databricks Connect and PySpark

- [Databricks Connect overview](https://docs.databricks.com/aws/en/dev-tools/databricks-connect/)
- [Usage and version requirements](https://docs.databricks.com/aws/en/dev-tools/databricks-connect/requirements)
- [Install Databricks Connect for Python](https://docs.databricks.com/aws/en/dev-tools/databricks-connect/python/install)
- [Configure compute and validate a connection](https://docs.databricks.com/aws/en/dev-tools/databricks-connect/cluster-config)
- [Current Python limitations](https://docs.databricks.com/aws/en/dev-tools/databricks-connect/python/limitations)
- [Python troubleshooting, including conflicting PySpark installs](https://docs.databricks.com/aws/en/dev-tools/databricks-connect/python/troubleshooting)
- [Run Python tests through the Databricks IDE extension](https://docs.databricks.com/aws/en/dev-tools/vscode-ext/pytest)
- [Python unit testing in the workspace](https://docs.databricks.com/aws/en/files/python-unit-tests)

## Automation and resource command groups

- [Declarative Automation Bundle commands](https://docs.databricks.com/aws/en/dev-tools/cli/bundle-commands)
- [`jobs` commands](https://docs.databricks.com/aws/en/dev-tools/cli/reference/jobs-commands)
- [`catalogs` commands](https://docs.databricks.com/aws/en/dev-tools/cli/reference/catalogs-commands)
- [`schemas` commands](https://docs.databricks.com/aws/en/dev-tools/cli/reference/schemas-commands)
- [`tables` commands](https://docs.databricks.com/aws/en/dev-tools/cli/reference/tables-commands)
- [`volumes` commands](https://docs.databricks.com/aws/en/dev-tools/cli/reference/volumes-commands)
- [`grants` commands](https://docs.databricks.com/aws/en/dev-tools/cli/reference/grants-commands)
- [`fs` commands](https://docs.databricks.com/aws/en/dev-tools/cli/reference/fs-commands)
- [`workspace` file and notebook commands](https://docs.databricks.com/aws/en/dev-tools/cli/reference/workspace-commands)
- [`secrets` commands](https://docs.databricks.com/aws/en/dev-tools/cli/reference/secrets-commands)
- [`repos` commands](https://docs.databricks.com/aws/en/dev-tools/cli/reference/repos-commands)
- [`permissions` commands](https://docs.databricks.com/aws/en/dev-tools/cli/reference/permissions-commands)
- [`aitools` commands](https://docs.databricks.com/aws/en/dev-tools/cli/reference/aitools-commands)
- [`environments` commands](https://docs.databricks.com/aws/en/dev-tools/cli/reference/environments-commands)
- [`ssh` commands](https://docs.databricks.com/aws/en/dev-tools/cli/reference/ssh-commands)
- [Developer-tool selection guidance](https://docs.databricks.com/aws/en/dev-tools)

## “Quest” clarification

The [v1.14.0 CLI command inventory](https://docs.databricks.com/aws/en/dev-tools/cli/commands) has no core command group named `quest`. Databricks documents erwin Data Modeler by Quest as a separate [partner integration](https://docs.databricks.com/aws/en/partners/data-governance/erwin); it is not evidence of a Databricks CLI `quest` command.

## Source-use rule for agents

1. Treat installed `databricks ... -h` output as the syntax authority for the installed binary.
2. Use the matching official reference page to understand semantics and risk.
3. Treat Preview/Beta labels as operational constraints, not decoration.
4. Never copy credentials, signed result URLs, customer identifiers, or business data into a research query, issue, log, or Markdown artifact.
5. If installed help and online documentation disagree, stop before a write, record `databricks version`, and resolve the version mismatch.
