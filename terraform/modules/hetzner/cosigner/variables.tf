variable "name" {
  description = "Server name, e.g. testnet-1-hetzner-cosigner-c1"
  type        = string
}

variable "location" {
  description = "Spread cosigners across locations (and clouds) — a 2-of-3 cluster with two shards in one datacentre loses liveness with that datacentre."
  type        = string
}

variable "server_type" {
  type    = string
  default = "cpx11"
}

variable "ssh_key_ids" {
  type = list(string)
}

variable "network_id" {
  type = string
}

variable "private_ip" {
  description = "Static private IP; horcrux's cosigner list (ansible/roles/horcrux) is built from it, so it must never change while a shard lives here."
  type        = string
}

variable "firewall_ids" {
  description = "See modules/hetzner/monitoring: no public interface, so ufw (node_role=cosigner) is the real control."
  type        = list(string)
}

variable "ssh_public_key" {
  type = string
}

variable "default_route_via" {
  description = "See modules/hetzner/monitoring."
  type        = string
  default     = ""
}

variable "labels" {
  type    = map(string)
  default = {}
}
