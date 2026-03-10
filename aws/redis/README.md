# Redis (AWS ElastiCache)

Provisions a managed Redis instance using AWS ElastiCache.

## What's already configured for you

The following are set to sensible production defaults. You don't need to touch them unless you have a specific reason to.

| Setting | Default | What it does |
|---|---|---|
| Networking | Auto-discovered from your Qovery EKS cluster | VPC, subnets, security group -- all wired automatically |
| Encryption at rest | Enabled | Your data is encrypted on disk |
| Encryption in transit | Enabled (TLS) | All connections use TLS. Your app must connect with `rediss://` (note the double `s`) |
| Auth token | Required | A password is required to connect |
| Snapshots | 14 days retention, daily at 00:00-01:00 UTC | Automatic daily snapshots |
| Final snapshot | Enabled | A snapshot is taken before any deletion, so you can restore |
| Maintenance window | Tuesdays 02:00-04:00 UTC | When AWS applies patches |

## What you need to set

These are the variables you **must** provide when creating the service in Qovery:

| Variable | Example | Description |
|---|---|---|
| `elasticache_identifier` | `my-app-redis` | A unique name for your Redis instance (max 40 characters) |
| `auth_token` | *(secret, min 16 characters)* | The password to connect to Redis. Set this as a **secret** in Qovery. Must be at least 16 characters when TLS is enabled. |

## Qovery environment variables to configure

Set these as **environment variables** on the Terraform service in Qovery. They map built-in Qovery values to Terraform variables automatically:

| Env var name | Value | Scope |
|---|---|---|
| `TF_VAR_qovery_cluster_name` | `{{QOVERY_KUBERNETES_CLUSTER_NAME}}` | Environment |
| `TF_VAR_region` | `{{QOVERY_CLOUD_PROVIDER_REGION}}` | Environment |
| `TF_VAR_qovery_environment_id` | `{{QOVERY_ENVIRONMENT_ID}}` | Environment |
| `TF_VAR_qovery_project_id` | `{{QOVERY_PROJECT_ID}}` | Environment |
| `TF_VAR_auth_token` | *(your password)* | Service (secret) |
| `TF_VAR_elasticache_identifier` | `my-app-redis` | Service |

## What you might want to change

These are the most common things a developer would adjust depending on the use case:

### Instance size

| Variable | Default | Description |
|---|---|---|
| `node_type` | `cache.t4g.micro` | The node size. Use `cache.t4g.small` or `cache.t4g.medium` for more memory. For production caching workloads, consider `cache.r6g.large` or above. |
| `num_cache_clusters` | `1` | Number of nodes. Use `2` for production (1 primary + 1 replica with automatic failover). |

### Engine version

| Variable | Default | Description |
|---|---|---|
| `elasticache_version` | `7.0` | The Redis version. Supported: `6.2`, `7.0`. |
| `parameter_group_name` | `default.redis7` | Must match the major version. Use `default.redis6.x` for version 6.2. |

### Backups

| Variable | Default | Description |
|---|---|---|
| `snapshot_retention_limit` | `14` | Number of days to keep daily snapshots. Set to `0` to disable snapshots entirely. |
| `skip_final_snapshot` | `false` | Set to `true` **only** for dev/test environments where you don't care about data on deletion. |

## Connecting from your application

Since TLS is enabled by default, you must use the `rediss://` scheme (with double `s`):

```
rediss://:<auth_token>@<primary_endpoint>:6379
```

Most Redis libraries support this natively. Example with `ioredis` (Node.js):

```js
const redis = new Redis({
  host: "<primary_endpoint>",
  port: 6379,
  password: "<auth_token>",
  tls: {},
});
```

## Outputs

After deployment, these values are available as Terraform outputs:

| Output | Description |
|---|---|
| `primary_endpoint` | The primary endpoint to connect to (for read/write) |
| `reader_endpoint` | The reader endpoint (for read-only, load-balanced across replicas) |
| `port` | The Redis port |
| `connection_string` | A ready-to-use `rediss://` connection string (without password) |
| `arn` | The AWS ARN of the ElastiCache replication group |
