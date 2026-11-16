resource "google_compute_instance" "bench_vm" {
  name                = "pgstac-bench-vm"
  machine_type        = var.machine_type
  zone                = var.zone
  tags                = ["pgstac-tester"]
  deletion_protection = false

  boot_disk {
    initialize_params {
      image = data.google_compute_image.image.self_link
      size  = var.vm_disk_size_gb
      type  = "pd-ssd"
    }
  }

  metadata = {
    ssh-keys    = "${var.ssh_username}:${file(var.ssh_pub_key_path)}"
    alloydb-ip  = var.enable_alloydb ? google_alloydb_instance.alloydb[0].ip_address : "disabled"
    postgres-ip = var.enable_postgres ? google_sql_database_instance.postgres[0].private_ip_address : "disabled"
  }

  metadata_startup_script = templatefile(
    "startup_script.sh",
    {
      projectid      = var.project_name
      region         = local.region
      alloydb_ip     = var.enable_alloydb ? google_alloydb_instance.alloydb[0].ip_address : "disabled"
      postgres_ip    = var.enable_postgres ? google_sql_database_instance.postgres[0].private_ip_address : "disabled"
      default_pghost = var.enable_alloydb ? google_alloydb_instance.alloydb[0].ip_address : (var.enable_postgres ? google_sql_database_instance.postgres[0].private_ip_address : "localhost")
      db_user        = var.db_user
      db_pass        = var.db_pass
      db_name        = var.db_name
    }
  )

  service_account {
    email  = google_service_account.bench_vm_sa.email
    scopes = ["cloud-platform"]
  }

  allow_stopping_for_update = true
  lifecycle {
    ignore_changes = [boot_disk]
  }

  network_interface {
    network = data.google_compute_network.network.id
    access_config {
      nat_ip = google_compute_address.static.address
    }
  }

  shielded_instance_config {
    enable_secure_boot = true
  }
}
