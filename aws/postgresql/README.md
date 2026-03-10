# PostgreSQL (AWS RDS)

Provisions a managed PostgreSQL database on AWS RDS.

## What's already configured for you

The following are set to sensible production defaults. You don't need to touch them unless you have a specific reason to.

| Setting                | Default                                      | What it does                                                |
| ---------------------- | -------------------------------------------- | ----------------------------------------------------------- |
| Networking             | Auto-discovered from your Qovery EKS cluster | VPC, subnets, security group -- all wired automatically     |
| Encryption at rest     | Enabled                                      | Your data is encrypted on disk                              |
| Multi-AZ               | Enabled                                      | A standby replica in another availability zone for failover |
| Backups                | 14 days retention, daily at 00:00-01:00 UTC  | Automatic daily backups                                     |
| Final snapshot         | Enabled                                      | A snapshot is taken before any deletion, so you can restore |
| Minor version upgrades | Automatic                                    | Security patches are applied during the maintenance window  |
| Maintenance window     | Tuesdays 02:00-04:00 UTC                     | When AWS applies patches and minor upgrades                 |
| Performance Insights   | Enabled (7-day retention)                    | Helps you understand query performance                      |
| Enhanced Monitoring    | 10-second granularity                        | Detailed OS-level metrics in CloudWatch                     |

## What you need to set

These are the variables you **must** provide when creating the service in Qovery:

| Variable                | Example                      | Description                                             |
| ----------------------- | ---------------------------- | ------------------------------------------------------- |
| `postgresql_identifier` | `my-app-db`                  | A unique name for your database instance                |
| `password`              | _(secret, min 9 characters)_ | The master password. Set this as a **secret** in Qovery |

## Qovery environment variables to configure

Set these as **environment variables** on the Terraform service in Qovery. They map built-in Qovery values to Terraform variables automatically:

| Env var name                   | Value                                | Scope            |
| ------------------------------ | ------------------------------------ | ---------------- |
| `TF_VAR_qovery_cluster_name`   | `{{QOVERY_KUBERNETES_CLUSTER_NAME}}` | Environment      |
| `TF_VAR_region`                | `{{QOVERY_CLOUD_PROVIDER_REGION}}`   | Environment      |
| `TF_VAR_qovery_environment_id` | `{{QOVERY_ENVIRONMENT_ID}}`          | Environment      |
| `TF_VAR_qovery_project_id`     | `{{QOVERY_PROJECT_ID}}`              | Environment      |
| `TF_VAR_password`              | _(your password)_                    | Service (secret) |
| `TF_VAR_postgresql_identifier` | `my-app-db`                          | Service          |

## What you might want to change

These are the most common things a developer would adjust depending on the use case:

### Instance size

| Variable         | Default       | Description                                                                                                                            |
| ---------------- | ------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| `instance_class` | `db.t3.micro` | The instance size. Use `db.t3.small` or `db.t3.medium` for more demanding workloads. For production, consider `db.r6g.large` or above. |
| `disk_size`      | `20` (GiB)    | How much storage to allocate. Increase this based on your data size.                                                                   |

### Database basics

| Variable             | Default    | Description                                                |
| -------------------- | ---------- | ---------------------------------------------------------- |
| `postgresql_version` | `16`       | The PostgreSQL version. Supported: `13`, `14`, `15`, `16`. |
| `database_name`      | `postgres` | The name of the default database created on the instance.  |
| `username`           | `qovery`   | The master username.                                       |
| `port`               | `5432`     | The port PostgreSQL listens on.                            |

### Backups

| Variable                  | Default | Description                                                                                   |
| ------------------------- | ------- | --------------------------------------------------------------------------------------------- |
| `backup_retention_period` | `14`    | Number of days to keep daily backups (1-35).                                                  |
| `skip_final_snapshot`     | `false` | Set to `true` **only** for dev/test environments where you don't care about data on deletion. |

### Access

| Variable              | Default | Description                                                                                   |
| --------------------- | ------- | --------------------------------------------------------------------------------------------- |
| `publicly_accessible` | `false` | Set to `true` if you need to connect from outside the cluster (e.g. from your local machine). |
| `multi_az`            | `true`  | Set to `false` for dev/test to save costs (no standby replica).                               |

## Outputs

After deployment, these values are available as Terraform outputs:

| Output              | Description                                         |
| ------------------- | --------------------------------------------------- |
| `hostname`          | The database hostname to connect to                 |
| `port`              | The database port                                   |
| `endpoint`          | Full endpoint (`hostname:port`)                     |
| `database_name`     | The default database name                           |
| `username`          | The master username                                 |
| `connection_string` | A ready-to-use connection string (without password) |
| `arn`               | The AWS ARN of the RDS instance                     |
