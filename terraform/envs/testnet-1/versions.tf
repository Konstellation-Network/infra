terraform {
  required_version = ">= 1.9.0"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.48"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

provider "hcloud" {
  token = var.hcloud_token
}

provider "google" {
  project = var.gcp_project
  region  = var.gcp_region
  # Credentials via Application Default Credentials (`gcloud auth application-default
  # login`) or GOOGLE_APPLICATION_CREDENTIALS pointing at a service account key —
  # never a key file committed here.
}
