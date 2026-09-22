# Dedicated Horcrux cosigner host (ENGINEERING.md §9.2: threshold signing
# across 3+ hosts/regions, separate from the validator hosts). One of
# envs/<net> var.cosigner_placement entries; the others may be on the other
# cloud — cosigners talk to each other (2222/tcp) and dial the validators'
# priv_validator_laddr (1234/tcp) on private IPs, across the bastions'
# WireGuard tunnel when the peer is in the other cloud.
#
# No public IP. Small: horcrux is a signer, not a node. Local disk only — the
# only state that matters is the shard and the last-signed-state file, and
# both are tiny.
#
# Key material is NEVER provisioned by Terraform or Ansible. The shard
# ceremony (`horcrux create-ed25519-shards`) is a human, offline step —
# runbooks/validator-key-rotation.md. prevent_destroy: a plan must never be
# able to remove a host holding a shard and its signing state (§2.7).

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
    role = "cosigner"
  })

  lifecycle {
    prevent_destroy = true
  }
}
