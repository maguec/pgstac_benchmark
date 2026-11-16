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

On boot, `startup_script.sh` installs `/opt/stac-venv` (`stac-api-load-testing`, `stac-fastapi.pgstac==7.2.0`, `pypgstac[psycopg]`), `postgresql-client-18`, enables `postgis` (`+ google_columnar_engine` on AlloyDB), runs `pypgstac migrate`, and starts `systemd` services (`USE_API_HYDRATE=true`) for each endpoint:

| Local VM Endpoint | Env Variable | Target Database | Connection Port |
| --- | --- | --- | --- |
| `http://localhost:8081` | `$ALLOYDB_API_URL` | AlloyDB Direct | `5432` |
| `http://localhost:8082` | `$ALLOYDB_POOLED_API_URL` | AlloyDB Managed Pooler | `6432` |
| `http://localhost:8083` | `$POSTGRES_API_URL` | Cloud SQL Postgres Direct | `5432` |
| `http://localhost:8084` | `$POSTGRES_POOLED_API_URL` | Cloud SQL Managed Pooler | `6432` |

## 4. Benchmark Workflow on the VM (200,000 Items)

Once connected via SSH (`terraform output -raw a-ssh-command`), use the pre-loaded shell helpers in `/etc/bash.bashrc`:

```bash
# 1. Ingest 4 collections x 500 base items and expand in SQL to 50,000 items/collection (200,000 total)
stac_ingest 4 500 50000

# 2. Populate all pgstac.items leaf partitions & projected CQL2/BBox columns into the AlloyDB Columnar Engine
alloydb_columnarize

# 3. Run the Locust load-test sweep across all active endpoints (10, 50, 100, 150 users, 8 workers)
stac_benchmark 10,50,100,150 1m results.csv

# Optional: Re-scale existing collections in SQL (e.g. to 100,000 items/collection = 400,000 total)
stac_scale_sql "$ALLOYDB_DIRECT_URL" 100000 && stac_scale_sql "$POSTGRES_DIRECT_URL" 100000 && alloydb_columnarize

# Optional: Drop leaf partitions from the Columnar Engine to A/B test AlloyDB with and without columnarization
alloydb_decolumnarize
```

## 5. Key Optimizations Applied

1. **Leaf-Partition Columnarization + Projected Scalar Columns**: Adds unindexed generated columns (`platform`, `constellation`, `grid_square`, `minx`, `miny`, `maxx`, `maxy`) and maps them in `pgstac.queryable_column` and `pgstac.stac_search_to_where` on both databases, allowing AlloyDB's Columnar Engine (`google_columnar_engine_add`) to run SIMD vectorized scans (`0.38 ms` CQL2 count vs `9.67 ms` heap scan; `0.50 ms` BBox count vs `25.27 ms` PostGIS `Bitmap Heap Scan`).
2. **Rust API Hydration (`USE_API_HYDRATE=true`)**: Offloads STAC item JSONB hydration from recursive PL/pgSQL `pgstac.merge_jsonb()` (`~500` SQL `FULL JOIN`s per search) to `stac-fastapi.pgstac`'s compiled Rust `hydraters` library.
3. **Read-Only Search Mode + Real Total-Hit Counting (`readonly = 'true'`, `context = 'on'`)**: Disables synchronous `UPDATE pgstac.searches` writes on every read request and enables real `SELECT count(*)` (`numberMatched`) calculation on every search.
4. **200,000-Item Scale + Managed Connection Pooling (`:6432`)**: Ensures partitions (`50,000` rows / `4,812` pages each) exceed AlloyDB's `Columnar Check: table is too small` threshold and configures `asyncpg` (`statement_cache_size=0`) for transaction pooling on port `6432`.
