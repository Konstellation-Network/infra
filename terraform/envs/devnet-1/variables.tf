# devnet-1: the dapp-developer network (D18, decided 2026-09-29). One
# foundation-run validator, one provider (Hetzner). See README.md "devnet-1".

variable "ssh_user" {
  type    = string
  default = "deploy"
}

variable "ssh_public_key" {
  description = "Public key for the `deploy` user Ansible connects as, on every devnet-1 host. It carries NOPASSWD sudo (cloud-init). Use a different key from testnet-1's: one leaked key should not reach two networks."
  type        = string
}

variable "operator_ssh_cidrs" {
  description = "Source CIDRs allowed to SSH to the bastion — operator workstations/VPN egress, one /32 each. Nothing else accepts SSH from the internet: every other host takes 22 only from the bastion's private IP (ProxyJump, see ansible/inventories/devnet-1/ssh_config)."
  type        = list(string)

  validation {
    condition     = length(var.operator_ssh_cidrs) > 0 && !contains(var.operator_ssh_cidrs, "0.0.0.0/0") && !contains(var.operator_ssh_cidrs, "::/0")
    error_message = "operator_ssh_cidrs must list at least one specific CIDR and must not contain 0.0.0.0/0 or ::/0."
  }
}

variable "sentry_count" {
  description = <<-EOT
    Sentries in front of the one validator (ENGINEERING.md §9.2: the sentry
    architecture is mandatory on every network). Default 1: on a
    single-validator network a sentry outage does not stop block production
    (the validator holds 100 % of voting power and needs no peers to
    commit); it only cuts the RPC and archive nodes off from new blocks
    until the sentry is back. 2 removes that (and is P23's target shape);
    the validator peers with every sentry and they cross-peer.
  EOT
  type        = number
  default     = 1

  validation {
    condition     = var.sentry_count >= 1 && var.sentry_count <= 5 && floor(var.sentry_count) == var.sentry_count
    error_message = "sentry_count must be a whole number from 1 to 5 (the .21-.25 address slots)."
  }
}

variable "explorer_cidrs" {
  description = "Address(es) of the devnet explorer's Blockscout backend, allowed to reach the archive node's RPC/REST/JSON-RPC (26657, 1317, 8545-8546). Same rule as testnet-1: private-network or tunnel addresses, never 0.0.0.0/0; empty until the explorer host exists. Mirror any change in ansible group_vars/archive.yml archive_explorer_cidrs."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.explorer_cidrs : can(regex("^[0-9.]+/(2[4-9]|3[0-2])$", c))])
    error_message = "explorer_cidrs entries must be IPv4 prefixes of /24 or narrower — the archive node's debug JSON-RPC is never opened wider than one private subnet (ENGINEERING.md §5.2 / §6.5)."
  }
}

# --- Hetzner ---

variable "hcloud_token" {
  description = "Hetzner Cloud API token. Set via TF_VAR_hcloud_token env var, never in a checked-in .tfvars file. A separate hcloud project from testnet-1 is recommended, so a devnet token cannot touch testnet hosts."
  type        = string
  sensitive   = true
}

variable "hetzner_ssh_key_ids" {
  description = "hcloud SSH key IDs (project-level keys, uploaded out of band) allowed to provision hosts"
  type        = list(string)
}

variable "hetzner_network_ip_range" {
  description = "CIDR for devnet-1's private network. Disjoint from testnet-1's 10.0.1.0/24 and 10.0.2.0/24 so the two can never be confused in a firewall rule or routed together by accident."
  type        = string
  default     = "10.0.3.0/24"
}

variable "hetzner_network_zone" {
  type    = string
  default = "eu-central"

  validation {
    condition     = contains(keys(local.hetzner_zone_locations), var.hetzner_network_zone)
    error_message = "hetzner_network_zone must be one of eu-central, us-east, us-west, ap-southeast."
  }
}

variable "hetzner_location" {
  description = "The one Hetzner location every devnet-1 host lives in. With one validator there is no failure domain to spread across — any location outage stops the chain regardless — so one location keeps the private network simple."
  type        = string
  default     = "fsn1"

  validation {
    condition     = contains(local.hetzner_zone_locations[var.hetzner_network_zone], var.hetzner_location)
    error_message = "hetzner_location must be inside hetzner_network_zone (eu-central: fsn1, nbg1, hel1; us-east: ash; us-west: hil; ap-southeast: sin)."
  }
}

# Server types default to each module's own default (validator ccx33:
# dedicated vCPU, local NVMe — ENGINEERING.md §9.2's disk rule applies to a
# block-producing node on any network). Override here to trade headroom for
# cost; never move the validator onto a shared-vCPU or volume-backed type.
variable "validator_server_type" {
  type    = string
  default = "ccx33"
}

variable "rpc_server_type" {
  type    = string
  default = "cpx41"
}
