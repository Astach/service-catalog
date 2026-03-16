# Service Catalog -- Product Specification

---

# Context and Problem Statement

## Why are we developing this feature?

Qovery users today can create Terraform Services manually -- pointing to a git repo, filling in variables, and deploying. This works for infrastructure teams, but has significant friction:

- **No discoverability.** Users must know which Terraform modules exist, where they live, and what variables they need. There's no catalog to browse.
- **No guardrails.** Nothing validates inputs before deployment. A wrong variable value means a failed deploy and wasted time.
- **No visibility before deploy.** Users click "Deploy" and hope for the best. There's no preview of what resources will be created, changed, or destroyed.
- **No upgrade path.** When a Terraform module is updated (security patch, new variable, improved defaults), there's no way to notify users or help them upgrade. Each provisioned service drifts independently.
- **No tracking.** After creation, there's no record of "this Terraform Service was created from module X at version Y." The provenance is lost.

## Who is affected?

- **Platform teams** who maintain Terraform modules and want to offer them as self-service to developers
- **Developers** who need cloud resources (databases, S3 buckets, caches, monitoring stacks) but don't want to write Terraform
- **DevOps leads** who want visibility into what's provisioned, from what definition, and at what version

## What pain point do we solve?

Turn Terraform modules into a **self-service catalog with plan visibility and version tracking**. Users browse, configure, review a plan, approve, and get resources -- with the confidence of knowing exactly what will happen before it happens.

---

# Discovery

## Competition

| Platform | Model | Plan/Review | Upgrades | Strengths | Weaknesses |
|----------|-------|-------------|----------|-----------|------------|
| **SpectroCloud Palette** | Layered cluster profiles composed of versioned packs from registries | YAML diff editor (config-level, not resource-level) | "Updates Available" badge + YAML diff editor. Recommends new profile version. | Two-level versioning (pack + profile). Version trains. Profile variables. | No resource-level plan. Manual inter-service wiring. No output system. |
| **Kratix** | K8s-native Promises (CRDs). Pipeline containers run on resource request. | None. `kubectl apply` runs immediately. Manual approval via pipeline image. | With feature flag: PromiseRevisions. Without: re-runs all workflows immediately. | K8s-native. Compound Promises for composition. Status-based outputs. | No diff/plan. No catalog UI (OSS). Tight K8s coupling. |
| **Backstage** | Software Templates (one-shot scaffolders). Catalog for discovery. | Input review page only. No infrastructure plan. | None. Templates are fire-and-forget. | Rich catalog model (relations, APIs, Systems, Domains). Ecosystem of plugins. | No live binding. No upgrades. No plan. Not infrastructure-focused. |
| **Cortex** | Entity catalog + Cookiecutter scaffolder + Workflows. | Manual approval blocks in Workflows. No infra plan. | None for scaffolded services. Scorecards track compliance drift. | Auto-discovery from integrations. Relationship graphs. Breaking API detection. | No provisioning plan. No upgrade mechanism. Focused on catalog/compliance, not provisioning. |
| **Pulumi** | IaC SDK (TypeScript/Python/Go/Java) + Organization Templates + Registry. Pulumi Deployments for remote execution. | `pulumi preview` shows resource-level diffs. Saved plans experimental. | Templates are one-shot. **Component model** for shared libraries: bump package version + `pulumi up`. | StackReferences for cross-stack outputs. ESC for secrets/config. Pulumi Deployments (drift detection, TTL stacks). Real programming languages. | Requires Pulumi SDK (not standard TF). Templates have no live binding. Component upgrade requires code changes by consumer. |

## Key insight

Pulumi is the only competitor with real resource-level plan diffs (`pulumi preview`), but it's a CLI/SDK tool -- not an integrated catalog experience. SpectroCloud has YAML-level diffs. The rest have nothing. Our differentiator is **embedding the plan into the catalog provisioning flow** -- users see diffs in the Console, not in a terminal.

## Market positioning

- **Backstage and Cortex** are catalog-first (discovery, ownership, compliance). They scaffold code, not infrastructure.
- **SpectroCloud and Kratix** are infrastructure-first but K8s-centric. They manage cluster composition, not arbitrary cloud resources.
- **Pulumi** is the closest competitor -- real IaC with plan/preview, templates, component model, and strong outputs. But it requires adopting the Pulumi SDK and is developer-tooling, not a self-service catalog.
- **We are provisioning-first with plan visibility in a self-service UI** -- standard Terraform, any provider, any cloud resource, plan review in the Console, live version tracking and upgrades.

---

# MVP (Scope)

## In Scope (MVP)

**1. Blueprint repository with QSM contract**
- Blueprints are standard Terraform modules with a `qsm.yml` manifest
- `spec.provider` determines which credentials the engine injects (aws, gcp, azure, qovery, helm)
- `qoveryVariables` auto-filled from cluster/environment context (some overridable)
- `userVariables` shown in the provisioning form
- `metadata.categories` for catalog filtering
- Versioned via git tags: `{blueprint-name}/{major}.{minor}.{patch}`

**2. Catalog browsing**
- Browse blueprints filtered by provider (pre-set to cluster's cloud provider) and categories
- Each card shows: icon, name, description, categories, latest version

**3. Provisioning with plan/approve**
- User selects blueprint, fills in variables
- Engine runs `terraform plan`, stores plan JSON + binary planfile
- User reviews what will be created/changed/destroyed
- User approves -> `terraform apply plan.bin`
- Plan states: `PENDING_REVIEW`, `APPROVED`, `APPLYING`, `APPLIED`, `REJECTED`, `EXPIRED` (1h), `FAILED`

**4. Service binding**
- Each provisioned instance tracked by `catalog_service` record (blueprint name, version, TF state ref, variables)
- Console shows which blueprint created a service and at what version

**5. Upgrade detection and plan diff**
- Version index built from git tags
- When a new version exists, Console shows "Update available" badge
- User clicks "Review" -> `terraform plan` with new version against existing state -> reviews diff -> approves

**6. Metadata-only updates**
- When a new version only changes metadata (description, icon, categories) and spec is identical, update immediately without plan/apply

**7. Cache and webhook**
- In-memory cache in q-core for blueprints and version index
- GitHub webhook invalidates cache on tag push

**8. CI validation**
- PR CI: QSM schema validation, variables match `variables.tf`, `terraform validate`
- Release CI: tag matches QSM version, backwards compatibility check for minor/patch

## Out of Scope

| Feature | When |
|---------|------|
| **Alias Bridge** (outputs -> environment-scoped variables) | Post-MVP. Spec in `v2/FUTURE.md`. |
| **Upgrade policies** (auto_patch, auto_minor) | Post-MVP. Spec in `v2/FUTURE.md`. |
| **Notification system** for available updates | Post-MVP. |
| **Custom/private catalogs** per organization | Future. |
| **StackBlueprint composition** (multi-service stacks with stages) | Available in blueprints but the Console UI for multi-stage provisioning is post-MVP. |
| **Terraform state import** for existing resources | Future. |

---

# User Experience

## User Journey

### 1. Browse Catalog

1. User navigates to an environment
2. Opens Service Catalog
3. Provider filter pre-set to cluster's cloud provider
4. Filters by categories (database, storage, monitoring, etc.)
5. Sees blueprint cards: icon, name, description, categories, version

### 2. Provision a Service

1. Clicks "Provision" on a blueprint card
2. Fills in variables:
   - Qovery variables are pre-filled (cluster name, region, VPC, etc.). Overridable ones are editable.
   - User variables are empty or show defaults
3. Clicks "Plan"
4. Sees the plan diff: resources to add, change, or destroy
5. Reviews and clicks "Approve & Deploy" (or "Reject")
6. Resources are created. Service appears in environment list with catalog badge.

### 3. Upgrade a Service

1. Views a catalog-provisioned service
2. Sees "Update available" badge (current: 1.0.0, latest: 1.1.0)
3. Clicks "Review Update"
4. Sees plan diff (new version against existing state): what changes
5. Approves -> apply

### 4. Destroy a Service

1. Clicks "Destroy" on a catalog-provisioned service
2. Sees destroy plan (all resources to be removed)
3. Approves -> resources destroyed, `catalog_service` marked destroyed

## Edge Cases & Constraints

**Permissions**
- Creating a service from the catalog requires the same permissions as creating a Terraform Service
- Approving a plan may require a separate "approve" permission (TBD)

**Limits**
- Plan expires after 1 hour if not approved
- Only one active plan per blueprint+environment at a time (new plan supersedes old)

**Error scenarios**
- Plan fails (TF error): status `FAILED`, user sees error output, can re-plan
- Apply fails after approval: status `FAILED`, TF state may be partially applied. User can re-plan to see current state and retry.
- Blueprint version deleted from repo: existing services unaffected (pinned to commit SHA). Upgrade badge disappears.
- Webhook failure: cache stale until TTL or manual flush via admin endpoint

---

# Technical Design

See the following docs for full technical details:

| Doc | Contents |
|-----|----------|
| [PLAN.md](PLAN.md) | Product decisions, technical decisions, architecture, QSM contract, versioning, service binding |
| [v2/DESIGN.md](v2/DESIGN.md) | Architecture diagrams, workflow sequences, plan object schema, API endpoints, engine integration, state management |
| [v2/OPERATIONS.md](v2/OPERATIONS.md) | Catalog update propagation, TF state location, TF runner execution, service-to-blueprint binding, infrastructure scope, metadata-only updates |
| [v2/FUTURE.md](v2/FUTURE.md) | Alias Bridge spec, upgrade policies, notification system |
| [COMPETITIVE-ANALYSIS.md](COMPETITIVE-ANALYSIS.md) | SpectroCloud, Kratix, Backstage, Cortex comparison |

### Architecture summary

```
Console -> q-core (CatalogApi, PlanService, BlueprintRegistry, Cache)
                -> Engine (terraform plan / apply)
                        -> Target (AWS / Qovery API / K8s)
```

### Key technical choices

- **Always Terraform.** No separate Helm engine. Helm charts deployed via `helm_release` resource.
- **`spec.provider` = credential selector.** Engine injects AWS creds, Qovery API token, or kubeconfig based on the provider field.
- **Binary planfile.** `terraform apply plan.bin` guarantees what the user reviewed is exactly what gets applied.
- **TF state in Kubernetes backend.** Each stack gets its own state (Secret on customer's cluster). Isolated, portable, standard.
- **`catalog_service` record** in q-core DB is the single source of truth for service-to-blueprint binding. No resource annotations needed.

---

# Risks & Open Questions

### Open questions

- **Plan approval permissions.** Should "approve a plan" be a separate permission from "create a plan"? This enables a maker-checker workflow (dev plans, lead approves) but adds RBAC complexity.
- **StackBlueprint UI.** The QSM supports StackBlueprints with stages, but the Console UI for multi-stage provisioning (showing deployment ordering, per-stage progress) is not designed yet.
- **Helm outputs.** Helm has no native output mechanism. The current approach (TF kubernetes data sources to read back created resources) works but requires chart-specific knowledge from blueprint authors. Is this acceptable for MVP?
- **Multi-provider StackBlueprints.** A single `main.tf` can declare AWS + Qovery + Helm providers. The engine needs to inject all credentials. How does `spec.provider` work when it's multiple? Should it become a list, or should we detect providers from `providers.tf` automatically?

### Known risks

- **GitHub API rate limits.** Cache miss on a cold start fetches qsm.yml for every blueprint. With 50+ blueprints, this could hit GitHub's 5,000 req/hr limit. Mitigation: aggressive caching, conditional requests (ETags).
- **Plan binary storage.** Plan files can be large (10-50MB for complex stacks). Storing them in the DB as blobs may cause performance issues. May need object storage (S3) for plan binaries.
- **Plan staleness.** Between plan and approve (up to 1h), the underlying infrastructure may change (drift). The plan binary is still valid (Terraform handles this), but the user's mental model of "what I reviewed" may not match reality. Mitigation: 1h expiry, option to re-plan.
- **Customer's cloud credentials on our infrastructure.** For `provider: "aws"`, the engine runs on Qovery's infrastructure with the customer's AWS credentials. This is already the case for Terraform Services today, but the catalog makes it more prominent. Credential isolation and scoping must be airtight.

### Decisions pending

- Exact API contract for `/catalog/plan` and `/catalog/plans/{id}/approve` (request/response schemas)
- Console UI design for plan review (how to render the TF plan JSON in a user-friendly way)
- Whether to support `terraform import` for adopting existing resources into a catalog-managed stack
