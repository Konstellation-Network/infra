variable "name" {
  type = string
}

variable "zone" {
  description = "Spread cosigners across zones/regions/clouds — see modules/hetzner/cosigner."
  type        = string
}

variable "machine_type" {
  type    = string
  default = "e2-small"
}

variable "network" {
  type = string
}

variable "subnetwork" {
  type = string
}

variable "private_ip" {
  description = "Static internal IP; horcrux's cosigner list is built from it — never change while a shard lives here."
  type        = string
}

variable "ssh_user" {
  type    = string
  default = "deploy"
}

variable "ssh_public_key" {
  description = "The cosigner admin key — a different key from the fleet's deploy key (STATUS §5a P21: one leaked deploy key must not be three shards)."
  type        = string
}

variable "tags" {
  type    = list(string)
  default = ["konstellation", "cosigner"]
}

variable "labels" {
  type    = map(string)
  default = {}
}

variable "service_account_email" {
  description = "Dedicated, scope-less service account the instance runs as (envs/<net>/gcp.tf google_service_account.nodes). Never the default Compute SA."
  type        = string
}
