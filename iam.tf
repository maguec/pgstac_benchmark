resource "google_service_account" "bench_vm_sa" {
  account_id   = "pgstac-bench-sa"
  display_name = "pgSTAC Benchmark VM Service Account"
}

resource "google_project_iam_member" "alloydb_admin" {
  project = var.project_name
  role    = "roles/alloydb.admin"
  member  = "serviceAccount:${google_service_account.bench_vm_sa.email}"
}

resource "google_project_iam_member" "cloudsql_admin" {
  project = var.project_name
  role    = "roles/cloudsql.admin"
  member  = "serviceAccount:${google_service_account.bench_vm_sa.email}"
}

resource "google_project_iam_member" "alloydb_ai_binding" {
  count   = var.enable_alloydb ? 1 : 0
  project = var.project_name
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-alloydb.iam.gserviceaccount.com"

  depends_on = [google_alloydb_cluster.alloydb]
}
