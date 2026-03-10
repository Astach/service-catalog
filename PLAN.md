# Qovery Service Catalog -- Implementation Plan

> **Status:** Draft v2.0
> **Date:** 2026-03-10
> **Scope:** MVP implementation across q-core, engine, console, and the existing `service-catalog` blueprint repository

---

## Table of Contents

1. [Product Decisions](#1-product-decisions)
2. [Technical Decisions](#2-technical-decisions)
3. [User Journey](#3-user-journey)
4. [Architecture & Workflow Diagrams](#4-architecture--workflow-diagrams)
5. [Versioning Mechanism](#5-versioning-mechanism)
6. [QSM Contract Specification](#6-qsm-contract-specification)
7. [Implementation Plan](#7-implementation-plan)
8. [Examples](#8-examples)

---

## 1. Product Decisions

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| P1 | Core concept | The catalog is a **discovery and pre-fill layer** on top of the existing Terraform Service. No new service type. A user selects a blueprint, fills variables, and q-core creates a standard Terraform Service under the hood. | Minimal new code. Reuses the entire existing Terraform Service stack end-to-end. |
| P2 | Custom/private catalogs | **Not supported** | Only the single public Qovery blueprint repo. Private repos deferred. |
| P3 | Detach feature | **Dropped** | Out of scope entirely. |
| P4 | MVP provider scope | 4 AWS blueprints (PostgreSQL, MySQL, Redis, MongoDB) already exist. Add one per remaining provider (GCP, Azure, Scaleway) later. | Ship fast with what's already written. |
| P5 | Dependency model | Loose coupling via environment variables | Services share data through `QOVERY_*` outputs -> auto-computed env vars. No enforced dependency graph. `qsm.yml` `dependencies` field is informational only (UI hints). |
| P6 | Version selection (MVP) | Always provision the latest published version | Users don't pick a version. Version selector deferred. |
| P7 | Alias naming | **Enforced pattern:** `{SERVICE_NAME}_{OUTPUT_SUFFIX}` | Deterministic, no collisions, no user configuration needed. Service name "my-database" + output `QOVERY_POSTGRESQL_HOST` -> env var `MY_DATABASE_POSTGRESQL_HOST`. |
| P8 | Alias editing | **Not supported** | Aliases are computed from the service name. No alias editing UI or API. |
| P9 | Provisioning UI | **2 steps:** Name + Variables | No alias step (aliases are automatic). Simpler UX. |

---

## 2. Technical Decisions

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| T1 | Blueprint repository | Existing `service-catalog` repo (`github.com/Astach/service-catalog`) | Already contains 4 AWS blueprints. Add `qsm.yml` to each. |
| T2 | Repo structure | One directory per blueprint, flat | `aws/postgresql/`, `aws/redis/`, etc. No version subdirectories. |
| T3 | Versioning | Git tags with blueprint-name prefix | Tags like `aws-postgresql-v1.0.0`. The `qsm.yml` carries a `version` field that CI validates against the tag. |
| T4 | Blueprint immutability | CI-enforced | Once a tag is pushed, the files at that commit are frozen. |
| T5 | q-core fetches blueprints via | **GitHub REST API** | `GET /repos/{owner}/{repo}/contents/{path}?ref={tag}`. No cloning in q-core. |
| T6 | Caching | **In-memory cache** in q-core (e.g., `ConcurrentHashMap` or Caffeine) | Dataset is tiny (~4-50 blueprints, <100KB total). Read-heavy, write-rare. Invalidated by webhook. No Redis needed for this. |
| T7 | Cache invalidation | GitHub webhook -> `POST /internal/catalog/webhook` -> clears in-memory cache | Next request re-fetches from GitHub API. Admin endpoint as fallback. |
| T8 | New DB table | **None** | No `catalog_service` table. Add 3 columns to existing `terraform` table: `is_from_catalog`, `blueprint_name`, `blueprint_version`. |
| T9 | Engine changes | Minimal -- add `is_catalog_service` flag | Allow `QOVERY_*` output prefix for catalog services (currently rejected). |
| T10 | Alias computation | q-core computes deterministically: strip `QOVERY_` prefix, prepend normalized service name | No alias config stored or editable. Convention: `{UPPER_SNAKE_SERVICE_NAME}_{OUTPUT_WITHOUT_QOVERY_PREFIX}`. |
| T11 | QSM strictness | `qsm.yml` mandatory for catalog blueprints | CI validates against JSON Schema on every PR and tag. |

---

## 3. User Journey

### 3.1 Browsing the Catalog

```
+---------------------------------------------------------------------+
|  QOVERY CONSOLE - Environment "production" - Service Catalog        |
+---------------------------------------------------------------------+
|                                                                      |
|  Provider: [AWS v]    Category: [All v]    Search: [__________]     |
|                                                                      |
|  +----------------+  +----------------+  +----------------+         |
|  |  PostgreSQL    |  |  MySQL         |  |  Redis         |         |
|  |  RDS           |  |  RDS           |  |  ElastiCache   |         |
|  |  v1.0.0        |  |  v1.0.0        |  |  v1.0.0        |         |
|  |  [database]    |  |  [database]    |  |  [cache]       |         |
|  |                |  |                |  |                |         |
|  |  [Provision]   |  |  [Provision]   |  |  [Provision]   |         |
|  +----------------+  +----------------+  +----------------+         |
|                                                                      |
|  +----------------+                                                  |
|  |  MongoDB       |                                                  |
|  |  DocumentDB    |                                                  |
|  |  v1.0.0        |                                                  |
|  |  [database]    |                                                  |
|  |                |                                                  |
|  |  [Provision]   |                                                  |
|  +----------------+                                                  |
|                                                                      |
+----------------------------------------------------------------------+
```

**Steps:**
1. User navigates to an environment and opens the Service Catalog
2. The **provider filter is pre-set** to match the environment's cluster cloud provider
3. User can further filter by category and search by name/tags
4. Each card shows: icon, name, latest version, category tag, and a "Provision" button

### 3.2 Provisioning a Service

```
+---------------------------------------------------------------------+
|  Provision: AWS RDS PostgreSQL (v1.0.0)                             |
+---------------------------------------------------------------------+
|                                                                      |
|  Step 1 of 2: Service Name                                          |
|  --------------------------                                          |
|  Name: [my-database__________________]                              |
|                                                                      |
|  (i) This name determines your environment variable prefix.         |
|      Example: MY_DATABASE_POSTGRESQL_HOST                            |
|                                                                      |
|  Step 2 of 2: Configuration                                         |
|  ---------------------------                                         |
|  Instance Identifier: [my-prod-pg_____________] (required)          |
|  Password:            [************************] (required)          |
|  Instance Class:      [db.t3.micro v]            (optional)         |
|  PostgreSQL Version:  [16 v]                     (optional)         |
|  Storage (GB):        [20_____]                  (optional)         |
|  Multi-AZ:            [x]                        (optional)         |
|  Database Name:       [postgres___]              (optional)         |
|  Username:            [qovery_____]              (optional)         |
|                                                                      |
|  (i) Cluster context (region, VPC, subnets) is injected             |
|      automatically from your environment.                            |
|                                                                      |
|                                        [Cancel]  [Provision ->]     |
+----------------------------------------------------------------------+
```

**Steps:**
1. User clicks "Provision" on a blueprint card
2. **Step 1:** Name the service (drives the env var prefix)
3. **Step 2:** Fill in user-facing variables (dynamic form from `qsm.yml`). Injected variables (cluster name, region, VPC, subnets) are auto-filled and hidden.
4. User clicks "Provision"
5. q-core creates a standard Terraform Service with the blueprint's git_url/commit/path + merged variables
6. Deployment runs through the existing engine pipeline
7. On success, env vars are auto-created: `MY_DATABASE_POSTGRESQL_HOST`, `MY_DATABASE_POSTGRESQL_PORT`, etc.

### 3.3 Managing a Provisioned Service

After provisioning, it appears in the environment's service list as a regular **Terraform Service** with a "catalog" badge showing the blueprint name and version.

**Available actions (all existing Terraform Service actions):**
- **View:** Status, variables, Terraform resources, output values, auto-generated env vars
- **Redeploy:** Re-run Terraform apply
- **Edit Variables:** Update input variables, redeploy
- **Delete:** Destroy the cloud resource via `terraform destroy`

### 3.4 Connecting Services via Auto-Generated Env Vars

```
+----------------------------------------------------------------------+
|  Environment "production"                                             |
|                                                                       |
|  Services:                                                            |
|  +-- my-database (terraform, catalog: aws-postgresql v1.0.0)        |
|  |   auto-generated env vars:                                        |
|  |     MY_DATABASE_POSTGRESQL_HOST     = "mydb.abc.rds.amazonaws.."  |
|  |     MY_DATABASE_POSTGRESQL_PORT     = "5432"                      |
|  |     MY_DATABASE_POSTGRESQL_DATABASE = "postgres"                  |
|  |     MY_DATABASE_POSTGRESQL_USERNAME = "qovery"                    |
|  |                                                                    |
|  +-- my-cache (terraform, catalog: aws-redis v1.0.0)                |
|  |   auto-generated env vars:                                        |
|  |     MY_CACHE_REDIS_HOST = "cache.xyz.elasticache.amazonaws.com"   |
|  |     MY_CACHE_REDIS_PORT = "6379"                                  |
|  |                                                                    |
|  +-- api-server (container)                                          |
|      reads: MY_DATABASE_POSTGRESQL_HOST, MY_CACHE_REDIS_HOST, etc.   |
|                                                                       |
+-----------------------------------------------------------------------+
```

**How it works:**
1. User provisions "my-database" from aws-postgresql blueprint
2. After Terraform apply, q-core reads outputs (`QOVERY_POSTGRESQL_HOST`, etc.)
3. q-core computes env var names: `MY_DATABASE` + `_` + `POSTGRESQL_HOST`
4. Env vars are created at environment scope, available to all services
5. User's container reads them as standard env vars -- no SDK needed

---

## 4. Architecture & Workflow Diagrams

### 4.1 High-Level Architecture

```
+-------------+     +--------------------------------------------------------------+
|             |     |                       q-core                                  |
|  Console    |---->|  +--------------+   +-------------------+                    |
|  (React)    | REST|  | CatalogApi   |-->| CreateTerraform   |                    |
|             |     |  | Controller   |   | FromCatalogUseCase|                    |
+-------------+     |  +--------------+   +--------+----------+                    |
                    |         |                     |                               |
                    |         v                     v                               |
                    |  +--------------+   +-------------------+   +--------------+ |
                    |  | Blueprint    |   | TerraformService  |   | AliasBridge  | |
                    |  | Registry     |   | CreationUseCase   |   | Service      | |
                    |  | Service      |   | (existing)        |   | (new)        | |
                    |  +------+-------+   +--------+----------+   +------+-------+ |
                    |         |                     |                     |         |
                    |  +------+-------+             |              +------+-------+ |
                    |  | In-Memory    |             v              | Environment  | |
                    |  | Cache        |      +-----------+        | Variable     | |
                    |  | (blueprints) |      | terraform |        | (existing)   | |
                    |  +--------------+      | (DB table)|        +--------------+ |
                    |                        | + 3 cols  |                         |
                    +------------------------+-----------+-------------------------+
                              |                     |
                    +---------v---------+  +--------v-----------+
                    |  GitHub API       |  |  Redis Streams     |
                    |  (read qsm.yml, |  |  (EngineRequest)   |
                    |   list tags)      |  +--------+-----------+
                    +---------+---------+           |
                              |              +------v----------+
                    +---------v---------+    |     Engine      |
                    |  Blueprint Repo   |    |     (Rust)      |
                    |  (GitHub)         |<---| git clone repo  |
                    |  service-catalog  |    | terraform apply |
                    +-------------------+    +------+----------+
                                                    |
                                             +------v----------+
                                             | Cloud Provider  |
                                             | (AWS/GCP/Azure/ |
                                             |  Scaleway)      |
                                             +-----------------+
```

### 4.2 Provisioning Workflow (Sequence)

```
 Console          q-core                     In-Memory     Engine          Cloud
   |                |                         Cache           |               |
   | POST /catalog  |                           |             |               |
   | Service        |                           |             |               |
   | {blueprint,    |                           |             |               |
   |  name, vars}   |                           |             |               |
   |--------------->|                           |             |               |
   |                |                           |             |               |
   |                |  Lookup blueprint          |             |               |
   |                |-------------------------->|             |               |
   |                |                           |             |               |
   |                |  [cache hit: return]       |             |               |
   |                |  [cache miss: fetch        |             |               |
   |                |   from GitHub API,         |             |               |
   |                |   populate cache]          |             |               |
   |                |<--------------------------|             |               |
   |                |                           |             |               |
   |                |-- Validate user vars                    |               |
   |                |-- Resolve injected vars                 |               |
   |                |   from cluster context                  |               |
   |                |-- Merge all variables                   |               |
   |                |                                         |               |
   |                |-- Create TerraformService (DB)          |               |
   |                |   {git_url, commit_sha,                 |               |
   |                |    root_module_path, vars,               |               |
   |                |    is_from_catalog=true,                 |               |
   |                |    blueprint_name, blueprint_version}    |               |
   |                |                                         |               |
   |                |-- Trigger deploy (existing flow)        |               |
   |                |-----------------------------> Redis --->|               |
   |                |                                         |               |
   |  <-- 202 Accepted (terraform service ID) --|             |               |
   |<---------------|                                         |               |
   |                |                                         |               |
   |                |                                         | git clone     |
   |                |                                         | @commit_sha   |
   |                |                                         |               |
   |                |                                         | terraform     |
   |                |                                         | init + apply  |
   |                |                                         |-------------->|
   |                |                                         |<--------------|
   |                |                                         |               |
   |                |                                         | terraform     |
   |                |                                         | show -json    |
   |                |                                         | (extract      |
   |                |                                         |  QOVERY_*     |
   |                |                                         |  outputs)     |
   |                |                                         |               |
   |                |  gRPC: sendTerraformResources           |               |
   |                |<----------------------------------------|               |
   |                |                                         |               |
   |                |-- AliasBridgeService:                   |               |
   |                |   1. Filter QOVERY_* outputs            |               |
   |                |   2. Normalize service name             |               |
   |                |      "my-database" -> "MY_DATABASE"     |               |
   |                |   3. Strip QOVERY_ prefix               |               |
   |                |      "QOVERY_POSTGRESQL_HOST"           |               |
   |                |      -> "POSTGRESQL_HOST"               |               |
   |                |   4. Combine:                           |               |
   |                |      "MY_DATABASE_POSTGRESQL_HOST"      |               |
   |                |   5. Create EnvironmentVariable         |               |
   |                |      records (existing system)          |               |
   |                |                                         |               |
   |  <-- WebSocket: deployment complete ----|               |               |
   |<---------------|                                         |               |
```

### 4.3 Blueprint Cache & Webhook Flow

```
 Blueprint Repo       GitHub           q-core
 (developer push)       |                |
       |                |                |
       |  git push tag  |                |
       |  aws-pg-v1.1.0 |                |
       |--------------->|                |
       |                |                |
       |                |  POST /internal/catalog/webhook
       |                |  {ref: "aws-postgresql-v1.1.0",
       |                |   type: "tag"}
       |                |--------------->|
       |                |                |
       |                |                |  Clear in-memory cache
       |                |                |  (all blueprints)
       |                |                |
       |                |                |  Next API request:
       |                |                |  1. Cache miss
       |                |                |  2. GET GitHub API /repos/.../tags
       |                |                |  3. GET qsm.yml for each blueprint
       |                |                |  4. Populate cache
       |                |                |  5. Return response
```

### 4.4 Alias Bridge Data Flow

```
+----------------------------------------------------------------------+
|                        Environment                                    |
|                                                                       |
|  Terraform Service "my-database"                                      |
|  (is_from_catalog=true, blueprint: aws-postgresql v1.0.0)            |
|  +------------------------------------------------------------+      |
|  |  Terraform Apply Outputs:                                   |      |
|  |    QOVERY_POSTGRESQL_HOST       = "mydb.abc.rds.aws.com"   |      |
|  |    QOVERY_POSTGRESQL_PORT       = "5432"                    |      |
|  |    QOVERY_POSTGRESQL_DATABASE   = "postgres"                |      |
|  |    QOVERY_POSTGRESQL_USERNAME   = "qovery"                  |      |
|  |    QOVERY_POSTGRESQL_CONNECTION_STRING = "postgresql://..."  |      |
|  +-----------------------------+------------------------------+      |
|                                |                                      |
|                                v                                      |
|  Alias Computation (automatic, deterministic):                        |
|    Service name: "my-database" -> "MY_DATABASE"                       |
|    Strip "QOVERY_" prefix from each output name                       |
|    Prepend normalized service name                                    |
|                                |                                      |
|                                v                                      |
|  Environment Variables (auto-created):                                |
|  +------------------------------------------------------------+      |
|  |  MY_DATABASE_POSTGRESQL_HOST       = "mydb.abc.rds.aws.."  |      |
|  |  MY_DATABASE_POSTGRESQL_PORT       = "5432"                 |      |
|  |  MY_DATABASE_POSTGRESQL_DATABASE   = "postgres"             |      |
|  |  MY_DATABASE_POSTGRESQL_USERNAME   = "qovery"               |      |
|  |  MY_DATABASE_POSTGRESQL_CONNECTION_STRING = "postgresql://.." |      |
|  +------------------------------------------------------------+      |
|                                |                                      |
|              +-----------------+------------------+                   |
|              v                 v                  v                   |
|         +--------+       +--------+         +--------+               |
|         | my-api |       | worker |         | cron   |               |
|         | (app)  |       | (job)  |         | (job)  |               |
|         +--------+       +--------+         +--------+               |
|         reads             reads              reads                    |
|         MY_DATABASE_*     MY_DATABASE_*      MY_DATABASE_*            |
|                                                                       |
+-----------------------------------------------------------------------+
```

---

## 5. Versioning Mechanism

### 5.1 Repository Layout

The existing `service-catalog` repo at `github.com/Astach/service-catalog`:

```
service-catalog/
+-- aws/
|   +-- postgresql/
|   |   +-- main.tf               (exists)
|   |   +-- variables.tf          (exists)
|   |   +-- outputs.tf            (exists, needs QOVERY_ rename)
|   |   +-- providers.tf          (exists)
|   |   +-- terraform.tfvars.example (exists)
|   |   +-- README.md             (exists)
|   |   +-- qsm.yml             (TO ADD)
|   +-- mysql/
|   |   +-- ... (same pattern)
|   +-- redis/
|   |   +-- ... (same pattern)
|   +-- mongodb/
|       +-- ... (same pattern)
+-- gcp/                          (empty, future)
+-- azure/                        (empty, future)
+-- scaleway/                     (TO ADD, future)
+-- schemas/
|   +-- qsm-schema.json          (TO ADD)
+-- .github/
|   +-- workflows/
|       +-- validate.yml          (TO ADD)
+-- .gitignore                    (exists)
+-- README.md                     (TO ADD)
```

**Key rules:**
- One directory per blueprint (never version subdirectories)
- `main` branch is always the latest working state
- Published versions are Git tags

### 5.2 How Versioning Works

**Publishing the initial release:**

```bash
# 1. Add qsm.yml to each blueprint, rename outputs to QOVERY_*
# 2. qsm.yml contains: version: "1.0.0"
# 3. Merge to main

# 4. Tag each blueprint independently
git tag aws-postgresql-v1.0.0
git tag aws-mysql-v1.0.0
git tag aws-redis-v1.0.0
git tag aws-mongodb-v1.0.0
git push origin --tags

# CI validates: tag name matches qsm.yml version field
# GitHub webhook fires -> q-core in-memory cache cleared
```

**Updating an existing blueprint:**

```bash
# 1. Modify aws/postgresql/main.tf (e.g., add parameter group)
# 2. Bump aws/postgresql/qsm.yml version to "1.1.0"
# 3. Merge to main
# 4. Tag only the changed blueprint
git tag aws-postgresql-v1.1.0
git push origin aws-postgresql-v1.1.0
# Other blueprints are unaffected
```

**Git history:**

```
Commit A --- Commit B --- Commit C --- Commit D --- HEAD (main)
   |                                      |
   |                                      +-- tag: aws-postgresql-v1.1.0
   |                                          (added parameter group)
   |
   +-- tag: aws-postgresql-v1.0.0
   +-- tag: aws-mysql-v1.0.0
   +-- tag: aws-redis-v1.0.0
   +-- tag: aws-mongodb-v1.0.0
       (initial releases)
```

**Key properties:**
- Tags are immutable. `aws-postgresql-v1.0.0` always points to Commit A.
- Blueprints are tagged independently.
- `main` is always ahead of or equal to the latest tags.

### 5.3 How q-core Resolves Versions

```
"List all AWS blueprints"
        |
        v
q-core: Check in-memory cache
        |
        v (cache miss)
q-core: GET GitHub API /repos/{owner}/{repo}/git/matching-refs/tags/aws-
        |
        v
Returns: ["aws-postgresql-v1.0.0", "aws-postgresql-v1.1.0",
          "aws-mysql-v1.0.0", "aws-redis-v1.0.0", "aws-mongodb-v1.0.0"]
        |
        v
q-core: Group by blueprint name, pick highest semver per blueprint
        |
        v
Result:  aws-postgresql -> v1.1.0 (commit SHA: abc123)
         aws-mysql      -> v1.0.0 (commit SHA: def456)
         aws-redis      -> v1.0.0 (commit SHA: def456)
         aws-mongodb    -> v1.0.0 (commit SHA: def456)
        |
        v
q-core: For each, GET /repos/.../contents/aws/postgresql/qsm.yml?ref=abc123
        |
        v
Parse qsm.yml -> BlueprintResponse -> Store in cache -> Return to UI
```

### 5.4 How Provisioned Services Are Pinned

When a user provisions from the catalog, q-core creates a standard Terraform Service with:

```
terraform table row:
  id:                 <uuid>
  environment_id:     <env-uuid>
  name:               "my-database"
  git_url:            "https://github.com/Astach/service-catalog.git"
  commit_id:          "abc123def456..."    <- resolved from tag at provision time
  root_module_path:   "aws/postgresql"
  variables:          [["qovery_cluster_name","my-cluster"],
                       ["region","eu-west-1"],
                       ["password","s3cr3t",true],
                       ["postgresql_identifier","my-prod-pg"], ...]
  engine:             "TERRAFORM"
  is_from_catalog:    true                 <- NEW COLUMN
  blueprint_name:     "aws-postgresql"     <- NEW COLUMN
  blueprint_version:  "1.1.0"             <- NEW COLUMN
```

Even if the blueprint repo evolves, this service stays on its pinned commit SHA. The blueprint version is stored for display purposes.

---

## 6. QSM Contract Specification

### 6.1 Full `qsm.yml` Schema

```yaml
# Required. Always "qovery.com/v1".
apiVersion: "qovery.com/v1"

# Required. Always "ServiceBlueprint".
kind: "ServiceBlueprint"

metadata:
  # Required. Unique name. Must match the directory path ({provider}/{name}).
  name: "aws-postgresql"

  # Required. Semver. Must match the Git tag version suffix.
  version: "1.0.0"

  # Required. Human-readable description shown in the catalog UI.
  description: "Provision an AWS RDS PostgreSQL instance with encryption, backups, and monitoring"

  # Optional. URL to an icon image for the catalog card.
  icon: "https://cdn.qovery.com/icons/aws-rds-postgresql.svg"

  # Optional. Tags for search and filtering.
  tags:
    - "database"
    - "postgresql"
    - "rds"
    - "relational"

spec:
  # Required. Cloud provider. Used for filtering.
  # Allowed: "aws", "gcp", "azure", "scaleway"
  provider: "aws"

  # Required. Service category. Used for filtering.
  # Allowed: "storage", "database", "cache", "messaging", "networking",
  #          "compute", "security", "monitoring", "other"
  category: "database"

  # Required. IaC engine.
  # Allowed: "terraform", "opentofu"
  engine: "terraform"

  # Optional. Version constraint for the engine binary.
  engineVersionConstraint: ">= 1.5"

  # Variables auto-filled by q-core from environment/cluster context.
  # These are NEVER shown to the user.
  # Each must match a variable name in variables.tf.
  injectedVariables:
    - name: "qovery_cluster_name"
      source: "cluster.name"
    - name: "region"
      source: "cluster.region"
    - name: "qovery_environment_id"
      source: "environment.id"
    - name: "qovery_project_id"
      source: "project.id"
    - name: "vpc_id"
      source: "cluster.vpc_id"
    - name: "subnet_ids"
      source: "cluster.subnet_ids"
    - name: "security_group_ids"
      source: "cluster.security_group_ids"

  # Variables shown to the user in the provisioning form.
  # Each must match a variable name in variables.tf.
  userVariables:
    - name: "postgresql_identifier"
      type: "string"
      required: true
      description: "Unique identifier for the RDS instance"
      uiHint: "text"
    - name: "password"
      type: "string"
      required: true
      description: "Master password (minimum 9 characters)"
      uiHint: "password"
      sensitive: true
    - name: "instance_class"
      type: "string"
      required: false
      default: "db.t3.micro"
      description: "RDS instance class"
      uiHint: "dropdown"
      options:
        - "db.t3.micro"
        - "db.t3.small"
        - "db.t3.medium"
        - "db.t3.large"
        - "db.r6g.large"
        - "db.r6g.xlarge"
    - name: "postgresql_version"
      type: "string"
      required: false
      default: "16"
      description: "PostgreSQL engine version"
      uiHint: "dropdown"
      options: ["14", "15", "16", "17"]
    - name: "disk_size"
      type: "number"
      required: false
      default: "20"
      description: "Storage size in GB"
      uiHint: "text"
    - name: "multi_az"
      type: "bool"
      required: false
      default: "true"
      description: "Deploy across multiple availability zones"
      uiHint: "toggle"
    - name: "database_name"
      type: "string"
      required: false
      default: "postgres"
      description: "Name of the default database"
      uiHint: "text"
    - name: "username"
      type: "string"
      required: false
      default: "qovery"
      description: "Master username"
      uiHint: "text"
    - name: "encrypt_disk"
      type: "bool"
      required: false
      default: "true"
      description: "Enable storage encryption"
      uiHint: "toggle"
    - name: "backup_retention_period"
      type: "number"
      required: false
      default: "14"
      description: "Days to retain automated backups"
      uiHint: "text"

  # Outputs produced by the blueprint after Terraform apply.
  # Names MUST start with "QOVERY_" prefix.
  # Environment variables are auto-computed as:
  #   {NORMALIZED_SERVICE_NAME}_{OUTPUT_NAME_WITHOUT_QOVERY_PREFIX}
  outputs:
    - name: "QOVERY_POSTGRESQL_HOST"
      description: "Database hostname"
      sensitive: false
    - name: "QOVERY_POSTGRESQL_PORT"
      description: "Database port"
      sensitive: false
    - name: "QOVERY_POSTGRESQL_DATABASE"
      description: "Default database name"
      sensitive: false
    - name: "QOVERY_POSTGRESQL_USERNAME"
      description: "Master username"
      sensitive: false
    - name: "QOVERY_POSTGRESQL_CONNECTION_STRING"
      description: "Connection string (without password)"
      sensitive: false
    - name: "QOVERY_POSTGRESQL_ENDPOINT"
      description: "Full endpoint (host:port)"
      sensitive: false
    - name: "QOVERY_POSTGRESQL_ARN"
      description: "RDS instance ARN"
      sensitive: false

  # Optional. Informational only. Shown as "You might also need..." in the UI.
  dependencies:
    - blueprint: "aws-secrets-manager"
      reason: "Store database credentials securely with automatic rotation"

  # Optional. Default resource allocation for the Terraform Job.
  resources:
    defaultCpu: 500       # millicores
    defaultRam: 512       # MiB
    defaultTimeout: 30    # minutes
```

### 6.2 Injected Variable Sources

q-core resolves `injectedVariables[].source` from the cluster/environment context:

| Source | Resolved From |
|--------|--------------|
| `cluster.name` | `KubernetesProvider.name` |
| `cluster.region` | `CloudProviderRegion` of the cluster |
| `cluster.vpc_id` | `InfrastructureOutputs.vpcId` (EKS/GKE/AKS) |
| `cluster.subnet_ids` | `InfrastructureOutputs.subnetIds` |
| `cluster.security_group_ids` | `InfrastructureOutputs.securityGroupIds` |
| `environment.id` | `Environment.id` |
| `project.id` | `Project.id` |
| `organization.id` | `Organization.id` |

### 6.3 Validation Rules (enforced by CI)

| Rule | Where |
|------|-------|
| `qsm.yml` passes JSON Schema validation | PR CI |
| `metadata.name` matches `{provider}/{directory-name}` | PR CI |
| All `injectedVariables[].name` exist in `variables.tf` | PR CI |
| All `injectedVariables[].source` are valid source paths | PR CI |
| All `userVariables[].name` exist in `variables.tf` | PR CI |
| All `outputs[].name` start with `QOVERY_` | PR CI |
| All `outputs[].name` exist as `output` blocks in `*.tf` | PR CI |
| `terraform init && terraform validate` passes | PR CI |
| On tag push: tag version suffix matches `metadata.version` | Tag CI |
| On tag push: tag prefix matches `metadata.name` (with `/` -> `-`) | Tag CI |
| No force-push to existing tags | Branch protection rule |

---

## 7. Implementation Plan

### Phase 0: Blueprint Repository Changes

**Repo:** `service-catalog` (`github.com/Astach/service-catalog`)

| # | Task | Description | Priority |
|---|------|-------------|----------|
| 0.1 | Rename outputs | In all 4 blueprints, rename outputs in `outputs.tf` to use `QOVERY_` prefix: `QOVERY_POSTGRESQL_*`, `QOVERY_MYSQL_*`, `QOVERY_REDIS_*`, `QOVERY_MONGODB_*` | High |
| 0.2 | Add `qsm.yml` to `aws/postgresql/` | Full manifest with injectedVariables, userVariables, outputs (see section 6.1) | High |
| 0.3 | Add `qsm.yml` to `aws/mysql/` | Same pattern, MySQL-specific | High |
| 0.4 | Add `qsm.yml` to `aws/redis/` | Same pattern, Redis-specific | High |
| 0.5 | Add `qsm.yml` to `aws/mongodb/` | Same pattern, MongoDB/DocumentDB-specific | High |
| 0.6 | Add `schemas/qsm-schema.json` | JSON Schema for `qsm.yml` validation | High |
| 0.7 | Add root `README.md` | Repo overview, structure, QSM contract reference | Medium |
| 0.8 | Add CI pipeline | `.github/workflows/validate.yml`: validate qsm.yml, terraform validate, output prefix check, tag/version check | High |
| 0.9 | Configure branch protection | Prevent force-push to tags, require CI pass on PRs | Medium |
| 0.10 | Tag initial releases | `aws-postgresql-v1.0.0`, `aws-mysql-v1.0.0`, `aws-redis-v1.0.0`, `aws-mongodb-v1.0.0` | High |
| 0.11 | Configure GitHub webhook | Webhook on tag/push events pointing to q-core's `/internal/catalog/webhook` | High |

---

### Phase 1: q-core -- Catalog Layer

**Repo:** `q-core`

New code goes under `corenetto/src/main/kotlin/com/qovery/corenetto/service/catalog/`. Follows existing patterns from `service/terraform/` and `template/`.

#### 1.1 DB Migration

| # | Task | Description |
|---|------|-------------|
| 1.1.1 | Add columns to `terraform` table | Flyway migration: `ALTER TABLE terraform ADD COLUMN is_from_catalog BOOLEAN NOT NULL DEFAULT false; ADD COLUMN blueprint_name TEXT; ADD COLUMN blueprint_version TEXT;` |

#### 1.2 Domain Layer

| # | Task | File | Description |
|---|------|------|-------------|
| 1.2.1 | Blueprint domain model | `domain/Blueprint.kt` | Data class: name, version, description, icon, provider, category, tags, engine, engineVersionConstraint, injectedVariables (list), userVariables (list), outputs (list), dependencies (list), resources. Parsed from `qsm.yml`. |
| 1.2.2 | Catalog exceptions | `domain/CatalogException.kt` | Sealed class: `BlueprintNotFound`, `VariableValidationFailed`, `ProviderMismatch` |

#### 1.3 Blueprint Registry Service

| # | Task | File | Description |
|---|------|------|-------------|
| 1.3.1 | GitHub API client | `service/GitHubBlueprintClient.kt` | HTTP client (Unirest) calling GitHub REST API. Methods: `listTags(prefix)`, `getFileContent(path, ref)`, `resolveTagToSha(tag)`. Auth via GitHub token from config. |
| 1.3.2 | In-memory cache | `service/BlueprintCache.kt` | `ConcurrentHashMap<String, List<Blueprint>>` keyed by provider. `clearAll()` method for webhook invalidation. Populated on first access per provider. |
| 1.3.3 | Blueprint registry | `service/BlueprintRegistryService.kt` | Orchestrates: check cache -> miss? fetch from GitHub API -> parse `qsm.yml` -> populate cache -> return. Methods: `listBlueprints(provider, category?)`, `getBlueprint(name)`, `getLatestVersion(name)`. |
| 1.3.4 | Webhook handler | `service/BlueprintWebhookService.kt` | Receives GitHub webhook payload, validates signature, calls `cache.clearAll()`. |
| 1.3.5 | Configuration | `config/CatalogConfiguration.kt` | `@ConfigurationProperties("qovery.catalog")`: `github.repo-owner`, `github.repo-name`, `github.token`, `github.webhook-secret`. |

#### 1.4 Use Cases

| # | Task | File | Description |
|---|------|------|-------------|
| 1.4.1 | Query blueprints | `service/BlueprintQueryUseCase.kt` | `listBlueprints(provider, category?)` -- calls registry, applies filters. `getBlueprint(name)` -- returns single blueprint with variables and outputs. |
| 1.4.2 | Create from catalog | `service/CreateTerraformFromCatalogUseCase.kt` | Accepts: environmentId, blueprintName, serviceName, userVariableValues. Steps: (1) fetch blueprint, (2) resolve latest tag -> commit SHA, (3) validate user vars against `userVariables`, (4) validate provider matches cluster, (5) resolve injected vars from cluster/environment context, (6) merge all variables, (7) delegate to existing `TerraformServiceCreationUseCase` with git_url/commit/path/vars + set `is_from_catalog=true`, `blueprint_name`, `blueprint_version`, (8) trigger deployment. |
| 1.4.3 | Alias bridge | `service/AliasBridgeService.kt` | Triggered after a catalog Terraform Service deploy completes. Steps: (1) check `is_from_catalog == true`, (2) read `TerraformResource` outputs, (3) filter to `QOVERY_*`, (4) normalize service name (uppercase, hyphens -> underscores), (5) compute env var name: `{NORMALIZED_NAME}_{OUTPUT_WITHOUT_QOVERY_PREFIX}`, (6) create/update `EnvironmentVariable` records via existing system, (7) mark sensitive outputs as secret. |

#### 1.5 Web Layer

| # | Task | File | Description |
|---|------|------|-------------|
| 1.5.1 | DTOs | `web/CatalogDto.kt` | `BlueprintResponse`, `BlueprintVariableResponse`, `BlueprintOutputResponse`, `CreateFromCatalogRequest` (blueprintName, serviceName, variableValues map), `CreateFromCatalogResponse` (terraformServiceId, blueprintName, blueprintVersion) |
| 1.5.2 | API interface | `web/CatalogApi.kt` | Endpoint definitions (see table below) |
| 1.5.3 | Controller | `web/CatalogController.kt` | Thin controller delegating to use cases |
| 1.5.4 | Webhook controller | `web/CatalogWebhookController.kt` | `POST /internal/catalog/webhook` -- validates GitHub signature, delegates to `BlueprintWebhookService` |
| 1.5.5 | Security config | Update `SecurityConfiguration.kt` | Add new endpoints with proper auth |

**API Endpoints:**

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/organization/{orgId}/catalog/blueprints` | List blueprints. Query params: `provider` (required), `category`, `search`. |
| `GET` | `/api/v1/catalog/blueprint/{blueprintName}` | Get blueprint detail (latest version) with injectedVariables, userVariables, outputs. |
| `POST` | `/api/v1/environment/{envId}/catalog/terraform` | Create a Terraform Service from a catalog blueprint. Returns the Terraform Service. |
| `POST` | `/internal/catalog/webhook` | GitHub webhook receiver. |
| `POST` | `/admin/catalog/cache/invalidate` | Manual cache invalidation. |

Note: All other operations (get/edit/delete/redeploy the provisioned service) use the **existing Terraform Service API** -- no new endpoints needed.

#### 1.6 Hook Into Deployment Completion

| # | Task | Description |
|---|------|-------------|
| 1.6.1 | Wire AliasBridgeService | In the existing deployment status callback handler (where `TerraformResourcesCreationUseCase` is called), add a hook: if `terraform.is_from_catalog == true`, call `AliasBridgeService` to compute and create env vars. |

#### 1.7 Update Existing Terraform Persistence

| # | Task | Description |
|---|------|-------------|
| 1.7.1 | Update `TerraformJpaEntity` | Add `is_from_catalog`, `blueprint_name`, `blueprint_version` fields |
| 1.7.2 | Update `Terraform` domain model | Add same fields |
| 1.7.3 | Update `TerraformDto` | Add `is_from_catalog`, `blueprint_name`, `blueprint_version` to response DTO |

#### 1.8 OpenAPI Spec

| # | Task | Repo |
|---|------|------|
| 1.8.1 | Add catalog endpoints | `qovery-openapi-spec` -- add the 3 public + 1 internal + 1 admin endpoints above |
| 1.8.2 | Update Terraform Service response | Add `is_from_catalog`, `blueprint_name`, `blueprint_version` to existing Terraform response schema |

---

### Phase 2: Engine -- Minimal Changes

**Repo:** `engine`

| # | Task | File | Description |
|---|------|------|-------------|
| 2.1 | Add `is_catalog_service` field | `lib-engine/src/io_models/terraform/mod.rs` | Add `is_catalog_service: bool` to `TerraformService` struct (default `false`). Serde deserialization. |
| 2.2 | Allow QOVERY_ outputs | `lib-engine/src/environment/resource_extraction/parser.rs` | When `is_catalog_service == true`, skip the `QOVERY_` prefix rejection check on outputs. |
| 2.3 | Propagate in engine request | `q-core`: `EngineRequest.kt` + `EngineRequestService.kt` | Set `is_catalog_service = true` when `terraform.is_from_catalog == true`. |
| 2.4 | Tests | `lib-engine/tests/services/terraform_service.rs` | Test: catalog service with `QOVERY_*` outputs passes validation. |

---

### Phase 3: Console UI

**Repo:** `console`

| # | Task | Description |
|---|------|-------------|
| 3.1 | Catalog page route | New route: `/organization/{orgId}/project/{projId}/environment/{envId}/catalog` |
| 3.2 | Blueprint list | Grid of cards. Provider filter (pre-set from cluster). Category filter. Search. |
| 3.3 | Provisioning wizard | 2-step form: (1) Service Name with env var preview, (2) User Variables (dynamic from blueprint). Calls `POST /environment/{envId}/catalog/terraform`. |
| 3.4 | Catalog badge on Terraform services | In the environment service list, Terraform Services with `is_from_catalog=true` show a badge: "aws-postgresql v1.0.0". |
| 3.5 | Auto-generated env vars display | On the Terraform Service detail page, show the computed env var names and values when `is_from_catalog=true`. |
| 3.6 | Feature flag | Gate behind `service-catalog` feature flag. |

---

### Phase 4: Supporting Tools (Post-MVP)

| # | Task | Repo | Description |
|---|------|------|-------------|
| 4.1 | CLI: list blueprints | `qovery-cli` | `qovery catalog list --provider aws --category database` |
| 4.2 | CLI: provision | `qovery-cli` | `qovery catalog create --blueprint aws-postgresql --name my-db --env <id> --var password=xxx` |
| 4.3 | TF provider | `terraform-provider-qovery` | Data source `qovery_catalog_blueprints`, update `qovery_terraform_service` resource to accept `blueprint_name` |

---

## 8. Examples

### 8.1 Example: Provisioning API Call

**Request:**
```http
POST /api/v1/environment/env-uuid-123/catalog/terraform
Content-Type: application/json
Authorization: Bearer <token>

{
  "blueprint_name": "aws-postgresql",
  "name": "my-database",
  "variable_values": {
    "postgresql_identifier": "my-prod-pg",
    "password": "super-s3cr3t-pw",
    "instance_class": "db.t3.small",
    "postgresql_version": "16",
    "disk_size": "50",
    "multi_az": "true"
  }
}
```

Note: `region`, `qovery_cluster_name`, `vpc_id`, `subnet_ids`, `security_group_ids` are NOT in the request. q-core injects them automatically.

**Response (202 Accepted):**
```json
{
  "id": "tf-svc-uuid-789",
  "name": "my-database",
  "is_from_catalog": true,
  "blueprint_name": "aws-postgresql",
  "blueprint_version": "1.0.0",
  "status": "DEPLOYING",
  "created_at": "2026-03-10T14:30:00Z"
}
```

**After successful deployment (GET /api/v1/terraform/tf-svc-uuid-789):**
```json
{
  "id": "tf-svc-uuid-789",
  "name": "my-database",
  "is_from_catalog": true,
  "blueprint_name": "aws-postgresql",
  "blueprint_version": "1.0.0",
  "status": "DEPLOYED",
  "auto_generated_environment_variables": [
    { "key": "MY_DATABASE_POSTGRESQL_HOST", "value": "my-prod-pg.abc123.eu-west-1.rds.amazonaws.com" },
    { "key": "MY_DATABASE_POSTGRESQL_PORT", "value": "5432" },
    { "key": "MY_DATABASE_POSTGRESQL_DATABASE", "value": "postgres" },
    { "key": "MY_DATABASE_POSTGRESQL_USERNAME", "value": "qovery" },
    { "key": "MY_DATABASE_POSTGRESQL_CONNECTION_STRING", "value": "postgresql://qovery@my-prod-pg.abc123.eu-west-1.rds.amazonaws.com:5432/postgres" },
    { "key": "MY_DATABASE_POSTGRESQL_ENDPOINT", "value": "my-prod-pg.abc123.eu-west-1.rds.amazonaws.com:5432" },
    { "key": "MY_DATABASE_POSTGRESQL_ARN", "value": "arn:aws:rds:eu-west-1:123456789:db:my-prod-pg" }
  ],
  "created_at": "2026-03-10T14:30:00Z"
}
```

### 8.2 Example: Multi-Service Environment

```
Environment "production" on AWS EKS cluster
|
+-- "main-db" (terraform, catalog: aws-postgresql v1.0.0)
|   env vars:
|     MAIN_DB_POSTGRESQL_HOST             = "main.abc.rds.amazonaws.com"
|     MAIN_DB_POSTGRESQL_PORT             = "5432"
|     MAIN_DB_POSTGRESQL_DATABASE         = "postgres"
|     MAIN_DB_POSTGRESQL_USERNAME         = "qovery"
|     MAIN_DB_POSTGRESQL_CONNECTION_STRING = "postgresql://..."
|
+-- "analytics-db" (terraform, catalog: aws-postgresql v1.0.0)
|   env vars:
|     ANALYTICS_DB_POSTGRESQL_HOST             = "analytics.def.rds.amazonaws.com"
|     ANALYTICS_DB_POSTGRESQL_PORT             = "5432"
|     ANALYTICS_DB_POSTGRESQL_DATABASE         = "analytics"
|     ANALYTICS_DB_POSTGRESQL_USERNAME         = "qovery"
|     ANALYTICS_DB_POSTGRESQL_CONNECTION_STRING = "postgresql://..."
|
+-- "cache" (terraform, catalog: aws-redis v1.0.0)
|   env vars:
|     CACHE_REDIS_HOST = "cache.xyz.elasticache.amazonaws.com"
|     CACHE_REDIS_PORT = "6379"
|
+-- "api-server" (container)
|   reads: MAIN_DB_POSTGRESQL_HOST, CACHE_REDIS_HOST, etc.
|
+-- "analytics-worker" (job)
    reads: ANALYTICS_DB_POSTGRESQL_HOST, ANALYTICS_DB_POSTGRESQL_CONNECTION_STRING
```

Two PostgreSQL instances, no collisions -- each prefixed with its service name.

### 8.3 Example: How an App Consumes Outputs

```python
# Python -- standard env vars, no Qovery SDK
import os

db_host = os.environ["MAIN_DB_POSTGRESQL_HOST"]
db_port = os.environ["MAIN_DB_POSTGRESQL_PORT"]
db_name = os.environ["MAIN_DB_POSTGRESQL_DATABASE"]
db_user = os.environ["MAIN_DB_POSTGRESQL_USERNAME"]
db_pass = os.environ["DB_PASSWORD"]  # set manually by user as a secret

redis_host = os.environ["CACHE_REDIS_HOST"]
redis_port = os.environ["CACHE_REDIS_PORT"]
```

```javascript
// Node.js
const dbHost = process.env.MAIN_DB_POSTGRESQL_HOST;
const redisHost = process.env.CACHE_REDIS_HOST;
```

### 8.4 Example: Version Upgrade Flow (Post-MVP)

```
Current: "main-db" running aws-postgresql v1.0.0 (commit abc123)
Available: aws-postgresql v1.1.0 (tag aws-postgresql-v1.1.0, commit def456)

Post-MVP flow:
1. UI shows "Update available: v1.1.0" badge on the Terraform Service
2. User clicks "Upgrade"
3. q-core resolves new tag -> new commit SHA
4. Updates the Terraform Service's commit_id + blueprint_version
5. Triggers redeploy
6. Terraform runs with the new code at the new commit
```

---

## Execution Order & Dependencies

```
Phase 0 (Blueprint repo: qsm.yml + output renames + CI + tags)
   |
   +---> Phase 1.1 (DB migration: 3 columns on terraform table)
   |        |
   |        +---> Phase 1.2-1.3 (Domain + Blueprint Registry + Cache)
   |                 |
   |                 +---> Phase 1.4 (Use Cases: create from catalog + alias bridge)
   |                          |
   |                          +---> Phase 1.5-1.7 (Web Layer + Hook + Persistence updates)
   |                          |        |
   |                          |        +---> Phase 1.8 (OpenAPI Spec)
   |                          |
   |                          +---> Phase 2 (Engine: is_catalog_service flag)
   |                          |
   |                          +---> Phase 3 (Console UI)
   |
   +---> Phase 4 (CLI + TF Provider) -- post-MVP
```

**MVP = Phase 0 + Phase 1 + Phase 2 + Phase 3**
