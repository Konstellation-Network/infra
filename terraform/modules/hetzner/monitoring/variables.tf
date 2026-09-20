variable "name" {
  type = string
}

variable "location" {
  type = string
}

variable "server_type" {
  description = "Prometheus for ~15 targets at 15s plus Grafana and tenderduty is light; grow the TSDB volume, not the box."
  type        = string
  default     = "cpx21"
}

variable "data_volume_size_gb" {
  type    = number
  default = 100
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
  description = "Irrelevant to private traffic on Hetzner (hcloud firewalls filter the public interface only, and this host has none) — attached for consistency; ufw (ansible/roles/firewall, node_role=monitoring) is the real control."
  type        = list(string)
}

variable "ssh_public_key" {
  type = string
}

variable "default_route_via" {
  description = "Private-network gateway (first address of the hcloud_network range) to install as the default route, so this public-IP-less host egresses through the bastion's NAT. Empty = leave routing alone."
  type        = string
  default     = ""
}

variable "labels" {
  type    = map(string)
  default = {}
}
