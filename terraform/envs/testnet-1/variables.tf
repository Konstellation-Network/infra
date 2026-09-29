# Shared across both clouds

variable "ssh_user" {
  type    = string
  default = "deploy"
}

variable "ssh_public_key" {
  description = "Public key for the `deploy` user Ansible connects as, on every host in both clouds EXCEPT the Horcrux cosigners (cosigner_ssh_public_key). It carries NOPASSWD sudo everywhere it is installed (cloud-init) — see README 'Cosigner admin domains' and STATUS §5a P21."
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

# D7 re-decided 2026-09-29: 4 foundation-run validators (was 10 = 5 + 5).
# The placement rule is 4 separate failure domains, so that losing one
# provider/region never halts the chain — with 4 equal-power validators one
# down leaves 75 % (> 2/3, live) and two down leaves 50 % (halt). WHICH four
# domains is still OPEN (Contabo / more clouds / more regions; STATUS §5a
# P16), so the per-provider split is a pair of variables. The testnet-1
# default, 2 Hetzner (fsn1 + hel1) + 2 GCP (two zones), puts 2 of 4 — 50 %
# of voting power — behind one provider: losing either provider halts the
# chain. Accepted for testnet-1 only; outputs.tf validator_placement_warning
# says so in every plan. Names run v1..vN on Hetzner then continue on GCP;
# private-IP slots are fixed per cloud (.11-.15 / .16-.20), hence <= 5 each.
variable "hetzner_validator_count" {
  description = "Validators (and 1:1 sentries) on Hetzner, spread over hetzner_locations in order. 0-5."
  type        = number
  default     = 2

  validation {
    condition     = var.hetzner_validator_count >= 0 && var.hetzner_validator_count <= 5 && floor(var.hetzner_validator_count) == var.hetzner_validator_count
    error_message = "hetzner_validator_count must be a whole number from 0 to 5 (the .11-.15 / .21-.25 address slots)."
  }
}

variable "gcp_validator_count" {
  description = "Validators (and 1:1 sentries) on GCP, spread over gcp_zones in order. 0-5. Named after the Hetzner ones (default v3, v4)."
  type        = number
  default     = 2

  validation {
    condition     = var.gcp_validator_count >= 0 && var.gcp_validator_count <= 5 && floor(var.gcp_validator_count) == var.gcp_validator_count
    error_message = "gcp_validator_count must be a whole number from 0 to 5 (the .16-.20 / .26-.30 address slots)."
  }

  validation {
    condition     = var.hetzner_validator_count + var.gcp_validator_count >= 1
    error_message = "The fleet needs at least one validator."
  }
}

variable "cosigner_ssh_public_key" {
  description = <<-EOT
    SSH public key for the Horcrux cosigner hosts (horcrux_mode = dedicated)
    — a DIFFERENT key from ssh_public_key, held by whoever administers the
    signing cluster, so one leaked fleet deploy key is not three shards, i.e.
    the consensus key of every validator in the fleet. Interim for STATUS §5a P21
    (cosigner admin domains: separate keys/operators per cosigner, hardware-
    backed, sudo restricted — not decided). Required in dedicated mode and
    must differ from ssh_public_key; ignored in colocated mode. The
    cosigner hosts still get the same `deploy` user with NOPASSWD sudo
    (cloud-init) — the key is what differs, the sudo policy is P21's.
  EOT
  type        = string
  default     = ""

  validation {
    condition     = var.horcrux_mode != "dedicated" || (length(var.cosigner_ssh_public_key) > 0 && var.cosigner_ssh_public_key != var.ssh_public_key)
    error_message = "horcrux_mode = dedicated requires cosigner_ssh_public_key, and it must not be the fleet's ssh_public_key (P21)."
  }
}

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
  description = <<-EOT
    Cosigner hosts for horcrux_mode = dedicated: 3 (a 2-of-3 threshold,
    ansible/roles/horcrux horcrux_threshold/horcrux_shares). `location` is a
    Hetzner location, `zone` a GCP zone; the other is ignored. Order is the
    shard ID order (c1 = shard 1). HONEST DEFAULT: with only two clouds, the
    default puts TWO shards in one hcloud account (fsn1 + hel1) — one Hetzner
    API token can rescue-boot both servers and reach the threshold. No single
    *location* holds two shards; a single *provider* does. Fixing that needs
    a third provider (STATUS §5a P21, ties to P16) — not decided here. A
    placement with two shards in one cloud is accepted with a warning in
    the plan output (check "cosigner_placement_warning" in outputs.tf).
  EOT
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
    condition     = alltrue([for c in var.explorer_cidrs : can(regex("^[0-9.]+/(2[4-9]|3[0-2])$", c))])
    error_message = "explorer_cidrs entries must be IPv4 prefixes of /24 or narrower — the archive node's debug JSON-RPC is never opened wider than one private subnet (ENGINEERING.md §5.2 / §6.5)."
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
  description = "CIDR for Hetzner's private validator/sentry/archive network. Disjoint from the GCP network below: the two are joined by the bastions' routed WireGuard tunnel (topology.tf, README.md 'Cross-cloud connectivity'), so both must be routable as distinct prefixes."
  type        = string
  default     = "10.0.1.0/24"
}

variable "hetzner_network_zone" {
  description = "Network zone of the private network's subnet. A server can only join the network from a location inside this zone, so hetzner_locations is validated against it (an earlier default listed ash, us-east — the first apply would have failed attaching v3)."
  type        = string
  default     = "eu-central"

  validation {
    condition     = contains(keys(local.hetzner_zone_locations), var.hetzner_network_zone)
    error_message = "hetzner_network_zone must be one of eu-central, us-east, us-west, ap-southeast."
  }
}

variable "hetzner_locations" {
  description = "Hetzner locations to spread this cloud's share of the fleet across, in order (validator i -> element i mod n; default v1 fsn1, v2 hel1) — all inside hetzner_network_zone (eu-central: fsn1, nbg1, hel1). Each validator should get its own location (validator_placement_warning flags a shared one); within Hetzner, three datacentres is what one network zone allows."
  type        = list(string)
  default     = ["fsn1", "hel1", "nbg1"]

  validation {
    condition     = length(var.hetzner_locations) > 0 && alltrue([for l in var.hetzner_locations : contains(local.hetzner_zone_locations[var.hetzner_network_zone], l)])
    error_message = "Every hetzner_locations entry must be a location inside hetzner_network_zone (eu-central: fsn1, nbg1, hel1; us-east: ash; us-west: hil; ap-southeast: sin) — hcloud refuses to attach a server to a network from another zone."
  }
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
  description = "Zones within gcp_region to spread this cloud's share of testnet-1 across, in order (default v3 us-central1-a, v4 us-central1-b). Zones are separate failure domains for a zonal outage only — every GCP validator still shares gcp_region, so a regional outage takes all of them (validator_placement_warning)."
  type        = list(string)
  default     = ["us-central1-a", "us-central1-b", "us-central1-c"]
}

variable "gcp_network_ip_range" {
  description = "CIDR for GCP's private validator/sentry/archive/rpc subnetwork."
  type        = string
  default     = "10.0.2.0/24"
}
