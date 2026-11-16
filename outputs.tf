output "a-ssh-command" {
  value = "gcloud compute ssh --zone ${var.zone} ${google_compute_instance.bench_vm.name} --project ${var.project_name} --tunnel-through-iap"
}

output "b-alloydb-psql-direct" {
  value = var.enable_alloydb ? "psql postgresql://${var.db_user}:${var.db_pass}@${google_alloydb_instance.alloydb[0].ip_address}:5432/${var.db_name}" : "AlloyDB disabled (set enable_alloydb = true)"
}

output "c-alloydb-psql-pooled" {
  value = var.enable_alloydb ? "psql postgresql://${var.db_user}:${var.db_pass}@${google_alloydb_instance.alloydb[0].ip_address}:6432/${var.db_name}" : "AlloyDB disabled"
}

output "d-postgres-psql-direct" {
  value = var.enable_postgres ? "psql postgresql://${var.db_user}:${var.db_pass}@${google_sql_database_instance.postgres[0].private_ip_address}:5432/${var.db_name}" : "Postgres disabled (set enable_postgres = true)"
}

output "e-postgres-psql-pooled" {
  value = var.enable_postgres ? "psql postgresql://${var.db_user}:${var.db_pass}@${google_sql_database_instance.postgres[0].private_ip_address}:6432/${var.db_name}" : "Postgres disabled"
}

output "f-vm-benchmark-workflow" {
  value = "stac_ingest 4 500 50000 && alloydb_columnarize && stac_benchmark 10,50,100,150 1m results.csv"
}
