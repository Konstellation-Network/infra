variable "name" {
  type = string
}

variable "location" {
  type = string
}

variable "server_type" {
  type    = string
  default = "cpx41"
}

variable "data_volume_size_gb" {
  description = "Attached volume for chain data. Archive nodes prune=nothing so this grows unbounded; unlike validators, IAVL commit latency here doesn't gate consensus, so network-attached storage is acceptable."
  type        = number
  default     = 500
}

variable "ssh_key_ids" {
  type = list(string)
}

variable "network_id" {
  type = string
}

variable "private_ip" {
  type = string
}

variable "firewall_ids" {
  description = "Internal-only firewall: no public inbound. ENGINEERING.md §5.2/§6.5 — the archive node backing the explorer is not public."
  type        = list(string)
}

variable "ssh_public_key" {
  type = string
}

variable "labels" {
  type    = map(string)
  default = {}
}

variable "default_route_via" {
  description = "Private-network gateway (first address of the hcloud_network range) to install as the default route on this public-IP-less host, so it egresses through the bastion's NAT (modules/hetzner/bastion). Empty = leave routing alone (host has no internet access)."
  type        = string
  default     = ""
}
