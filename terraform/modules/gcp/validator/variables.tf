variable "name" {
  description = "Instance name, e.g. testnet-1-gcp-validator-1"
  type        = string
}

variable "zone" {
  description = "GCP zone (e.g. us-central1-a). Spread validators across zones."
  type        = string
}

variable "machine_type" {
  description = "n2-standard-8 (8 vCPU / 32 GB) is the low end of ENGINEERING.md §9.2's 8-16 vCPU / 32-64 GB spec. Must be a family that supports Local SSD (n1, n2, n2d, c2, c2d, c3...)."
  type        = string
  default     = "n2-standard-8"
}

variable "local_ssd_count" {
  description = <<-EOT
    Number of 375 GiB Local SSD volumes to attach (striped in ansible into one
    volume — see roles/node). 8 = 3 TB, matching the low end of ENGINEERING.md
    §9.2's "2-4 TB local NVMe".

    READ THIS: GCP Local SSD is ephemeral across a stop or most host
    maintenance events (it survives a plain reboot, not a stop/terminate or a
    host error; scheduled maintenance live-migrates the VM *with* the disk,
    per current GCP docs, so main.tf sets MIGRATE — re-check that on every
    provider bump). Losing this disk loses priv_validator_state.json,
    and restarting a validator without that file's last-signed-height is
    exactly the double-sign scenario ENGINEERING.md §2.7 calls unrecoverable
    (5% slash). This choice was made explicitly for testnet-1 to match
    Hetzner's local-NVMe performance profile on the other half of the fleet —
    see infra/README.md "Known gaps" — and MUST be re-decided before any
    mainnet validator runs on GCP. Do not copy this default forward without
    re-reading this comment.
  EOT
  type        = number
  default     = 8
}

variable "network" {
  type = string
}

variable "subnetwork" {
  type = string
}

variable "private_ip" {
  description = "Static internal IP on the subnetwork"
  type        = string
}

variable "ssh_user" {
  type    = string
  default = "deploy"
}

variable "ssh_public_key" {
  description = "Public key added via instance metadata (GCP's guest agent creates the user automatically); ansible connects as this user."
  type        = string
}

variable "tags" {
  description = "Network tags matched by google_compute_firewall target_tags"
  type        = list(string)
  default     = ["konstellation", "validator"]
}

variable "labels" {
  type    = map(string)
  default = {}
}

variable "service_account_email" {
  description = "Dedicated, scope-less service account the instance runs as (envs/<net>/gcp.tf google_service_account.nodes). Never the default Compute SA."
  type        = string
}
