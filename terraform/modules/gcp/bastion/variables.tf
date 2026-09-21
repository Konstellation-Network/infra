variable "name" {
  type = string
}

variable "zone" {
  type = string
}

variable "region" {
  description = "Region of the static external address (the zone's region)."
  type        = string
}

variable "machine_type" {
  description = "sshd + one WireGuard tunnel + routing; the smallest shared-core type is enough."
  type        = string
  default     = "e2-small"
}

variable "network" {
  type = string
}

variable "subnetwork" {
  type = string
}

variable "private_ip" {
  description = "Static internal IP. Peer bastions and the routes below depend on it — never change once applied."
  type        = string
}

variable "ssh_user" {
  type    = string
  default = "deploy"
}

variable "ssh_public_key" {
  type = string
}

variable "tags" {
  description = "Deliberately NOT tagged `konstellation`: that tag's SSH rule admits the bastion's own private IP, which must not apply to the bastion itself. See envs/<net>/gcp.tf bastion_* firewall rules."
  type        = list(string)
  default     = ["bastion"]
}

variable "remote_cidrs" {
  description = "Private CIDRs of the other cloud(s), keyed by a short name, routed to this VM (and on through its WireGuard tunnel)."
  type        = map(string)
  default     = {}
}

variable "labels" {
  type    = map(string)
  default = {}
}

variable "service_account_email" {
  description = "Dedicated, scope-less service account the instance runs as (envs/<net>/gcp.tf google_service_account.nodes). Never the default Compute SA."
  type        = string
}
