# Dedicated Horcrux cosigner host on GCP — see modules/hetzner/cosigner for
# the role description and the key-material rules. No public IP; egress via
# Cloud NAT. pd-balanced, not Local SSD: the shard and signing state are
# tiny, and a cosigner that loses its last-signed-state file on a host
# maintenance event is exactly the failure mode to avoid (§2.7) — horcrux
# refuses to regress, but only if the file survives.

resource "google_compute_instance" "this" {
  name         = var.name
  zone         = var.zone
  machine_type = var.machine_type
  tags         = var.tags
  labels       = var.labels

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 20
      type  = "pd-balanced"
    }
  }

  network_interface {
    network    = var.network
    subnetwork = var.subnetwork
    network_ip = var.private_ip
    # no access_config block => no public IP
  }

  metadata = {
    ssh-keys       = "${var.ssh_user}:${var.ssh_public_key}"
    startup-script = file("${path.module}/../startup-script.sh")
  }

  scheduling {
    on_host_maintenance = "MIGRATE"
    automatic_restart   = true
  }

  lifecycle {
    prevent_destroy = true
  }
}
