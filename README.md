# pgSTAC AlloyDB vs. Cloud SQL PostgreSQL Benchmark (`StacLabs/stac-api-load-testing`)

Terraform environment to benchmark `pgstac` (`stac-fastapi.pgstac`) using [StacLabs/stac-api-load-testing](https://github.com/StacLabs/stac-api-load-testing) on Google Cloud AlloyDB (with Columnar Engine, Vectorized Joins, Managed Connection Pooling, and Query Insights) against Cloud SQL for PostgreSQL (`ENTERPRISE_PLUS`) on `POSTGRES_18`.

## 1. Provision Infrastructure

```bash
terraform init
terraform plan -var-file=mague.tfvars
terraform apply -var-file=mague.tfvars
```

## 2. Toggling Databases

Edit `mague.tfvars` to turn either database or Managed Connection Pooling on or off independently:

```hcl
enable_alloydb            = true
enable_postgres           = true
enable_connection_pooling = true
```

## 3. Pre-Configured VM Environment & `stac-fastapi.pgstac` Endpoints

On boot, `startup_script.sh` installs `/opt/stac-venv` (`stac-api-load-testing`, `stac-fastapi.pgstac==7.2.0`, `pypgstac[psycopg]`), enables `postgis` (`+ google_columnar_engine` on AlloyDB), runs `pypgstac migrate`, and starts `systemd` services for each endpoint:

| Local VM Endpoint | Env Variable | Target Database | Connection Port |
| --- | --- | --- | --- |
| `http://localhost:8081` | `$ALLOYDB_API_URL` | AlloyDB Direct | `5432` |
| `http://localhost:8082` | `$ALLOYDB_POOLED_API_URL` | AlloyDB Managed Pooler | `6432` |
| `http://localhost:8083` | `$POSTGRES_API_URL` | Cloud SQL Postgres Direct | `5432` |
| `http://localhost:8084` | `$POSTGRES_POOLED_API_URL` | Cloud SQL Managed Pooler | `6432` |

## 4. Benchmark Workflow on the VM

Once connected via SSH (`terraform output -raw a-ssh-command`), use the pre-loaded shell helpers in `/etc/bash.bashrc`:

```bash
# 1. Ingest synthetic Sentinel-2 L2A items into AlloyDB and Cloud SQL (default: 4 collections x 500 items)
stac_ingest 4 500

# 2. Populate all pgstac.items leaf partitions & CQL2 JSONB paths into the AlloyDB Columnar Engine
alloydb_columnarize

# 3. Run the Locust load-test sweep across all active endpoints (10, 50, 100, 150 users, 8 workers)
stac_benchmark 10,50,100,150 1m results.csv

# Optional: Drop leaf partitions from the Columnar Engine to A/B test AlloyDB with and without columnarization
alloydb_decolumnarize
```
