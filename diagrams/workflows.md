# Service Catalog -- Mermaid Diagrams

All workflows, architecture, and user journeys for the Qovery Service Catalog.

---

## 1. High-Level Architecture

```mermaid
graph TB
    Console["Console<br/> "]

    subgraph qcore["q-core"]
        CatalogApi["CatalogApi<br/>Controller"]
        CreateUseCase["CreateTerraform<br/>FromCatalogUseCase"]
        BlueprintRegistry["Blueprint<br/>RegistryService"]
        TerraformDomain["TerraformDomain<br/>.create()"]
        AliasBridge["AliasBridge<br/>Service"]
        Cache["In-Memory Cache<br/>(blueprints + versions)"]
        VersionIndex["Version Index<br/>(git tags → semver list)"]
        EnvVar["Environment<br/>Variable"]
        TFTable[("terraform<br/>(DB table)")]
    end

    GitHubAPI["GitHub REST API<br/>(read qsm.yml,<br/>list dirs, list tags)"]
    BlueprintRepo["Blueprint Repo<br/>(GitHub)<br/>service-catalog"]
    Redis["Redis Streams<br/>(EngineReq)"]
    Engine["Engine  <br/>git shallow fetch @tag_SHA<br/>tf apply / helm install"]
    Cloud["Cloud Provider<br/>(AWS / GCP / Azure /<br/>Scaleway)"]

    Console -->|REST| CatalogApi
    CatalogApi --> CreateUseCase
    CatalogApi --> BlueprintRegistry
    BlueprintRegistry --> Cache
    Cache --> VersionIndex
    BlueprintRegistry --> GitHubAPI
    GitHubAPI --> BlueprintRepo
    CreateUseCase --> TerraformDomain
    TerraformDomain --> TFTable
    TerraformDomain --> Redis
    Redis --> Engine
    Engine -->|"git shallow fetch @tag_SHA"| BlueprintRepo
    Engine -->|"tf apply / helm install"| Cloud
    Engine -->|"gRPC: sendTerraformResources"| AliasBridge
    AliasBridge --> EnvVar
```

---

## 2. Provisioning Workflow (Sequence)

```mermaid
sequenceDiagram
    actor User
    participant Console
    participant qcore as q-core
    participant Cache as In-Memory Cache
    participant GitHub as GitHub API
    participant Redis as Redis Streams
    participant Engine
    participant Cloud as Cloud Provider

    User ->> Console: Click "Provision" on blueprint card
    Console ->> qcore: POST /catalog/services<br/>{blueprint, version, name, vars}

    qcore ->> Cache: Lookup blueprint@version
    alt Cache hit
        Cache -->> qcore: Return cached QSM
    else Cache miss
        Cache ->> GitHub: GET /repos/.../contents/{path}/qsm.yml<br/>?ref={blueprint}/{version}
        GitHub -->> Cache: qsm.yml content
        Cache -->> qcore: Return QSM + populate cache
    end

    Note over qcore: Validate user vars against QSM
    Note over qcore: Resolve injected vars from cluster context
    Note over qcore: Merge all variables

    qcore ->> qcore: TerraformDomain.create()<br/>{git_url, commit_sha (from tag),<br/>root_module_path, vars,<br/>catalog_blueprint_name,<br/>catalog_blueprint_version}

    qcore ->> Redis: Trigger deploy (existing flow)
    qcore -->> Console: 202 Accepted (terraform service ID)
    Console -->> User: Show "Deploying..." status

    Redis ->> Engine: Engine request
    Engine ->> Engine: git init + shallow fetch @tag_sha
    Engine ->> Cloud: terraform init + apply
    Cloud -->> Engine: Resources created
    Engine ->> Engine: terraform show -json (extract outputs)

    Engine ->> qcore: gRPC: sendTerraformResources

    Note over qcore: AliasBridgeService:<br/>1. Scan outputs for QSM_* prefix<br/>2. Normalize service name → "MY_DATABASE"<br/>3. Strip QSM_ prefix<br/>4. Combine: MY_DATABASE_POSTGRESQL_HOST<br/>5. Create EnvironmentVariable records

    qcore -->> Console: WebSocket: deployment complete
    Console -->> User: Show success + alias env vars
```

---

## 3. Blueprint Cache & Webhook Flow

```mermaid
sequenceDiagram
    actor Dev as Blueprint Developer
    participant Repo as Blueprint Repo
    participant GitHub
    participant qcore as q-core
    participant Cache as In-Memory Cache

    Dev ->> Repo: git push to main
    Dev ->> Repo: git tag aws-postgresql/1.2.0
    Dev ->> GitHub: git push origin aws-postgresql/1.2.0

    GitHub ->> qcore: POST /internal/catalog/webhook<br/>{ref: "refs/tags/aws-postgresql/1.2.0"}

    qcore ->> Cache: Clear all blueprints + version index

    Note over qcore,Cache: Cache is now empty.<br/>Next API request triggers rebuild.

    par On next catalog request
        qcore ->> GitHub: GET /repos/.../git/refs/tags/<br/>(rebuild version index)
        GitHub -->> qcore: All tag refs
        qcore ->> GitHub: GET /repos/.../contents/{provider}?ref=main<br/>(list blueprint dirs)
        GitHub -->> qcore: Directory listing
        qcore ->> GitHub: GET /repos/.../contents/{path}/qsm.yml?ref={tag}<br/>(for each blueprint at requested version)
        GitHub -->> qcore: qsm.yml content
        qcore ->> Cache: Populate cache
    end
```

---

## 4. Release Workflow (Developer → Production)

```mermaid
flowchart TD
    A["Developer updates blueprint files<br/>+ bumps metadata.version in qsm.yml"] --> B["Open PR to main"]
    B --> C{"PR CI (validate.yml)"}

    C -->|"qsm.yml vs JSON Schema"| C
    C -->|"metadata.name matches directory"| C
    C -->|"variables match variables.tf"| C
    C -->|"outputs start with QSM_"| C
    C -->|"terraform validate"| C

    C -->|Pass| D["Merge PR to main"]
    C -->|Fail| E["Fix & push again"]
    E --> C

    D --> F["Create git tag<br/>git tag aws-postgresql/1.2.0<br/>git push origin aws-postgresql/1.2.0"]

    F --> G{"Release CI (release.yml)"}
    G -->|"Tag matches qsm.yml version?"| G
    G -->|"Minor/patch: backwards compat check"| G
    G -->|"Major: skip compat check"| G

    G -->|Pass| H["GitHub webhook fires"]
    G -->|Fail| I["Delete tag, fix, re-tag"]
    I --> F

    H --> J["q-core: invalidate cache<br/>+ rebuild version index"]
    J --> K["New version available<br/>in catalog"]
```

---

## 5. Version Resolution Flow

```mermaid
flowchart TD
    A["User or StackBlueprint<br/>requests a blueprint version"] --> B{"Version format?"}

    B -->|"Exact: '1.2.0'"| C["Resolve tag<br/>aws-postgresql/1.2.0<br/>→ commit SHA"]

    B -->|"Train: '1.x'"| D["List all tags for<br/>aws-postgresql/*"]
    D --> E["Filter: major == 1"]
    E --> F["Sort by semver descending"]
    F --> G["Pick latest: e.g. 1.3.2"]
    G --> C

    B -->|"Range: '>=1.1.0 <2.0.0'"| H["List all tags for<br/>aws-postgresql/*"]
    H --> I["Filter by constraint"]
    I --> J["Sort by semver descending"]
    J --> K["Pick latest match: e.g. 1.4.0"]
    K --> C

    C --> L["Fetch qsm.yml<br/>GET /contents/aws/postgresql/qsm.yml<br/>?ref=aws-postgresql/{resolved-version}"]
    L --> M["Pin commit SHA<br/>for deterministic deploys"]
```

---

## 6. Upgrade Flow

```mermaid
sequenceDiagram
    actor User
    participant Console
    participant qcore as q-core
    participant VersionIdx as Version Index
    participant GitHub as GitHub API
    participant Engine
    participant Cloud as Cloud Provider

    User ->> Console: View catalog-provisioned service page

    Console ->> qcore: GET /terraform-services/{id}
    qcore ->> VersionIdx: Compare catalog_blueprint_version<br/>against version index
    VersionIdx -->> qcore: latest_version = "1.3.0"<br/>(current = "1.0.0")
    qcore -->> Console: {service..., upgrade_available: true,<br/>latest_version: "1.3.0"}

    Console -->> User: Show "Update available" badge

    User ->> Console: Click "Review Update"
    Console ->> qcore: GET /catalog/blueprints/aws-postgresql<br/>?version=1.3.0

    qcore ->> GitHub: Fetch qsm.yml @ aws-postgresql/1.0.0<br/>+ qsm.yml @ aws-postgresql/1.3.0
    GitHub -->> qcore: Both QSM versions

    Note over qcore: Compute structured diff:<br/>+ NEW variable: disk_type (default: "gp3")<br/>+ NEW output: QSM_POSTGRESQL_MONITORING_ARN<br/>~ CHANGED default: disk_size 20 → 50

    qcore -->> Console: Diff payload
    Console -->> User: Show diff with pre-filled defaults

    User ->> Console: Click "Save & Redeploy"
    Console ->> qcore: PUT /terraform-services/{id}/upgrade<br/>{target_version: "1.3.0", vars: {...}}

    Note over qcore: Update commit SHA to new tag<br/>Merge variables (user overrides + new defaults)

    qcore ->> Engine: Trigger redeploy
    Engine ->> Cloud: terraform apply (new version)
    Cloud -->> Engine: Done
    Engine ->> qcore: gRPC: sendTerraformResources

    Note over qcore: AliasBridgeService processes<br/>any new QSM_* outputs<br/>→ creates additional env vars

    qcore -->> Console: Deployment complete
    Console -->> User: Service upgraded to v1.3.0
```

---

## 7. Auto-Upgrade Policy Flow

```mermaid
flowchart TD
    A["q-core periodic check<br/>(every 15 min)"] --> B["List all catalog-provisioned<br/>Terraform Services"]
    B --> C{"Upgrade policy?"}

    C -->|manual| D["Skip<br/>(user handles it)"]

    C -->|auto_patch| E["Check version index<br/>for newer patch"]
    E --> F{"New x.y.Z available?"}
    F -->|No| G["No action"]
    F -->|Yes| H{"Service healthy?<br/>(last deploy succeeded)"}
    H -->|No| I["Skip, wait for healthy state"]
    H -->|Yes| J["Auto-upgrade:<br/>update SHA + redeploy"]

    C -->|auto_minor| K["Check version index<br/>for newer minor/patch"]
    K --> L{"New x.Y.z available?"}
    L -->|No| G
    L -->|Yes| M{"Service healthy?"}
    M -->|No| I
    M -->|Yes| J

    Note over J: Major bumps are NEVER<br/>auto-applied regardless<br/>of policy
```

---

## 8. User Journey -- Browse Catalog

```mermaid
flowchart TD
    A["User navigates to<br/>an environment"] --> B["Opens Service Catalog"]
    B --> C["Provider filter pre-set<br/>to cluster's cloud provider"]
    C --> D["Catalog grid displayed:<br/>icon, name, version,<br/>category tag, Provision button"]

    D --> E{"User action"}
    E -->|"Filter by category"| F["e.g. database, cache,<br/>messaging"]
    F --> D
    E -->|"Search by name/tags"| G["e.g. 'postgres', 'redis'"]
    G --> D
    E -->|"Click Provision"| H["→ Provisioning flow"]
```

---

## 9. User Journey -- Provision a Service

```mermaid
flowchart TD
    A["User clicks 'Provision'<br/>on a blueprint card"] --> B["Step 1: Name the service<br/>(e.g. 'my-database')"]
    B --> C["Step 2: Fill variables"]

    C --> D["Injected variables shown first<br/>(read-only, auto-filled):<br/>cluster name, region, VPC, subnets"]
    D --> E["User variables form<br/>(from qsm.yml userVariables):<br/>instance_class, disk_size, password..."]
    E --> F["Step 3: Configure aliases"]
    F --> G["Map QSM_* outputs to<br/>environment variable names:<br/>QSM_POSTGRESQL_HOST →<br/>MY_DATABASE_POSTGRESQL_HOST"]

    G --> H["User clicks 'Provision'"]
    H --> I["q-core creates<br/>Terraform Service"]
    I --> J["Deployment runs through<br/>existing engine pipeline"]
    J --> K{"Deploy success?"}
    K -->|Yes| L["Aliases created as<br/>environment-scoped variables"]
    L --> M["Service appears in<br/>environment service list"]
    K -->|No| N["Error displayed<br/>User can retry"]
```

---

## 10. User Journey -- Upgrade a Service

```mermaid
flowchart TD
    A["User views a catalog-provisioned<br/>Terraform Service page"] --> B{"Update available?"}
    B -->|No| C["Service is up to date"]
    B -->|Yes| D["'Update available' badge shown<br/>current: 1.0.0 → latest: 1.3.0"]

    D --> E["User clicks 'Review Update'"]
    E --> F["Structured diff displayed"]
    F --> G["+ NEW variables (with defaults)<br/>~ CHANGED defaults<br/>+ NEW outputs → new env vars<br/>+ NEW dropdown options"]

    G --> H{"User decision"}
    H -->|"Confirm"| I["Click 'Save & Redeploy'"]
    I --> J["q-core updates commit SHA<br/>to new tag"]
    J --> K["Variables merged:<br/>existing values kept,<br/>new vars get defaults"]
    K --> L["Redeploy triggered"]
    L --> M["New QSM_* outputs<br/>→ additional alias env vars"]
    M --> N["Service running on v1.3.0"]

    H -->|"Cancel"| O["Stay on current version"]
```

---

## 11. Alias Bridge Mechanism

```mermaid
flowchart LR
    TFOutputs["Terraform Outputs<br/>(after apply)"] --> Scan{"Scan for<br/>QSM_* prefix"}

    Scan -->|"QSM_POSTGRESQL_HOST"| Strip["Strip QSM_ prefix<br/>→ POSTGRESQL_HOST"]
    Scan -->|"QSM_POSTGRESQL_PORT"| Strip
    Scan -->|"non-QSM output"| Skip["Ignored"]

    Strip --> Normalize["Normalize service name<br/>'my-database'<br/>→ MY_DATABASE"]
    Normalize --> Combine["Combine:<br/>MY_DATABASE_POSTGRESQL_HOST<br/>MY_DATABASE_POSTGRESQL_PORT"]
    Combine --> EnvVar["Create EnvironmentVariable<br/>records (environment-scoped)"]
    EnvVar --> Available["Available to all services<br/>in the environment"]
```
