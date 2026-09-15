# Archive node: pruning = "nothing", tracing enabled (ansible/roles/node sets
# both from group_vars/archive.yml). No public IP — Blockscout (in the
# `explorer` repo) reaches this over the private network only.

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
    ssh_public_key = var.ssh_public_key
  })

  labels = merge(var.labels, {
    role = "archive"
  })
}

resource "hcloud_volume" "data" {
  name     = "${var.name}-data"
  size     = var.data_volume_size_gb
  location = var.location
  format   = "ext4"
}

resource "hcloud_volume_attachment" "data" {
  volume_id = hcloud_volume.data.id
  server_id = hcloud_server.this.id
  automount = false # ansible/roles/node mounts it at $DAEMON_HOME/data explicitly
}
