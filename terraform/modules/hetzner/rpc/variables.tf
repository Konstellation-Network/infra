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
  description = "Public RPC firewall: 26657 (RPC), 1317 (REST), 9090 (gRPC), 8545/8546 (JSON-RPC/WS) — rate-limited at the reverse proxy, not here"
  type        = list(string)
}

variable "ssh_public_key" {
  type = string
}

variable "labels" {
  type    = map(string)
  default = {}
}
