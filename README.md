# Qovery Service Catalog

Pre-built Terraform blueprints for provisioning cloud infrastructure through the Qovery platform.

## Repository Structure

```
service-catalog/
├── aws/
│   ├── postgresql/    # AWS RDS PostgreSQL
│   ├── mysql/         # AWS RDS MySQL
│   ├── redis/         # AWS ElastiCache Redis
│   └── mongodb/       # AWS DocumentDB (MongoDB-compatible)
├── gcp/               # (future)
├── azure/             # (future)
├── schemas/
│   └── qsm-schema.json   # JSON Schema for qsm.yml validation
└── .github/
    └── workflows/
        └── validate.yml   # CI pipeline
```

Each blueprint directory contains:

| File           | Description                    |
| -------------- | ------------------------------ |
| `main.tf`      | Terraform resources            |
| `variables.tf` | Input variables                |
| `outputs.tf`   | Outputs (prefixed with `QSM_`) |
| `providers.tf` | Provider configuration         |
| `qsm.yml`      | Qovery Service Manifest        |
| `README.md`    | Blueprint documentation        |

## QSM (Qovery Service Manifest)

Every blueprint requires a `qsm.yml` file that describes the blueprint for the catalog. Key sections:

- **metadata**: name, version, description, tags
- **spec.injectedVariables**: Variables auto-filled from cluster/environment context (hidden from user)
- **spec.userVariables**: Variables shown in the provisioning form
- **spec.outputs**: Terraform outputs exposed as environment variables

See `schemas/qsm-schema.json` for the full schema.

## Versioning

Blueprints are always fetched from the `main` branch. q-core resolves `main` to a commit SHA via the GitHub API and stores that SHA for deterministic deployments.

The `metadata.version` field in `qsm.yml` is informational only (shown in the catalog UI). There are no git tags for versioning.

## Alias Variable Mechanism

Catalog services use an automatic alias bridge to expose Terraform outputs as environment variables to other services in the same environment.

### How it works

1. Every Terraform output in a blueprint **must** be prefixed with `QSM_` (Qovery Service Manifest), e.g. `QSM_POSTGRESQL_HOST`.
2. When a user provisions a service, they give it a **service name** (e.g. `my-database`).
3. After Terraform apply, q-core reads the outputs and computes environment variable names using the formula:

```
{UPPER_SNAKE_SERVICE_NAME}_{OUTPUT_NAME_WITHOUT_QSM_PREFIX}
```

1. These environment variables are created at **environment scope**, so every other service in the environment can read them.

### Detection mechanism

The `QSM_` prefix is the sole detection mechanism. Any terraform service whose outputs start with `QSM_*` gets alias env vars created, regardless of how it was created. There is no `isFromCatalog` flag, no DB column, no engine change.

### Example

A user provisions the `aws-postgresql` blueprint and names the service `my-database`.

| Terraform output                   | Environment variable                       |
| ---------------------------------- | ------------------------------------------ |
| `QSM_POSTGRESQL_HOST`              | `MY_DATABASE_POSTGRESQL_HOST`              |
| `QSM_POSTGRESQL_PORT`              | `MY_DATABASE_POSTGRESQL_PORT`              |
| `QSM_POSTGRESQL_DATABASE`          | `MY_DATABASE_POSTGRESQL_DATABASE`          |
| `QSM_POSTGRESQL_USERNAME`          | `MY_DATABASE_POSTGRESQL_USERNAME`          |
| `QSM_POSTGRESQL_CONNECTION_STRING` | `MY_DATABASE_POSTGRESQL_CONNECTION_STRING` |

The service name is normalized: lowercased with hyphens/spaces replaced by underscores, then uppercased (`my-database` -> `MY_DATABASE`).

### No collisions

Because each service has a unique name within an environment, the prefix is always unique. Two PostgreSQL instances named `main-db` and `analytics-db` produce separate variable sets:

```
MAIN_DB_POSTGRESQL_HOST       = "main.abc.rds.amazonaws.com"
ANALYTICS_DB_POSTGRESQL_HOST  = "analytics.def.rds.amazonaws.com"
```

### Rules for blueprint authors

- All output names **must** start with `QSM_` (enforced by CI and JSON Schema).
- The part after `QSM_` should identify the service type (`POSTGRESQL_`, `MYSQL_`, `REDIS_`, `MONGODB_`).
- Aliases are **not user-editable** -- they are deterministic from the service name.
- Sensitive outputs should be marked with `sensitive: true` in `qsm.yml` and will be stored as secrets.

## Contributing

1. Create or modify a blueprint in the appropriate `{provider}/{service}/` directory
2. Ensure `qsm.yml` is valid against the JSON Schema
3. All variables referenced in `qsm.yml` must exist in `variables.tf`
4. All outputs referenced in `qsm.yml` must exist in `outputs.tf` and start with `QSM_`
5. Run `terraform init -backend=false && terraform validate` locally
6. Open a PR -- CI validates everything automatically
