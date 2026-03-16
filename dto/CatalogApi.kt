package com.qovery.core.catalog.dto

import com.fasterxml.jackson.annotation.JsonCreator
import com.fasterxml.jackson.annotation.JsonProperty
import com.fasterxml.jackson.annotation.JsonValue

// ──────────────────────────────────────────────
// Enums
// ──────────────────────────────────────────────

enum class CloudProvider(
    @JsonValue val value: String,
) {
    AWS("aws"),
    GCP("gcp"),
    AZURE("azure"),
    SCALEWAY("scaleway"),
    ;

    companion object {
        @JsonCreator
        @JvmStatic
        fun fromValue(value: String): CloudProvider = entries.first { it.value == value }
    }
}

enum class BlueprintCategory(
    @JsonValue val value: String,
) {
    STORAGE("storage"),
    DATABASE("database"),
    CACHE("cache"),
    MESSAGING("messaging"),
    NETWORKING("networking"),
    COMPUTE("compute"),
    SECURITY("security"),
    MONITORING("monitoring"),
    OTHER("other"),
    ;

    companion object {
        @JsonCreator
        @JvmStatic
        fun fromValue(value: String): BlueprintCategory = entries.first { it.value == value }
    }
}

enum class BlueprintEngine(
    @JsonValue val value: String,
) {
    TERRAFORM("terraform"),
    OPENTOFU("opentofu"),
    ;

    companion object {
        @JsonCreator
        @JvmStatic
        fun fromValue(value: String): BlueprintEngine = entries.first { it.value == value }
    }
}

enum class VariableType(
    @JsonValue val value: String,
) {
    STRING("string"),
    NUMBER("number"),
    BOOL("bool"),
    ;

    companion object {
        @JsonCreator
        @JvmStatic
        fun fromValue(value: String): VariableType = entries.first { it.value == value }
    }
}

enum class InjectedSource(
    @JsonValue val value: String,
) {
    CLUSTER_NAME("cluster.name"),
    CLUSTER_REGION("cluster.region"),
    CLUSTER_VPC_ID("cluster.vpc_id"),
    CLUSTER_SUBNET_IDS("cluster.subnet_ids"),
    CLUSTER_SECURITY_GROUP_IDS("cluster.security_group_ids"),
    ENVIRONMENT_ID("environment.id"),
    PROJECT_ID("project.id"),
    ORGANIZATION_ID("organization.id"),
    ;

    companion object {
        @JsonCreator
        @JvmStatic
        fun fromValue(value: String): InjectedSource = entries.first { it.value == value }
    }
}

// ──────────────────────────────────────────────
// 1. List Blueprints
//
//    GET /catalog/blueprints?provider=aws&category=database&search=postgres
// ──────────────────────────────────────────────

data class ListBlueprintsRequest(
    @JsonProperty("provider")
    val provider: CloudProvider? = null,
    @JsonProperty("category")
    val category: BlueprintCategory? = null,
    @JsonProperty("search")
    val search: String? = null,
)

data class ListBlueprintsResponse(
    @JsonProperty("blueprints")
    val blueprints: List<BlueprintSummaryDto>,
)

data class BlueprintSummaryDto(
    /** Unique name, e.g. "aws-postgresql". */
    @JsonProperty("name")
    val name: String,
    /** Human-readable name for the UI card, e.g. "RDS Postgres". */
    @JsonProperty("displayed_name")
    val displayedName: String,
    @JsonProperty("description")
    val description: String,
    @JsonProperty("icon")
    val icon: String? = null,
    @JsonProperty("provider")
    val provider: CloudProvider,
    @JsonProperty("categories")
    val categories: List<BlueprintCategory>,
    @JsonProperty("engine")
    val engine: BlueprintEngine,
    /** Highest semver version available. */
    @JsonProperty("latest_version")
    val latestVersion: String,
    /** All published versions sorted ascending. Built from git tags. */
    @JsonProperty("available_versions")
    val availableVersions: List<String>,
)

// ──────────────────────────────────────────────
// 2. Get Blueprint Detail
//
//    GET /catalog/blueprints/{name}?version=1.2.0
//
//    If version is omitted, returns the latest.
// ──────────────────────────────────────────────

data class BlueprintDetailResponse(
    // ── Metadata (same as summary) ──────────
    @JsonProperty("name")
    val name: String,
    @JsonProperty("displayed_name")
    val displayedName: String,
    @JsonProperty("description")
    val description: String,
    @JsonProperty("icon")
    val icon: String? = null,
    @JsonProperty("provider")
    val provider: CloudProvider,
    @JsonProperty("categories")
    val categories: List<BlueprintCategory>,
    @JsonProperty("engine")
    val engine: BlueprintEngine,
    /** The exact resolved version being returned. */
    @JsonProperty("version")
    val version: String,
    /** All published versions for this blueprint. */
    @JsonProperty("available_versions")
    val availableVersions: List<String>,
    // ── Version constraint on the engine binary ──
    @JsonProperty("engine_version_constraint")
    val engineVersionConstraint: String? = null,
    // ── Spec details ────────────────────────
    @JsonProperty("injected_variables")
    val injectedVariables: List<InjectedVariableDto>,
    @JsonProperty("user_variables")
    val userVariables: List<UserVariableDto>,
    @JsonProperty("outputs")
    val outputs: List<OutputDto>,
    @JsonProperty("dependencies")
    val dependencies: List<DependencyDto> = emptyList(),
    // ── Upgrade info (populated by q-core) ──
    @JsonProperty("upgrade_available")
    val upgradeAvailable: Boolean = false,
    @JsonProperty("latest_version")
    val latestVersion: String? = null,
)

// ──────────────────────────────────────────────
// Sub-DTOs
// ──────────────────────────────────────────────

data class InjectedVariableDto(
    /** Variable name as declared in variables.tf, e.g. "qovery_cluster_name". */
    @JsonProperty("name")
    val name: String,
    /** Context path q-core resolves, e.g. "cluster.name". */
    @JsonProperty("source")
    val source: InjectedSource,
)

data class UserVariableDto(
    @JsonProperty("name")
    val name: String,
    @JsonProperty("type")
    val type: VariableType,
    @JsonProperty("required")
    val required: Boolean,
    @JsonProperty("default")
    val `default`: String? = null,
    @JsonProperty("description")
    val description: String,
    @JsonProperty("sensitive")
    val sensitive: Boolean = false,
    /** Available choices for dropdown-style variables. */
    @JsonProperty("options")
    val options: List<String>? = null,
    @JsonProperty("validation")
    val validation: VariableValidationDto? = null,
)

data class VariableValidationDto(
    @JsonProperty("min")
    val min: Double? = null,
    @JsonProperty("max")
    val max: Double? = null,
    /** Regex pattern the value must match. */
    @JsonProperty("pattern")
    val pattern: String? = null,
)

data class OutputDto(
    /** Output name, always prefixed with QSM_, e.g. "QSM_POSTGRESQL_HOST". */
    @JsonProperty("name")
    val name: String,
    @JsonProperty("description")
    val description: String,
    @JsonProperty("sensitive")
    val sensitive: Boolean = false,
)

data class DependencyDto(
    /** Name of the recommended blueprint, e.g. "aws-secrets-manager". */
    @JsonProperty("blueprint")
    val blueprint: String,
    @JsonProperty("reason")
    val reason: String,
)

// ──────────────────────────────────────────────
// 3. Provision from Catalog
//
//    POST /environment/{environmentId}/catalog/provision
// ──────────────────────────────────────────────

data class ProvisionFromCatalogRequest(
    /** Blueprint name from the catalog, e.g. "aws-postgresql". */
    @JsonProperty("blueprint_name")
    val blueprintName: String,
    /** User-chosen service name, e.g. "my-database". */
    @JsonProperty("service_name")
    val serviceName: String,
    /** User-provided variable values. Keys must match userVariables[].name from the blueprint. */
    @JsonProperty("user_variables")
    val userVariables: Map<String, String>,
    /** User-chosen alias mapping. Keys are QSM_ output names, values are the alias prefix.
     *  Example: {"QSM_POSTGRESQL_HOST": "MY_DATABASE", "QSM_POSTGRESQL_PORT": "MY_DATABASE"} */
    @JsonProperty("output_aliases")
    val outputAliases: Map<String, String>,
)

data class ProvisionFromCatalogResponse(
    /** ID of the created Terraform (or Helm) service. */
    @JsonProperty("service_id")
    val serviceId: String,
    /** Type of service created. */
    @JsonProperty("service_type")
    val serviceType: String,
    /** Blueprint name used. */
    @JsonProperty("blueprint_name")
    val blueprintName: String,
    /** Blueprint version used. */
    @JsonProperty("blueprint_version")
    val blueprintVersion: String,
)
