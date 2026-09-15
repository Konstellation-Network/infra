# Sentry node on GCP: public-facing, shields one validator (ENGINEERING.md
# §9.2). private_peer_ids on this node must be the validator's node ID so its
# address is never gossiped over pex — enforced in ansible/roles/node.

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

  network_interface {
    network    = var.network
    subnetwork = var.subnetwork
    network_ip = var.private_ip

    access_config {} # ephemeral public IP
  }

  metadata = {
    ssh-keys       = "${var.ssh_user}:${var.ssh_public_key}"
    startup-script = file("${path.module}/../startup-script.sh")
  }
}
