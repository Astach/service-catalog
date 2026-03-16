# Service Catalog -- Mermaid Diagrams

---

## 1. High-Level Architecture

```mermaid
graph TB
    Console["Console"]

    subgraph qcore["q-core"]
        CatalogApi["CatalogApi"]
        PlanService["PlanService"]
        BlueprintRegistry["BlueprintRegistry"]
        Cache["Cache + Version Index"]
    end

    subgraph engine["Engine"]
        PlanRunner["terraform plan → JSON"]
        ApplyRunner["terraform apply plan.bin"]
    end

    GitHub["GitHub API"]
    Repo["Blueprint Repo"]
    PlanStore[("Plan Store")]
    AWS["AWS"]
    QoveryAPI["Qovery API"]
    K8s["K8s (Helm)"]

    Console -->|"POST /catalog/plan"| CatalogApi
    CatalogApi --> BlueprintRegistry
    BlueprintRegistry --> Cache
    BlueprintRegistry --> GitHub --> Repo
    CatalogApi --> PlanService --> PlanStore
    PlanService -->|"plan"| PlanRunner --> PlanStore

    Console -->|"POST /catalog/plans/{id}/approve"| CatalogApi
    CatalogApi --> PlanService
    PlanService -->|"apply"| ApplyRunner
    ApplyRunner -->|"provider: aws"| AWS
    ApplyRunner -->|"provider: qovery"| QoveryAPI
    ApplyRunner -->|"provider: helm"| K8s
```

---

## 2. Provisioning Sequence

```mermaid
sequenceDiagram
    actor User
    participant Console
    participant qcore as q-core
    participant Engine
    participant PlanStore as Plan Store
    participant Target as Target (AWS/Qovery/K8s)

    User ->> Console: Select blueprint + fill variables
    Console ->> qcore: POST /catalog/plan<br/>{blueprint, version, vars}

    Note over qcore: Fetch blueprint, resolve qoveryVariables,<br/>merge with user vars, generate tfvars,<br/>inject credentials based on spec.provider

    qcore ->> Engine: terraform plan -out=plan.bin
    Engine -->> qcore: Plan JSON

    qcore ->> PlanStore: Store (PENDING_REVIEW)
    qcore -->> Console: {plan_id, summary}
    Console -->> User: Show plan diff

    User ->> Console: Approve
    Console ->> qcore: POST /catalog/plans/{id}/approve

    qcore ->> Engine: terraform apply plan.bin
    Engine ->> Target: Create resources
    Engine -->> qcore: Done + outputs

    qcore ->> PlanStore: APPLIED
    Console -->> User: Resources created
```

---

## 3. Cache & Webhook

```mermaid
sequenceDiagram
    actor Dev as Developer
    participant GitHub
    participant qcore as q-core
    participant Cache

    Dev ->> GitHub: Push tag aws-s3/1.1.0
    GitHub ->> qcore: POST /internal/catalog/webhook
    qcore ->> Cache: Invalidate all
    Note over qcore: Next request rebuilds from GitHub API
```

---

## 4. Upgrade Flow

```mermaid
sequenceDiagram
    actor User
    participant Console
    participant qcore as q-core
    participant Engine
    participant Target as Target

    User ->> Console: Click "Upgrade to v1.1.0"
    Console ->> qcore: POST /catalog/plan<br/>{blueprint, version: "1.1.0",<br/>existing_state_id: "..."}

    Note over qcore: Load existing TF state

    qcore ->> Engine: terraform plan (new version vs existing state)
    Engine -->> qcore: Plan diff

    Console -->> User: Show what changes

    User ->> Console: Approve
    qcore ->> Engine: terraform apply plan.bin
    Engine ->> Target: Update/create resources
    Console -->> User: Upgraded
```

---

## 5. Release Workflow

```mermaid
flowchart TD
    A["Update blueprint + bump version"] --> B["Open PR"]
    B --> C{"CI validates"}
    C -->|Pass| D["Merge"]
    C -->|Fail| E["Fix"] --> C
    D --> F["Tag + push"]
    F --> G{"Release CI"}
    G -->|Pass| H["Webhook → cache invalidated"]
    G -->|Fail| I["Delete tag, fix, re-tag"] --> F
    H --> J["Live in catalog"]
```

---

## 6. Version Resolution

```mermaid
flowchart TD
    A["Request a blueprint version"] --> B{"Format?"}
    B -->|"Exact: '1.2.0'"| C["Resolve tag → commit SHA"]
    B -->|"Train: '1.x'"| D["List tags → filter major=1 → latest"]
    D --> C
    B -->|"Range: '>=1.1.0 <2.0.0'"| E["List tags → filter by constraint → latest"]
    E --> C
    C --> F["Pin SHA for deterministic deploys"]
```

---

## 7. Plan States

```mermaid
flowchart TD
    A["PENDING_REVIEW"] --> B{"Action"}
    B -->|"Approve"| C["APPROVED → APPLYING → APPLIED"]
    B -->|"Reject"| D["REJECTED"]
    B -->|"Timeout 1h"| E["EXPIRED"]
    B -->|"Re-plan"| F["SUPERSEDED"]
    C -->|"Failure"| G["FAILED"]
```

---

## 8. User Journey -- Provision

```mermaid
flowchart TD
    A["Select blueprint"] --> B["Fill variables<br/>(qoveryVars pre-filled)"]
    B --> C["Engine runs terraform plan"]
    C --> D["Review plan diff"]
    D --> E{"Approve?"}
    E -->|Yes| F["terraform apply"]
    E -->|No| G["Reject / re-configure"]
    F --> H["Done"]
```

---

## 9. User Journey -- Upgrade

```mermaid
flowchart TD
    A["'Update available' badge"] --> B["Click 'Review'"]
    B --> C["terraform plan<br/>(new version vs existing state)"]
    C --> D["Review diff"]
    D --> E{"Approve?"}
    E -->|Yes| F["terraform apply"]
    E -->|No| G["Stay on current version"]
    F --> H["Upgraded"]
```

---

## 10. Credential Injection

```mermaid
flowchart TD
    QSM["Read spec.provider<br/>from qsm.yml"] --> Switch{"Provider?"}
    Switch -->|"aws"| AWS["Inject AWS_ACCESS_KEY_ID<br/>AWS_SECRET_ACCESS_KEY<br/>(from cluster config)"]
    Switch -->|"gcp"| GCP["Inject GOOGLE_CREDENTIALS<br/>(from cluster config)"]
    Switch -->|"azure"| AZ["Inject ARM_CLIENT_ID<br/>ARM_CLIENT_SECRET<br/>(from cluster config)"]
    Switch -->|"qovery"| QOV["Inject QOVERY_API_TOKEN<br/>(org-scoped)"]
    Switch -->|"helm"| HELM["Inject KUBECONFIG<br/>(from cluster)"]
    AWS --> TF["terraform plan / apply"]
    GCP --> TF
    AZ --> TF
    QOV --> TF
    HELM --> TF
```
