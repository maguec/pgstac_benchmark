#!/usr/bin/env bash
set -euxo pipefail

sed -i '/# pgSTAC Benchmark ENV vars/,$d' /etc/bash.bashrc
cat << 'EOF' >> /etc/bash.bashrc

# pgSTAC Benchmark ENV vars
export GOOGLE_CLOUD_PROJECT="${projectid}"
export GOOGLE_CLOUD_LOCATION="${region}"

export ALLOYDB_IP="${alloydb_ip}"
export POSTGRES_IP="${postgres_ip}"
export DB_DIRECT_PORT="5432"
export DB_POOLER_PORT="6432"

export PGUSER="${db_user}"
export PGPASSWORD="${db_pass}"
export PGDATABASE="${db_name}"
export PGPORT="5432"
export PGHOST="${default_pghost}"

export ALLOYDB_DIRECT_URL="postgresql://${db_user}:${db_pass}@${alloydb_ip}:5432/${db_name}"
export ALLOYDB_POOLED_URL="postgresql://${db_user}:${db_pass}@${alloydb_ip}:6432/${db_name}"
export POSTGRES_DIRECT_URL="postgresql://${db_user}:${db_pass}@${postgres_ip}:5432/${db_name}"
export POSTGRES_POOLED_URL="postgresql://${db_user}:${db_pass}@${postgres_ip}:6432/${db_name}"

export ALLOYDB_API_URL="http://localhost:8081"
export ALLOYDB_POOLED_API_URL="http://localhost:8082"
export POSTGRES_API_URL="http://localhost:8083"
export POSTGRES_POOLED_API_URL="http://localhost:8084"

export PATH="/opt/stac-venv/bin:$${PATH}"

use_alloydb()         { export PGHOST="$${ALLOYDB_IP}"  PGPORT="$${DB_DIRECT_PORT}"; echo "Target: AlloyDB Direct ($${PGHOST}:$${PGPORT})"; }
use_alloydb_pooled()  { export PGHOST="$${ALLOYDB_IP}"  PGPORT="$${DB_POOLER_PORT}"; echo "Target: AlloyDB Pooled ($${PGHOST}:$${PGPORT})"; }
use_postgres()        { export PGHOST="$${POSTGRES_IP}" PGPORT="$${DB_DIRECT_PORT}"; echo "Target: Postgres Direct ($${PGHOST}:$${PGPORT})"; }
use_postgres_pooled() { export PGHOST="$${POSTGRES_IP}" PGPORT="$${DB_POOLER_PORT}"; echo "Target: Postgres Pooled ($${PGHOST}:$${PGPORT})"; }

psql_alloydb()         { psql "$${ALLOYDB_DIRECT_URL}" "$@"; }
psql_alloydb_pooled()  { psql "$${ALLOYDB_POOLED_URL}" "$@"; }
psql_postgres()        { psql "$${POSTGRES_DIRECT_URL}" "$@"; }
psql_postgres_pooled() { psql "$${POSTGRES_POOLED_URL}" "$@"; }

stac_ingest() {
  local cols="$${1:-4}"
  local items="$${2:-500}"
  local target_per_col="$${3:-25000}"
  if [ "$${ALLOYDB_IP}" != "disabled" ]; then
    echo "=== Ingesting $${cols} collections x $${items} base items into AlloyDB ($${ALLOYDB_API_URL}) ==="
    stac-api-load-testing --ingest --api-address "$${ALLOYDB_API_URL}" --collections "$${cols}" --items-per-collection "$${items}"
    stac_scale_sql "$${ALLOYDB_DIRECT_URL}" "$${target_per_col}"
  fi
  if [ "$${POSTGRES_IP}" != "disabled" ]; then
    echo "=== Ingesting $${cols} collections x $${items} base items into Cloud SQL Postgres ($${POSTGRES_API_URL}) ==="
    stac-api-load-testing --ingest --api-address "$${POSTGRES_API_URL}" --collections "$${cols}" --items-per-collection "$${items}"
    stac_scale_sql "$${POSTGRES_DIRECT_URL}" "$${target_per_col}"
  fi
}

stac_scale_sql() {
  local db_url="$1"
  local target_per_col="$${2:-50000}"
  local max_batch=$(( (target_per_col / 100) - 1 ))
  echo "=== Scaling each collection to $${target_per_col} items & tuning pgstac_settings on $${db_url} ==="
  psql "$${db_url}" << EOSQL
SET synchronous_commit = off;
ALTER TABLE pgstac.items
  ADD COLUMN IF NOT EXISTS platform text GENERATED ALWAYS AS (content -> 'properties' ->> 'platform') STORED,
  ADD COLUMN IF NOT EXISTS constellation text GENERATED ALWAYS AS (content -> 'properties' ->> 'constellation') STORED,
  ADD COLUMN IF NOT EXISTS grid_square text GENERATED ALWAYS AS (content -> 'properties' ->> 'sentinel:grid_square') STORED,
  ADD COLUMN IF NOT EXISTS minx float8 GENERATED ALWAYS AS ((content -> 'bbox' ->> 0)::float8) STORED,
  ADD COLUMN IF NOT EXISTS miny float8 GENERATED ALWAYS AS ((content -> 'bbox' ->> 1)::float8) STORED,
  ADD COLUMN IF NOT EXISTS maxx float8 GENERATED ALWAYS AS ((content -> 'bbox' ->> 2)::float8) STORED,
  ADD COLUMN IF NOT EXISTS maxy float8 GENERATED ALWAYS AS ((content -> 'bbox' ->> 3)::float8) STORED;

CREATE OR REPLACE FUNCTION pgstac.queryable_column(dotpath text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS \$function\$
    SELECT CASE pgstac.strip_properties_prefix(dotpath)
        WHEN 'start_datetime' THEN 'datetime'
        WHEN 'id' THEN 'id'
        WHEN 'geometry' THEN 'geometry'
        WHEN 'datetime' THEN 'datetime'
        WHEN 'end_datetime' THEN 'end_datetime'
        WHEN 'collection' THEN 'collection'
        WHEN 'platform' THEN 'platform'
        WHEN 'constellation' THEN 'constellation'
        WHEN 'sentinel:grid_square' THEN 'grid_square'
    END;
\$function\$;

CREATE OR REPLACE FUNCTION pgstac.stac_search_to_where(j jsonb)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pgstac', 'public'
AS \$function\$
DECLARE
    where_segments text[];
    _where text;
    dtrange tstzrange;
    collections text[];
    geom geometry;
    sdate timestamptz;
    edate timestamptz;
    filterlang text;
    filter jsonb := j->'filter';
    ft_query tsquery;
BEGIN
    IF j ? 'ids' THEN
        where_segments := where_segments || format('id = ANY (%L) ', to_text_array(j->'ids'));
    END IF;
    IF j ? 'collections' THEN
        collections := to_text_array(j->'collections');
        where_segments := where_segments || format('collection = ANY (%L) ', collections);
    END IF;
    IF j ? 'datetime' THEN
        dtrange := parse_dtrange(j->'datetime');
        sdate := lower(dtrange);
        edate := upper(dtrange);
        where_segments := where_segments || format(' datetime %s %L::timestamptz AND end_datetime >= %L::timestamptz ',
            CASE WHEN upper_inc(dtrange) THEN '<=' ELSE '<' END,
            edate,
            sdate
        );
    END IF;
    IF j ? 'q' THEN
        ft_query := q_to_tsquery(j->'q');
        where_segments := where_segments || format(
            \$quote\$
            (
                to_tsvector('english', content->'properties'->>'description') ||
                to_tsvector('english', coalesce(content->'properties'->>'title', '')) ||
                to_tsvector('english', coalesce(content->'properties'->>'keywords', ''))
            ) @@ %L
            \$quote\$,
            ft_query
        );
    END IF;
    IF j ? 'bbox' AND NOT (j ? 'intersects') AND jsonb_array_length(j->'bbox') = 4 THEN
        where_segments := where_segments || format(
            'maxx >= %L::float8 AND minx <= %L::float8 AND maxy >= %L::float8 AND miny <= %L::float8',
            (j->'bbox'->>0)::float8,
            (j->'bbox'->>2)::float8,
            (j->'bbox'->>1)::float8,
            (j->'bbox'->>3)::float8
        );
    ELSE
        geom := stac_geom(j);
        IF geom IS NOT NULL THEN
            where_segments := where_segments || format('st_intersects(geometry, %L)',geom);
        END IF;
    END IF;
    filterlang := COALESCE(
        j->>'filter-lang',
        get_setting('default_filter_lang', j->'conf')
    );
    IF NOT filter @? '\$.**.op' THEN
        filterlang := 'cql-json';
    END IF;
    IF filterlang NOT IN ('cql-json','cql2-json') AND j ? 'filter' THEN
        RAISE EXCEPTION '% is not a supported filter-lang. Please use cql-json or cql2-json.', filterlang;
    END IF;
    IF j ? 'query' AND j ? 'filter' THEN
        RAISE EXCEPTION 'Can only use either query or filter at one time.';
    END IF;
    IF j ? 'query' THEN
        filter := query_to_cql2(j->'query');
    ELSIF filterlang = 'cql-json' THEN
        filter := cql1_to_cql2(filter);
    END IF;
    where_segments := where_segments || cql2_query(filter, NULL, collections);
    IF cardinality(where_segments) < 1 THEN
        RETURN ' TRUE ';
    END IF;
    _where := array_to_string(array_remove(where_segments, NULL), ' AND ');
    IF _where IS NULL OR BTRIM(_where) = '' THEN
        RETURN ' TRUE ';
    END IF;
    RETURN _where;
END;
\$function\$;

DELETE FROM pgstac.items WHERE id ~ '-[5-9][0-9]{2}\$' OR id ~ '-[1-9][0-9]{3,}\$';
INSERT INTO pgstac.items (id, geometry, collection, datetime, end_datetime, content, private)
SELECT
  regexp_replace(id, '-1([0-9]{2})\$', '-' || (batch * 100 + substring(id from '-1([0-9]{2})\$')::int)),
  geometry,
  collection,
  datetime,
  end_datetime,
  jsonb_set(
    content,
    '{id}',
    to_jsonb(regexp_replace(id, '-1([0-9]{2})\$', '-' || (batch * 100 + substring(id from '-1([0-9]{2})\$')::int)))
  ),
  private
FROM pgstac.items
CROSS JOIN generate_series(5, $${max_batch}) AS batch
WHERE id ~ '-1[0-9]{2}\$';

UPDATE pgstac.pgstac_settings SET value = 'on' WHERE name = 'context';
UPDATE pgstac.pgstac_settings SET value = '0 seconds' WHERE name = 'context_stats_ttl';
UPDATE pgstac.pgstac_settings SET value = 'true' WHERE name = 'readonly';
TRUNCATE pgstac.searches;
TRUNCATE pgstac.search_wheres;
ANALYZE pgstac.items;
SELECT collection, count(*) AS items FROM pgstac.items GROUP BY collection ORDER BY collection;
EOSQL
}

alloydb_columnarize() {
  if [ "$${ALLOYDB_IP}" = "disabled" ]; then
    echo "AlloyDB is disabled."
    return 1
  fi
  echo "=== Populating pgstac.items leaf partitions & CQL2 JSONB virtual columns into AlloyDB Columnar Engine ==="
  psql "$${ALLOYDB_DIRECT_URL}" << 'EOSQL'
CREATE EXTENSION IF NOT EXISTS google_columnar_engine;

CREATE OR REPLACE FUNCTION pgstac.to_text(jsonb)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE STRICT COST 1
AS $function$
  SELECT $1 #>> '{}';
$function$;

ANALYZE pgstac.items;

SELECT
  relid::text AS partition_name,
  google_columnar_engine_add(relation => relid::text) AS added_table
FROM pg_partition_tree('pgstac.items'::regclass)
WHERE isleaf = true;

SELECT
  relid::text AS partition_name,
  google_columnar_engine_add(
    relation => relid::text,
    expressions => $expr$"content -> 'properties'", "content -> 'properties' ->> 'platform'", "content -> 'properties' ->> 'constellation'", "content -> 'properties' ->> 'sentinel:grid_square'"$expr$
  ) AS added_cql2_expressions
FROM pg_partition_tree('pgstac.items'::regclass)
WHERE isleaf = true;

SELECT schema_name, relation_name, status, size, block_count_in_cc, total_block_count
FROM g_columnar_relations
ORDER BY relation_name;
EOSQL
}

alloydb_decolumnarize() {
  if [ "$${ALLOYDB_IP}" = "disabled" ]; then
    echo "AlloyDB is disabled."
    return 1
  fi
  echo "=== Dropping pgstac.items leaf partitions from AlloyDB Columnar Engine ==="
  psql "$${ALLOYDB_DIRECT_URL}" << 'EOSQL'
SELECT
  relid::text AS partition_name,
  google_columnar_engine_drop(relation => relid::text) AS dropped_table
FROM pg_partition_tree('pgstac.items'::regclass)
WHERE isleaf = true;

SELECT schema_name, relation_name, status, size, block_count_in_cc, total_block_count
FROM g_columnar_relations
ORDER BY relation_name;
EOSQL
}

stac_benchmark() {
  local users="$${1:-10,50,100,150}"
  local runtime="$${2:-1m}"
  local output="$${3:-results.csv}"
  local targets=()
  if [ "$${ALLOYDB_IP}" != "disabled" ]; then
    targets+=("alloydb-direct=$${ALLOYDB_API_URL}" "alloydb-pooled=$${ALLOYDB_POOLED_API_URL}")
  fi
  if [ "$${POSTGRES_IP}" != "disabled" ]; then
    targets+=("postgres-direct=$${POSTGRES_API_URL}" "postgres-pooled=$${POSTGRES_POOLED_API_URL}")
  fi
  local IFS=","
  local api_list="$${targets[*]}"
  echo "=== Running stac-api-load-testing benchmark against: $${api_list} ==="
  stac-api-load-testing --benchmark \
    --api-address "$${api_list}" \
    --users "$${users}" \
    --run-time "$${runtime}" \
    -w 8 \
    -o "$${output}"
}
EOF

# 1. Install system dependencies & PostgreSQL 18 CLI client (psql, pgbench, pg_dump)
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y \
  make build-essential pkg-config libssl-dev libpq-dev \
  python3 python3-venv python3-dev python3-pip \
  git jq curl ca-certificates gnupg postgresql-common

/usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y
apt-get install -y postgresql-client-18

# 2. Build /opt/stac-venv with stac-fastapi.pgstac, pypgstac, and StacLabs/stac-api-load-testing
python3 -m venv /opt/stac-venv
/opt/stac-venv/bin/pip install --upgrade pip setuptools wheel
/opt/stac-venv/bin/pip install "stac-fastapi.pgstac[server]==7.2.0" "pypgstac[psycopg]"

if [ ! -d /opt/stac-api-load-testing ]; then
  git clone https://github.com/StacLabs/stac-api-load-testing.git /opt/stac-api-load-testing
fi
/opt/stac-venv/bin/pip install -e /opt/stac-api-load-testing
ln -sf /opt/stac-venv/bin/stac-api-load-testing /usr/local/bin/stac-api-load-testing
ln -sf /opt/stac-venv/bin/pypgstac /usr/local/bin/pypgstac
ln -sf /opt/stac-venv/bin/locust /usr/local/bin/locust

# Configure asyncpg pooler compatibility for Managed Connection Pooling (port 6432)
python3 -c '
p = "/opt/stac-venv/lib/python3.12/site-packages/stac_fastapi/pgstac/db.py"
s = open(p).read()
target = "server_settings=settings.server_settings.model_dump(),"
replacement = "server_settings={\"application_name\": \"pgstac\"} if int(settings.pgport) == 6432 else settings.server_settings.model_dump(), statement_cache_size=0 if int(settings.pgport) == 6432 else 100,"
if target in s:
    open(p, "w").write(s.replace(target, replacement))
'

# 3. Helper to bootstrap a database with PostGIS + pgstac schema
init_pgstac_db() {
  local host="$1"
  local is_alloy="$2"
  if [ "$${host}" = "disabled" ]; then
    return 0
  fi

  export PGUSER="${db_user}"
  export PGPASSWORD="${db_pass}"
  export PGHOST="$${host}"
  export PGPORT="5432"

  # Create database if missing
  psql -d postgres -tc "SELECT 1 FROM pg_database WHERE datname = '${db_name}'" | grep -q 1 \
    || psql -d postgres -c "CREATE DATABASE ${db_name};"

  # Enable extensions and grant PG16+ SET ROLE privileges for pgstac roles
  psql -d "${db_name}" << 'EOSQL'
CREATE EXTENSION IF NOT EXISTS postgis;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'pgstac_admin') THEN CREATE ROLE pgstac_admin; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'pgstac_read') THEN CREATE ROLE pgstac_read; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'pgstac_ingest') THEN CREATE ROLE pgstac_ingest; END IF;
END
$$;
GRANT pgstac_admin, pgstac_read, pgstac_ingest TO "${db_user}" WITH INHERIT TRUE, SET TRUE;
ALTER DATABASE "${db_name}" SET search_path TO pgstac, public;
ALTER ROLE "${db_user}" SET search_path TO pgstac, public;
EOSQL

  if [ "$${is_alloy}" = "true" ]; then
    psql -d "${db_name}" -c "CREATE EXTENSION IF NOT EXISTS google_columnar_engine;"
  fi

  # Migrate pgstac schema
  PGDATABASE="${db_name}" /opt/stac-venv/bin/pypgstac migrate
}

init_pgstac_db "${alloydb_ip}" "true"
init_pgstac_db "${postgres_ip}" "false"

# 4. Create systemd services for stac-fastapi.pgstac endpoints
create_stac_service() {
  local name="$1"
  local db_host="$2"
  local db_port="$3"
  local app_port="$4"

  if [ "$${db_host}" = "disabled" ]; then
    return 0
  fi

  cat << EOSVC > "/etc/systemd/system/$${name}.service"
[Unit]
Description=stac-fastapi-pgstac ($${name} -> $${db_host}:$${db_port})
After=network.target

[Service]
Type=simple
Environment="ENVIRONMENT=local"
Environment="PGUSER=${db_user}"
Environment="PGPASSWORD=${db_pass}"
Environment="PGDATABASE=${db_name}"
Environment="PGHOST=$${db_host}"
Environment="PGPORT=$${db_port}"
Environment="WEB_CONCURRENCY=10"
Environment="ENABLE_TRANSACTIONS_EXTENSIONS=true"
Environment="USE_API_HYDRATE=true"
Environment="DB_MIN_CONN_SIZE=2"
Environment="DB_MAX_CONN_SIZE=10"
ExecStart=/opt/stac-venv/bin/uvicorn stac_fastapi.pgstac.app:create_app --factory --host 0.0.0.0 --port $${app_port} --workers 10
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOSVC

  systemctl daemon-reload
  systemctl enable --now "$${name}.service"
}

create_stac_service "stac-fastapi-alloydb"        "${alloydb_ip}"  "5432" "8081"
create_stac_service "stac-fastapi-alloydb-pooled" "${alloydb_ip}"  "6432" "8082"
create_stac_service "stac-fastapi-postgres"       "${postgres_ip}" "5432" "8083"
create_stac_service "stac-fastapi-postgres-pooled" "${postgres_ip}" "6432" "8084"
