# Shared across both clouds

variable "ssh_user" {
  type    = string
  default = "deploy"
}

variable "ssh_public_key" {
  description = "Public key for the operator user Ansible connects as, on every host in both clouds."
  type        = string
}

variable "bastion_ipv4" {
  description = "Source IP (or CIDR) allowed SSH to any host. No wide-open 0.0.0.0/0 SSH per ENGINEERING.md §9.2 sentry-architecture intent."
  type        = string
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
