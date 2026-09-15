variable "name" {
  description = "Server name, e.g. testnet-1-sentry-3"
  type        = string
}

variable "location" {
  type = string
}

variable "server_type" {
  type    = string
  default = "cpx31"
}

variable "ssh_key_ids" {
  type = list(string)
}

variable "network_id" {
  description = "hcloud_network ID for the private validator<->sentry network"
  type        = string
}

variable "private_ip" {
  type = string
}

variable "firewall_ids" {
  description = "Public firewall: allow 26656 (p2p) from anywhere, SSH from bastion only"
  type        = list(string)
}

variable "ssh_public_key" {
  type = string
}

variable "validator_node_id" {
  description = "Node ID of the validator this sentry shields, so ansible/roles/node can set private_peer_ids and never gossip it"
  type        = string
}

variable "labels" {
  type    = map(string)
  default = {}
}
