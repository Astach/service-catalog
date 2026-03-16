# EnvBlueprint (StackBlueprint) Specification

> **Status**: Spec only. Not in MVP.

## Table of Contents

1. [Overview](#1-overview)
2. [StackBlueprint Schema](#2-stackblueprint-schema)
3. [Version Resolution](#3-version-resolution)
4. [Provisioning Flow](#4-provisioning-flow)
5. [Dependency Ordering via Deployment Stages](#5-dependency-ordering-via-deployment-stages)
6. [Variable Resolution](#6-variable-resolution)
7. [q-core Implementation](#7-q-core-implementation)
8. [Examples](#8-examples)

---

## 1. Overview

A **StackBlueprint** (also called EnvBlueprint) is a YAML file that composes multiple catalog ServiceBlueprints into a single deployable stack. Users author StackBlueprints in their **own Git repos** (not in the service-catalog repo) and reference catalog services with pinned versions.

**Key concepts:**

- StackBlueprints live in user repos, ServiceBlueprints live in the catalog repo
- Each service entry references a catalog blueprint by name + version constraint
- `alias` becomes the Qovery service name and the env var prefix for QSM_ outputs
- `dependsOn` controls deployment ordering (maps to q-core's deployment stages)
- The same blueprint can appear multiple times with different aliases (e.g., two PostgreSQL instances)
- All services in a stack are created in the same Qovery environment

---

## 2. StackBlueprint Schema

```yaml
apiVersion: "qovery.com/v1"
kind: "StackBlueprint"

metadata:
  name: "production-stack"
  version: "1.0.0"
  description: "Production environment with PostgreSQL, Redis, and monitoring"

spec:
  services:
    - blueprint: "aws-postgresql"         # Catalog blueprint name
      version: "1.2.0"                    # Version constraint (exact, train, or range)
      alias: "main-db"                    # Becomes service name + env var prefix
      variables:                          # Pre-configured variable overrides
        instance_class: "db.r6g.large"
        multi_az: "true"
        disk_size: "100"
        database_name: "production"
      dependsOn: []                       # No dependencies -> Stage 1

    - blueprint: "aws-redis"
      version: "1.x"                      # Version train: latest 1.x.x
      alias: "cache"
      variables:
        node_type: "cache.r6g.large"
        num_cache_clusters: "2"
      dependsOn: []                       # No dependencies -> Stage 1

    - blueprint: "aws-postgresql"
      version: ">=1.1.0 <2.0.0"          # Version range
      alias: "analytics-db"
      variables:
        instance_class: "db.t3.medium"
        database_name: "analytics"
      dependsOn: ["main-db"]             # Wait for main-db -> Stage 2
```

### Field Reference

| Field | Required | Type | Description |
|---|---|---|---|
| `apiVersion` | Yes | String | Must be `"qovery.com/v1"` |
| `kind` | Yes | String | Must be `"StackBlueprint"` |
| `metadata.name` | Yes | String | Stack name |
| `metadata.version` | Yes | String | Stack version (semver) |
| `metadata.description` | Yes | String | Human-readable description |
| `spec.services` | Yes | List | One or more service entries |
| `spec.services[].blueprint` | Yes | String | Catalog blueprint name (e.g., `"aws-postgresql"`) |
| `spec.services[].version` | Yes | String | Version constraint (see [Version Resolution](#3-version-resolution)) |
| `spec.services[].alias` | Yes | String | Unique service name within the stack. Becomes Qovery service name and QSM_ alias prefix. |
| `spec.services[].variables` | No | Map | Pre-configured variable values. Keys must match `userVariables[].name` from the ServiceBlueprint. |
| `spec.services[].dependsOn` | No | List | List of `alias` names that must deploy before this service. Empty or absent = no dependencies. |

### Constraints

1. `alias` must be unique within the stack
2. `dependsOn` entries must reference valid `alias` names within the same stack
3. `dependsOn` must not form cycles
4. `variables` keys must match `userVariables[].name` from the referenced ServiceBlueprint
5. Required variables without defaults that are not in `variables` will be prompted to the user at provisioning time

---

## 3. Version Resolution

The `version` field on each service entry supports three formats. Resolution uses the **Version Index** -- a sorted list of semver versions built from git tags in the catalog repo.

### Version Index

q-core builds the version index by listing git tags via GitHub API:

```
GET /repos/{owner}/{repo}/git/refs/tags/{blueprint-name}/
```

For `aws-postgresql`, this might return tags:
```
aws-postgresql/1.0.0
aws-postgresql/1.1.0
aws-postgresql/1.2.0
aws-postgresql/2.0.0
```

Parsed into a sorted list: `[1.0.0, 1.1.0, 1.2.0, 2.0.0]`

### Resolution Formats

| Format | Example | Resolution | Use Case |
|---|---|---|---|
| **Exact** | `"1.2.0"` | Resolves to exactly version 1.2.0 | Production pinning. Fully deterministic. |
| **Train** | `"1.x"` | Resolves to the latest `1.*.*` release (e.g., `1.2.0` from the list above) | Auto-follow minor/patch within major. |
| **Range** | `">=1.1.0 <2.0.0"` | Resolves to the latest version matching the constraint (e.g., `1.2.0`) | Flexible constraints. |

### Resolution at Provisioning Time

When a StackBlueprint is provisioned, q-core resolves each version constraint to an **exact version**, then resolves the exact version to a **git tag**, then resolves the tag to a **commit SHA**:

```
"1.x"  ->  "1.2.0"  ->  tag "aws-postgresql/1.2.0"  ->  commit SHA abc123
```

The commit SHA is used as the `TerraformFilesSource.Git.gitRepository.commit` (or Helm chart version) so that deploys are deterministic.

### VersionIndexService (q-core)

```kotlin
@Service
class VersionIndexService(
    private val gitService: GitService,
    @Value("\${catalog.repository-url}") private val catalogRepoUrl: String,
    @Value("\${catalog.git-token-id}") private val catalogGitTokenId: String,
    @Value("\${catalog.organization-id}") private val catalogOrgId: String,
) {
    // Cache: blueprint name -> sorted list of versions
    private val versionCache = ConcurrentHashMap<String, List<SemVer>>()

    fun getVersions(blueprintName: String): List<SemVer>
    fun resolveVersion(blueprintName: String, constraint: String): SemVer
    fun getTagCommitSha(blueprintName: String, version: SemVer): String
    fun invalidateCache()
}
```

**Implementation:**
- Uses `org.kohsuke:github-api` (already a dependency) to call `GHRepository.listTags()` or the refs API
- Parses tag names: `aws-postgresql/1.2.0` -> blueprint=`aws-postgresql`, version=`1.2.0`
- Sorts by semver descending
- Cached in `ConcurrentHashMap`, invalidated by the same webhook as `BlueprintRegistryService`

---

## 4. Provisioning Flow

### Sequence Diagram

```
 Console              q-core                                            GitHub
   |                    |                                                 |
   | POST /environment/ |                                                 |
   |  {envId}/stack/    |                                                 |
   |  provision         |                                                 |
   | {                  |                                                 |
   |   git_url: "https://github.com/user/infra",                         |
   |   file_path: "stacks/production.yml",                                |
   |   branch: "main",                                                    |
   |   variable_overrides: {                                              |
   |     "main-db": {password: "s3cur3!"},                                |
   |     "analytics-db": {password: "an@lyt1cs!"}                         |
   |   }                                                                  |
   | }                  |                                                 |
   |------------------->|                                                 |
   |                    |                                                 |
   |                    | 1. Fetch StackBlueprint from user's Git repo    |
   |                    |  GitService.getFile(userRepo, "stacks/          |
   |                    |    production.yml")                              |
   |                    |------------------------------------------------>|
   |                    |<------------------------------------------------|
   |                    |                                                 |
   |                    | 2. Parse YAML -> StackBlueprint                 |
   |                    |                                                 |
   |                    | 3. For each service entry:                      |
   |                    |    Resolve version constraint                   |
   |                    |    "1.x" -> "1.2.0" -> tag -> commit SHA        |
   |                    |    VersionIndexService.resolveVersion()          |
   |                    |------------------------------------------------>|
   |                    |<------------------------------------------------|
   |                    |                                                 |
   |                    | 4. For each service entry:                      |
   |                    |    Fetch ServiceBlueprint at resolved version    |
   |                    |    BlueprintRegistryService.getBlueprintManifest |
   |                    |      (name, version)                            |
   |                    |                                                 |
   |                    | 5. Validate all variables:                      |
   |                    |    - Pre-configured from StackBlueprint          |
   |                    |    - Overrides from user request                 |
   |                    |    - Defaults from ServiceBlueprint              |
   |                    |    - Check all required vars are satisfied       |
   |                    |                                                 |
   |                    | 6. Build dependency graph -> deployment stages   |
   |                    |    dependsOn: [] -> Stage 1                     |
   |                    |    dependsOn: ["main-db"] -> Stage 2            |
   |                    |                                                 |
   |                    | 7. For each service (in dependency order):      |
   |                    |    CreateTerraformFromCatalogUseCase.provision() |
   |                    |    or CreateHelmFromCatalogUseCase.provision()   |
   |                    |    -> assigns to computed deployment stage       |
   |                    |                                                 |
   |                    | 8. Trigger environment deploy                   |
   |                    |    StartEnvironmentUseCase.startServices()       |
   |                    |                                                 |
   |  <- 202 Accepted   |                                                 |
   |  {environment_id,  |                                                 |
   |   services: [      |                                                 |
   |     {alias: "main-db", terraform_id: "..."},                         |
   |     {alias: "cache", terraform_id: "..."},                           |
   |     {alias: "analytics-db", terraform_id: "..."}                     |
   |   ]}               |                                                 |
   |<-------------------|                                                 |
   |                    |                                                 |
   |                    | Engine deploys Stage 1:                         |
   |                    |   main-db (aws-postgresql@1.2.0)                |
   |                    |   cache (aws-redis@1.2.0)                       |
   |                    |   -> in parallel                                |
   |                    |                                                 |
   |                    | Stage 1 complete.                               |
   |                    |                                                 |
   |                    | Engine deploys Stage 2:                         |
   |                    |   analytics-db (aws-postgresql@1.2.0)           |
   |                    |                                                 |
   |                    | Stage 2 complete.                               |
   |                    |                                                 |
   |  <- WebSocket: all services deployed                                 |
   |<-------------------|                                                 |
```

### Two-Phase Provisioning (Preview + Confirm)

For better UX, the provisioning can be split into two API calls:

**Phase 1: Preview**
```
POST /environment/{envId}/stack/preview
```
q-core resolves all versions, fetches all blueprints, and returns the fully resolved stack with:
- Each service's resolved version and blueprint detail
- Which variables are pre-filled vs need user input
- Computed deployment stages

**Phase 2: Provision**
```
POST /environment/{envId}/stack/provision
```
User confirms (with any variable overrides) and q-core creates all services.

---

## 5. Dependency Ordering via Deployment Stages

### How `dependsOn` Maps to Existing Deployment Stages

q-core already has a **deployment stage** system that executes stages sequentially, with services within a stage deployed in parallel. The StackBlueprint's `dependsOn` maps directly to this:

**Algorithm (topological sort -> stage assignment):**

```
Input:
  services = [
    {alias: "main-db",      dependsOn: []},
    {alias: "cache",         dependsOn: []},
    {alias: "analytics-db",  dependsOn: ["main-db"]},
    {alias: "monitoring",    dependsOn: ["main-db", "cache"]},
  ]

Step 1: Build adjacency list
  main-db      -> []
  cache        -> []
  analytics-db -> [main-db]
  monitoring   -> [main-db, cache]

Step 2: Topological sort with level assignment
  Level 0 (no dependencies):     main-db, cache
  Level 1 (depends on level 0):  analytics-db, monitoring

Step 3: Map levels to deployment stages
  Stage 1: main-db, cache              (parallel)
  Stage 2: analytics-db, monitoring    (parallel)

Step 4: Cycle detection
  If topological sort fails -> reject with error
```

**Existing code used:**

| Concept | Existing code | How it's used |
|---|---|---|
| Deployment stages | `DeploymentStageService.create()` | Create a stage for each dependency level |
| Stage ordering | `DeploymentStageService.insertStageAt()` | Order stages sequentially |
| Service-to-stage assignment | `DeploymentStageService.attachServiceToStage()` | Assign each service to its computed stage |
| Sequential execution | `EnvEngineDeploymentProcessor` for-loop | Stages execute one after another; services within a stage are parallel |
| Failure handling | Existing: if a stage fails, remaining stages are canceled | Automatic -- no new code needed |

### Resulting Qovery Environment State

After provisioning the example StackBlueprint:

```
Environment: "production"
├── Deployment Stage 1 (order=1, name="Stack: dependencies level 0")
│   ├── Terraform Service: "main-db"       (aws-postgresql@1.2.0)
│   └── Terraform Service: "cache"         (aws-redis@1.2.0)
├── Deployment Stage 2 (order=2, name="Stack: dependencies level 1")
│   ├── Terraform Service: "analytics-db"  (aws-postgresql@1.2.0)
│   └── Terraform Service: "monitoring"    (k8s-prometheus@1.0.0) [Helm, future]
```

---

## 6. Variable Resolution

When provisioning a StackBlueprint, variables are resolved with this priority (highest wins):

```
1. Injected variables          (from cluster/environment context -- always applied, never overridden)
2. User overrides at provision (from the API request's variable_overrides map)
3. StackBlueprint variables    (from spec.services[].variables map)
4. ServiceBlueprint defaults   (from the catalog qsm.yml userVariables[].default)
```

### Example

For the `main-db` service entry:

```yaml
# StackBlueprint says:
variables:
  instance_class: "db.r6g.large"   # priority 3
  multi_az: "true"                 # priority 3
  disk_size: "100"                 # priority 3

# ServiceBlueprint (aws-postgresql qsm.yml) says:
userVariables:
  - name: "instance_class"
    default: "db.t3.micro"         # priority 4 (overridden by StackBlueprint)
  - name: "password"
    required: true                 # no default -> must come from user override (priority 2)
  - name: "database_name"
    default: "postgres"            # priority 4 (no override -> uses this default)

# User provides at provisioning time:
variable_overrides:
  "main-db":
    password: "s3cur3!"            # priority 2

# Injected by q-core:
cluster.region -> "eu-west-3"     # priority 1 (always applied)
cluster.vpc_id -> "vpc-abc123"    # priority 1
```

**Final merged variables for `main-db`:**

| Variable | Value | Source |
|---|---|---|
| `region` | `"eu-west-3"` | Injected (priority 1) |
| `vpc_id` | `"vpc-abc123"` | Injected (priority 1) |
| `instance_class` | `"db.r6g.large"` | StackBlueprint (priority 3) |
| `multi_az` | `"true"` | StackBlueprint (priority 3) |
| `disk_size` | `"100"` | StackBlueprint (priority 3) |
| `password` | `"s3cur3!"` | User override (priority 2) |
| `database_name` | `"production"` | StackBlueprint (priority 3) |
| `username` | `"qovery"` | ServiceBlueprint default (priority 4) |

### Missing Required Variables

If a required variable with no default is not provided by any source, q-core returns an error listing all missing variables per service:

```json
{
  "error": "MISSING_REQUIRED_VARIABLES",
  "details": {
    "main-db": ["password"],
    "analytics-db": ["password"]
  }
}
```

The console can use Phase 1 (preview) to detect this before submission.

---

## 7. q-core Implementation

### New Files

```
corenetto/src/main/kotlin/com/qovery/corenetto/service/catalog/
├── domain/
│   └── StackBlueprint.kt                          # StackBlueprint YAML -> Kotlin model
├── service/
│   ├── VersionIndexService.kt                     # Git tags -> semver index
│   └── StackBlueprintProvisioningUseCase.kt       # Orchestrates multi-service creation
└── web/
    └── StackBlueprintDtos.kt                      # API DTOs
```

#### `StackBlueprint.kt`

```kotlin
data class StackBlueprint(
    val apiVersion: String,
    val kind: String,
    val metadata: Metadata,
    val spec: Spec,
) {
    data class Metadata(
        val name: String,
        val version: String,
        val description: String,
    )

    data class Spec(
        val services: List<ServiceEntry>,
    )

    data class ServiceEntry(
        val blueprint: String,
        val version: String,
        val alias: String,
        val variables: Map<String, String> = emptyMap(),
        val dependsOn: List<String> = emptyList(),
    )
}
```

#### `StackBlueprintProvisioningUseCase.kt`

```kotlin
@Service
class StackBlueprintProvisioningUseCase(
    private val gitService: GitService,
    private val blueprintRegistryService: BlueprintRegistryService,
    private val versionIndexService: VersionIndexService,
    private val createTerraformFromCatalogUseCase: CreateTerraformFromCatalogUseCase,
    // future: private val createHelmFromCatalogUseCase: CreateHelmFromCatalogUseCase,
    private val deploymentStageService: DeploymentStageService,
    private val startEnvironmentUseCase: StartEnvironmentUseCase,
) {
    @Transactional
    fun provision(
        environmentId: Id,
        request: ProvisionStackRequest,
    ): Result<StackProvisionResult, StackException>
}
```

**Pseudocode:**

```
fun provision(environmentId, request):
    // 1. Fetch StackBlueprint from user's Git repo
    userRepo = gitService.buildRepository(request.gitUrl, ...)
    stackYaml = gitService.getFile(userRepo, request.filePath, orgId)
    stack = yamlMapper.readValue<StackBlueprint>(stackYaml)

    // 2. Validate structure
    validateAliasesUnique(stack.spec.services)
    validateNoCycles(stack.spec.services)

    // 3. Resolve versions
    resolvedServices = stack.spec.services.map { entry ->
        val version = versionIndexService.resolveVersion(entry.blueprint, entry.version)
        val commitSha = versionIndexService.getTagCommitSha(entry.blueprint, version)
        ResolvedService(entry, version, commitSha)
    }

    // 4. Compute deployment stages from dependsOn (topological sort)
    stageLevels = topologicalSort(resolvedServices)
    //   Level 0: [main-db, cache]
    //   Level 1: [analytics-db]

    // 5. Create deployment stages
    stages = stageLevels.mapIndexed { level, services ->
        deploymentStageService.create(environmentId,
            name = "Stack: level $level",
            deploymentOrder = level + 1
        )
    }

    // 6. For each service, create via catalog use case
    createdServices = resolvedServices.map { resolved ->
        // Merge variables: user overrides > stack variables > blueprint defaults
        val mergedVars = mergeVariables(
            stackVars = resolved.entry.variables,
            userOverrides = request.variableOverrides[resolved.entry.alias] ?: emptyMap(),
        )

        val terraform = createTerraformFromCatalogUseCase.provision(
            environmentId,
            ProvisionFromCatalogRequest(
                blueprintName = resolved.entry.blueprint,
                serviceName = resolved.entry.alias,
                userVariables = mergedVars,
                outputAliases = buildAliasMap(resolved.entry.alias, resolved.blueprint),
                commitSha = resolved.commitSha,  // pin to resolved version
            ),
        )

        // Assign to computed stage
        val stageLevel = stageLevels.indexOfFirst { it.contains(resolved) }
        deploymentStageService.attachServiceToStage(
            environmentId,
            terraform.id,
            stages[stageLevel].id,
        )

        terraform
    }

    // 7. Trigger deploy
    startEnvironmentUseCase.startServices(environmentId, createdServices.map { it.id })

    return StackProvisionResult(environmentId, createdServices)
```

### New API Endpoints

```kotlin
// In CatalogApi.kt
@PostMapping("/api/environment/{environmentId}/stack/preview")
fun previewStack(jwt, environmentId, body: ProvisionStackRequest): ResponseEntity<StackPreviewResponse>

@PostMapping("/api/environment/{environmentId}/stack/provision")
fun provisionStack(jwt, environmentId, body: ProvisionStackRequest): ResponseEntity<StackProvisionResponse>
```

### Database Changes

No additional DB changes beyond what's already specified for the Terraform catalog (the `catalog_blueprint_name`, `catalog_blueprint_version`, and `catalog_output_aliases` columns). Each service in a stack is a regular Terraform/Helm entity with catalog metadata.

---

## 8. Examples

### Example 1: Simple Web App Stack

```yaml
apiVersion: "qovery.com/v1"
kind: "StackBlueprint"
metadata:
  name: "web-app-stack"
  version: "1.0.0"
  description: "Standard web application with PostgreSQL and Redis"
spec:
  services:
    - blueprint: "aws-postgresql"
      version: "1.x"
      alias: "db"
      variables:
        instance_class: "db.t3.small"
        database_name: "webapp"

    - blueprint: "aws-redis"
      version: "1.x"
      alias: "cache"
      variables:
        node_type: "cache.t4g.micro"
```

**Result:**
- Stage 1: `db` + `cache` deploy in parallel
- Environment variables created:
  - `DB_POSTGRESQL_HOST`, `DB_POSTGRESQL_PORT`, ...
  - `CACHE_REDIS_HOST`, `CACHE_REDIS_PORT`, ...

### Example 2: Multi-Tier with Dependencies

```yaml
apiVersion: "qovery.com/v1"
kind: "StackBlueprint"
metadata:
  name: "multi-tier"
  version: "1.0.0"
  description: "Multi-tier architecture with primary DB, read replica, and cache"
spec:
  services:
    - blueprint: "aws-postgresql"
      version: "1.2.0"
      alias: "primary-db"
      variables:
        instance_class: "db.r6g.large"
        multi_az: "true"

    - blueprint: "aws-postgresql"
      version: "1.2.0"
      alias: "read-replica"
      variables:
        instance_class: "db.r6g.large"
      dependsOn: ["primary-db"]

    - blueprint: "aws-redis"
      version: ">=1.0.0 <2.0.0"
      alias: "app-cache"
      variables:
        node_type: "cache.r6g.large"
      dependsOn: ["primary-db"]
```

**Result:**
- Stage 1: `primary-db`
- Stage 2: `read-replica` + `app-cache` (parallel, both depend only on `primary-db`)

### Example 3: Version Pinning Strategies

```yaml
spec:
  services:
    # Exact pin: production database, never auto-update
    - blueprint: "aws-postgresql"
      version: "1.2.0"
      alias: "prod-db"

    # Train: follow latest 1.x, auto-get bug fixes and new features
    - blueprint: "aws-redis"
      version: "1.x"
      alias: "cache"

    # Range: flexible but bounded
    - blueprint: "aws-mysql"
      version: ">=1.1.0 <2.0.0"
      alias: "legacy-db"
```
