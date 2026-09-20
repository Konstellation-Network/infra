# Shared across both clouds

variable "ssh_user" {
  type    = string
  default = "deploy"
}

variable "ssh_public_key" {
  description = "Public key for the operator user Ansible connects as, on every host in both clouds."
  type        = string
}

variable "operator_ssh_cidrs" {
  description = "Source CIDRs allowed to SSH to the bastion(s) — operator workstations/VPN egress, one /32 each. Nothing else in either cloud accepts SSH from the internet: every other host takes 22 only from its own cloud's bastion private IP (ProxyJump, see ansible/inventories/testnet-1/ssh_config). No default on purpose: 0.0.0.0/0 here would be the wide-open SSH ENGINEERING.md §9.2's sentry architecture exists to avoid."
  type        = list(string)

  validation {
    condition     = length(var.operator_ssh_cidrs) > 0 && !contains(var.operator_ssh_cidrs, "0.0.0.0/0") && !contains(var.operator_ssh_cidrs, "::/0")
    error_message = "operator_ssh_cidrs must list at least one specific CIDR and must not contain 0.0.0.0/0 or ::/0."
  }
}

# --- Topology choices (see README.md "Decisions parametrised here") ---

variable "bastion_ssh_entry" {
  description = <<-EOT
    Where operators may SSH in from the internet. A gateway host exists in
    EACH cloud regardless (it terminates the WireGuard tunnel and, on
    Hetzner, is the NAT egress), so this only decides which of them runs an
    internet-facing sshd:
      "per-cloud" (default) — both bastions accept operator SSH; each cloud's
                   hosts are reached through their own bastion. No cross-cloud
                   dependency for SSH access: the tunnel being down never locks
                   you out of either side.
      "hetzner" / "gcp" — only that bastion accepts operator SSH; the other
                   cloud's hosts are reached ProxyJump -> that bastion -> across
                   the WireGuard tunnel. One entry point to audit, but a tunnel
                   outage means the far cloud is unreachable for humans too.
    OPEN DECISION for a human (infra/README.md): the default is the safer
    one for an emergency-halt scenario, not necessarily the final answer.
    Bootstrap note: a non-entry bastion is only reachable through the
    tunnel, which ansible/roles/wireguard has not built on a first run —
    so a single-entry topology is applied in two steps: apply + site.yml
    with "per-cloud", then switch and apply + site.yml again.
  EOT
  type        = string
  default     = "per-cloud"

  validation {
    condition     = contains(["per-cloud", "hetzner", "gcp"], var.bastion_ssh_entry)
    error_message = "bastion_ssh_entry must be one of: per-cloud, hetzner, gcp."
  }
}

variable "monitoring_cloud" {
  description = "Which cloud hosts the single Prometheus/Grafana/Alertmanager/tenderduty box (modules/<cloud>/monitoring). It scrapes the other cloud through the bastions' WireGuard tunnel. Default gcp: Cloud NAT keeps the GCP bastion out of the egress path, so the GCP side has fewer moving parts to host the thing that pages you."
  type        = string
  default     = "gcp"

  validation {
    condition     = contains(["hetzner", "gcp"], var.monitoring_cloud)
    error_message = "monitoring_cloud must be hetzner or gcp."
  }
}

variable "horcrux_mode" {
  description = <<-EOT
    "colocated" (default for testnet-1) — no cosigner hosts; ansible/roles/
                horcrux installs horcrux on the validator hosts themselves,
                cosigner list filled by hand. The original scaffold behaviour.
    "dedicated" — provisions the hosts in var.cosigner_placement (3 by
                default, spread across both clouds) and ansible builds one
                horcrux instance per validator on each of them. ENGINEERING.md
                §9.2's requirement and mandatory for mainnet (§18).
    Switching a live validator between modes is a key ceremony
    (runbooks/validator-key-rotation.md), not a `terraform apply`.
  EOT
  type        = string
  default     = "colocated"

  validation {
    condition     = contains(["colocated", "dedicated"], var.horcrux_mode)
    error_message = "horcrux_mode must be colocated or dedicated."
  }
}

variable "cosigner_placement" {
  description = "Cosigner hosts for horcrux_mode = dedicated: 3 (a 2-of-3 threshold, ansible/roles/horcrux horcrux_threshold/horcrux_shares) spread so no single location — or cloud — holds two shards. `location` is a Hetzner location, `zone` a GCP zone; the other is ignored. Order is the shard ID order (c1 = shard 1)."
  type = list(object({
    cloud    = string
    location = optional(string, "")
    zone     = optional(string, "")
  }))
  default = [
    { cloud = "hetzner", location = "fsn1" },
    { cloud = "gcp", zone = "us-central1-b" },
    { cloud = "hetzner", location = "hel1" },
  ]

  validation {
    condition     = alltrue([for p in var.cosigner_placement : contains(["hetzner", "gcp"], p.cloud)])
    error_message = "cosigner_placement[*].cloud must be hetzner or gcp."
  }
}

variable "explorer_cidrs" {
  description = "Address(es) of the explorer's Blockscout backend, allowed to reach the archive nodes' RPC/REST/JSON-RPC (26657, 1317, 8545-8546) in addition to the fleet's private networks. The explorer runs on the app tier outside this fleet (ENGINEERING.md §9.1) and must reach a private address — routed in via one of the bastions — so entries here are private-network or tunnel addresses, never a public 0.0.0.0/0. Empty until the explorer host exists. Mirror any change in ansible group_vars/archive.yml archive_rpc_allowed_cidrs."
  type        = list(string)
  default     = []

  validation {
    condition     = !contains(var.explorer_cidrs, "0.0.0.0/0") && !contains(var.explorer_cidrs, "::/0")
    error_message = "explorer_cidrs must never open the archive node to the internet (ENGINEERING.md §5.2 / §6.5)."
  }
}

variable "wireguard_cidr" {
  description = "Tunnel-interface addresses for the site-to-site WireGuard link between the two bastions (.1 = Hetzner, .2 = GCP). Disjoint from both private networks."
  type        = string
  default     = "10.0.9.0/24"
}

variable "wireguard_port" {
  type    = number
  default = 51820
}

# --- Hetzner ---

variable "hcloud_token" {
  description = "Hetzner Cloud API token. Set via TF_VAR_hcloud_token env var, never in a checked-in .tfvars file."
  type        = string
  sensitive   = true
}

variable "hetzner_ssh_key_ids" {
  description = "hcloud SSH key IDs (project-level keys, uploaded out of band) allowed to provision hosts"
  type        = list(string)
}

variable "hetzner_network_ip_range" {
  description = "CIDR for Hetzner's private validator/sentry/archive network. Independent of the GCP network below — there is no interconnect between the two clouds in this scaffold; sentries from both peer with each other over the public internet like any other node (see README.md)."
  type        = string
  default     = "10.0.1.0/24"
}

variable "hetzner_locations" {
  description = "Hetzner locations to spread this cloud's share of testnet-1 across. ENGINEERING.md §9.2 provider/ASN diversity is a mainnet requirement (D7); running both Hetzner and GCP for testnet-1 goes further than §9.4 ('5, all in-house') strictly requires, but doesn't violate it — all keys are still team-held."
  type        = list(string)
  default     = ["fsn1", "hel1", "ash"]
}

# --- GCP ---

variable "gcp_project" {
  description = "GCP project ID. Must already exist — this scaffold doesn't create it."
  type        = string
}

variable "gcp_region" {
  type    = string
  default = "us-central1"
}

variable "gcp_zones" {
  description = "Zones within gcp_region to spread this cloud's share of testnet-1 across."
  type        = list(string)
  default     = ["us-central1-a", "us-central1-b", "us-central1-c"]
}

variable "gcp_network_ip_range" {
  description = "CIDR for GCP's private validator/sentry/archive/rpc subnetwork."
  type        = string
  default     = "10.0.2.0/24"
}
