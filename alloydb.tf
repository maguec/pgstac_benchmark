resource "google_alloydb_cluster" "alloydb" {
  count               = var.enable_alloydb ? 1 : 0
  cluster_id          = var.alloydb_cluster_id
  location            = local.region
  database_version    = var.postgres_version
  deletion_protection = false
  deletion_policy     = "FORCE"

  network_config {
    network = data.google_compute_network.network.id
  }

  continuous_backup_config {
    enabled = false
  }

  automated_backup_policy {
    enabled = false
  }

  initial_user {
    user     = var.db_user
    password = var.db_pass
  }

  depends_on = [google_service_networking_connection.vpc_connection]
}

resource "google_alloydb_instance" "alloydb" {
  count         = var.enable_alloydb ? 1 : 0
  cluster       = google_alloydb_cluster.alloydb[0].name
  instance_id   = var.alloydb_instance_id
  instance_type = "PRIMARY"

  machine_config {
    cpu_count = var.alloydb_cpu_count
  }

  connection_pool_config {
    enabled = var.enable_connection_pooling
    flags   = var.alloydb_pooler_flags
  }

  query_insights_config {
    query_string_length     = 4500
    record_application_tags = true
    record_client_address   = true
    query_plans_per_minute  = 20
  }

  database_flags = var.alloydb_flags

  depends_on = [
    google_service_networking_connection.vpc_connection,
    google_project_iam_member.alloydb_ai_binding
  ]
}
