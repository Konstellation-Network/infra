# Central monitoring host on GCP — see modules/hetzner/monitoring for the
# role description; only one of the two is instantiated per environment
# (envs/<net> var.monitoring_cloud). No public IP; egress via Cloud NAT.

resource "google_compute_instance" "this" {
  name         = var.name
  zone         = var.zone
  machine_type = var.machine_type
  tags         = var.tags
  labels       = var.labels

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 30
      type  = "pd-balanced"
    }
  }

  attached_disk {
    source      = google_compute_disk.data.id
    device_name = "data"
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
}

resource "google_compute_disk" "data" {
  name = "${var.name}-data"
  zone = var.zone
  size = var.data_disk_size_gb
  type = "pd-balanced"
}
