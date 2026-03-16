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
5. q-core loads existing TF state + fetches new blueprint version
6. Engine runs `terraform plan` (new TF files against existing state)
7. Plan shows what changes (e.g., `+ aws_s3_bucket_lifecycle_configuration.this`)
8. Customer reviews → approves (or rejects)
9. Engine runs `terraform apply plan.bin`
10. State updated, `catalog_blueprint_version` bumped to `1.1.0`

### If the customer doesn't upgrade

Nothing happens. Service stays pinned to `1.0.0`. Badge stays visible.

---

## 2. Where things run and live

### TF state

- Each provisioned stack gets its own TF state
- Stored in Kubernetes backend (Secret on customer's cluster, dedicated namespace)
- Keyed by unique instance identifier (not blueprint name)
- On upgrade, engine loads this state so `terraform plan` produces accurate diff

### TF runner

- Runs on **Qovery's infrastructure** (engine)
- Credentials injected based on `spec.provider`:
  - `aws` → cluster's AWS creds → engine talks directly to AWS APIs
  - `qovery` → org-scoped API token → engine talks to Qovery API
  - `helm` → kubeconfig → engine talks to customer's K8s cluster
- Token/credential scoping ensures isolation between customers
- State read/write goes through K8s API of the customer's cluster

---

## 3. Service-to-blueprint binding

Every provisioned instance is tracked by a **catalog_service** record in q-core's DB:

- `id` -- unique instance identifier
- `environment_id` -- target environment
- `blueprint_name` -- e.g. `aws-s3`
- `blueprint_version` -- version at provisioning time
- `terraform_state_ref` -- reference to K8s Secret holding TF state
- `variables` -- user-provided values

### How it works

1. q-core creates `catalog_service` record before running terraform
2. TF state (containing resource IDs) linked via `terraform_state_ref`
3. Console reads `catalog_service` record → shows catalog badge + upgrade status

That's it. The `catalog_service` record is the single source of truth for "this service was created from blueprint X at version Y." No annotations on individual resources needed.

### Destroy

1. "Destroy" → `terraform plan -destroy` → user reviews → approves
2. `terraform apply plan.bin` destroys all resources
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
