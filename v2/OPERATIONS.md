# Operations -- How It Actually Works

---

## 1. Catalog update propagation

**Scenario:** Blueprint `aws-s3` bumped from `1.0.0` to `1.1.0`. A customer has a bucket provisioned from `1.0.0`.

### Detection

1. Developer pushes tag `aws-s3/1.1.0`
2. GitHub webhook → q-core invalidates version index cache
3. Next time customer views their service → `upgrade_available: true`

### Review & Apply

4. Customer clicks "Review Update"
5. q-core resolves variables, sends blueprint reference (repo + new tag) to **TF runner**
6. TF runner clones the blueprint at the new tag, runs `terraform plan` against existing S3 state → streams diff back
7. Plan shows what changes (e.g., `+ aws_s3_bucket_lifecycle_configuration.this`)
8. Customer reviews → approves (or rejects)
9. q-core forwards plan binary to the **engine** → engine runs `terraform apply plan.bin`
10. State updated, `catalog_blueprint_version` bumped to `1.1.0`

### If the customer doesn't upgrade

Nothing happens. Service stays pinned to `1.0.0`. Badge stays visible.

---

## 2. Where things run and live

### TF state

- Each provisioned stack gets its own TF state
- Stored in **S3 backend** (dedicated bucket, one key per instance)
- Key format: `catalog/{instance_id}/terraform.tfstate`
- Optional DynamoDB table for state locking
- Encryption at rest enabled by default
- Both the TF runner (plan) and the engine (apply) use the same S3 backend config

### TF runner (plan only)

- **Rust gRPC service** packaged with the Terraform CLI + git in a single Docker image (`runner/`)
- Runs on **Qovery's infrastructure**, not on the customer's cluster
- **Only runs `terraform plan`** -- never apply or destroy
- q-core sends a **blueprint reference** (repo URL + git tag + subdirectory path) + variables + S3 backend config via gRPC
- Runner **shallow-clones the blueprint repo** at the specified tag, reads .tf files from the subdirectory
- Injects `backend.tf` and `terraform.tfvars.json` into the workspace
- Runs `terraform init` + `terraform plan`, streams stdout/stderr back in real-time
- Returns the raw `terraform show -json` diff + binary planfile
- q-core stores the plan JSON (for the UI) and binary planfile (for the engine to apply)
- Fallback: q-core can send pre-assembled files directly instead of a git reference
- Credentials injected as environment variables based on `spec.provider`:
  - `aws` → `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` (from cluster config)
  - `qovery` → `QOVERY_API_TOKEN` (org-scoped)
  - `helm` → `KUBECONFIG` (from cluster)
- Runner needs S3 read access to the state bucket (for `terraform init` to load current state)
- Only public git repos are supported (no git auth token for now)

### Engine (apply / destroy)

- Runs on the **customer's cluster** (existing engine infrastructure)
- Receives the approved plan binary from q-core after user approval
- Runs `terraform apply plan.bin` or `terraform plan -destroy` + `terraform apply`
- Has direct access to the target cloud provider (AWS, GCP, etc.) via injected credentials
- Can create resources outside of Kubernetes (S3 buckets, RDS instances, etc.) -- the engine's existing `TerraformInfraResources` pattern supports this
- Resources created by the engine live in the customer's cloud account, tied to their cluster

### Service location

A catalog service is always tied to a specific Qovery environment:

- Environment → namespace in a K8s cluster, or a standalone cluster
- Resources created via catalog (e.g., an S3 bucket, an RDS instance) are created in the cloud account associated with that cluster
- The `catalog_service` record in q-core links: `environment_id` → `cluster` → cloud account
- This ensures resources are visible/reachable from the correct context, even though they may not live inside Kubernetes

---

## 3. Service-to-blueprint binding

Every provisioned instance is tracked by a **catalog_service** record in q-core's DB:

- `id` -- unique instance identifier
- `environment_id` -- target environment (maps to a cluster + namespace)
- `blueprint_name` -- e.g. `aws-s3`
- `blueprint_version` -- version at provisioning time
- `terraform_state_ref` -- S3 key for the TF state (e.g. `catalog/{id}/terraform.tfstate`)
- `variables` -- user-provided values

### How it works

1. q-core creates `catalog_service` record before running terraform
2. TF state (containing resource IDs) linked via `terraform_state_ref`
3. Console reads `catalog_service` record → shows catalog badge + upgrade status

That's it. The `catalog_service` record is the single source of truth for "this service was created from blueprint X at version Y." No annotations on individual resources needed.

### Destroy

1. "Destroy" → q-core sends blueprint to TF runner → `terraform plan -destroy` → user reviews → approves
2. q-core sends destroy plan binary to engine → `terraform apply plan.bin` destroys all resources
3. `catalog_service` marked destroyed, state cleaned up

---

## 4. Infrastructure scope

Blueprints can create **any resource** supported by their declared Terraform provider:

| Provider | Example resources |
|----------|------------------|
| `aws` | `aws_s3_bucket`, `aws_db_instance`, `aws_sqs_queue`, `aws_lb`, `aws_iam_role` |
| `gcp` | `google_storage_bucket`, `google_sql_database_instance`, `google_pubsub_topic` |
| `azure` | `azurerm_storage_account`, `azurerm_mssql_database`, `azurerm_servicebus_namespace` |
| `qovery` | `qovery_database`, `qovery_container`, `qovery_application` |
| `helm` | `helm_release` (any Helm chart) |

There is no limitation to a fixed set of resources. If a Terraform provider supports it, a blueprint can create it.

---

## 5. Metadata-only updates

When a new version only changes `metadata` (description, icon, categories) and `spec` is unchanged:

1. q-core compares `spec` of old vs new version
2. Specs identical → metadata-only update
3. `catalog_service` record updated immediately (new version + metadata)
4. No plan/apply, no engine run, no downtime
5. Console reflects changes instantly
