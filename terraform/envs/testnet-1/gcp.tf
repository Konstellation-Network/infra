# GCP's share of testnet-1: 2 validators, 2 sentries (1:1), 1 archive, 1 RPC.
# See hetzner.tf for the other 3 validators/sentries and 1 archive.
#
# Validators here use Local SSD (see terraform/modules/gcp/validator's
# local_ssd_count variable) — read the warning there before treating this as
# a mainnet pattern; it's a testnet-1-only choice.
#
# A custom-mode VPC with no rules denies all ingress by default, same as the
# Hetzner firewalls' implicit deny — no separate "default deny" rule needed.
# IPv4 only on this side (Hetzner's sentry/rpc firewalls also open ::/0;
# adding that here means a dual-stack VPC, not done in this pass).

resource "google_compute_network" "testnet_1" {
  name                    = "testnet-1-gcp"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "testnet_1" {
  name          = "testnet-1-gcp"
  network       = google_compute_network.testnet_1.id
  region        = var.gcp_region
  ip_cidr_range = var.gcp_network_ip_range
}

resource "google_compute_firewall" "ssh" {
  name          = "testnet-1-gcp-ssh"
  network       = google_compute_network.testnet_1.id
  direction     = "INGRESS"
  source_ranges = [var.bastion_ipv4]
  target_tags   = ["konstellation"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "p2p_validator" {
  name          = "testnet-1-gcp-p2p-validator"
  network       = google_compute_network.testnet_1.id
  direction     = "INGRESS"
  source_ranges = [var.gcp_network_ip_range]
  target_tags   = ["validator"]

  allow {
    protocol = "tcp"
    ports    = ["26656"]
  }
}

resource "google_compute_firewall" "p2p_sentry" {
  name        = "testnet-1-gcp-p2p-sentry"
  network     = google_compute_network.testnet_1.id
  direction   = "INGRESS"
  target_tags = ["sentry"]

  allow {
    protocol = "tcp"
    ports    = ["26656"]
  }
}

resource "google_compute_firewall" "monitoring_internal" {
  name          = "testnet-1-gcp-monitoring-internal"
  network       = google_compute_network.testnet_1.id
  direction     = "INGRESS"
  source_ranges = [var.gcp_network_ip_range]
  target_tags   = ["konstellation"]

  allow {
    protocol = "tcp"
    ports    = ["26660", "9100"]
  }
}

resource "google_compute_firewall" "rpc_public" {
  name        = "testnet-1-gcp-rpc-public"
  network     = google_compute_network.testnet_1.id
  direction   = "INGRESS"
  target_tags = ["rpc"]

  allow {
    protocol = "tcp"
    ports    = ["26656", "26657", "1317", "8545-8546"]
  }
}

resource "google_compute_firewall" "archive_internal" {
  name          = "testnet-1-gcp-archive-internal"
  network       = google_compute_network.testnet_1.id
  direction     = "INGRESS"
  source_ranges = [var.gcp_network_ip_range]
  target_tags   = ["archive"]

  allow {
    protocol = "tcp"
    ports    = ["26657", "1317", "8545-8546"]
  }
}

locals {
  gcp_validator_names = ["v4", "v5"] # continues the Hetzner v1-v3 numbering

  gcp_validators = {
    for i, n in local.gcp_validator_names : n => {
      zone       = element(var.gcp_zones, i % length(var.gcp_zones))
      private_ip = cidrhost(var.gcp_network_ip_range, 10 + i + 1) # .14-.15 (continuing from hetzner's .11-.13)
    }
  }

  gcp_sentries = {
    for i, n in local.gcp_validator_names : n => {
      zone       = element(var.gcp_zones, i % length(var.gcp_zones))
      private_ip = cidrhost(var.gcp_network_ip_range, 20 + i + 1) # .24-.25
    }
  }

  gcp_archive_private_ip = cidrhost(var.gcp_network_ip_range, 42)
  gcp_rpc_private_ip     = cidrhost(var.gcp_network_ip_range, 31)

  # Kept as a root local (not just the module default) so outputs.tf can put
  # it in the ansible inventory without a module needing to echo its own input
  # back out as an output.
  gcp_validator_local_ssd_count = 8
}

module "gcp_validator" {
  source = "../../modules/gcp/validator"

  for_each = local.gcp_validators

  name            = "testnet-1-gcp-validator-${each.key}"
  zone            = each.value.zone
  network         = google_compute_network.testnet_1.id
  subnetwork      = google_compute_subnetwork.testnet_1.id
  private_ip      = each.value.private_ip
  local_ssd_count = local.gcp_validator_local_ssd_count
  ssh_user        = var.ssh_user
  ssh_public_key  = var.ssh_public_key
  labels          = { network = "testnet-1" }
}

module "gcp_sentry" {
  source = "../../modules/gcp/sentry"

  for_each = local.gcp_sentries

  name              = "testnet-1-gcp-sentry-${each.key}"
  zone              = each.value.zone
  network           = google_compute_network.testnet_1.id
  subnetwork        = google_compute_subnetwork.testnet_1.id
  private_ip        = each.value.private_ip
  ssh_user          = var.ssh_user
  ssh_public_key    = var.ssh_public_key
  validator_node_id = "" # filled in after first boot, once validator node IDs are known — see README.md
  labels            = { network = "testnet-1" }
}

module "gcp_archive" {
  source = "../../modules/gcp/archive"

  name           = "testnet-1-gcp-archive-1"
  zone           = var.gcp_zones[0]
  network        = google_compute_network.testnet_1.id
  subnetwork     = google_compute_subnetwork.testnet_1.id
  private_ip     = local.gcp_archive_private_ip
  ssh_user       = var.ssh_user
  ssh_public_key = var.ssh_public_key
  labels         = { network = "testnet-1" }
}

module "gcp_rpc" {
  source = "../../modules/gcp/rpc"

  name           = "testnet-1-gcp-rpc-1"
  zone           = var.gcp_zones[0]
  network        = google_compute_network.testnet_1.id
  subnetwork     = google_compute_subnetwork.testnet_1.id
  private_ip     = local.gcp_rpc_private_ip
  ssh_user       = var.ssh_user
  ssh_public_key = var.ssh_public_key
  labels         = { network = "testnet-1" }
}
