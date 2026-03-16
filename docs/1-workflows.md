# Service Catalog Workflows

## Table of Contents

1. [Browse Catalog](#1-browse-catalog)
2. [Provision a Terraform Service](#2-provision-a-terraform-service)
3. [Provision a Helm Service (future)](#3-provision-a-helm-service-future)

---

## 1. Browse Catalog

### Actors

- **Console (React)**: The UI the user interacts with.
- **q-core**: Backend API that fetches and caches blueprint data.
- **GitHub API**: Source of truth for the `service-catalog` repository.

### Sequence

```
 Console                        q-core                           GitHub API
   |                              |                                  |
   | GET /catalog/blueprints      |                                  |
   |  ?provider=aws               |                                  |
   |  &category=database          |                                  |
   |----------------------------->|                                  |
   |                              |                                  |
   |                              |  [cache hit?]                    |
   |                              |  YES -> filter & return          |
   |                              |  NO  -> fetch from GitHub        |
   |                              |                                  |
   |                              |  GET /repos/{owner}/{repo}/      |
   |                              |    contents/aws?ref=main         |
   |                              |--------------------------------->|
   |                              |  <- [aws/postgresql/, aws/redis/,|
   |                              |      aws/mysql/, aws/mongodb/]   |
   |                              |<---------------------------------|
   |                              |                                  |
   |                              |  For each directory:             |
   |                              |  GET /repos/{owner}/{repo}/      |
   |                              |    contents/aws/{name}/qsm.yml  |
   |                              |    ?ref=main                     |
   |                              |--------------------------------->|
   |                              |  <- qsm.yml content (Base64)    |
   |                              |<---------------------------------|
   |                              |                                  |
   |                              |  Parse YAML -> BlueprintManifest |
   |                              |  Populate in-memory cache        |
   |                              |  Filter by provider & category   |
   |                              |                                  |
   |  <- 200 ListBlueprintsResponse                                  |
   |  {blueprints: [              |                                  |
   |    {name: "aws-postgresql",  |                                  |
   |     displayed_name: "RDS     |                                  |
   |       Postgres",             |                                  |
   |     categories: ["database"],|                                  |
   |     engine: "terraform",     |                                  |
   |     ...},                    |                                  |
   |    ...                       |                                  |
   |  ]}                          |                                  |
   |<-----------------------------|                                  |
```

### Cache Invalidation

```
 service-catalog repo       GitHub              q-core
   |                          |                    |
   | git push to main         |                    |
   |------------------------->|                    |
   |                          |                    |
   | git tag aws-pg/1.2.0     |                    |
   |------------------------->|                    |
   |                          |                    |
   |                          | POST /internal/    |
   |                          |  catalog/webhook   |
   |                          | {ref: "refs/..."}  |
   |                          |------------------->|
   |                          |                    |
   |                          |                    | Clear in-memory
   |                          |                    | cache (all entries)
   |                          |                    |
   |                          |                    | Next request:
   |                          |                    |  -> cache miss
   |                          |                    |  -> re-fetch from
   |                          |                    |     GitHub API
```

### Get Blueprint Detail

```
 Console                        q-core
   |                              |
   | GET /catalog/blueprints/     |
   |     aws-postgresql           |
   |----------------------------->|
   |                              |
   |                              | Lookup "aws-postgresql" in cache
   |                              | (or fetch aws/postgresql/qsm.yml
   |                              |  from GitHub if cache miss)
   |                              |
   |  <- 200 BlueprintDetailResponse
   |  {                           |
   |    name: "aws-postgresql",   |
   |    displayed_name: "RDS Postgres",
   |    categories: ["database"], |
   |    engine: "terraform",      |
   |    version: "1.0.0",         |
   |    injected_variables: [     |
   |      {name: "region",        |
   |       source: "cluster.region"},
   |      ...                     |
   |    ],                        |
   |    user_variables: [         |
   |      {name: "instance_class",|
   |       type: "string",        |
   |       required: false,       |
   |       default: "db.t3.micro",|
   |       options: [...]},       |
   |      ...                     |
   |    ],                        |
   |    outputs: [                |
   |      {name: "QSM_POSTGRESQL_HOST",
   |       sensitive: false},     |
   |      ...                     |
   |    ]                         |
   |  }                           |
   |<-----------------------------|
```

---

## 2. Provision a Terraform Service

### User Journey (3 steps)

**Step 1** -- Name the service
**Step 2** -- Fill user variables (dynamic form from qsm.yml). Injected variables are shown as read-only context.
**Step 3** -- Review output aliases. Each `QSM_*` output gets a user-editable alias prefix.

### Sequence Diagram

```
 Console              q-core                                   Engine        Cloud
   |                    |                                        |              |
   | POST /environment/ |                                        |              |
   |  {envId}/catalog/  |                                        |              |
   |  provision         |                                        |              |
   | {                  |                                        |              |
   |   blueprint_name:  |                                        |              |
   |     "aws-postgresql",                                       |              |
   |   service_name:    |                                        |              |
   |     "my-database", |                                        |              |
   |   user_variables: {|                                        |              |
   |     instance_class:|                                        |              |
   |       "db.t3.small",                                        |              |
   |     password:      |                                        |              |
   |       "s3cur3!",   |                                        |              |
   |     ...            |                                        |              |
   |   },               |                                        |              |
   |   output_aliases: {|                                        |              |
   |     "QSM_POSTGRESQL_HOST":                                  |              |
   |       "MY_DATABASE",                                        |              |
   |     ...            |                                        |              |
   |   }                |                                        |              |
   | }                  |                                        |              |
   |---->               |                                        |              |
   |                    |                                        |              |
   |  ┌─────────────────────────────────────────────────────┐    |              |
   |  │ CreateTerraformFromCatalogUseCase                   │    |              |
   |  │                                                     │    |              |
   |  │ 1. Fetch blueprint manifest from cache              │    |              |
   |  │                                                     │    |              |
   |  │ 2. Validate user variables against qsm.yml:         │    |              |
   |  │    - required fields present                        │    |              |
   |  │    - types match (string/number/bool)               │    |              |
   |  │    - options valid (if dropdown)                    │    |              |
   |  │    - validation rules pass (min/max/pattern)        │    |              |
   |  │                                                     │    |              |
   |  │ 3. Resolve injected variables from context:         │    |              |
   |  │    cluster.name    -> KubernetesProvider.name       │    |              |
   |  │    cluster.region  -> KubernetesProvider.region     │    |              |
   |  │    cluster.vpc_id  -> InfrastructureOutputs.vpcId   │    |              |
   |  │    environment.id  -> Environment.id                │    |              |
   |  │    project.id      -> Environment.projectId         │    |              |
   |  │    organization.id -> Project.organizationId        │    |              |
   |  │                                                     │    |              |
   |  │ 4. Merge variables:                                 │    |              |
   |  │    injected + user-provided + defaults              │    |              |
   |  │    -> List<InputVariable>                           │    |              |
   |  │                                                     │    |              |
   |  │ 5. Build TerraformMutationRequest:                  │    |              |
   |  │    name = "my-database"                             │    |              |
   |  │    terraformFilesSource = Git(                      │    |              |
   |  │      catalogRepo@main,                              │    |              |
   |  │      rootModulePath = "aws/postgresql/"             │    |              |
   |  │    )                                                │    |              |
   |  │    engine = TERRAFORM                               │    |              |
   |  │    backend = KUBERNETES                             │    |              |
   |  │    useClusterCredentials = true                     │    |              |
   |  │    inputVariables = [merged vars]                   │    |              |
   |  │                                                     │    |              |
   |  │ 6. Call TerraformServiceCreationUseCase.create()    │    |              |
   |  │    -> validates, persists, creates builtin vars,    │    |              |
   |  │       assigns deployment stage                      │    |              |
   |  │                                                     │    |              |
   |  │ 7. Store catalog metadata on Terraform entity:      │    |              |
   |  │    catalog_blueprint_name = "aws-postgresql"        │    |              |
   |  │    catalog_blueprint_version = "1.0.0"              │    |              |
   |  │    catalog_output_aliases = {QSM_* -> alias map}    │    |              |
   |  │                                                     │    |              |
   |  │ 8. Trigger deploy via StartEnvironmentUseCase       │    |              |
   |  └─────────────────────────────────────────────────────┘    |              |
   |                    |                                        |              |
   |  <- 202 Accepted   |                                        |              |
   |  {terraform_id:    |                                        |              |
   |    "uuid-..."}     |                                        |              |
   |<-------------------|                                        |              |
   |                    |                                        |              |
   |                    |  Deployment queued                      |              |
   |                    |  -> Engine request via Redis            |              |
   |                    |--------------------------------------->|              |
   |                    |                                        |              |
   |                    |                     git shallow fetch   |              |
   |                    |                     catalog@main_sha   |              |
   |                    |                     cd aws/postgresql/  |              |
   |                    |                                        |              |
   |                    |                     terraform init      |              |
   |                    |                     terraform plan      |              |
   |                    |                     terraform apply     |              |
   |                    |                                        |------------->|
   |                    |                                        |<-------------|
   |                    |                                        |              |
   |                    |                     terraform output    |              |
   |                    |                     -json              |              |
   |                    |                     {                  |              |
   |                    |                       "QSM_POSTGRESQL_HOST":          |
   |                    |                         {value: "rds-abc.rds.amazonaws.com",
   |                    |                          sensitive: false},           |
   |                    |                       "QSM_POSTGRESQL_PORT":          |
   |                    |                         {value: "5432",               |
   |                    |                          sensitive: false},           |
   |                    |                       ...              |              |
   |                    |                     }                  |              |
   |                    |                                        |              |
   |                    |  gRPC: log event (TerraformServiceOutput)             |
   |                    |  payload = terraform output JSON       |              |
   |                    |<---------------------------------------|              |
   |                    |                                        |              |
   |  ┌─────────────────────────────────────────────────────┐    |              |
   |  │ EngineCoreConfigurationUpdateService                │    |              |
   |  │                                                     │    |              |
   |  │ 1. Existing behavior (unchanged):                   │    |              |
   |  │    Create BUILT_IN vars:                            │    |              |
   |  │      QOVERY_OUTPUT_TERRAFORM_ZABC_                  │    |              |
   |  │        QSM_POSTGRESQL_HOST = "rds-abc..."           │    |              |
   |  │    Create ALIAS vars:                               │    |              |
   |  │      QSM_POSTGRESQL_HOST -> QOVERY_OUTPUT_...       │    |              |
   |  │                                                     │    |              |
   |  │ 2. NEW -- Alias Bridge:                             │    |              |
   |  │    Load Terraform entity                            │    |              |
   |  │    Check catalog_output_aliases is not null         │    |              |
   |  │    For each QSM_* output:                           │    |              |
   |  │      QSM_POSTGRESQL_HOST                            │    |              |
   |  │        -> strip "QSM_" -> "POSTGRESQL_HOST"         │    |              |
   |  │        -> prepend alias "MY_DATABASE"               │    |              |
   |  │        -> "MY_DATABASE_POSTGRESQL_HOST"             │    |              |
   |  │      Check alias doesn't already exist              │    |              |
   |  │      Create ALIAS at ENVIRONMENT scope:             │    |              |
   |  │        MY_DATABASE_POSTGRESQL_HOST                   │    |              |
   |  │        -> QOVERY_OUTPUT_TERRAFORM_ZABC_             │    |              |
   |  │           QSM_POSTGRESQL_HOST                       │    |              |
   |  └─────────────────────────────────────────────────────┘    |              |
   |                    |                                        |              |
   |  <- WebSocket:     |                                        |              |
   |  deployment done   |                                        |              |
   |<-------------------|                                        |              |
```

### Resulting Environment Variables

After provisioning `aws-postgresql` with service name `my-database`:

| Variable Name | Type | Scope | Value |
|---|---|---|---|
| `QOVERY_OUTPUT_TERRAFORM_ZABC_QSM_POSTGRESQL_HOST` | BUILT_IN | ENVIRONMENT | `rds-abc.rds.amazonaws.com` |
| `QOVERY_OUTPUT_TERRAFORM_ZABC_QSM_POSTGRESQL_PORT` | BUILT_IN | ENVIRONMENT | `5432` |
| `QSM_POSTGRESQL_HOST` | ALIAS | ENVIRONMENT | -> `QOVERY_OUTPUT_TERRAFORM_ZABC_QSM_POSTGRESQL_HOST` |
| `QSM_POSTGRESQL_PORT` | ALIAS | ENVIRONMENT | -> `QOVERY_OUTPUT_TERRAFORM_ZABC_QSM_POSTGRESQL_PORT` |
| `MY_DATABASE_POSTGRESQL_HOST` | ALIAS | ENVIRONMENT | -> `QOVERY_OUTPUT_TERRAFORM_ZABC_QSM_POSTGRESQL_HOST` |
| `MY_DATABASE_POSTGRESQL_PORT` | ALIAS | ENVIRONMENT | -> `QOVERY_OUTPUT_TERRAFORM_ZABC_QSM_POSTGRESQL_PORT` |

Any service in the same environment can reference `MY_DATABASE_POSTGRESQL_HOST` to get the database hostname.

### Variable Resolution Order

When provisioning, variables are merged with this priority (highest wins):

```
1. Injected variables        (from cluster/environment context, always applied, never overridden)
2. User-provided values      (from the provisioning form)
3. qsm.yml defaults          (for optional variables not provided by the user)
```

---

## 3. Provision a Helm Service (future)

> **Status**: Spec only. Not in MVP.

### How It Differs from Terraform

| Aspect | Terraform Blueprint | Helm Blueprint |
|---|---|---|
| Engine | `terraform apply` | `helm upgrade --install` |
| Source | Git repo + root module path | Helm chart repository + chart name + version |
| Variables | Terraform `variables.tf` inputs | Helm `--set` values via `valuePath` mapping |
| Outputs | `terraform output -json` -> automatic | Engine reads K8s resources post-install -> manual source mapping |
| Backend | Kubernetes secrets (Terraform state) | Helm release (Tiller-less, stored in K8s secrets) |

### Sequence Diagram

```
 Console              q-core                                   Engine         K8s
   |                    |                                        |              |
   | POST /environment/ |                                        |              |
   |  {envId}/catalog/  |                                        |              |
   |  provision         |                                        |              |
   | {                  |                                        |              |
   |   blueprint_name:  |                                        |              |
   |     "k8s-prometheus",                                       |              |
   |   service_name:    |                                        |              |
   |     "monitoring",  |                                        |              |
   |   user_variables: {|                                        |              |
   |     retention_days:|                                        |              |
   |       "30",        |                                        |              |
   |     ...            |                                        |              |
   |   }                |                                        |              |
   | }                  |                                        |              |
   |------------------->|                                        |              |
   |                    |                                        |              |
   |  ┌─────────────────────────────────────────────────────┐    |              |
   |  │ CreateHelmFromCatalogUseCase                        │    |              |
   |  │                                                     │    |              |
   |  │ 1. Fetch blueprint (engine: "helm")                 │    |              |
   |  │                                                     │    |              |
   |  │ 2. Map userVariables to Helm --set values:          │    |              |
   |  │    retention_days has valuePath:                     │    |              |
   |  │      "prometheus.prometheusSpec.retention"           │    |              |
   |  │    -> setValues.add(valuePath, "30")                │    |              |
   |  │                                                     │    |              |
   |  │ 3. Register Helm repository if needed:              │    |              |
   |  │    "https://prometheus-community.github.io/..."     │    |              |
   |  │    -> find or create HelmRepositoryProvider         │    |              |
   |  │                                                     │    |              |
   |  │ 4. Build HelmRequest:                               │    |              |
   |  │    source = Repository(repoId, chartName, version)  │    |              |
   |  │    valuesOverride.set = [{valuePath: value}, ...]   │    |              |
   |  │    timeoutSec = helm.timeout                        │    |              |
   |  │                                                     │    |              |
   |  │ 5. Call HelmService.createHelm()                    │    |              |
   |  │    -> existing creation flow                        │    |              |
   |  │                                                     │    |              |
   |  │ 6. Store catalog metadata + output source specs     │    |              |
   |  │                                                     │    |              |
   |  │ 7. Trigger deploy                                   │    |              |
   |  └─────────────────────────────────────────────────────┘    |              |
   |                    |                                        |              |
   |  <- 202 Accepted   |                                        |              |
   |<-------------------|                                        |              |
   |                    |                                        |              |
   |                    | Engine request via Redis                |              |
   |                    |--------------------------------------->|              |
   |                    |                                        |              |
   |                    |                     helm upgrade        |              |
   |                    |                       --install         |              |
   |                    |                       monitoring        |              |
   |                    |                       kube-prometheus-  |              |
   |                    |                         stack           |              |
   |                    |                       --set prometheus. |              |
   |                    |                         prometheusSpec. |              |
   |                    |                         retention=30    |              |
   |                    |                                        |              |
   |                    |                                        |------------->|
   |                    |                                        |<-------------|
   |                    |                                        |              |
   |                    |              NEW: Post-install output   |              |
   |                    |              extraction step:           |              |
   |                    |                                        |              |
   |                    |              For each output source:    |              |
   |                    |              source: "service:          |              |
   |                    |                monitoring/prometheus-   |              |
   |                    |                server:9090"             |              |
   |                    |              -> kubectl get svc         |              |
   |                    |                 prometheus-server       |              |
   |                    |                 -n monitoring           |              |
   |                    |              -> extract ClusterIP:9090  |              |
   |                    |                                        |              |
   |                    |              Package as JSON:           |              |
   |                    |              {"QSM_PROMETHEUS_URL":     |              |
   |                    |                {value: "http://         |              |
   |                    |                  10.0.1.5:9090",        |              |
   |                    |                 sensitive: false}}      |              |
   |                    |                                        |              |
   |                    |  gRPC: log event (HelmServiceOutput)   |              |
   |                    |<---------------------------------------|              |
   |                    |                                        |              |
   |                    | Alias bridge (same as Terraform)       |              |
   |                    |                                        |              |
   |  <- deploy done    |                                        |              |
   |<-------------------|                                        |              |
```

### Helm Output Source Formats

The `outputs[].source` field in `qsm.yml` tells the engine where to read the value from Kubernetes after `helm install`:

| Source Format | Example | Engine Action |
|---|---|---|
| `configmap:{namespace}/{name}:{key}` | `configmap:monitoring/prometheus-config:url` | `kubectl get cm {name} -n {namespace} -o jsonpath='{.data.{key}}'` |
| `service:{namespace}/{name}:{port}` | `service:monitoring/prometheus-server:9090` | `kubectl get svc {name} -n {namespace}` -> extract ClusterIP + port |
| `secret:{namespace}/{name}:{key}` | `secret:monitoring/grafana-admin:password` | `kubectl get secret {name} -n {namespace} -o jsonpath='{.data.{key}}'` (base64 decoded) |

### Helm Variable Mapping

Unlike Terraform where variables map 1:1 to `variables.tf` inputs, Helm variables use a `valuePath` to map flat QSM variables into Helm's nested `values.yaml` structure:

```yaml
# qsm.yml
userVariables:
  - name: "retention_days"
    type: "number"
    default: "15"
    description: "Data retention in days"
    valuePath: "prometheus.prometheusSpec.retention"  # <-- maps into values.yaml

# At deploy time, this becomes:
# helm upgrade --set prometheus.prometheusSpec.retention=15
```
