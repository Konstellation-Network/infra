variable "name" {
  description = "Server name, e.g. testnet-1-hetzner-bastion"
  type        = string
}

variable "location" {
  type = string
}


variable "server_type" {
  description = "Small shared-vCPU type is plenty: sshd, NAT forwarding and one WireGuard tunnel. Not a node."
  type        = string
  default     = "cpx11"
}

variable "ssh_key_ids" {
  type = list(string)
}

variable "network_id" {
  description = "hcloud_network ID for this cloud's private network"
  type        = string
}

variable "private_ip" {
  description = "Static private IP. Also the gateway address for the NAT / remote-cloud routes below, so it must never change once hosts route through it."
  type        = string
}

variable "firewall_ids" {
  description = "Public firewall: 22 from operator CIDRs, 51820/udp from the peer bastion. Nothing else."
  type        = list(string)
}

variable "ssh_public_key" {
  type = string
}

variable "nat_gateway" {
  description = "Install a 0.0.0.0/0 route on the private network through this host so private-only servers (validators, archive, monitoring, cosigners) have internet egress. Required on Hetzner — there is no managed NAT — unless another host provides it."
  type        = bool
  default     = true
}

variable "remote_cidrs" {
  description = "Private CIDRs of the other cloud(s), keyed by a short name, routed through this host's WireGuard tunnel. Empty set = no cross-cloud routing from this side."
  type        = map(string)
  default     = {}
}

variable "labels" {
  type    = map(string)
  default = {}
}
