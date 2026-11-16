variable "project_name" {
  type = string
}

variable "zone" {
  type    = string
  default = "us-west1-c"
}

variable "gcp_credentials_path" {
  type = string
}

variable "ssh_pub_key_path" {
  type    = string
  default = "~/.ssh/id_rsa.pub"
}

variable "ssh_username" {
  type    = string
  default = "ubuntu"
}

variable "machine_type" {
  type    = string
  default = "n2-standard-16"
}

variable "vm_disk_size_gb" {
  type    = number
  default = 100
}

variable "instance_project_id" {
  type    = string
  default = "ubuntu-os-cloud"
}

variable "instance_family" {
  type    = string
  default = "ubuntu-2404-lts-amd64"
}

variable "network" {
  type    = string
  default = "default"
}

#################################################################
# Database Toggles, Connection Pooling & Common Credentials
#################################################################

variable "enable_alloydb" {
  description = "Provision the AlloyDB cluster and primary instance"
  type        = bool
  default     = true
}

variable "enable_postgres" {
  description = "Provision the vanilla Cloud SQL for PostgreSQL instance"
  type        = bool
  default     = true
}

variable "enable_connection_pooling" {
  description = "Enable Managed Connection Pooling (port 6432) on AlloyDB and Cloud SQL"
  type        = bool
  default     = true
}

variable "deletion_protection" {
  type    = bool
  default = false
}

variable "postgres_version" {
  type    = string
  default = "POSTGRES_18"
}

variable "db_user" {
  type    = string
  default = "postgres"
}

variable "db_pass" {
  type    = string
  default = "AlloyWinzz"
}

variable "db_name" {
  type    = string
  default = "postgis"
}

#################################################################
# AlloyDB Configuration (Columnar Engine + Vectorized Joins)
#################################################################

variable "alloydb_cluster_id" {
  type    = string
  default = "pgstac-alloydb-cluster"
}

variable "alloydb_instance_id" {
  type    = string
  default = "pgstac-alloydb-primary"
}

variable "alloydb_cpu_count" {
  type    = number
  default = 8
}

variable "alloydb_flags" {
  type = map(string)
  default = {
    work_mem                                              = "65536"
    default_statistics_target                             = "200"
    "google_columnar_engine.enabled"                      = "on"
    "google_columnar_engine.enable_auto_columnarization"  = "off"
    "google_columnar_engine.enable_vectorized_join"       = "on"
    "google_columnar_engine.memory_size_in_mb"            = "16384"
    "google_columnar_engine.max_non_toasted_column_size"  = "8192"
    "google_columnar_engine.populate_detoasted_max_bytes" = "4096"
    "google_columnar_engine.relations"                    = ""
  }
}

variable "alloydb_pooler_flags" {
  type    = map(string)
  default = {}
}

#################################################################
# Vanilla PostgreSQL (Cloud SQL Enterprise Plus) Configuration
#################################################################

variable "postgres_tier" {
  description = "db-perf-optimized-N-8 provides 8 vCPUs / 64 GB RAM on Enterprise Plus to match 8-vCPU AlloyDB"
  type        = string
  default     = "db-perf-optimized-N-8"
}

variable "postgres_edition" {
  type    = string
  default = "ENTERPRISE_PLUS"
}

variable "postgres_disk_size_gb" {
  type    = number
  default = 100
}

variable "postgres_flags" {
  type = map(string)
  default = {
    work_mem                  = "65536"
    default_statistics_target = "200"
  }
}

variable "postgres_pooler_flags" {
  type    = map(string)
  default = {}
}
