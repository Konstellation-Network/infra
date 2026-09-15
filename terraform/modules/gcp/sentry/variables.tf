variable "name" {
  type = string
}

variable "zone" {
  type = string
}

variable "machine_type" {
  type    = string
  default = "n2-standard-4"
}

variable "network" {
  type = string
}

variable "subnetwork" {
  type = string
}

variable "private_ip" {
  type = string
}

variable "ssh_user" {
  type    = string
  default = "deploy"
}

variable "ssh_public_key" {
  type = string
}

variable "tags" {
  type    = list(string)
  default = ["konstellation", "sentry"]
}

variable "validator_node_id" {
  description = "Node ID of the validator this sentry shields, so ansible/roles/node can set private_peer_ids and never gossip it"
  type        = string
  default     = ""
}

variable "labels" {
  type    = map(string)
  default = {}
}
