# Databricks CLI command catalog for agents

Baseline: Databricks CLI **v1.14.0**, checked **2026-08-27**. This is a capability and risk map, not a replacement for `databricks <group> <command> -h` or the [complete official inventory](https://docs.databricks.com/aws/en/dev-tools/cli/commands).

Risk labels:

- **R** — read/inspect by default.
- **X** — executes work, can read data, start compute, or incur cost.
- **W** — mutates local or remote state.
- **D** — destructive, access-changing, secret-bearing, or otherwise high impact.

One command group can contain multiple risk classes. Authorization is based on the chosen subcommand, not the group name.

## Core control and discovery

| Group | Useful capabilities | Risk | Agent direction |
|---|---|---:|---|
| `version`, `help`, `<group> -h` | Prove installed version and grammar | R | Always prefer installed help over remembered syntax |
| `auth` | `profiles`, `describe`, interactive `login`, `logout`, `switch`, `token` | R/W/D | Use `profiles` and non-sensitive `describe`; never run or expose `token` or `describe --sensitive` output |
| `current-user me` | Resolve authenticated user or service principal | R | Mandatory identity preflight |
| `api` | Raw authenticated REST `get`, `post`, `put`, `patch`, `delete`, `head` | R/X/W/D | Use for Statement Execution or endpoints without a typed group; endpoint semantics control risk |
| `cache clear` | Clear the CLI's local cache | W | Troubleshooting only; do not use as a generic recovery step |
| `completion` | Generate shell completion scripts | W | Local shell change; optional |

Global flags include `--profile`, `--output`, `--log-file`, `--log-format`, `--log-level`, and bundle `--target`. Use `--profile <exact-name>` and `--output json` for automation.

Sources: [commands](https://docs.databricks.com/aws/en/dev-tools/cli/commands), [`auth`](https://docs.databricks.com/aws/en/dev-tools/cli/reference/auth-commands), and [`api`](https://docs.databricks.com/aws/en/dev-tools/cli/reference/api-commands).

## Declarative Automation Bundles

`databricks bundle` manages versioned Databricks projects as code.

| Command family | Risk | Agent direction |
|---|---:|---|
| `validate`, `schema`, `summary` | R | Run first; archive machine-readable validation where useful |
| `plan` | R | Preferred change preview; inspect target/workspace and every create/update/delete |
| `generate`, `init` | W | Writes local project files; inspect generated diff before keeping it |
| `sync` | W | Changes workspace files; use only for an approved development target |
| `deploy` | W | Remote create/update/delete may occur; require approved target and reviewed plan |
| `run` | X | Executes a deployed job/pipeline and can incur cost/write data |
| `destroy` | D | Destructive; require immediate confirmation and exact target re-check |

Always pass an explicit target, validate it, and compare host/principal before deploy or destroy. CLI v1.14.0 can migrate eligible Terraform-backed bundle state to the direct engine; see the [v1.14.0 release](https://github.com/databricks/cli/releases/tag/v1.14.0) and [bundle command reference](https://docs.databricks.com/aws/en/dev-tools/cli/bundle-commands).

## Lakeflow Jobs

`databricks jobs` supports job definitions and runs.

- **R:** `list`, `get`, `list-runs`, `get-run`, `get-run-output`, `export-run`.
- **X:** `run-now`, `submit`, `repair-run`.
- **W:** `create`, `update`, `reset`.
- **D:** `delete`, `delete-run`, `cancel-run`, `cancel-all-runs`.

Agent rules:

1. Resolve job ID and inspect settings before a run or mutation.
2. Do not confuse a job ID with a run ID or task-run ID.
3. Complete pagination. `jobs get` and `get-run` can paginate arrays after 100 elements.
4. Prefer Declarative Automation Bundles for CI/CD-managed jobs.
5. For direct run submission, use a documented idempotency token when available and preserve the returned run ID.
6. A successful submission is not a successful job: poll lifecycle/result state and inspect task failures.

Reference: [`jobs` commands](https://docs.databricks.com/aws/en/dev-tools/cli/reference/jobs-commands) and [job automation guidance](https://docs.databricks.com/aws/en/jobs/automate).

## Unity Catalog

Unity Catalog's primary data namespace is `catalog.schema.object`.

| Group | Capability | Typical risk |
|---|---|---:|
| `metastores` | Inspect/assign metastore resources | R/W/D |
| `catalogs` | Manage first-level namespaces | R/W/D |
| `schemas` | Manage second-level namespaces | R/W/D |
| `tables` | Inspect/create/delete tables and summaries | R/W/D |
| `volumes` | Manage governed file volumes | R/W/D |
| `functions` | Manage Unity Catalog functions | R/W/D |
| `grants` | Read/effectively resolve/update Unity Catalog privileges | R/D |
| `connections` | Manage Lakehouse Federation connections | R/W/D |
| `external-locations`, `storage-credentials`, `credentials` | Govern access to external cloud resources/services | R/D |
| `workspace-bindings` | Isolate/bind securables to workspaces | R/D |
| `registered-models`, `model-versions` | Manage ML models in Unity Catalog | R/W/D |
| `entity-tag-assignments`, `data-classification`, `data-quality` | Tags, classification, and monitors | R/X/W |

Use exact fully qualified names. `get` the parent and current object before create/update/delete. Metadata visibility depends on privileges; an empty list does not prove an object is absent globally. For access analysis, distinguish direct `grants get` from effective grants.

Never create a credential, external location, connection, or grant as a convenience workaround. Those operations cross data-governance and cloud-IAM boundaries.

References: [`catalogs`](https://docs.databricks.com/aws/en/dev-tools/cli/reference/catalogs-commands), [`schemas`](https://docs.databricks.com/aws/en/dev-tools/cli/reference/schemas-commands), [`tables`](https://docs.databricks.com/aws/en/dev-tools/cli/reference/tables-commands), [`volumes`](https://docs.databricks.com/aws/en/dev-tools/cli/reference/volumes-commands), and [`grants`](https://docs.databricks.com/aws/en/dev-tools/cli/reference/grants-commands).

## Files and workspace content

There are different file surfaces; choose intentionally.

### `fs`

Commands: `cat`, `cp`, `ls`, `mkdir`, `rm`.

- Use `databricks fs` for DBFS-scheme paths and Unity Catalog Volume files.
- For a volume, the CLI requires `dbfs:/Volumes/<catalog>/<schema>/<volume>/<path>`.
- Databricks recommends Unity Catalog Volumes, external locations, or workspace files instead of legacy DBFS root/mounts.
- `cp`, `mkdir`, and `rm` mutate remote storage. Recursive `rm` is destructive.

### `workspace`

Commands include `list`, `get-status`, `export`, `export-dir`, `import`, `import-dir`, `mkdirs`, and `delete`, plus permission subcommands. This surface manages workspace notebooks/files/directories, not Unity Catalog tables or arbitrary volume data.

### Agent rules

- Prove source and destination path kinds before copying.
- Do not overwrite or recursively delete by inferred path.
- Treat exports as potentially sensitive source code/metadata.
- Validate size/hash/count after transfer; exit code zero alone is insufficient.
- For tabular data, prefer governed tables; for non-tabular governed files, prefer Volumes.

References: [`fs`](https://docs.databricks.com/aws/en/dev-tools/cli/reference/fs-commands), [`workspace`](https://docs.databricks.com/aws/en/dev-tools/cli/reference/workspace-commands), and [files in Volumes](https://docs.databricks.com/aws/en/volumes/volume-files).

## Secrets

The workspace `secrets` group manages secret scopes, ACLs, and secrets. Unity Catalog also has a separate `secrets-uc` group in Public Preview in the v1.14.0 inventory.

- **R:** `list-scopes`, `list-secrets`, `list-acls`, `get-acl` expose metadata, not a reason to retrieve values.
- **D:** `get-secret` returns secret material (encoded in the API response), `put-secret`, delete operations, and ACL changes.

Agent rules:

1. Never run `get-secret` to test whether a key exists; use `list-secrets` metadata.
2. Never decode, print, log, or place a secret in an argument, request file, transcript, or artifact.
3. Secret creation/rotation/deletion requires an approved secure-input channel and owner-defined lifecycle. Chat is not that channel.
4. Never migrate secret values between scopes/workspaces without a separate security-approved process.

References: [`secrets` commands](https://docs.databricks.com/aws/en/dev-tools/cli/reference/secrets-commands) and [secret management](https://docs.databricks.com/aws/en/security/secrets/).

## Git folders (`repos`)

`databricks repos` can create, list, get, update, and delete workspace Git folders and manage their permissions. Updating can switch branch/tag/commit and affect users or jobs that depend on the folder.

Use `list/get` for inventory. Before `update`, prove repository URL, provider, current branch/head, target ref, and consumers. `delete` is destructive. Git credentials are managed separately by `git-credentials`; never inspect or copy their underlying token values.

Reference: [`repos` commands](https://docs.databricks.com/aws/en/dev-tools/cli/reference/repos-commands).

## Permissions and access control

`databricks permissions` supports `get`, `get-permission-levels`, `update`, and `set` across workspace resource types.

- `get` and `get-permission-levels` are read operations.
- `update` changes direct permissions.
- `set` **replaces existing direct permissions**; an empty ACL removes all direct permissions. Treat it as destructive.

Unity Catalog data privileges generally use `grants`, not this generic workspace-permissions group. Always capture current ACL/grants, inherited/effective context, and principal IDs. Never select principals by fuzzy display name.

Reference: [`permissions` commands](https://docs.databricks.com/aws/en/dev-tools/cli/reference/permissions-commands).

## SQL warehouses and SQL surfaces

### `warehouses`

- **R:** `list`, `get`, configuration/permission reads.
- **X/W:** `start`, `create`, `edit`; starting compute can incur cost.
- **D/W:** `stop`, `delete`, workspace configuration changes.

The `warehouses` group manages compute. It does not execute arbitrary SQL. Use the Statement Execution API in `SQL_STATEMENT_EXECUTION.md`.

### `queries` and `query-history`

- `queries` performs CRUD on saved query definitions. It **does not execute SQL**.
- `query-history list` reads prior execution history and is paginated.
- `alerts`/`alerts-v2` manage scheduled conditions on query results; creating/updating alerts is a remote mutation with notification and cost implications.

References: [`warehouses`](https://docs.databricks.com/aws/en/dev-tools/cli/reference/warehouses-commands), [`queries`](https://docs.databricks.com/aws/en/dev-tools/cli/reference/queries-commands), and [`query-history`](https://docs.databricks.com/aws/en/dev-tools/cli/reference/query-history-commands).

## Genie

`databricks genie` covers spaces, conversations, messages, feedback, query attachments/results, and evaluations. Examples include `list-spaces`, `get-space`, `ask`, `start-conversation`, `get-message`, `execute-message-attachment-query`, and full-result download operations.

- Listing/getting space metadata is generally R.
- `ask`, starting conversations, or executing an attachment query is X/W and can access data/incur warehouse cost.
- Space updates/trash, conversation/message deletion, feedback, and eval runs mutate state.
- Downloaded query results are business data and require protected handling.

Use Genie when the user explicitly wants an existing space's conversational semantics. Use parameterized Statement Execution for deterministic reconciliation. See [`genie` commands](https://docs.databricks.com/aws/en/dev-tools/cli/reference/genie-commands) and `QUEST_OR_QUERIES.md`.

## AI tools for coding agents

`databricks aitools` can `install`, `list`, `update`, `uninstall`, and report `version` for Databricks agent skills/plugins.

- `list`/`version` are local reads.
- `install`, `update`, and `uninstall` modify agent/project or global user configuration.
- `update --check` previews available changes.
- `install --path <directory>` resolves raw skill files to a directory without modifying detected agents or writing install state.

Do not silently install agent plugins. Review source/version/scope and use project scope or `--path` for a POC. Experimental skills require an explicit decision. Reference: [`aitools` commands](https://docs.databricks.com/aws/en/dev-tools/cli/reference/aitools-commands).

## Environments

The `environments` group manages workspace base environments for serverless notebooks/jobs and can configure a matching local Python environment.

- **R:** get/list base environments, get default, get operation.
- **W/X:** create, refresh, update, change the default; these are asynchronous remote operations.
- **D:** delete can affect linked notebooks/jobs and is irreversible.
- **W (local):** `setup-local` creates/updates `.venv` and `pyproject.toml`; use `--dry-run` first.

Do not confuse workspace base environments with a Python `venv`, cluster libraries, or a Unity Catalog schema named “environment.” Reference: [`environments` commands](https://docs.databricks.com/aws/en/dev-tools/cli/reference/environments-commands) and `PYSPARK_CONNECT.md`.

## SSH

The `ssh` group is **Beta**.

- `ssh connect` creates an SSH connection to serverless or a dedicated single-user cluster. When connecting to a cluster, `--auto-start-cluster` defaults to true.
- `ssh setup` modifies the user's SSH configuration for classic dedicated compute. Serverless does not require setup.
- `--auto-approve` skips local IDE/configuration prompts; it is not security approval.

An SSH session is an interactive execution channel, not a read-only inspector. It can start compute, run arbitrary commands, and access data available to that principal/compute. Require explicit authorization and avoid it when a typed CLI/API operation is sufficient. Reference: [`ssh` commands](https://docs.databricks.com/aws/en/dev-tools/cli/reference/ssh-commands).

## Other high-value groups

The CLI also covers clusters/policies/pools, Lakeflow pipelines, MLflow experiments and models, serving endpoints, vector/AI Search, dashboards, apps, clean rooms, Marketplace, identity, account provisioning/billing, settings, and Lakebase/Postgres. Discover them through the [official command inventory](https://docs.databricks.com/aws/en/dev-tools/cli/commands). Account/admin groups can alter infrastructure, identity, billing, network, OAuth, or security policy and require a separate admin runbook.

## Selection principle

Databricks' [developer-tool guidance](https://docs.databricks.com/aws/en/dev-tools) recommends:

- CLI for direct interaction, shell scripting, experiments, raw REST calls, profiles, and sync;
- Bundles for versioned project/resource deployment and CI/CD;
- SDKs for application logic and custom services;
- SQL drivers or Statement Execution for SQL;
- Terraform for broader infrastructure/account provisioning.

Choose the narrowest typed surface that expresses the task. Raw `api` and SSH are escape hatches, not first choices.
