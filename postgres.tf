resource "random_id" "db_name_suffix" {
  count       = var.enable_postgres ? 1 : 0
  byte_length = 4
}

resource "google_sql_database_instance" "postgres" {
  count               = var.enable_postgres ? 1 : 0
  provider            = google-beta
  project             = var.project_name
  name                = "pgstac-postgres-${random_id.db_name_suffix[0].hex}"
  region              = local.region
  database_version    = var.postgres_version
  deletion_protection = false

  depends_on = [google_service_networking_connection.vpc_connection]

  settings {
    tier                        = var.postgres_tier
    edition                     = var.postgres_edition
    availability_type           = "ZONAL"
    disk_type                   = "PD_SSD"
    disk_size                   = var.postgres_disk_size_gb
    deletion_protection_enabled = false
    retain_backups_on_delete    = false

    backup_configuration {
      enabled                        = false
      point_in_time_recovery_enabled = false
    }

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = data.google_compute_network.network.id
      enable_private_path_for_google_cloud_services = true
    }

    connection_pool_config {
      connection_pooling_enabled = var.enable_connection_pooling

      dynamic "flags" {
        for_each = var.postgres_pooler_flags
        content {
          name  = flags.key
          value = tostring(flags.value)
        }
      }
    }

    insights_config {
      query_insights_enabled  = true
      query_string_length     = 4500
      record_application_tags = true
      record_client_address   = true
      query_plans_per_minute  = 20
    }

    dynamic "database_flags" {
      for_each = var.postgres_flags
      content {
        name  = database_flags.key
        value = tostring(database_flags.value)
      }
    }
  }
}

resource "google_sql_user" "postgres_user" {
  count    = var.enable_postgres ? 1 : 0
  name     = var.db_user
  instance = google_sql_database_instance.postgres[0].name
  password = var.db_pass
}

resource "google_sql_database" "postgis" {
  count    = var.enable_postgres ? 1 : 0
  name     = var.db_name
  instance = google_sql_database_instance.postgres[0].name
}
