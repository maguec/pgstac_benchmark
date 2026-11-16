resource "google_compute_address" "static" {
  name = "ipv4-address-pgstac-bench"
}

resource "google_compute_firewall" "pgstac_tester" {
  name    = "pgstac-tester"
  network = data.google_compute_network.network.id

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
  }

  allow {
    protocol = "udp"
  }

  source_ranges = [
    "${chomp(data.http.icanhazip.response_body)}/32",
    "35.235.240.0/20",
  ]
  source_tags = ["pgstac-tester"]
  target_tags = ["pgstac-tester"]
}

resource "google_compute_global_address" "private_ip_alloc" {
  name          = "pgstac-private-ip-alloc"
  address_type  = "INTERNAL"
  purpose       = "VPC_PEERING"
  prefix_length = 16
  network       = data.google_compute_network.network.id
}

resource "google_service_networking_connection" "vpc_connection" {
  network                 = data.google_compute_network.network.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_alloc.name]
  update_on_creation_fail = true
}

resource "google_compute_route" "default_internet" {
  name             = "pgstac-default-internet"
  network          = data.google_compute_network.network.id
  dest_range       = "0.0.0.0/0"
  next_hop_gateway = "default-internet-gateway"
  priority         = 1000
  tags             = ["pgstac-tester"]
}
