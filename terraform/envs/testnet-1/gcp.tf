# GCP's share of testnet-1: var.gcp_validator_count validators (2 by default,
# in two different zones), as many sentries (1:1), 1 archive, 1 RPC,
# the GCP bastion/gateway, Cloud NAT for the public-IP-less VMs, and —
# depending on var.monitoring_cloud / var.horcrux_mode — the monitoring host
# and/or some cosigners. See hetzner.tf for the other half.
#
# Validators here use Local SSD (see terraform/modules/gcp/validator's
# local_ssd_count variable) — read the warning there before treating this as
# a mainnet pattern; it's a testnet-1-only choice.
#
# A custom-mode VPC with no rules denies all ingress by default, same as the
# Hetzner firewalls' implicit deny — no separate "default deny" rule needed.
# Unlike Hetzner, GCP firewall rules DO apply to private-network traffic, so
# everything below is effective. IPv4 only on this side (Hetzner's sentry
# firewall also opens ::/0; adding that here means a dual-stack VPC, not
# done in this pass).

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

# Every instance runs as this scope-less service account (modules/gcp/*
# service_account block): identity without API access. Creating it needs
# roles/iam.serviceAccountAdmin on the project for whoever applies.
resource "google_service_account" "nodes" {
  account_id   = "testnet-1-nodes"
  display_name = "testnet-1 node instances (no API scopes)"
}

# Egress for VMs with no public IP (validators, archive, monitoring,
# cosigners): apt, the checksummed binary download, GitHub. Managed, so
# the bastion is not in the egress path (contrast modules/hetzner/bastion).
resource "google_compute_router" "testnet_1" {
  name    = "testnet-1-gcp"
  network = google_compute_network.testnet_1.id
  region  = var.gcp_region
}

resource "google_compute_router_nat" "testnet_1" {
  name                               = "testnet-1-gcp-nat"
  router                             = google_compute_router.testnet_1.name
  region                             = var.gcp_region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

# --- SSH ---

# Every non-bastion host: 22 only from the bastion private IP(s). The
# bastion's own tag is `bastion`, not `konstellation`, so this never
# applies to it.
resource "google_compute_firewall" "ssh" {
  name          = "testnet-1-gcp-ssh"
  network       = google_compute_network.testnet_1.id
  direction     = "INGRESS"
  source_ranges = [for ip in local.gcp_ssh_sources : "${ip}/32"]
  target_tags   = ["konstellation"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

# Operator SSH to the bastion from the internet — only if this bastion is an
# entry point (var.bastion_ssh_entry).
resource "google_compute_firewall" "bastion_ssh" {
  count = length(local.gcp_bastion_ssh_cidrs) > 0 ? 1 : 0

  name          = "testnet-1-gcp-bastion-ssh"
  network       = google_compute_network.testnet_1.id
  direction     = "INGRESS"
  source_ranges = local.gcp_bastion_ssh_cidrs
  target_tags   = ["bastion"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

# --- Cross-cloud tunnel ---

resource "google_compute_firewall" "bastion_wireguard" {
  name          = "testnet-1-gcp-bastion-wireguard"
  network       = google_compute_network.testnet_1.id
  direction     = "INGRESS"
  source_ranges = ["${module.hetzner_bastion.public_ipv4}/32"]
  target_tags   = ["bastion"]

  allow {
    protocol = "udp"
    ports    = [tostring(var.wireguard_port)]
  }
}

# Packets the bastion forwards between the tunnel and this VPC arrive at
# its NIC from the local subnet (return traffic) and from the tunnel
# (Hetzner sources, already inside the VM). GCP evaluates ingress rules per
# NIC, so the local side must be admitted explicitly. Port-level policy for
# that traffic is enforced at the destination VM, not here.
resource "google_compute_firewall" "bastion_forward" {
  name          = "testnet-1-gcp-bastion-forward"
  network       = google_compute_network.testnet_1.id
  direction     = "INGRESS"
  source_ranges = [var.gcp_network_ip_range]
  target_tags   = ["bastion"]

  allow {
    protocol = "all"
  }
}

# --- Chain traffic ---

# Validators take p2p from this cloud's sentries only — not the /24, which
# includes the internet-facing RPC node (P23 interim, 2026-09-21).
resource "google_compute_firewall" "p2p_validator" {
  name          = "testnet-1-gcp-p2p-validator"
  network       = google_compute_network.testnet_1.id
  direction     = "INGRESS"
  source_ranges = [for s in local.gcp_sentries : "${s.private_ip}/32"]
  target_tags   = ["validator"]

  allow {
    protocol = "tcp"
    ports    = ["26656"]
  }
}

# Public rules: the provider requires an explicit source; 0.0.0.0/0 here is
# the intent (the original scaffold omitted it, which fails at plan).
# CometBFT RPC on sentries for tenderduty: the monitoring host only.
resource "google_compute_firewall" "sentry_rpc_monitoring" {
  name          = "testnet-1-gcp-sentry-rpc-monitoring"
  network       = google_compute_network.testnet_1.id
  direction     = "INGRESS"
  source_ranges = ["${local.monitoring_host_private_ip}/32"]
  target_tags   = ["sentry"]

  allow {
    protocol = "tcp"
    ports    = ["26657"]
  }
}

resource "google_compute_firewall" "p2p_sentry" {
  name          = "testnet-1-gcp-p2p-sentry"
  network       = google_compute_network.testnet_1.id
  direction     = "INGRESS"
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["sentry"]

  allow {
    protocol = "tcp"
    ports    = ["26656"]
  }
}

# Metrics scrape: the monitoring host may be in either cloud, so both
# private CIDRs are admitted (the tunnel is routed, source IP preserved).
resource "google_compute_firewall" "monitoring_internal" {
  name          = "testnet-1-gcp-monitoring-internal"
  network       = google_compute_network.testnet_1.id
  direction     = "INGRESS"
  source_ranges = local.fleet_cidrs
  target_tags   = ["konstellation"]

  allow {
    protocol = "tcp"
    ports    = ["26660", "9100"]
  }
}

resource "google_compute_firewall" "rpc_public" {
  name          = "testnet-1-gcp-rpc-public"
  network       = google_compute_network.testnet_1.id
  direction     = "INGRESS"
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["rpc"]

  allow {
    protocol = "tcp"
    ports    = ["26656", "26657", "1317", "8545-8546"]
  }
}

# The monitoring host plus the explorer backend (var.explorer_cidrs) — not
# the fleet, which includes hosts with public interfaces; the JSON-RPC bind
# itself is the node's private address (ansible group_vars/archive.yml).
resource "google_compute_firewall" "archive_rpc" {
  name          = "testnet-1-gcp-archive-rpc"
  network       = google_compute_network.testnet_1.id
  direction     = "INGRESS"
  source_ranges = local.archive_rpc_cidrs
  target_tags   = ["archive"]

  allow {
    protocol = "tcp"
    ports    = ["26657"]
  }
}

# REST and the debug-enabled JSON-RPC: the explorer only (never the
# monitoring host). No rule at all until var.explorer_cidrs is set.
resource "google_compute_firewall" "archive_explorer" {
  count = length(var.explorer_cidrs) > 0 ? 1 : 0

  name          = "testnet-1-gcp-archive-explorer"
  network       = google_compute_network.testnet_1.id
  direction     = "INGRESS"
  source_ranges = var.explorer_cidrs
  target_tags   = ["archive"]

  allow {
    protocol = "tcp"
    ports    = ["1317", "8545-8546"]
  }
}

# --- Horcrux (dedicated mode only) ---

# Cosigners dial the validators' priv_validator_laddr.
resource "google_compute_firewall" "privval" {
  count = var.horcrux_mode == "dedicated" ? 1 : 0

  name          = "testnet-1-gcp-privval"
  network       = google_compute_network.testnet_1.id
  direction     = "INGRESS"
  source_ranges = [for ip in values(local.cosigner_private_ips) : "${ip}/32"]
  target_tags   = ["validator"]

  allow {
    protocol = "tcp"
    ports    = ["1234"]
  }
}

# Cosigner <-> cosigner raft/grpc. One horcrux instance per validator per
# host, ports 2222+ (ansible/roles/horcrux horcrux_p2p_base_port).
resource "google_compute_firewall" "cosigner_p2p" {
  count = var.horcrux_mode == "dedicated" ? 1 : 0

  name          = "testnet-1-gcp-cosigner-p2p"
  network       = google_compute_network.testnet_1.id
  direction     = "INGRESS"
  source_ranges = [for ip in values(local.cosigner_private_ips) : "${ip}/32"]
  target_tags   = ["cosigner"]

  allow {
    protocol = "tcp"
    ports    = ["2222-2299"]
  }
}

# --- Hosts ---

locals {
  # Continues the Hetzner numbering (default: v3, v4). D7 re-decided
  # 2026-09-29: 4 validators fleet-wide, see hetzner.tf.
  gcp_validator_names = [for i in range(var.gcp_validator_count) : "v${var.hetzner_validator_count + i + 1}"]

  gcp_validators = {
    for i, n in local.gcp_validator_names : n => {
      zone       = element(var.gcp_zones, i % length(var.gcp_zones))
      private_ip = cidrhost(var.gcp_network_ip_range, 15 + i + 1) # .16-.20 slots (count <= 5; hetzner has .11-.15)
    }
  }

  gcp_sentries = {
    for i, n in local.gcp_validator_names : n => {
      zone       = element(var.gcp_zones, i % length(var.gcp_zones))
      private_ip = cidrhost(var.gcp_network_ip_range, 25 + i + 1) # .26-.30 slots
    }
  }

  gcp_archive_private_ip = cidrhost(var.gcp_network_ip_range, 42)
  gcp_rpc_private_ip     = cidrhost(var.gcp_network_ip_range, 31)

  # Kept as a root local (not just the module default) so outputs.tf can put
  # it in the ansible inventory without a module needing to echo its own input
  # back out as an output.
  gcp_validator_local_ssd_count = 8
}

module "gcp_bastion" {
  source = "../../modules/gcp/bastion"

  name                  = "testnet-1-gcp-bastion"
  zone                  = var.gcp_zones[0]
  region                = var.gcp_region
  network               = google_compute_network.testnet_1.id
  subnetwork            = google_compute_subnetwork.testnet_1.id
  private_ip            = local.gcp_bastion_private_ip
  service_account_email = google_service_account.nodes.email
  ssh_user              = var.ssh_user
  ssh_public_key        = var.ssh_public_key
  remote_cidrs          = { hetzner = var.hetzner_network_ip_range }
  labels                = { network = "testnet-1" }
}

module "gcp_validator" {
  source = "../../modules/gcp/validator"

  for_each = local.gcp_validators

  name                  = "testnet-1-gcp-validator-${each.key}"
  zone                  = each.value.zone
  network               = google_compute_network.testnet_1.id
  subnetwork            = google_compute_subnetwork.testnet_1.id
  private_ip            = each.value.private_ip
  local_ssd_count       = local.gcp_validator_local_ssd_count
  service_account_email = google_service_account.nodes.email
  ssh_user              = var.ssh_user
  ssh_public_key        = var.ssh_public_key
  labels                = { network = "testnet-1" }
}

module "gcp_sentry" {
  source = "../../modules/gcp/sentry"

  for_each = local.gcp_sentries

  name                  = "testnet-1-gcp-sentry-${each.key}"
  zone                  = each.value.zone
  network               = google_compute_network.testnet_1.id
  subnetwork            = google_compute_subnetwork.testnet_1.id
  private_ip            = each.value.private_ip
  service_account_email = google_service_account.nodes.email
  ssh_user              = var.ssh_user
  ssh_public_key        = var.ssh_public_key
  validator_node_id     = "" # filled in after first boot, once validator node IDs are known — see README.md
  labels                = { network = "testnet-1" }
}

module "gcp_archive" {
  source = "../../modules/gcp/archive"

  name                  = "testnet-1-gcp-archive-1"
  zone                  = var.gcp_zones[0]
  network               = google_compute_network.testnet_1.id
  subnetwork            = google_compute_subnetwork.testnet_1.id
  private_ip            = local.gcp_archive_private_ip
  service_account_email = google_service_account.nodes.email
  ssh_user              = var.ssh_user
  ssh_public_key        = var.ssh_public_key
  labels                = { network = "testnet-1" }
}

module "gcp_rpc" {
  source = "../../modules/gcp/rpc"

  name                  = "testnet-1-gcp-rpc-1"
  zone                  = var.gcp_zones[0]
  network               = google_compute_network.testnet_1.id
  subnetwork            = google_compute_subnetwork.testnet_1.id
  private_ip            = local.gcp_rpc_private_ip
  service_account_email = google_service_account.nodes.email
  ssh_user              = var.ssh_user
  ssh_public_key        = var.ssh_public_key
  labels                = { network = "testnet-1" }
}

module "gcp_monitoring" {
  source = "../../modules/gcp/monitoring"

  count = var.monitoring_cloud == "gcp" ? 1 : 0

  name                  = "testnet-1-gcp-monitoring-1"
  zone                  = var.gcp_zones[0]
  network               = google_compute_network.testnet_1.id
  subnetwork            = google_compute_subnetwork.testnet_1.id
  private_ip            = local.gcp_monitoring_private_ip
  service_account_email = google_service_account.nodes.email
  ssh_user              = var.ssh_user
  ssh_public_key        = var.ssh_public_key
  labels                = { network = "testnet-1" }
}

module "gcp_cosigner" {
  source = "../../modules/gcp/cosigner"

  for_each = local.gcp_cosigners

  name                  = "testnet-1-gcp-cosigner-${each.key}"
  zone                  = each.value.zone
  network               = google_compute_network.testnet_1.id
  subnetwork            = google_compute_subnetwork.testnet_1.id
  private_ip            = local.cosigner_private_ips[each.key]
  service_account_email = google_service_account.nodes.email
  ssh_user              = var.ssh_user
  ssh_public_key        = var.cosigner_ssh_public_key # NOT the deploy key — P21
  labels                = { network = "testnet-1" }
}
