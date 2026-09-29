# devnet-1 (D18, 2026-09-29): the dapp-developer network. Runs the mainnet
# binary version, one foundation-run validator, everything on Hetzner in one
# location. Same modules as testnet-1 (terraform/modules/hetzner/*); what is
# left out, and why, is in README.md "devnet-1":
#
#   bastion     .5    public   SSH entry + NAT egress (Hetzner has no managed NAT)
#   validator   .11   private  v1 — plain priv_validator_key.json, no Horcrux
#   sentry      .21+  public   sentry_count of them (default 1), §9.2 sentry architecture
#   rpc         .31   public   EVM JSON-RPC/WS + CometBFT RPC + REST — dapps and the faucet
#   archive     .41   private  pruning=nothing + debug tracing — the explorer's backend
#   monitoring  .50   private  prometheus/alertmanager/grafana/tenderduty
#
# No second cloud, so no WireGuard tunnel, no cross-cloud routes and no
# cosigners. hcloud firewalls filter the PUBLIC interface only (see
# envs/testnet-1/hetzner.tf header): on the private-only hosts ufw
# (ansible/roles/firewall) is the real control and the rules below are
# documentation of intent; on the bastion, sentries and rpc they bite.

locals {
  # Which Hetzner locations belong to which network zone (hcloud docs).
  hetzner_zone_locations = {
    eu-central   = ["fsn1", "nbg1", "hel1"]
    us-east      = ["ash"]
    us-west      = ["hil"]
    ap-southeast = ["sin"]
  }

  # One private network; "fleet" = this network (the ansible roles and the
  # inventory template speak in fleet_cidrs, shared with testnet-1).
  fleet_cidrs = [var.hetzner_network_ip_range]

  gateway            = cidrhost(var.hetzner_network_ip_range, 1)
  bastion_private_ip = cidrhost(var.hetzner_network_ip_range, 5)
  validator_ip       = cidrhost(var.hetzner_network_ip_range, 11)
  rpc_private_ip     = cidrhost(var.hetzner_network_ip_range, 31)
  archive_private_ip = cidrhost(var.hetzner_network_ip_range, 41)
  monitoring_ip      = cidrhost(var.hetzner_network_ip_range, 50)

  sentries = {
    for i in range(var.sentry_count) : tostring(i + 1) => {
      private_ip = cidrhost(var.hetzner_network_ip_range, 20 + i + 1) # .21-.25
    }
  }

  # Archive RPC/REST/JSON-RPC: the monitoring host (26657 only, tenderduty)
  # and the explorer backend — never the network, which includes the public
  # rpc node and sentries.
  archive_rpc_cidrs = distinct(concat(["${local.monitoring_ip}/32"], var.explorer_cidrs))

  labels = { network = "devnet-1" }
}

resource "hcloud_network" "devnet_1" {
  name     = "devnet-1-hetzner"
  ip_range = var.hetzner_network_ip_range
}

resource "hcloud_network_subnet" "devnet_1" {
  network_id   = hcloud_network.devnet_1.id
  type         = "cloud"
  network_zone = var.hetzner_network_zone
  ip_range     = var.hetzner_network_ip_range
}

# --- Firewalls ---

resource "hcloud_firewall" "validator" {
  name = "devnet-1-hetzner-validator"

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = ["${local.bastion_private_ip}/32"]
  }

  # p2p from the sentries only (P23 shape: never the /24, which holds the
  # public rpc node).
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "26656"
    source_ips = [for s in local.sentries : "${s.private_ip}/32"]
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

resource "hcloud_firewall" "sentry" {
  name = "devnet-1-hetzner-sentry"

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = ["${local.bastion_private_ip}/32"]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "26656"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # CometBFT RPC for tenderduty: the monitoring host only.
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "26657"
    source_ips = ["${local.monitoring_ip}/32"]
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

# The public endpoint dapp developers, wallets and the faucet use. Same
# port set as testnet-1's GCP rpc_public rule (p2p, CometBFT RPC, REST,
# EVM JSON-RPC + WS); gRPC 9090 stays closed. Unauthenticated and
# unmetered, like testnet-1's — README "Known gaps".
resource "hcloud_firewall" "rpc" {
  name = "devnet-1-hetzner-rpc"

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = ["${local.bastion_private_ip}/32"]
  }

  dynamic "rule" {
    for_each = ["26656", "26657", "1317", "8545-8546"]
    content {
      direction  = "in"
      protocol   = "tcp"
      port       = rule.value
      source_ips = ["0.0.0.0/0", "::/0"]
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

resource "hcloud_firewall" "archive" {
  name = "devnet-1-hetzner-archive"

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = ["${local.bastion_private_ip}/32"]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "26657"
    source_ips = local.archive_rpc_cidrs
  }

  # REST and the debug-enabled JSON-RPC: the explorer only; no rule until
  # var.explorer_cidrs is set.
  dynamic "rule" {
    for_each = length(var.explorer_cidrs) > 0 ? ["1317", "8545-8546"] : []
    content {
      direction  = "in"
      protocol   = "tcp"
      port       = rule.value
      source_ips = var.explorer_cidrs
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

# Operator SSH only. No WireGuard rule: there is no second cloud to tunnel to.
resource "hcloud_firewall" "bastion" {
  name = "devnet-1-hetzner-bastion"

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = var.operator_ssh_cidrs
  }
}

resource "hcloud_firewall" "internal" {
  name = "devnet-1-hetzner-internal"

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = ["${local.bastion_private_ip}/32"]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "9100"
    source_ips = local.fleet_cidrs
  }
}

# --- Hosts ---

module "bastion" {
  source = "../../modules/hetzner/bastion"

  name           = "devnet-1-hetzner-bastion"
  location       = var.hetzner_location
  ssh_key_ids    = var.hetzner_ssh_key_ids
  network_id     = hcloud_network.devnet_1.id
  private_ip     = local.bastion_private_ip
  firewall_ids   = [hcloud_firewall.bastion.id]
  ssh_public_key = var.ssh_public_key
  nat_gateway    = true # private-only hosts have no internet without it
  remote_cidrs   = {}   # single cloud: no tunnel routes
  labels         = local.labels

  depends_on = [hcloud_network_subnet.devnet_1]
}

# The one validator. No public IP, local NVMe, prevent_destroy (module).
# Signs with a plain priv_validator_key.json — no Horcrux on devnet-1
# (README "devnet-1": why, and the §2.7 rules that still apply).
module "validator" {
  source = "../../modules/hetzner/validator"

  name              = "devnet-1-hetzner-validator-v1"
  location          = var.hetzner_location
  server_type       = var.validator_server_type
  ssh_key_ids       = var.hetzner_ssh_key_ids
  network_id        = hcloud_network.devnet_1.id
  private_ip        = local.validator_ip
  firewall_ids      = [hcloud_firewall.validator.id]
  ssh_public_key    = var.ssh_public_key
  default_route_via = local.gateway
  labels            = local.labels

  depends_on = [hcloud_network_subnet.devnet_1]
}

module "sentry" {
  source = "../../modules/hetzner/sentry"

  for_each = local.sentries

  name              = "devnet-1-hetzner-sentry-${each.key}"
  location          = var.hetzner_location
  ssh_key_ids       = var.hetzner_ssh_key_ids
  network_id        = hcloud_network.devnet_1.id
  private_ip        = each.value.private_ip
  firewall_ids      = [hcloud_firewall.sentry.id]
  ssh_public_key    = var.ssh_public_key
  validator_node_id = "" # ansible/roles/node/tasks/peers.yml computes private_peer_ids after init
  labels            = local.labels

  depends_on = [hcloud_network_subnet.devnet_1]
}

module "rpc" {
  source = "../../modules/hetzner/rpc"

  name           = "devnet-1-hetzner-rpc-1"
  location       = var.hetzner_location
  server_type    = var.rpc_server_type
  ssh_key_ids    = var.hetzner_ssh_key_ids
  network_id     = hcloud_network.devnet_1.id
  private_ip     = local.rpc_private_ip
  firewall_ids   = [hcloud_firewall.rpc.id]
  ssh_public_key = var.ssh_public_key
  labels         = local.labels

  depends_on = [hcloud_network_subnet.devnet_1]
}

module "archive" {
  source = "../../modules/hetzner/archive"

  name              = "devnet-1-hetzner-archive-1"
  location          = var.hetzner_location
  ssh_key_ids       = var.hetzner_ssh_key_ids
  network_id        = hcloud_network.devnet_1.id
  private_ip        = local.archive_private_ip
  firewall_ids      = [hcloud_firewall.archive.id]
  ssh_public_key    = var.ssh_public_key
  default_route_via = local.gateway
  labels            = local.labels

  depends_on = [hcloud_network_subnet.devnet_1]
}

module "monitoring" {
  source = "../../modules/hetzner/monitoring"

  name              = "devnet-1-hetzner-monitoring-1"
  location          = var.hetzner_location
  ssh_key_ids       = var.hetzner_ssh_key_ids
  network_id        = hcloud_network.devnet_1.id
  private_ip        = local.monitoring_ip
  firewall_ids      = [hcloud_firewall.internal.id]
  ssh_public_key    = var.ssh_public_key
  default_route_via = local.gateway
  labels            = local.labels

  depends_on = [hcloud_network_subnet.devnet_1]
}
