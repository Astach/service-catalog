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

| File | Description |
|------|-------------|
| `main.tf` | Terraform resources |
| `variables.tf` | Input variables |
| `outputs.tf` | Outputs (prefixed with `QOVERY_`) |
| `providers.tf` | Provider configuration |
| `qsm.yml` | Qovery Service Manifest |
| `README.md` | Blueprint documentation |

## QSM (Qovery Service Manifest)

Every blueprint requires a `qsm.yml` file that describes the blueprint for the catalog. Key sections:

- **metadata**: name, version, description, tags
- **spec.injectedVariables**: Variables auto-filled from cluster/environment context (hidden from user)
- **spec.userVariables**: Variables shown in the provisioning form
- **spec.outputs**: Terraform outputs exposed as environment variables

See `schemas/qsm-schema.json` for the full schema.

## Versioning

Blueprints are versioned independently using Git tags with a name prefix:

```
aws-postgresql-v1.0.0
aws-mysql-v1.0.0
aws-redis-v1.0.0
aws-mongodb-v1.0.0
```

The `version` field in `qsm.yml` must match the tag suffix. CI enforces this on tag pushes.

## Output Naming Convention

All Terraform outputs must be prefixed with `QOVERY_` followed by the service type:

```
QOVERY_POSTGRESQL_HOST
QOVERY_POSTGRESQL_PORT
QOVERY_MYSQL_CONNECTION_STRING
QOVERY_REDIS_HOST
```

When a user provisions a service named "my-database", the platform computes environment variables as:

```
MY_DATABASE_POSTGRESQL_HOST
MY_DATABASE_POSTGRESQL_PORT
```

## Contributing

1. Create or modify a blueprint in the appropriate `{provider}/{service}/` directory
2. Ensure `qsm.yml` is valid against the JSON Schema
3. All variables referenced in `qsm.yml` must exist in `variables.tf`
4. All outputs referenced in `qsm.yml` must exist in `outputs.tf` and start with `QOVERY_`
5. Run `terraform init -backend=false && terraform validate` locally
6. Open a PR -- CI validates everything automatically
