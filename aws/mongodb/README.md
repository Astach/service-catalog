# MongoDB (AWS DocumentDB)

Provisions a managed MongoDB-compatible database using AWS DocumentDB.

DocumentDB is Amazon's MongoDB-compatible document database. It supports MongoDB drivers and tools but runs on a different engine under the hood. Most applications using MongoDB will work with DocumentDB without changes.

## What's already configured for you

The following are set to sensible production defaults. You don't need to touch them unless you have a specific reason to.

| Setting | Default | What it does |
|---|---|---|
| Networking | Auto-discovered from your Qovery EKS cluster | VPC, subnets, security group -- all wired automatically |
| Encryption at rest | Enabled | Your data is encrypted on disk |
| High availability | Cluster spread across multiple availability zones | Automatic failover if one AZ goes down |
| Backups | 14 days retention, daily at 00:00-01:00 UTC | Automatic daily backups |
| Final snapshot | Enabled | A snapshot is taken before any deletion, so you can restore |
| Minor version upgrades | Automatic | Security patches are applied during the maintenance window |
| Maintenance window | Tuesdays 02:00-04:00 UTC | When AWS applies patches and minor upgrades |
| Storage | Managed automatically by AWS | No need to specify disk size -- DocumentDB scales storage on its own |

## What you need to set

These are the variables you **must** provide when creating the service in Qovery:

| Variable | Example | Description |
|---|---|---|
| `documentdb_identifier` | `my-app-docdb` | A unique name for your DocumentDB cluster |
| `password` | *(secret, min 9 characters)* | The master password. Set this as a **secret** in Qovery |

## Qovery environment variables to configure

Set these as **environment variables** on the Terraform service in Qovery. They map built-in Qovery values to Terraform variables automatically:

| Env var name | Value | Scope |
|---|---|---|
| `TF_VAR_qovery_cluster_name` | `{{QOVERY_KUBERNETES_CLUSTER_NAME}}` | Environment |
| `TF_VAR_region` | `{{QOVERY_CLOUD_PROVIDER_REGION}}` | Environment |
| `TF_VAR_qovery_environment_id` | `{{QOVERY_ENVIRONMENT_ID}}` | Environment |
| `TF_VAR_qovery_project_id` | `{{QOVERY_PROJECT_ID}}` | Environment |
| `TF_VAR_password` | *(your password)* | Service (secret) |
| `TF_VAR_documentdb_identifier` | `my-app-docdb` | Service |

## What you might want to change

These are the most common things a developer would adjust depending on the use case:

### Instance size

| Variable | Default | Description |
|---|---|---|
| `instance_class` | `db.t3.medium` | The instance size. DocumentDB requires at least `db.t3.medium`. For production workloads, consider `db.r5.large` or above. |
| `instances_number` | `1` | Number of instances in the cluster. Use `3` for production (1 writer + 2 readers). |

### Database basics

| Variable | Default | Description |
|---|---|---|
| `documentdb_version` | `5.0` | The DocumentDB version (MongoDB compatibility level). Supported: `4.0`, `5.0`. |
| `username` | `qovery` | The master username. |
| `port` | `27017` | The port DocumentDB listens on. |

### Backups

| Variable | Default | Description |
|---|---|---|
| `backup_retention_period` | `14` | Number of days to keep daily backups (1-35). |
| `skip_final_snapshot` | `false` | Set to `true` **only** for dev/test environments where you don't care about data on deletion. |

## Connecting from your application

DocumentDB requires TLS by default. Your connection string should look like:

```
mongodb://<username>:<password>@<endpoint>:27017/?tls=true&replicaSet=rs0&readPreference=secondaryPreferred&retryWrites=false
```

You may need to download the [AWS RDS CA bundle](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.SSL.html) and pass it to your MongoDB driver.

## Outputs

After deployment, these values are available as Terraform outputs:

| Output | Description |
|---|---|
| `endpoint` | The cluster writer endpoint (use this for read/write operations) |
| `reader_endpoint` | The cluster reader endpoint (load-balanced across read replicas) |
| `port` | The database port |
| `username` | The master username |
| `connection_string` | A ready-to-use connection string (without password) |
| `arn` | The AWS ARN of the DocumentDB cluster |
| `instance_endpoints` | Individual endpoints for each instance |
