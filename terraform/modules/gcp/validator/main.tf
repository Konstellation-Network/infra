# Validator node on GCP. No public IP (no access_config block) — mirrors the
# Hetzner validator module's sentry-architecture requirement (ENGINEERING.md
# §9.2). Local SSD for local-NVMe-equivalent performance — see the extended
# warning on var.local_ssd_count about ephemerality and the double-sign risk
# it creates; this is a testnet-1-only choice, not a mainnet recommendation.
#
# Key material (priv_validator_key.json / horcrux shards) is never
# provisioned by Terraform — see ansible/roles/horcrux.

resource "google_compute_instance" "this" {
  name         = var.name
  zone         = var.zone
  machine_type = var.machine_type
  tags         = var.tags
  labels       = var.labels

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 50
      type  = "pd-balanced"
    }
  }

  dynamic "scratch_disk" {
    for_each = range(var.local_ssd_count)
    content {
      interface = "NVME"
    }
  }

  network_interface {
    network    = var.network
    subnetwork = var.subnetwork
    network_ip = var.private_ip
    # no access_config block => no public IP, matching the Hetzner validator module
  }

  metadata = {
    ssh-keys       = "${var.ssh_user}:${var.ssh_public_key}"
    startup-script = file("${path.module}/../startup-script.sh")
  }

  scheduling {
    # Live migration with Local SSD is supported and preserves the disk
    # (GCP "live migration process" docs, checked 2026-09-21: all series
    # except H4D and >18 TiB Z3) — so MIGRATE, not TERMINATE, which would
    # have thrown the data away on every maintenance event. Host *errors*
    # still restart the VM with empty Local SSDs; roles/cosmovisor's unit
    # refuses to start unless the data volume is mounted, so that path is a
    # NodeDown page, not a node signing from height 0 (§2.7). FLAGGED for a
    # human: confirm MIGRATE against the docs of the day before the first
    # apply — this was TERMINATE in the original scaffold.
    on_host_maintenance = "MIGRATE"
    automatic_restart   = true
  }

  lifecycle {
    prevent_destroy = true
  }
}
