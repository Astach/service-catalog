# Service Catalog -- Design

> **Date:** 2026-03-17

---

## Overview

Blueprints are standard Terraform modules with a `qsm.yml` manifest. `spec.provider` determines which credentials the engine injects (AWS, GCP, Qovery, Helm, etc.). All blueprints follow the same plan → review → approve → apply workflow.

---

## Architecture

```mermaid
graph TB
    Console["Console"]

    subgraph qcore["q-core"]
        CatalogApi["CatalogApi"]
        PlanService["PlanService"]
        BlueprintRegistry["BlueprintRegistry"]
        Cache["Cache"]
    end

    subgraph engine["Engine"]
        PlanRunner["terraform plan"]
        ApplyRunner["terraform apply"]
    end

    GitHub["GitHub API"]
    Repo["Blueprint Repo"]
    PlanStore[("Plan Store")]
    Target["Target<br/>(AWS, Qovery API,<br/>K8s for Helm)"]

    Console -->|"POST /catalog/plan"| CatalogApi
    CatalogApi --> BlueprintRegistry
    BlueprintRegistry --> Cache
    BlueprintRegistry --> GitHub --> Repo
    CatalogApi --> PlanService --> PlanStore
    PlanService -->|"plan"| PlanRunner --> PlanStore

    Console -->|"POST /catalog/plans/{id}/approve"| CatalogApi
    CatalogApi --> PlanService
    PlanService -->|"apply"| ApplyRunner --> Target
```

### Credential Injection

The engine reads `spec.provider` from the QSM and injects the appropriate credentials before running Terraform:

| `spec.provider` | Injected credentials |
|---|---|
| `aws` | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` (from cluster config) |
| `gcp` | `GOOGLE_CREDENTIALS` (from cluster config) |
| `azure` | `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, etc. (from cluster config) |
| `qovery` | `QOVERY_API_TOKEN` (org-scoped) |
| `helm` | `KUBECONFIG` (from cluster) |

For StackBlueprints with mixed providers, the engine injects all needed credentials.

---

## Workflow

```
1. BROWSE    → User selects a blueprint
2. CONFIGURE → User fills in variables (qoveryVariables pre-filled)
3. PLAN      → Engine runs terraform plan, stores JSON + binary planfile
4. REVIEW    → User sees what will be created/changed/destroyed
5. APPROVE   → User approves
6. APPLY     → Engine runs terraform apply plan.bin
7. DONE      → Resources created, service tracked in catalog DB
```

### Provisioning Sequence

```mermaid
sequenceDiagram
    actor User
    participant Console
    participant qcore as q-core
    participant Engine
    participant PlanStore as Plan Store
    participant Target as Target (AWS/Qovery/K8s)

    User ->> Console: Select blueprint + fill variables
    Console ->> qcore: POST /catalog/plan

    Note over qcore: Fetch blueprint, resolve qoveryVariables,<br/>merge with user vars, generate tfvars

    qcore ->> Engine: terraform plan -out=plan.bin
    Engine -->> qcore: Plan JSON

    qcore ->> PlanStore: Store (PENDING_REVIEW)
    qcore -->> Console: {plan_id, summary}
    Console -->> User: Show plan diff

    User ->> Console: Approve
    Console ->> qcore: POST /catalog/plans/{id}/approve

    qcore ->> Engine: terraform apply plan.bin
    Engine ->> Target: Create resources
    Engine -->> qcore: Done

    qcore ->> PlanStore: APPLIED
    Console -->> User: Resources created
```

### Plan States

```mermaid
flowchart TD
    A["PENDING_REVIEW"] --> B{"User action"}
    B -->|"Approve"| C["APPROVED → APPLYING → APPLIED"]
    B -->|"Reject"| D["REJECTED"]
    B -->|"No action 1h"| E["EXPIRED"]
    B -->|"Re-plan"| F["SUPERSEDED"]
    C -->|"Failure"| G["FAILED"]
```

---

## Plan Object

| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID | Plan identifier |
| `blueprint_name` | String | e.g. `aws-s3` |
| `blueprint_version` | String | e.g. `1.0.0` |
| `environment_id` | UUID | Target environment |
| `variables` | JSON | User-provided values |
| `plan_json` | JSON | `terraform show -json` output |
| `plan_binary` | Blob | Binary planfile for exact apply |
| `status` | Enum | `PENDING_REVIEW`, `APPROVED`, `APPLYING`, `APPLIED`, `REJECTED`, `EXPIRED`, `FAILED`, `SUPERSEDED` |
| `created_at` | Timestamp | |
| `expires_at` | Timestamp | Auto-expire after 1h |
| `terraform_state_id` | UUID | TF state reference (for upgrades) |

---

## QSM Spec

### ServiceBlueprint

```yaml
apiVersion: "qovery.com/v2"
kind: ServiceBlueprint

metadata:
  name: "aws-s3"
  version: "1.0.0"
  description: "S3 bucket"

spec:
  provider: "aws"          # credential selector
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

### StackBlueprint

A StackBlueprint composes existing ServiceBlueprints. No Terraform files -- just orchestration.

```yaml
apiVersion: "qovery.com/v2"
kind: StackBlueprint

metadata:
  name: "production-stack"
  version: "1.0.0"
  categories: ["stack", "database", "cache"]

spec:
  stages:
    - name: "databases"
      services:
        - blueprint: "aws-postgresql"
          version: ">=1.0.0 <2.0.0"
          alias: "main-db"
          variables:
            instance_class: "db.r6g.large"
        - blueprint: "aws-redis"
          version: "1.x"
          alias: "cache"
    - name: "applications"
      services:
        - blueprint: "container-app"
          version: "1.0.0"
          alias: "api"
```

- Stages execute sequentially. Services in the same stage run in parallel.
- Each service gets its own independent `terraform plan` and TF state.
- `qoveryVariables` resolved per-service from the referenced blueprint.
- `variables` override the ServiceBlueprint's defaults.
- Version constraints: exact (`"1.2.0"`), train (`"1.x"`), range (`">=1.0.0 <2.0.0"`).

### Metadata-Only Updates

When a new version only changes `metadata` (description, icon, categories) and `spec` is identical, q-core updates the catalog entry immediately. No plan/apply, no engine run.

---

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/catalog/plan` | Create a plan |
| `GET` | `/catalog/plans/{id}` | Get plan details |
| `POST` | `/catalog/plans/{id}/approve` | Approve and apply |
| `POST` | `/catalog/plans/{id}/reject` | Reject |

---

## Engine Integration

### Plan Phase

```bash
# Credentials already injected based on spec.provider
terraform init
terraform plan -out=plan.bin -var-file=user.tfvars
terraform show -json plan.bin > plan.json
```

### Apply Phase

```bash
terraform apply plan.bin
```

Binary planfile ensures what the user approved is exactly what gets applied.

### State

Each stack gets its own TF state in Kubernetes backend (Secret on customer's cluster). Linked to the `catalog_service` record for upgrades.
