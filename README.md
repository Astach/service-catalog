# Qovery Service Catalog

Pre-built blueprints for provisioning cloud resources and Qovery services through the catalog. Uses **Terraform** with a **plan → review → approve** workflow. Supports any Terraform provider (AWS, GCP, Helm, Qovery, etc.).

## How It Works

1. User selects a blueprint from the catalog
2. Fills in variables (Qovery variables are pre-filled from cluster/env context)
3. Engine runs `terraform plan` -- user reviews what will be created/changed/destroyed
4. User approves -- engine runs `terraform apply`
5. Resources created. Service tracked in the catalog DB (blueprint name + version + TF state).

## Repository Structure

```
service-catalog/
├── v2/
│   ├── examples/
│   │   ├── aws-s3/                    # S3 bucket (provider: aws)
│   │   ├── managed-postgresql/        # Managed DB (provider: qovery)
│   │   ├── helm-prometheus/           # Prometheus stack (provider: helm)
│   │   └── web-app-with-database/     # App + DB + Redis stack (StackBlueprint, qsm.yml only)
│   ├── DESIGN.md
│   └── OPERATIONS.md
├── schemas/
│   └── qsm-schema.json
├── diagrams/
│   └── workflows.md
└── PLAN.md
```

Each blueprint contains:

| File | Description |
|------|-------------|
| `main.tf` | Terraform resources (any provider) |
| `variables.tf` | Qovery + user variables |
| `outputs.tf` | Terraform outputs |
| `providers.tf` | Provider configuration |
| `qsm.yml` | Qovery Service Manifest |

## Providers

`spec.provider` in the QSM determines what credentials the engine injects:

| Provider | What blueprints create | Credentials |
|----------|----------------------|-------------|
| `aws` | S3, RDS, SQS, IAM, ELB... (any `aws_*` resource) | AWS creds from cluster config |
| `gcp` | GCS, Cloud SQL, Pub/Sub... (any `google_*` resource) | GCP SA from cluster config |
| `azure` | Storage, SQL, Service Bus... (any `azurerm_*` resource) | Azure SP from cluster config |
| `qovery` | Databases, containers, apps, jobs... (`qovery_*` resources) | `QOVERY_API_TOKEN` |
| `helm` | Any Helm chart via `helm_release` | Kubeconfig from cluster |

---

## Why Not Use the Qovery Terraform Provider for Everything?

An earlier iteration of this catalog used the Qovery Terraform provider (`Qovery/qovery`) as the sole blueprint engine. Every service -- databases, containers, apps -- was declared as `qovery_*` resources. This sounded clean but has fundamental problems:

### 1. Limited resource coverage

The Qovery provider supports a fixed set of service types (`qovery_database`, `qovery_container`, `qovery_application`, `qovery_helm`, `qovery_job`). It does **not** expose raw cloud resources. There is no `qovery_s3_bucket`, no `qovery_sqs_queue`, no `qovery_load_balancer`. Every new cloud service would need to be implemented in the provider first -- a Go resource, an API endpoint, and backend logic -- before it could appear in the catalog.

### 2. Double maintenance burden

To add a new service (say SQS) to the catalog, you'd need to:
1. Add a `qovery_sqs_queue` resource to the Qovery Terraform provider (Go)
2. Add the corresponding API endpoint to q-core
3. Add the backend provisioning logic
4. **Then** write the catalog blueprint

With native providers, step 1 is just writing `aws_sqs_queue` in a `.tf` file. Done.

### 3. Qovery-specific abstractions leak into user-facing config

The Qovery provider has its own conventions. `qovery_database` uses `mode = "MANAGED"`, `type = "POSTGRESQL"`, `accessibility = "PRIVATE"` -- these are Qovery-specific field names that don't match AWS/GCP/Azure terminology. Users who know AWS have to learn Qovery's abstraction layer instead of using the resources they already understand.

### 4. Customers can't bring their own blueprints

If the catalog only speaks `qovery_*`, customers can't contribute or customize blueprints using standard Terraform knowledge. They'd need to learn the Qovery provider's resource model. With native providers, a customer who has an existing Terraform module for RDS or S3 can wrap it in a QSM and add it to the catalog with minimal changes.

### 5. The Qovery provider is a middleman, not a simplification

For managed databases, the Qovery provider calls the Qovery API, which calls the cloud provider API. It adds a layer of indirection without adding value for the catalog use case. The plan shows `qovery_database` instead of `aws_db_instance`, which is **less** informative -- the user loses visibility into what's actually being created in their cloud account.

### What the Qovery provider IS good for

The Qovery provider makes sense for managing **Qovery-native concepts**: environments, deployment stages, deployment triggers, container registries, projects. These are things that only exist in Qovery and have no cloud-native equivalent. Blueprints with `provider: "qovery"` are appropriate for these.

---

## QSM (Qovery Service Manifest)

Every blueprint has a `qsm.yml`:

```yaml
apiVersion: "qovery.com/v2"
kind: ServiceBlueprint       # or StackBlueprint

metadata:
  name: "aws-s3"
  version: "1.0.0"
  description: "S3 bucket with encryption"
  icon: "https://..."
  categories: ["storage"]

spec:
  provider: "aws"             # credential selector

  qoveryVariables:            # auto-filled from cluster/env context
    - name: "region"
      source: "cluster.region"
      overridable: true       # user can override (default: false)

  userVariables:              # shown in provisioning form
    - name: "bucket_name"
      type: "string"
      required: true
      description: "S3 bucket name"

  outputs:
    - name: "bucket_arn"
      description: "Bucket ARN"
      sensitive: false
```

### StackBlueprint

StackBlueprints compose existing ServiceBlueprints. They have no Terraform files -- just a QSM that references catalog blueprints, pre-configures variables, and defines deployment stages.

```yaml
apiVersion: "qovery.com/v2"
kind: StackBlueprint

metadata:
  name: "production-stack"
  version: "1.0.0"
  categories: ["stack", "database"]

spec:
  stages:
    - name: "databases"
      services:
        - blueprint: "aws-postgresql"
          version: ">=1.0.0 <2.0.0"
          alias: "main-db"
          variables:
            instance_class: "db.r6g.large"
    - name: "applications"
      services:
        - blueprint: "container-app"
          version: "1.0.0"
          alias: "api"
```

Stages execute sequentially. Services within a stage run in parallel. Each service gets its own independent plan and TF state. Version constraints: exact (`"1.2.0"`), train (`"1.x"`), or range (`">=1.0.0 <2.0.0"`).

---

## Versioning

Git-tag-based semver: `{blueprint-name}/{major}.{minor}.{patch}`

```
aws-s3/1.0.0
managed-postgresql/1.1.0
helm-prometheus/1.0.0
```

- **Minor/patch**: additive only (new variables with defaults, new outputs, changed defaults)
- **Major**: breaking changes (removed/renamed variables or outputs, provider change)
- Metadata-only changes (icon, description, categories) update instantly -- no plan/apply needed

---

## Contributing

### Adding a Blueprint

1. Create a directory under `v2/examples/{name}/`
2. Write `main.tf`, `variables.tf`, `outputs.tf`, `providers.tf`, `qsm.yml`
3. Open a PR -- CI validates

### Releasing

```bash
git tag aws-s3/1.0.0
git push origin aws-s3/1.0.0
```
