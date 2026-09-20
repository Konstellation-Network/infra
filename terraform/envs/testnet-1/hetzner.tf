# Hetzner's share of testnet-1: 5 validators, 5 sentries (1:1), 1 archive,
# the Hetzner bastion/gateway, and — depending on var.monitoring_cloud /
# var.horcrux_mode — the monitoring host and/or some cosigners. See gcp.tf
# for the other half and README.md for why the fleet is split this way and
# how the two clouds' private networks are joined (bastion WireGuard tunnel).
#
# hcloud firewalls filter the PUBLIC interface only (Hetzner docs). Hosts
# with no public IP — validators, archive, monitoring, cosigners — are not
# touched by them at all; their attached firewall below is documentation of
# intent, and ufw (ansible/roles/firewall) is the actual control. The rules
# that DO bite are the sentry (public p2p), bastion (operator SSH, tunnel)
# ones.

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

# Private-only hosts. Nothing on the public interface (there is none); the
# rules here mirror what ufw enforces so a reader of this file sees the
# intended policy in one place.
resource "hcloud_firewall" "validator" {
  name = "testnet-1-hetzner-validator"

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = [for ip in local.hetzner_ssh_sources : "${ip}/32"]
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

  # Metrics: the monitoring host may be in either cloud.
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "26660"
    source_ips = local.fleet_cidrs
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "9100"
    source_ips = local.fleet_cidrs
  }

  # priv_validator_laddr: horcrux cosigners dial in. Dedicated mode only —
  # colocated horcrux talks over loopback.
  dynamic "rule" {
    for_each = var.horcrux_mode == "dedicated" ? [1] : []
    content {
      direction  = "in"
      protocol   = "tcp"
      port       = "1234"
      source_ips = [for ip in values(local.cosigner_private_ips) : "${ip}/32"]
    }
  }
}

resource "hcloud_firewall" "sentry" {
  name = "testnet-1-hetzner-sentry"

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = [for ip in local.hetzner_ssh_sources : "${ip}/32"]
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
    source_ips = local.fleet_cidrs
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "9100"
    source_ips = local.fleet_cidrs
  }
}

resource "hcloud_firewall" "archive" {
  name = "testnet-1-hetzner-archive"

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = [for ip in local.hetzner_ssh_sources : "${ip}/32"]
  }

  # No public rule at all. debug_traceTransaction is only reachable from
  # inside the private networks (explorer's Blockscout backend). One rule
  # per port: hcloud rule ports are a single port or a range, never a
  # comma list (the earlier "1317,8545,8546,26657" would have failed at
  # apply, not validate).
  dynamic "rule" {
    for_each = ["1317", "8545-8546", "26657"]
    content {
      direction  = "in"
      protocol   = "tcp"
      port       = rule.value
      source_ips = local.archive_rpc_cidrs
    }
  }

  dynamic "rule" {
    for_each = ["26660", "9100"]
    content {
      direction  = "in"
      protocol   = "tcp"
      port       = rule.value
      source_ips = local.fleet_cidrs
    }
  }
}

# The one Hetzner firewall whose rules are all on a public interface and
# therefore all effective. Operator SSH (if this bastion is an entry point)
# and the WireGuard tunnel from the GCP bastion; nothing else, ever.
resource "hcloud_firewall" "bastion" {
  name = "testnet-1-hetzner-bastion"

  dynamic "rule" {
    for_each = length(local.hetzner_bastion_ssh_cidrs) > 0 ? [1] : []
    content {
      direction  = "in"
      protocol   = "tcp"
      port       = "22"
      source_ips = local.hetzner_bastion_ssh_cidrs
    }
  }

  rule {
    direction  = "in"
    protocol   = "udp"
    port       = tostring(var.wireguard_port)
    source_ips = ["${module.gcp_bastion.public_ipv4}/32"]
  }
}

# Private-only, no public interface: intent only (see file header).
resource "hcloud_firewall" "internal" {
  name = "testnet-1-hetzner-internal"

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = [for ip in local.hetzner_ssh_sources : "${ip}/32"]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "9100"
    source_ips = local.fleet_cidrs
  }
}

locals {
  # 10 foundation-run validators fleet-wide (ENGINEERING.md D7, re-decided
  # 2026-09-20): v1-v5 here, v6-v10 on GCP.
  hetzner_validator_names = ["v1", "v2", "v3", "v4", "v5"]

  hetzner_validators = {
    for i, n in local.hetzner_validator_names : n => {
      location   = element(var.hetzner_locations, i % length(var.hetzner_locations))
      private_ip = cidrhost(var.hetzner_network_ip_range, 10 + i + 1) # .11-.15
    }
  }

  hetzner_sentries = {
    for i, n in local.hetzner_validator_names : n => {
      location   = element(var.hetzner_locations, i % length(var.hetzner_locations))
      private_ip = cidrhost(var.hetzner_network_ip_range, 20 + i + 1) # .21-.25
    }
  }

  hetzner_archive_private_ip = cidrhost(var.hetzner_network_ip_range, 41)
}

module "hetzner_bastion" {
  source = "../../modules/hetzner/bastion"

  name           = "testnet-1-hetzner-bastion"
  location       = var.hetzner_locations[0]
  ssh_key_ids    = var.hetzner_ssh_key_ids
  network_id     = hcloud_network.testnet_1.id
  private_ip     = local.hetzner_bastion_private_ip
  firewall_ids   = [hcloud_firewall.bastion.id]
  ssh_public_key = var.ssh_public_key
  nat_gateway    = true # no managed NAT on Hetzner; without this, private-only hosts have no internet
  remote_cidrs   = { gcp = var.gcp_network_ip_range }
  labels         = { network = "testnet-1" }

  depends_on = [hcloud_network_subnet.testnet_1]
}

module "hetzner_validator" {
  source = "../../modules/hetzner/validator"

  for_each = local.hetzner_validators

  name              = "testnet-1-hetzner-validator-${each.key}"
  location          = each.value.location
  ssh_key_ids       = var.hetzner_ssh_key_ids
  network_id        = hcloud_network.testnet_1.id
  private_ip        = each.value.private_ip
  firewall_ids      = [hcloud_firewall.validator.id]
  ssh_public_key    = var.ssh_public_key
  default_route_via = local.hetzner_gateway
  labels            = { network = "testnet-1" }

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

  name              = "testnet-1-hetzner-archive-1"
  location          = var.hetzner_locations[0]
  ssh_key_ids       = var.hetzner_ssh_key_ids
  network_id        = hcloud_network.testnet_1.id
  private_ip        = local.hetzner_archive_private_ip
  firewall_ids      = [hcloud_firewall.archive.id]
  ssh_public_key    = var.ssh_public_key
  default_route_via = local.hetzner_gateway
  labels            = { network = "testnet-1" }

  depends_on = [hcloud_network_subnet.testnet_1]
}

module "hetzner_monitoring" {
  source = "../../modules/hetzner/monitoring"

  count = var.monitoring_cloud == "hetzner" ? 1 : 0

  name              = "testnet-1-hetzner-monitoring-1"
  location          = var.hetzner_locations[0]
  ssh_key_ids       = var.hetzner_ssh_key_ids
  network_id        = hcloud_network.testnet_1.id
  private_ip        = local.hetzner_monitoring_private_ip
  firewall_ids      = [hcloud_firewall.internal.id]
  ssh_public_key    = var.ssh_public_key
  default_route_via = local.hetzner_gateway
  labels            = { network = "testnet-1" }

  depends_on = [hcloud_network_subnet.testnet_1]
}

module "hetzner_cosigner" {
  source = "../../modules/hetzner/cosigner"

  for_each = local.hetzner_cosigners

  name              = "testnet-1-hetzner-cosigner-${each.key}"
  location          = each.value.location
  ssh_key_ids       = var.hetzner_ssh_key_ids
  network_id        = hcloud_network.testnet_1.id
  private_ip        = local.cosigner_private_ips[each.key]
  firewall_ids      = [hcloud_firewall.internal.id]
  ssh_public_key    = var.ssh_public_key
  default_route_via = local.hetzner_gateway
  labels            = { network = "testnet-1" }

  depends_on = [hcloud_network_subnet.testnet_1]
}
