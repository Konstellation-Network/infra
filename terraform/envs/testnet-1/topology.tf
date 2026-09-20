# Shared topology locals: everything that both hetzner.tf and gcp.tf need to
# agree on. Read README.md "Cross-cloud connectivity" for the picture.

locals {
  # Both private networks. Internal-only rules (metrics scrape, archive RPC,
  # horcrux) admit the whole fleet, not just the local subnet, because the
  # monitoring host and cosigners may sit in either cloud and reach the other
  # through the bastions' tunnel with their real source IP (routed, not NAT'd).
  fleet_cidrs = [var.hetzner_network_ip_range, var.gcp_network_ip_range]

  # Archive nodes' RPC/REST/JSON-RPC: the fleet plus the explorer backend.
  archive_rpc_cidrs = distinct(concat(local.fleet_cidrs, var.explorer_cidrs))

  # Hetzner's private-network gateway is always the first address of the
  # network range; private-only Hetzner hosts point their default route at it
  # (cloud-init) so the bastion's 0.0.0.0/0 network route takes effect.
  hetzner_gateway = cidrhost(var.hetzner_network_ip_range, 1)

  # Fixed host slots inside each /24 (validators .11+, sentries .21+, rpc .31,
  # archive .41/.42 are in hetzner.tf/gcp.tf): bastion .5, monitoring .50,
  # cosigners .61+.
  hetzner_bastion_private_ip    = cidrhost(var.hetzner_network_ip_range, 5)
  gcp_bastion_private_ip        = cidrhost(var.gcp_network_ip_range, 5)
  hetzner_monitoring_private_ip = cidrhost(var.hetzner_network_ip_range, 50)
  gcp_monitoring_private_ip     = cidrhost(var.gcp_network_ip_range, 50)

  hetzner_bastion_wg_ip = cidrhost(var.wireguard_cidr, 1)
  gcp_bastion_wg_ip     = cidrhost(var.wireguard_cidr, 2)

  # Operator SSH ingress per bastion (var.bastion_ssh_entry).
  hetzner_bastion_ssh_cidrs = contains(["per-cloud", "hetzner"], var.bastion_ssh_entry) ? var.operator_ssh_cidrs : []
  gcp_bastion_ssh_cidrs     = contains(["per-cloud", "gcp"], var.bastion_ssh_entry) ? var.operator_ssh_cidrs : []

  # With a single entry point, the far cloud's hosts are reached across the
  # tunnel from the near bastion, so they must also accept 22 from the
  # entry bastion's private IP (the tunnel is routed, source IP preserved).
  hetzner_ssh_sources = distinct(concat(
    [local.hetzner_bastion_private_ip],
    var.bastion_ssh_entry == "gcp" ? [local.gcp_bastion_private_ip] : []
  ))
  gcp_ssh_sources = distinct(concat(
    [local.gcp_bastion_private_ip],
    var.bastion_ssh_entry == "hetzner" ? [local.hetzner_bastion_private_ip] : []
  ))

  # Cosigners: split var.cosigner_placement by cloud, keeping the global
  # index as the shard ID (c1..c3). Empty in colocated mode.
  cosigners = var.horcrux_mode == "dedicated" ? {
    for i, p in var.cosigner_placement : "c${i + 1}" => merge(p, { shard_id = i + 1, index = i })
  } : {}
  hetzner_cosigners = { for k, c in local.cosigners : k => c if c.cloud == "hetzner" }
  gcp_cosigners     = { for k, c in local.cosigners : k => c if c.cloud == "gcp" }

  cosigner_private_ips = merge(
    { for k, c in local.hetzner_cosigners : k => cidrhost(var.hetzner_network_ip_range, 61 + c.index) },
    { for k, c in local.gcp_cosigners : k => cidrhost(var.gcp_network_ip_range, 61 + c.index) },
  )
}
