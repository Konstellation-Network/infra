# Public RPC node on GCP. Pruned (not archive) — pruning params come from
# ansible/roles/node group_vars.

resource "google_compute_instance" "this" {
  name         = var.name
  zone         = var.zone
  machine_type = var.machine_type
  tags         = var.tags
  labels       = var.labels

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 100
      type  = "pd-balanced"
    }
  }

  network_interface {
    network    = var.network
    subnetwork = var.subnetwork
    network_ip = var.private_ip

    access_config {}
  }

  metadata = {
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
}
