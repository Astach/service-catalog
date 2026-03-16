# Competitive Analysis -- Service Catalogs

How SpectroCloud Palette, Kratix, Backstage, Cortex, and Pulumi handle service catalogs compared to our approach.

---

## 1. Versioning

| Platform | Approach |
|----------|----------|
| **SpectroCloud Palette** | Two-level: **packs** have semver in a registry + **profiles** have their own semver (`1.0.0`). Version trains (`1.x`) auto-track patches.
| **Kratix** | Label-based (`kratix.io/promise-version`). Not enforced as semver -- "latest" is whatever was most recently applied. PromiseRevisions track each version. Resources can be pinned to a revision or follow `latest`. |
| **Backstage** | No template versioning. `apiVersion` versions the schema format, not the content. Templates are one-shot generators -- versioning delegated to Git. |
| **Cortex** | No built-in entity versioning. Git commit history is the version trail. Templates have a `version` field in `cookiecutter.json` for tracking which version scaffolded a project. |
| **Pulumi** | Multi-level: **packages** (providers/components) use semver via language package managers (npm, pip, etc.). **Organization templates** support immutable semver (`pulumi template publish --version 1.0.0`). VCS-backed templates versioned implicitly via Git branch/tag. |
| **Qovery** | Git-tag semver per blueprint (`{name}/{major}.{minor}.{patch}`). Closest to SpectroCloud's pack versioning but simpler -- one level instead of two. Semver rules enforced by CI. |

---

## 2. Categorization & Discovery

| Platform | Approach |
|----------|----------|
| **SpectroCloud** | Hard layer types (OS, K8s, CNI, CSI, add-on). Freeform tags on profiles. Profiles typed as Infrastructure/Add-on/Full. |
| **Kratix** | No first-class categories. Standard K8s labels. Marketplace website has informal tags (Data, CI/CD, Security, etc.) but these aren't in the Promise spec. |
| **Backstage** | Rich multi-dimensional: `kind`, `spec.type`, `spec.lifecycle`, `metadata.tags`, `metadata.labels`, System/Domain hierarchy. Card-based gallery at `/create` with filtering. |
| **Cortex** | Entity types (service, domain, team, custom types) + domains + teams + catalogs scoped by type criteria. AI-powered ownership predictions. |
| **Pulumi** | Registry packages filtered by Type (Native Provider, Provider, Component) and Use Case (Cloud, Database, Infrastructure, Monitoring, etc.). Stack tags (custom key-value pairs) for grouping stacks. Template metadata for categorization. |
| **Qovery (ours)** | `metadata.categories` as a flat array. Simple and sufficient. Filterable in the catalog UI by category and provider. |

---

## 3. Service-to-Definition Binding

| Platform | Approach |
|----------|----------|
| **SpectroCloud** | Cluster is bound to a profile (name + version). Profile tab shows the binding. Changes generate update notifications. Cluster-level overrides are supported. |
| **Kratix** | CRD ownership -- Resource Request is an instance of the Promise's CRD. `ResourceBinding` CR explicitly links a request to a PromiseRevision version. Tight K8s-native binding. |
| **Backstage** | Lightweight `backstage.io/source-template` annotation on the created entity. Not a live binding -- just a record of origin. No ongoing relationship. |
| **Cortex** | `cortex.yaml` in Git is the source of truth. Scaffolder tracks which template version created the project. No live binding. |
| **Pulumi** | **Stack** is the binding. Fully-qualified name (`org/project/stack`) links to state in Pulumi Cloud or DIY backend. State tracks all managed resources, their IDs, properties, and dependencies. Live binding. But **no link back to the template** that created the stack -- templates are one-shot scaffolders. |
| **Qovery (ours)** | `catalog_service` DB record links provisioned instance to blueprint name + version + TF state. Live binding with upgrade detection. Stronger than Backstage annotation, lighter than Kratix CRDs. |

---

## 4. Upgrade When Definition Changes

| Platform | Approach |
|----------|----------|
| **SpectroCloud** | "Updates Available" badge on clusters. Diff editor with color-coded highlights (yellow = customized, orange = changed defaults, blue = new). User confirms. Recommends creating new profile version rather than editing in place. |
| **Kratix** | Without feature flag: re-runs all workflows immediately on Promise change (no review). With `promiseUpgrade` flag: new revision created, `latest`-pinned resources auto-upgrade, version-pinned resources stay. No diff preview. |
| **Backstage** | No upgrade mechanism. Templates are one-shot. Existing services are never retroactively updated. |
| **Cortex** | No upgrade mechanism for scaffolded services. Scorecards/Initiatives track compliance drift but don't apply changes. |
| **Pulumi** | Templates are one-shot (no retroactive updates). **But**: the recommended pattern is to use Component Resources as shared libraries. Platform team updates the component, consumers bump the package version and run `pulumi up`. `pulumi preview` shows what changes. Strong upgrade story for components, but requires the consumer to actively update their code. |
| **Qovery (ours)** | `terraform plan` against existing state shows resource-level diff. User reviews exactly what will change. Approves. `terraform apply plan.bin`. Strongest upgrade story of all six platforms. |

---

## 5. Outputs & Service Discovery

| Platform | Approach |
|----------|----------|
| **SpectroCloud** | No native outputs. Cluster Profile Variables for intra-profile sharing. Palette Macros (project/tenant-scoped key-value) for cross-profile. Inter-service wiring is manual YAML. |
| **Kratix** | Pipeline containers write to `/kratix/metadata/status.yaml`, merged into resource `.status`. No cross-Promise wiring. Manual via K8s Services/ConfigMaps/Secrets. HealthRecords for health reporting. |
| **Backstage** | Template step outputs (within scaffolding pipeline). Catalog relations (`providesApis`, `consumesApis`, `dependsOn`) for design-time discovery. No runtime service mesh. |
| **Cortex** | Auto-discovered dependencies from integrations (AWS, Datadog, Dynatrace). YAML-defined dependencies with endpoint-level granularity. Breaking API change detection on PRs. Relationship graph visualization. |
| **Pulumi** | **Best-in-class outputs.** `pulumi.export("key", value)` on any stack. **StackReferences** allow cross-stack reads: `new StackReference("org/project/stack").requireOutput("vpcId")`. Typed, secret-aware, dependency-tracked. Pulumi ESC can bridge stack outputs into config/secrets. |
| **Qovery (ours)** | TF outputs stored in state (MVP). Alias Bridge planned post-MVP (outputs become environment-scoped variables). When implemented, would be richer than any competitor. |

---

## 6. Plan / Review Workflow

| Platform | Approach |
|----------|----------|
| **SpectroCloud** | UI-driven: profile edit -> change summary -> YAML diff editor -> confirm -> cluster-level approval -> apply. Config-level diff, not resource-level. |
| **Kratix** | No plan/apply. `kubectl apply` triggers pipeline immediately. Manual approval gates possible via pipeline images (GitHub Issues-based). |
| **Backstage** | Parameters -> review page (input summary) -> execute. No infrastructure plan. Dry-run mode in Template Editor for testing only. |
| **Cortex** | No plan for provisioning. Workflows have manual approval blocks. Scorecards + Initiatives for compliance planning (not infrastructure planning). |
| **Pulumi** | `pulumi preview` shows resource-level diffs (create/update/delete/replace). `pulumi up` shows preview then asks for confirmation. Experimental: `pulumi preview --save-plan=plan.json` + `pulumi up --plan=plan.json` for saved plans. Pulumi Deployments runs these remotely. Strong, closest to our approach. |
| **Qovery (ours)** | Real `terraform plan` -> JSON diff -> user reviews resource-level changes -> approve -> `terraform apply plan.bin`. Binary planfile guarantees what was reviewed is what gets applied. Strongest of all six. |

---

## 7. Provisioning Workflow

| Platform | Steps |
|----------|-------|
| **SpectroCloud** | Create profile (select packs from registry per layer) -> configure YAML per pack -> deploy cluster from profile -> Palette agent reconciles on cluster. |
| **Kratix** | Install Promise (CRD registered) -> user `kubectl apply` a Resource Request -> pipeline containers run (fetch, transform, generate) -> output to State Store -> GitOps agent converges on destination cluster. |
| **Backstage** | User selects template -> multi-step form (JSON Schema) -> review inputs -> execute -> steps run sequentially (fetch:template, publish:github, catalog:register) -> new repo + catalog entity. |
| **Cortex** | User selects workflow/template -> fill parameters -> manual approval (optional) -> Cookiecutter scaffolds project -> creates repo + `cortex.yaml` -> entity appears in catalog. |
| **Pulumi** | `pulumi new <template>` (CLI or New Project Wizard in Pulumi Cloud) -> fill config values -> `pulumi preview` -> `pulumi up` -> resources created, state stored in backend. Pulumi Deployments can automate via git-push-to-deploy, drift detection, TTL stacks. |
| **Qovery (ours)** | User selects blueprint -> fill variables (qoveryVariables pre-filled) -> engine runs `terraform plan` -> user reviews plan diff -> approves -> `terraform apply plan.bin` -> resources created, tracked in `catalog_service`. |

---

## Key Takeaways

### Our differentiators

1. **Plan/approve workflow as a first-class feature.** Pulumi has `pulumi preview` (strong) but it's a CLI tool, not an integrated catalog experience. SpectroCloud has YAML-level diffs (weaker). The rest have nothing. We embed the plan into the catalog provisioning flow -- users see resource-level diffs in the Console before approving.

2. **Native Terraform, any provider.** Blueprints are standard TF modules. Customers can bring existing modules. Pulumi requires rewriting in their SDK. Kratix uses custom pipelines, Backstage uses custom actions, Cortex uses Cookiecutter.

3. **Live upgrade path with plan diff.** We detect new blueprint versions and show a diff against existing state. Backstage, Cortex, and Pulumi templates are all one-shot (no retroactive updates). Kratix auto-applies without review. SpectroCloud has config-level diffs. Pulumi's Component upgrade pattern is strong but requires the consumer to actively bump versions in their code.

4. **Blueprint-to-service binding with version tracking.** `catalog_service` record tracks exactly which blueprint and version created a service. Pulumi stacks have no link back to the template. Backstage has a weak annotation. We can detect upgrades because we maintain this binding.

### Where others are ahead

1. **Pulumi's StackReferences** are the gold standard for cross-stack output sharing. Typed, secret-aware, dependency-tracked. Our planned Alias Bridge is simpler (env vars) but less powerful.

2. **Pulumi Deployments** (drift detection, TTL stacks, git-push-to-deploy, review stacks for PRs) is a mature remote execution platform. Our engine is equivalent but less feature-rich.

3. **Pulumi's Component model** for shared infrastructure libraries (publish components, consumers bump version, `pulumi up` applies changes) is an elegant upgrade pattern. We don't have an equivalent -- our upgrade works at the blueprint level, not the shared library level.

4. **Backstage's catalog model** is richer for service discovery -- relations, APIs, Systems, Domains. Worth watching for post-MVP.

5. **Cortex's auto-discovery** from integrations (AWS, Datadog) is compelling for brownfield environments.

6. **Pulumi ESC** (centralized secrets/config with composable environments, dynamic credentials, rotation) is ahead of our credential injection model.

### What nobody does well

- **Integrated catalog + plan/approve in one flow.** Pulumi has the pieces (templates + preview) but they're separate tools. We unify catalog browsing, variable filling, plan review, and approval in a single Console experience.
- **Helm outputs.** Nobody has solved this. Helm has no native output mechanism.
- **Automatic output-to-env-var bridging.** Pulumi has StackReferences (manual, code-level). Nobody has automatic output-to-environment-variable mapping like our planned Alias Bridge.
