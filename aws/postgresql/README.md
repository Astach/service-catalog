# PostgreSQL (AWS RDS)

Provisions a managed PostgreSQL database on AWS RDS.

## What's configured by default

| Setting | Default | Description |
|---|---|---|
| Networking | Auto-discovered from EKS cluster | VPC, subnets, security group wired automatically |
| Encryption at rest | Enabled | Data encrypted on disk |
| Multi-AZ | Enabled | Standby replica in another AZ for failover |
| Backups | 14 days, daily at 00:00-01:00 UTC | Automatic daily backups |
| Final snapshot | Enabled | Snapshot taken before deletion |
| Minor version upgrades | Automatic | Security patches applied during maintenance window |
| Maintenance window | Tuesdays 02:00-04:00 UTC | When AWS applies patches |
| Performance Insights | Enabled (7-day retention) | Query performance visibility |
| Enhanced Monitoring | 10-second granularity | OS-level metrics in CloudWatch |

## Required variables

| Variable | Example | Description |
|---|---|---|
| `postgresql_identifier` | `my-app-db` | Unique name for the RDS instance |
| `password` | _(min 9 characters)_ | Master password (stored as secret) |

## Qovery variables (auto-filled)

These are populated automatically by q-core from your cluster/environment context. Network variables are overridable if you need custom VPC/subnet configuration.

| Variable | Source | Overridable |
|---|---|---|
| `qovery_cluster_name` | `cluster.name` | No |
| `region` | `cluster.region` | Yes |
| `qovery_environment_id` | `environment.id` | No |
| `qovery_project_id` | `project.id` | No |
| `vpc_id` | `cluster.vpc_id` | Yes |
| `subnet_ids` | `cluster.subnet_ids` | Yes |
| `security_group_ids` | `cluster.security_group_ids` | Yes |

## Common customizations

### Instance size

| Variable | Default | Description |
|---|---|---|
| `instance_class` | `db.t3.micro` | Instance size. Use `db.r6g.large`+ for production. |
| `disk_size` | `20` (GiB) | Storage allocation. |

### Database basics

| Variable | Default | Description |
|---|---|---|
| `postgresql_version` | `16` | PostgreSQL version (14, 15, 16, 17) |
| `database_name` | `postgres` | Default database name |
| `username` | `qovery` | Master username |

### Backups & access

| Variable | Default | Description |
|---|---|---|
| `backup_retention_period` | `14` | Days to keep backups (1-35) |
| `skip_final_snapshot` | `false` | Set `true` for dev/test only |
| `publicly_accessible` | `false` | Set `true` to connect from outside cluster |
| `multi_az` | `true` | Set `false` for dev/test to save costs |

## Outputs

After deployment, these outputs become environment variables (prefixed with the service name) via the alias bridge:

| Output | Description |
|---|---|
| `postgresql_host` | Database hostname |
| `postgresql_port` | Database port |
| `postgresql_database` | Default database name |
| `postgresql_username` | Master username |
| `postgresql_connection_string` | Connection string (without password) |
| `postgresql_endpoint` | Full endpoint (host:port) |
| `postgresql_arn` | RDS instance ARN |
| `postgresql_id` | RDS instance ID |
| `postgresql_identifier` | RDS instance identifier |
| `postgresql_resource_id` | RDS Resource ID (for IAM auth and CloudWatch) |
| `postgresql_vpc_id` | VPC ID where the instance is deployed |
| `postgresql_security_group_id` | Security group ID attached to the instance |
