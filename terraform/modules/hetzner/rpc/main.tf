# Public RPC node. Pruned (not archive) — config.toml/app.toml pruning params
# are set by ansible/roles/node from group_vars, defaulting to the same custom
# pruning as validators unless overridden.

resource "hcloud_server" "this" {
  name         = var.name
  location     = var.location
  server_type  = var.server_type
  image        = "debian-12"
  ssh_keys     = var.ssh_key_ids
  firewall_ids = var.firewall_ids

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  network {
    network_id = var.network_id
    ip         = var.private_ip
  }

  user_data = templatefile("${path.module}/../validator/cloud-init.yaml.tpl", {
    ssh_public_key = var.ssh_public_key
  })

  labels = merge(var.labels, {
    role = "rpc"
  })
}
