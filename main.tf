terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.15.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 6.15.0"
    }
  }
}

provider "google" {
  credentials = file(var.gcp_credentials_path)
  project     = var.project_name
  region      = local.region
}

provider "google-beta" {
  credentials = file(var.gcp_credentials_path)
  project     = var.project_name
  region      = local.region
}

locals {
  region = join("-", slice(split("-", var.zone), 0, 2))
}
