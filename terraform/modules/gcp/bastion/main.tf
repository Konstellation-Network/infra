# Bastion / gateway host for the GCP side. Same three jobs as
# modules/hetzner/bastion (read that header): SSH jump host (the only
# userland listener), site-to-site WireGuard endpoint to the other cloud's
# bastion, and router for the other cloud's private CIDR from inside this
# VPC (google_compute_route below — GCP forwards on VPC routes, so unlike
# Hetzner no per-VM default route is needed).
#
# NAT egress for public-IP-less VMs is NOT this host's job on GCP: envs/<net>
# gcp.tf uses managed Cloud NAT (google_compute_router_nat). Keeping this
# host out of the egress path means a bastion reboot doesn't take apt away
# from the validators.

# Static external address: the tunnel endpoint the Hetzner bastion dials
# and the address in operators' ssh_config. An ephemeral one would change
# on every stop/start and silently break both.
resource "google_compute_address" "ipv4" {
  name         = "${var.name}-ipv4"
  region       = var.region
  address_type = "EXTERNAL"
}

resource "google_compute_instance" "this" {
  name         = var.name
  zone         = var.zone
  machine_type = var.machine_type
  tags         = var.tags
  labels       = var.labels

  # Required to forward packets whose source/destination isn't this VM's own
  # address — i.e. everything crossing the WireGuard tunnel.
  can_ip_forward = true

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

    access_config {
      nat_ip = google_compute_address.ipv4.address
    }
  }

  metadata = {
    ssh-keys       = "${var.ssh_user}:${var.ssh_public_key}"
    startup-script = file("${path.module}/../startup-script.sh")
  }
}

# Send the other cloud's private CIDR(s) via this VM. GCP evaluates VPC
# routes for every VM in the network, so validators/monitoring/cosigners need
# no local configuration to reach 10.0.1.x — it just goes to the bastion,
# which pushes it into the tunnel.
resource "google_compute_route" "remote" {
  for_each = var.remote_cidrs

  name              = "${var.name}-to-${each.key}"
  network           = var.network
  dest_range        = each.value
  next_hop_instance = google_compute_instance.this.self_link
  priority          = 100
}
