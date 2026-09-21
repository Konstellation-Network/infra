variable "name" {
  type = string
}

variable "zone" {
  type = string
}

variable "machine_type" {
  type    = string
  default = "n2-standard-8"
}

variable "data_disk_size_gb" {
  description = "Persistent disk for chain data. Archive nodes prune=nothing so this grows unbounded; unlike validators, IAVL commit latency here doesn't gate consensus, so persistent (network) disk is acceptable — same rationale as the Hetzner archive module."
  type        = number
  default     = 500
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
  description = "No public-facing tag — this instance gets no access_config block regardless (ENGINEERING.md §5.2/§6.5: the archive node backing the explorer is not public)."
  type        = list(string)
  default     = ["konstellation", "archive"]
}

variable "labels" {
  type    = map(string)
  default = {}
}

variable "service_account_email" {
  description = "Dedicated, scope-less service account the instance runs as (envs/<net>/gcp.tf google_service_account.nodes). Never the default Compute SA."
  type        = string
}
