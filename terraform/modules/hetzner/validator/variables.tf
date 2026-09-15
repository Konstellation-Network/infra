variable "name" {
  description = "Server name, e.g. testnet-1-validator-3"
  type        = string
}

variable "location" {
  description = "Hetzner location (e.g. fsn1, hel1, ash). Spread validators across locations."
  type        = string
}

variable "server_type" {
  description = "Hetzner server type. Must be a type with local NVMe, not a shared-volume type (ENGINEERING.md §9.2: network block storage costs block time)."
  type        = string
  default     = "ccx33" # dedicated vCPU, local NVMe
}

variable "ssh_key_ids" {
  description = "hcloud SSH key IDs allowed to provision this host"
  type        = list(string)
}

variable "network_id" {
  description = "hcloud_network ID for the private validator<->sentry network"
  type        = string
}

variable "private_ip" {
  description = "Static private IP to assign on the private network"
  type        = string
}

variable "firewall_ids" {
  description = "hcloud_firewall IDs to attach (see envs/testnet-1 for the validator firewall: no public inbound except from own sentries)"
  type        = list(string)
}

variable "ssh_public_key" {
  description = "Public key injected via cloud-init for the initial provisioning user. Ansible takes over configuration after this."
  type        = string
}

variable "labels" {
  description = "hcloud labels, e.g. { role = \"validator\", network = \"testnet-1\" }"
  type        = map(string)
  default     = {}
}
