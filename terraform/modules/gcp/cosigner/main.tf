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
    # var.ssh_public_key here is the COSIGNER admin key (envs/<net>
    # cosigner_ssh_public_key), never the fleet's deploy key — P21.
    ssh-keys       = "${var.ssh_user}:${var.ssh_public_key}"
    startup-script = file("${path.module}/../startup-script.sh")
    # Only the key above may log in — project-wide keys (anyone with
    # compute.projects.setCommonInstanceMetadata) are ignored. OS Login is
    # deliberately OFF: it would bind SSH to Google IAM identities, a
    # decision (P21, cosigner admin domains) not taken here.
    block-project-ssh-keys = "TRUE"
    enable-oslogin         = "FALSE"
  }

  # A dedicated, scope-less service account: the VM can prove its identity
  # but call no Google API. The default Compute SA with default scopes
  # (read access to storage, logging writes) is not what a validator needs.
  service_account {
    email  = var.service_account_email
    scopes = []
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  scheduling {
    on_host_maintenance = "MIGRATE"
    automatic_restart   = true
  }

  lifecycle {
    prevent_destroy = true
  }
}
