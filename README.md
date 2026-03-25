# Qovery Service Catalog

Pre-built blueprints for provisioning cloud resources and Kubernetes services through the Qovery catalog. Each blueprint is a **QSM manifest** (`qsm.yml`) paired with **Terraform files** or **Helm values**.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full design (provisioning flow, two-step diff, StackBlueprint orchestration, engine integration).

## How It Works

1. User browses the catalog in the Console -- q-core serves QSM manifests to render variable forms
2. User fills in variables, submits
3. q-core forwards the **repo URL + tag + filled variables** to the engine
4. Engine clones the blueprint, reads the QSM, interpolates variables, runs `terraform plan` / `helm diff`
5. Plan streamed back to user -- user reviews the diff
6. User approves -- engine applies
7. Resources created, service tracked in catalog

q-core is thin (serves QSM, forwards variables, stores plans, orchestrates stacks). The engine does the heavy lifting (clone, read QSM, interpolate, plan, apply). The engine needs a **new CatalogService type** for this.

## Blueprint Structure

| Engine | Blueprint contains | Example |
|--------|-------------------|---------|
| `terraform` / `opentofu` | `qsm.yml` + `.tf` files | [`examples/aws-s3`](examples/aws-s3) |
| `helm` | `qsm.yml` + `values.yaml` | [`examples/helm-redis`](examples/helm-redis) |

## Engine & Provider

`spec.engine` determines what runs. `spec.provider` (terraform/opentofu only) determines which credentials the engine injects.

| `spec.engine` | `spec.provider` | What runs | Credentials |
|---|---|---|---|
| `terraform` | `aws` | Terraform CLI | AWS access key/secret |
| `terraform` | `gcp` | Terraform CLI | GCP service account JSON |
| `terraform` | `azure` | Terraform CLI | Azure SP credentials |
| `terraform` | `qovery` | Terraform CLI | Qovery API token |
| `terraform` | `helm` | Terraform CLI (helm provider) | Kubeconfig |
| `opentofu` | *(same as terraform)* | OpenTofu CLI | *(same)* |
| `helm` | *(none)* | Helm CLI | Kubeconfig |

## QSM Quick Reference

### ServiceBlueprint (Terraform)

```yaml
apiVersion: "qovery.com/v2"
kind: ServiceBlueprint

metadata:
  name: "aws-s3"
  version: "1.0.0"
  description: "S3 bucket with encryption and versioning"
  categories: ["storage", "s3"]

spec:
  engine: terraform
  provider: aws

  qoveryVariables:
    - name: "region"
      source: "cluster.region"
      overridable: true

  userVariables:
    - name: "bucket_name"
      type: "string"
      required: true

  outputs:
    - name: "bucket_arn"
      sensitive: false
```

### ServiceBlueprint (Helm)

```yaml
apiVersion: "qovery.com/v2"
kind: ServiceBlueprint

metadata:
  name: "helm-redis"
  version: "1.0.0"
  categories: ["cache", "redis"]

spec:
  engine: helm

  chart:
    repository: "https://charts.bitnami.com/bitnami"
    name: "redis"
    version: "19.x"

  userVariables:
    - name: "replica_count"
      type: "number"
      default: "1"

  outputs:
    - name: "redis_host"
```

### StackBlueprint

Composes ServiceBlueprints from one or more catalog repos. Each service specifies its `url` (required). Users fill variables for every service in the Console before provisioning.

```yaml
apiVersion: "qovery.com/v2"
kind: StackBlueprint

metadata:
  name: "production-stack"
  version: "1.0.0"

spec:
  stages:
    - name: "databases"
      description: "Provision databases and caches first"
      services:
        - blueprint: "aws-postgresql"
          url: "https://github.com/my-org/my-catalog.git"
          version: ">=1.0.0 <2.0.0"
          name: "main-db"
        - blueprint: "aws-redis"
          url: "https://github.com/Qovery/service-catalog.git"
          version: "1.x"
          name: "cache"
    - name: "applications"
      description: "Deploy application after databases are ready"
      services:
        - blueprint: "container-app"
          url: "https://github.com/Qovery/service-catalog.git"
          version: "1.0.0"
          name: "api"
```

Stages run sequentially. Services within a stage run in parallel.

## Versioning

Git-tag-based semver: `{blueprint-name}/{major}.{minor}.{patch}`

```
aws-s3/1.0.0
helm-redis/1.1.0
```

| Change | Minor/Patch | Major |
|--------|-------------|-------|
| Add variable with default | Yes | -- |
| Add variable without default | -- | Yes |
| Remove/rename variable | -- | Yes |
| Add output | Yes | -- |
| Remove output | -- | Yes |
| Change engine or provider | -- | Yes |
| Metadata only (icon, description) | Instant, no diff | -- |

## Contributing

1. Create a directory under `examples/{name}/`
2. Add `qsm.yml` + Terraform files or Helm values
3. Open a PR -- CI validates

### Releasing

```bash
git tag aws-s3/1.0.0
git push origin aws-s3/1.0.0
```
