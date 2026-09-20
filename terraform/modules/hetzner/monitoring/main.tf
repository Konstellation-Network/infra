# Central monitoring host: Prometheus, Alertmanager, Grafana and tenderduty
# (ansible/roles/monitoring_server). No public IP — Grafana and the
# tenderduty dashboard are reached with an SSH port-forward through the
# bastion (see runbooks/on-call.md). It scrapes every node in BOTH clouds on
# private IPs: the other cloud is one hop away through the bastions'
# WireGuard tunnel (terraform/modules/*/bastion).
#
# Only one of terraform/modules/{hetzner,gcp}/monitoring is instantiated per
# environment — envs/<net> var.monitoring_cloud picks which.

resource "hcloud_server" "this" {
  name         = var.name
  location     = var.location
  server_type  = var.server_type
  image        = "debian-12"
  ssh_keys     = var.ssh_key_ids
  firewall_ids = var.firewall_ids

  public_net {
    ipv4_enabled = false
    ipv6_enabled = false
  }

  network {
    network_id = var.network_id
    ip         = var.private_ip
  }

  user_data = templatefile("${path.module}/../validator/cloud-init.yaml.tpl", {
    ssh_public_key    = var.ssh_public_key
    default_route_via = var.default_route_via
  })

  labels = merge(var.labels, {
    role = "monitoring"
  })
}

# Prometheus TSDB + Grafana state. Network-attached is fine here: nothing on
# this host gates consensus.
resource "hcloud_volume" "data" {
  name     = "${var.name}-data"
  size     = var.data_volume_size_gb
  location = var.location
  format   = "ext4"
}

resource "hcloud_volume_attachment" "data" {
  volume_id = hcloud_volume.data.id
  server_id = hcloud_server.this.id
  automount = false # ansible/roles/monitoring_server mounts it explicitly
}
