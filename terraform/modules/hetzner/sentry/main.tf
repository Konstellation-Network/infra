# Sentry node: public-facing, shields one validator (ENGINEERING.md §9.2).
# private_peer_ids on this node must be set to the validator's node ID so the
# validator's address is never gossiped over pex — enforced in ansible/roles/node,
# fed from var.validator_node_id via the inventory.

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
    ssh_public_key    = var.ssh_public_key
    default_route_via = "" # public IP: normal default route
  })

  labels = merge(var.labels, {
    role = "sentry"
  })
}
