# Hetzner's share of testnet-1: 3 validators, 3 sentries (1:1), 1 archive.
# See gcp.tf for the other 2 validators/sentries, 1 archive, and the 1 RPC
# node. README.md explains why the fleet is split this way and how the two
# clouds' sentries find each other without a cross-cloud VPN.

resource "hcloud_network" "testnet_1" {
  name     = "testnet-1-hetzner"
  ip_range = var.hetzner_network_ip_range
}

resource "hcloud_network_subnet" "testnet_1" {
  network_id   = hcloud_network.testnet_1.id
  type         = "cloud"
  network_zone = "eu-central"
  ip_range     = var.hetzner_network_ip_range
}

resource "hcloud_firewall" "validator" {
  name = "testnet-1-hetzner-validator"

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = [var.bastion_ipv4]
  }

  # p2p from sentries. Scoped to the private subnet, not per-sentry IP — the
  # actual "only my sentries" restriction is enforced at the CometBFT layer
  # (persistent_peers + pex=false, ansible/roles/node). Defense in depth, not
  # the primary control.
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "26656"
    source_ips = [var.hetzner_network_ip_range]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "26660"
    source_ips = [var.hetzner_network_ip_range]
  }
}

resource "hcloud_firewall" "sentry" {
  name = "testnet-1-hetzner-sentry"

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = [var.bastion_ipv4]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "26656"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "26660"
    source_ips = [var.hetzner_network_ip_range]
  }
}

resource "hcloud_firewall" "archive" {
  name = "testnet-1-hetzner-archive"

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = [var.bastion_ipv4]
  }

  # No public rule at all. debug_traceTransaction is only reachable from
  # inside the private network (explorer's Blockscout backend).
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "1317,8545,8546,26657"
    source_ips = [var.hetzner_network_ip_range]
  }
}

locals {
  hetzner_validator_names = ["v1", "v2", "v3"]

  hetzner_validators = {
    for i, n in local.hetzner_validator_names : n => {
      location   = element(var.hetzner_locations, i % length(var.hetzner_locations))
      private_ip = cidrhost(var.hetzner_network_ip_range, 10 + i + 1) # .11-.13
    }
  }

  hetzner_sentries = {
    for i, n in local.hetzner_validator_names : n => {
      location   = element(var.hetzner_locations, i % length(var.hetzner_locations))
      private_ip = cidrhost(var.hetzner_network_ip_range, 20 + i + 1) # .21-.23
    }
  }

  hetzner_archive_private_ip = cidrhost(var.hetzner_network_ip_range, 41)
}

module "hetzner_validator" {
  source = "../../modules/hetzner/validator"

  for_each = local.hetzner_validators

  name           = "testnet-1-hetzner-validator-${each.key}"
  location       = each.value.location
  ssh_key_ids    = var.hetzner_ssh_key_ids
  network_id     = hcloud_network.testnet_1.id
  private_ip     = each.value.private_ip
  firewall_ids   = [hcloud_firewall.validator.id]
  ssh_public_key = var.ssh_public_key
  labels         = { network = "testnet-1" }

  depends_on = [hcloud_network_subnet.testnet_1]
}

module "hetzner_sentry" {
  source = "../../modules/hetzner/sentry"

  for_each = local.hetzner_sentries

  name              = "testnet-1-hetzner-sentry-${each.key}"
  location          = each.value.location
  ssh_key_ids       = var.hetzner_ssh_key_ids
  network_id        = hcloud_network.testnet_1.id
  private_ip        = each.value.private_ip
  firewall_ids      = [hcloud_firewall.sentry.id]
  ssh_public_key    = var.ssh_public_key
  validator_node_id = "" # filled in after first boot, once validator node IDs are known — see README.md
  labels            = { network = "testnet-1" }

  depends_on = [hcloud_network_subnet.testnet_1]
}

module "hetzner_archive" {
  source = "../../modules/hetzner/archive"

  name           = "testnet-1-hetzner-archive-1"
  location       = var.hetzner_locations[0]
  ssh_key_ids    = var.hetzner_ssh_key_ids
  network_id     = hcloud_network.testnet_1.id
  private_ip     = local.hetzner_archive_private_ip
  firewall_ids   = [hcloud_firewall.archive.id]
  ssh_public_key = var.ssh_public_key
  labels         = { network = "testnet-1" }

  depends_on = [hcloud_network_subnet.testnet_1]
}
