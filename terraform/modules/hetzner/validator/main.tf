# Validator node.
#
# ENGINEERING.md §9.2 constraints this module enforces at the infra layer:
#   - no public IPv4/IPv6 (validators sit behind sentries, persistent_peers = own
#     sentries only, config.toml pex = false — enforced by ansible/roles/node)
#   - local NVMe only: server_type must be a dedicated-vCPU type with local disk.
#     Do NOT attach an hcloud_volume for $DAEMON_HOME/data — IAVL commit latency
#     is disk-bound and network storage costs block time.
#   - attached to the private validator/sentry network only.
#
# Key material (priv_validator_key.json / horcrux shards) is never provisioned
# by Terraform. This module only creates the host; ansible/roles/horcrux lays
# out config structure, and shard generation is a manual, offline ceremony
# (ENGINEERING.md §2.7 — double-signing is unrecoverable).

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

  user_data = templatefile("${path.module}/cloud-init.yaml.tpl", {
    ssh_public_key    = var.ssh_public_key
    default_route_via = var.default_route_via
  })

  labels = merge(var.labels, {
    role = "validator"
  })

  lifecycle {
    # Never let a plan silently swap the disk out from under a running validator.
    prevent_destroy = true
  }
}
