# Implementation Changes

Detailed breakdown of what changes in each codebase, and what stays the same.

## Table of Contents

1. [What Stays the Same](#1-what-stays-the-same)
2. [q-core Changes](#2-q-core-changes)
3. [Engine Changes](#3-engine-changes)
4. [Database Changes](#4-database-changes)
5. [service-catalog Repo Changes](#5-service-catalog-repo-changes)
6. [Console (Frontend) Changes](#6-console-frontend-changes)

---

## 1. What Stays the Same

### Engine (Rust) -- No MVP Changes

The engine is **completely untouched** for the Terraform catalog MVP. It already:

- Deploys Terraform services as Kubernetes Jobs (generic, no catalog awareness)
- Runs `terraform init` + `terraform apply` on any Git repo at any commit SHA
- Extracts outputs via `terraform output -json`
- Sends resources back to q-core via `sendTerraformResources` gRPC
- Sends outputs back via the event logging system (`TerraformServiceOutput`)
- Handles credentials injection via `use_cluster_credentials`

The engine operates on `TerraformService` models passed via gRPC -- it has no concept of "catalog". A catalog-created Terraform service is indistinguishable from a manually-created one.

**Future engine changes** (Helm blueprints, not MVP): see [Section 3](#3-engine-changes).

### Existing q-core Terraform Pipeline -- Unchanged

These existing components are **reused as-is**, not modified:

| Component | File(s) | Why unchanged |
|---|---|---|
| `TerraformServiceCreationUseCase` | `service/terraform/service/TerraformServiceCreationUseCase.kt` | Called by the new catalog use case. Validates, persists, creates builtin vars, assigns deployment stage. |
| `TerraformDomain.create()` | `service/terraform/domain/TerraformDomain.kt` | All validation logic (name, resources, git source, variables) works for catalog services. |
| `TerraformMutationRequest` | `service/terraform/domain/TerraformMutationRequest.kt` | The catalog use case builds this request from QSM data and passes it to the existing creation flow. |
| `TerraformVariablesCreationService` | `core/variable/service/TerraformVariablesCreationService.kt` | Creates `QOVERY_TERRAFORM_*` builtin variables. Works unchanged. |
| `DeploymentStageService` | `core/services/DeploymentStageService.kt` | Assigns the new service to a deployment stage. Works unchanged. |
| `StartEnvironmentUseCase` | `deployment/environment/service/StartEnvironmentUseCase.kt` | Triggers deployment. Works unchanged. |
| `EngineRequestService` | `deployment/service/EngineRequestService.kt` | Builds engine request from Terraform entity. Works unchanged. |
| `VariableDomain` | `core/variable/domain/VariableDomain.kt` | Alias system, variable resolution, scope hierarchy. Works unchanged. |
| `VariableCreationService` | `core/variable/service/VariableCreationService.kt` | Used by alias bridge to create new ALIAS variables. Works unchanged. |
| `GitService` | `git/service/GitService.kt` | Reads files from Git repos. Used to fetch qsm.yml from catalog repo. Works unchanged. |
| Deployment queue | `deployment/queue/` | One deployment per environment. Works unchanged. |
| Redis engine communication | `deployment/service/RedisEngineService.kt` | Sends engine requests. Works unchanged. |

### Existing q-core Output Pipeline -- Modified Minimally

| Component | Change |
|---|---|
| `EngineCoreConfigurationUpdateService` | **Additive change only**. After existing BUILT_IN + ALIAS creation, adds a new step for QSM_ alias bridge. Existing behavior for non-catalog services is untouched. |

---

## 2. q-core Changes

### 2.1 New Files

```
corenetto/src/main/kotlin/com/qovery/corenetto/service/catalog/
├── domain/
│   └── BlueprintManifest.kt           # QSM YAML -> Kotlin domain model
├── service/
│   ├── BlueprintRegistryService.kt    # Fetch, parse, cache blueprints from GitHub
│   ├── InjectedVariableResolver.kt    # Resolve cluster/env context -> variable values
│   └── CreateTerraformFromCatalogUseCase.kt  # Blueprint -> TerraformMutationRequest -> existing creation
└── web/
    ├── CatalogDtos.kt                 # DTOs (from dto/CatalogApi.kt, adapted)
    └── ProvisionFromCatalogRequest.kt # Provisioning request DTO
```

#### `BlueprintManifest.kt`

Domain model deserialized from `qsm.yml` via Jackson YAML.

```kotlin
data class BlueprintManifest(
    val apiVersion: String,
    val kind: String,
    val metadata: Metadata,
    val spec: Spec,
) {
    data class Metadata(
        val name: String,
        val version: String,
        val description: String,
        val icon: String? = null,
    )

    data class Spec(
        val provider: String,
        val categories: List<String>,
        val engine: String,
        val engineVersionConstraint: String? = null,
        val injectedVariables: List<InjectedVariable> = emptyList(),
        val userVariables: List<UserVariable> = emptyList(),
        val outputs: List<Output> = emptyList(),
        val dependencies: List<Dependency> = emptyList(),
        val helm: HelmSpec? = null,              // future: Helm blueprints
    )

    data class InjectedVariable(
        val name: String,
        val source: String,
    )

    data class UserVariable(
        val name: String,
        val type: String,
        val required: Boolean,
        val default: String? = null,
        val description: String,
        val sensitive: Boolean = false,
        val options: List<String>? = null,
        val validation: Validation? = null,
        val valuePath: String? = null,           // future: Helm valuePath mapping
    )

    data class Validation(
        val min: Double? = null,
        val max: Double? = null,
        val pattern: String? = null,
    )

    data class Output(
        val name: String,
        val description: String,
        val sensitive: Boolean = false,
        val source: String? = null,              // future: Helm output source
    )

    data class Dependency(
        val blueprint: String,
        val reason: String,
    )

    data class HelmSpec(                         // future
        val chart: HelmChart,
        val namespace: String? = null,
        val timeout: Int? = null,
    )

    data class HelmChart(                        // future
        val repository: String,
        val name: String,
        val version: String,
    )
}
```

#### `BlueprintRegistryService.kt`

Fetches and caches blueprints from the `service-catalog` GitHub repo.

```kotlin
@Service
class BlueprintRegistryService(
    private val gitService: GitService,
    private val gitTokenService: GitTokenService,
    @Value("\${catalog.repository-url}") private val catalogRepoUrl: String,
    @Value("\${catalog.git-token-id}") private val catalogGitTokenId: String,
    @Value("\${catalog.organization-id}") private val catalogOrgId: String,
) {
    private val cache = ConcurrentHashMap<String, BlueprintManifest>()
    private val yamlMapper = ObjectMapper(YAMLFactory())
        .registerModule(KotlinModule.Builder().build())

    fun listBlueprints(provider: String?, category: String?): List<BlueprintManifest>
    fun getBlueprintManifest(blueprintName: String): BlueprintManifest
    fun invalidateCache()
    // Internal:
    private fun populateCache()
    private fun fetchBlueprint(provider: String, serviceName: String): BlueprintManifest
}
```

**Key implementation details:**
- Uses `GitService.getProviderServiceForToken(orgId, gitTokenId)` for auth -- no user-scoped credentials needed
- Calls `gitProvider.listEntriesInDirectory()` to discover `aws/`, `gcp/`, `azure/` subdirectories
- Calls `gitProvider.getFileFromRepository()` to read each `qsm.yml`
- Cache is a flat `ConcurrentHashMap<String, BlueprintManifest>` keyed by `metadata.name`
- `invalidateCache()` clears the entire map; next request triggers re-fetch

#### `InjectedVariableResolver.kt`

Resolves QSM `injectedVariables[].source` paths to actual values from the cluster/environment context.

```kotlin
@Service
class InjectedVariableResolver(
    private val environmentQueryService: EnvironmentQueryService,
    private val kubernetesProviderRepository: KubernetesProviderJpaRepository,
    private val projectQueryService: ProjectQueryService,
) {
    fun resolve(
        injectedVariables: List<BlueprintManifest.InjectedVariable>,
        environmentId: Id,
    ): List<TerraformMutationRequest.InputVariable>
}
```

**Resolution table (what existing code provides):**

| Source | Resolved from | Existing code |
|---|---|---|
| `cluster.name` | `KubernetesProvider.name` | `kubernetesProviderRepository.findById()` |
| `cluster.region` | `KubernetesProvider.region.regionName` | `.getRegionName()` |
| `cluster.vpc_id` | `EksInfrastructureOutputs.vpcId` | `.infrastructureOutputs.getVpcId()` |
| `cluster.subnet_ids` | **Not in InfrastructureOutputs yet** | Requires future addition (see note) |
| `cluster.security_group_ids` | **Not in InfrastructureOutputs yet** | Requires future addition (see note) |
| `environment.id` | `Environment.id` | `environmentQueryService.getById()` |
| `project.id` | `Environment.projectId` | Direct from environment |
| `organization.id` | `Project.organizationId` | `projectQueryService.getById()` |

**Note on `subnet_ids` / `security_group_ids`:** These are not currently stored in `InfrastructureOutputs`. Two paths:
- **Short-term (MVP):** Move these to `userVariables` in `qsm.yml` so users provide them manually.
- **Long-term:** Add `subnetIds: List<String>` and `securityGroupIds: List<String>` to `EksInfrastructureOutputs`, update the engine's `ClusterOutputsUpdateRequest` to report them, and wire the resolution. This spans engine + q-core.

#### `CreateTerraformFromCatalogUseCase.kt`

The main orchestrator. Bridges catalog blueprint data into the existing Terraform creation pipeline.

```kotlin
@Service
class CreateTerraformFromCatalogUseCase(
    private val blueprintRegistryService: BlueprintRegistryService,
    private val injectedVariableResolver: InjectedVariableResolver,
    private val terraformServiceCreationUseCase: TerraformServiceCreationUseCase,
    private val terraformRepository: TerraformRepository,
    private val gitService: GitService,
    private val terraformVersionsQueryUseCase: TerraformVersionsQueryUseCase,
    @Value("\${catalog.repository-url}") private val catalogRepoUrl: String,
    @Value("\${catalog.git-token-id}") private val catalogGitTokenId: String,
    @Value("\${catalog.organization-id}") private val catalogOrgId: String,
) {
    @Transactional
    fun provision(
        environmentId: Id,
        request: ProvisionFromCatalogRequest,
    ): Result<Terraform, CatalogException>
}
```

**What it does, step by step:**

1. `blueprintRegistryService.getBlueprintManifest(request.blueprintName)`
2. Validate `request.userVariables` against `blueprint.spec.userVariables` (required, type, options, validation rules)
3. `injectedVariableResolver.resolve(blueprint.spec.injectedVariables, environmentId)`
4. Merge all variables into `List<TerraformMutationRequest.InputVariable>`:
   - Injected vars (secret = false)
   - User-provided vars (secret = true if `sensitive` in QSM)
   - Defaults for optional vars not in user input
5. Resolve the catalog Git repo as `GitRepository` via `gitService.getProviderServiceForToken()` + `gitProvider.getRepository()`
6. Build `TerraformMutationRequest` (see mapping table below)
7. Call `terraformServiceCreationUseCase.create(environmentId, request)` -- **existing code, unchanged**
8. Update the created entity with catalog metadata via `terraformRepository.updateCatalogMetadata()`
9. Return the created Terraform

**`TerraformMutationRequest` field mapping:**

| Field | Value | Source |
|---|---|---|
| `name` | `request.serviceName` | User input |
| `description` | `blueprint.metadata.description` | qsm.yml |
| `terraformFilesSource` | `Git(catalogGitRepo, Path.of("{provider}/{service}/"))` | Computed |
| `inputVariables` | Merged injected + user + defaults | Resolved |
| `valueFilesSource` | `emptyList()` | No tfvars |
| `engine` | `TERRAFORM` or `OPEN_TOFU` | From `spec.engine` |
| `backend` | `KUBERNETES` | Always for catalog |
| `providerVersion` | Best match from versions list | From `spec.engineVersionConstraint` |
| `timeoutSec` | `600` (10 min default) | Reasonable default |
| `autoDeployConfig` | `AutoDeployConfig(false)` | No auto-deploy |
| `jobCpuMilli` | `CPU(500)` | Default |
| `jobRamMib` | `RAM_MB(512)` | Default |
| `jobGpu` | `GPU(0)` | Default |
| `jobStorageSizeGib` | `StorageSizeGib(1)` | Default minimum |
| `advancedSettings` | `TerraformAdvancedSettings()` | Defaults |
| `iconUri` | `blueprint.metadata.icon` | qsm.yml |
| `useClusterCredentials` | `true` | Catalog uses cluster creds |
| `actionExtraArguments` | `emptySortedMap()` | Default |
| `dockerfileFragment` | `null` | Not used |

### 2.2 Modified Files

#### `CatalogApi.kt` -- Replace Stub Endpoints

**Before (current):**
```kotlin
interface CatalogApi {
    @GetMapping("/api/catalog/services")
    fun listServices(jwt, provider, body): ResponseEntity<ListCatalogServicesResponse>

    @GetMapping("/api/catalog/services/manifest")
    fun getServiceManifest(jwt, body): ResponseEntity<GetCatalogServiceManifestResponse>
}
```

**After:**
```kotlin
interface CatalogApi {
    @GetMapping("/api/catalog/blueprints")
    fun listBlueprints(jwt, provider, category, search): ResponseEntity<ListBlueprintsResponse>

    @GetMapping("/api/catalog/blueprints/{name}")
    fun getBlueprintDetail(jwt, name): ResponseEntity<BlueprintDetailResponse>

    @PostMapping("/api/environment/{environmentId}/catalog/provision")
    fun provisionFromCatalog(jwt, environmentId, body): ResponseEntity<ProvisionResponse>

    @PostMapping("/internal/catalog/webhook")
    fun handleWebhook(body): ResponseEntity<Unit>
}
```

#### `CatalogApiController.kt` -- Implement Endpoints

**Before (current):**
```kotlin
override fun listServices(...) {
    gitService.buildRepository()  // stub, no return
}
override fun getServiceManifest(...) {
    TODO("Not yet implemented")
}
```

**After:**
```kotlin
override fun listBlueprints(jwt, provider, category, search) {
    val blueprints = blueprintRegistryService.listBlueprints(provider, category)
    // filter by search if provided
    // map to ListBlueprintsResponse
    return ResponseEntity.ok(response)
}

override fun getBlueprintDetail(jwt, name) {
    val manifest = blueprintRegistryService.getBlueprintManifest(name)
    // map to BlueprintDetailResponse
    return ResponseEntity.ok(response)
}

override fun provisionFromCatalog(jwt, environmentId, body) {
    authorizationService.checkEnvironmentPermission(jwt, environmentId, MANAGER)
    val terraform = createTerraformFromCatalogUseCase.provision(environmentId, body)
    // trigger deploy
    return ResponseEntity.accepted().body(ProvisionResponse(terraform.id))
}

override fun handleWebhook(body) {
    blueprintRegistryService.invalidateCache()
    return ResponseEntity.ok().build()
}
```

#### `EngineCoreConfigurationUpdateService.kt` -- Add QSM Alias Bridge

**Location in existing flow:** After `createNewVariablesAndSecrets()` (line ~219), add:

```kotlin
// NEW: QSM Alias Bridge for catalog-provisioned services
private fun createCatalogAliases(
    terraformId: Id,
    newOutputs: Map<String, OutputEntry>,
    environmentId: Id,
) {
    val terraform = terraformRepository.findById(terraformId) ?: return
    val aliasMap = terraform.catalogOutputAliases ?: return  // not a catalog service

    for ((outputKey, outputEntry) in newOutputs) {
        if (!outputKey.startsWith("QSM_")) continue

        val userAlias = aliasMap[outputKey] ?: continue
        val suffix = outputKey.removePrefix("QSM_")        // "POSTGRESQL_HOST"
        val aliasName = "${userAlias}_${suffix}"            // "MY_DATABASE_POSTGRESQL_HOST"

        // Check alias doesn't already exist
        if (variableAlreadyExists(aliasName, environmentId)) continue

        // Create ALIAS at ENVIRONMENT scope pointing to the BUILT_IN var
        val builtInName = "${TERRAFORM_OUTPUT_PREFIX}${terraformId.toShortQoveryId().uppercase()}_${outputKey}"
        variableCreationService.createBuiltInVariable(
            name = aliasName,
            value = builtInName,           // alias target
            type = VariableType.ALIAS,
            scope = VariableScope.ENVIRONMENT,
            environmentId = environmentId,
            sensitive = outputEntry.sensitive,
        )
    }
}
```

#### `TerraformJpaEntity.kt` -- Add Catalog Metadata Fields

Add three nullable columns:

```kotlin
@Column(name = "catalog_blueprint_name")
var catalogBlueprintName: String? = null

@Column(name = "catalog_blueprint_version")
var catalogBlueprintVersion: String? = null

@Column(name = "catalog_output_aliases", columnDefinition = "jsonb")
@JdbcTypeCode(SqlTypes.JSON)
var catalogOutputAliases: Map<String, String>? = null
```

#### `Terraform.kt` (domain) -- Add Catalog Metadata Fields

```kotlin
data class Terraform(
    // ... existing fields ...
    val catalogBlueprintName: String? = null,
    val catalogBlueprintVersion: String? = null,
    val catalogOutputAliases: Map<String, String>? = null,
)
```

### 2.3 Configuration

Add to `application.yml`:

```yaml
catalog:
  repository-url: "https://github.com/Qovery/service-catalog"
  git-provider: "GITHUB"
  organization-id: "${CATALOG_ORGANIZATION_ID}"
  git-token-id: "${CATALOG_GIT_TOKEN_ID}"
```

---

## 3. Engine Changes

### MVP -- None

No engine changes for the Terraform catalog MVP.

### Future -- Helm Output Extraction

When Helm blueprints are implemented, the engine needs a post-install output extraction step.

**File to modify:** `lib-engine/src/environment/action/deploy_helm_chart.rs`

**Where in the flow:** After `helm upgrade --install` succeeds (in `on_create()`), before returning `Ok(())`.

**What to add:**

1. Accept output source specs as metadata on the Helm service (passed from q-core via the engine request JSON)
2. For each output spec, query Kubernetes:
   - `configmap:{ns}/{name}:{key}` -> `kubectl get cm {name} -n {ns} -o jsonpath='{.data.{key}}'`
   - `service:{ns}/{name}:{port}` -> `kubectl get svc {name} -n {ns}` -> extract ClusterIP + port
   - `secret:{ns}/{name}:{key}` -> `kubectl get secret {name} -n {ns}` -> base64 decode
3. Package results as JSON (same format as `terraform output -json`)
4. Send back via the logging system using a new method on `EnvSuccessLogger`:
   ```rust
   logger.core_configuration_for_helm_service(
       "Helm output extraction succeeded. Environment variables will be synchronized.",
       serde_json::to_string(&outputs).unwrap_or_else(|_| "{}".to_string()),
   );
   ```

**Files to modify in engine:**
- `lib-engine/src/environment/action/deploy_helm_chart.rs` -- add output extraction step
- `lib-engine/src/environment/report/logger.rs` -- add `core_configuration_for_helm_service()` method
- `lib-engine/src/events/mod.rs` -- add `HelmServiceOutput` stage variant
- `lib-engine/src/io_models/helm_chart.rs` -- add output source specs to the IO model

**Files to modify in q-core (for Helm outputs):**
- `deployment/service/EngineCoreConfigurationUpdateService.kt` -- add `updateHelmEnvironmentVariables()` method
- `deployment/model/EngineLogDto.kt` -- add `HelmOutputConfiguration` to `ConfigurationStep` enum
- `deployment/environment/service/EnvEngineDeploymentProcessor.kt` -- handle Helm output events

---

## 4. Database Changes

### Flyway Migration

**One migration file** adding catalog tracking columns to the `terraform` table.

```sql
-- V{next}__add_catalog_metadata_to_terraform.sql

ALTER TABLE terraform
    ADD COLUMN catalog_blueprint_name VARCHAR(255),
    ADD COLUMN catalog_blueprint_version VARCHAR(50),
    ADD COLUMN catalog_output_aliases JSONB;

-- Index for querying services by blueprint (useful for upgrade detection later)
CREATE INDEX idx_terraform_catalog_blueprint_name
    ON terraform (catalog_blueprint_name)
    WHERE catalog_blueprint_name IS NOT NULL;

-- Future: Helm catalog metadata
-- ALTER TABLE helm
--     ADD COLUMN catalog_blueprint_name VARCHAR(255),
--     ADD COLUMN catalog_blueprint_version VARCHAR(50),
--     ADD COLUMN catalog_output_aliases JSONB;
```

### Column Semantics

| Column | Type | Nullable | Description |
|---|---|---|---|
| `catalog_blueprint_name` | `VARCHAR(255)` | YES | Blueprint name (e.g., `"aws-postgresql"`). NULL for non-catalog services. |
| `catalog_blueprint_version` | `VARCHAR(50)` | YES | Blueprint version at provisioning time (e.g., `"1.0.0"`). NULL for non-catalog services. |
| `catalog_output_aliases` | `JSONB` | YES | User-chosen alias map. Example: `{"QSM_POSTGRESQL_HOST": "MY_DATABASE", "QSM_POSTGRESQL_PORT": "MY_DATABASE"}`. NULL for non-catalog services. |

### No Changes to Existing Tables

The existing tables are **not modified**:

| Table | Status |
|---|---|
| `terraform` | 3 new nullable columns added (additive) |
| `helm` | No changes (future) |
| `environment_variable` | No changes -- aliases use existing `type = 'ALIAS'` |
| `deployment_stage` / `deployment_stage_service` | No changes |
| `git_repository` | No changes |
| `kubernetes_provider` | No changes (future: add subnet_ids, security_group_ids to infrastructure_outputs) |

---

## 5. service-catalog Repo Changes

### QSM Schema Update

Remove `tags`, `uiHint`, and `resources` from the schema. Use `categories` (array) instead of `category` (single string) in the spec. See the updated `qsm-schema.json` and `qsm.yml` files.

### Blueprint qsm.yml Updates

All four blueprints need:
1. `metadata.tags` -> remove (use `spec.categories` instead)
2. `spec.category` (string) -> `spec.categories` (array)
3. Remove `uiHint` from all `userVariables`
4. Remove `resources` section

---

## 6. Console (Frontend) Changes

> Out of scope for this document, but listed for completeness.

### New Pages/Components

| Page | Route | Description |
|---|---|---|
| Catalog Browser | `/environment/{id}/catalog` | Grid of blueprint cards with provider/category filters and search |
| Blueprint Detail | `/environment/{id}/catalog/{name}` | Full blueprint info with "Provision" button |
| Provisioning Form | `/environment/{id}/catalog/{name}/provision` | 3-step wizard: Name -> Variables -> Aliases |

### API Integration

| Endpoint | Used by |
|---|---|
| `GET /catalog/blueprints` | Catalog browser (list + filter) |
| `GET /catalog/blueprints/{name}` | Blueprint detail page |
| `POST /environment/{id}/catalog/provision` | Provisioning form submission |

### Existing Pages Modified

| Page | Change |
|---|---|
| Terraform Service Detail | Show "Catalog: aws-postgresql v1.0.0" badge when `catalog_blueprint_name` is set |
| Environment Variable List | Show catalog aliases with their QSM_ source |
