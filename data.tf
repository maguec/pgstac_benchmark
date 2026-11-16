data "http" "icanhazip" {
  url = "https://checkip.amazonaws.com"
}

data "google_compute_image" "image" {
  family  = var.instance_family
  project = var.instance_project_id
}

data "google_compute_network" "network" {
  name = var.network
}

data "google_project" "project" {}
