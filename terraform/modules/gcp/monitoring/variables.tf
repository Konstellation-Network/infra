variable "name" {
  type = string
}

variable "zone" {
  type = string
}

variable "machine_type" {
  type    = string
  default = "e2-medium"
}

variable "data_disk_size_gb" {
  description = "Prometheus TSDB + Grafana state."
  type        = number
  default     = 100
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
  description = "`konstellation` gets it the bastion-only SSH rule and internal node_exporter scrape rule; `monitoring` is what the fleet's scrape-source rules key on."
  type        = list(string)
  default     = ["konstellation", "monitoring"]
}

variable "labels" {
  type    = map(string)
  default = {}
}

variable "service_account_email" {
  description = "Dedicated, scope-less service account the instance runs as (envs/<net>/gcp.tf google_service_account.nodes). Never the default Compute SA."
  type        = string
}
