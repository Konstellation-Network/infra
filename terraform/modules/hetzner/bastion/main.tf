# Bastion / gateway host for this cloud's private network (ENGINEERING.md
# §9.2: validators have no public IP, so every SSH session reaches them
# through here — ansible/inventories/<net>/ssh_config ProxyJumps through it).
#
# Three jobs, all parametrised in envs/<net>:
#   1. SSH jump host. sshd is the ONLY userland listener. Key-only, fail2ban,
#      no agent forwarding (ansible/roles/bastion). Operator source CIDRs are
#      the only thing allowed in on 22 — see envs/<net>/variables.tf
#      operator_ssh_cidrs.
#   2. NAT egress gateway (var.nat_gateway). A Hetzner server with no public
#      IP has NO route to the internet at all, so a validator could never
#      apt-get or fetch its own checksummed binary. hcloud_network_route
#      0.0.0.0/0 -> this host + kernel forwarding + masquerade fixes that
#      (Hetzner's documented NAT pattern). Kernel forwarding, not a service.
#   3. Site-to-site WireGuard endpoint to the other cloud's bastion
#      (var.wireguard_peer_public_ip). Kernel WireGuard: packets not from a
#      configured peer are dropped silently, nothing listens in userland.
#      This is what lets the monitoring host and dedicated Horcrux cosigners
#      reach hosts in either cloud on private IPs — see envs/<net>/README.
#
# Note on hcloud firewalls: they filter the PUBLIC interface only. The
# rules attached here (22 from operators, 51820/udp from the peer bastion)
# are therefore effective; private-network traffic through this host is
# governed by ufw (ansible/roles/firewall, node_role=bastion).

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
    default_route_via = "" # has its own public IP; never routes via itself
  })

  labels = merge(var.labels, {
    role = "bastion"
  })
}

# Everything in the private network that has no public IP egresses through
# this host. The route lives on the hcloud_network, the client side of it
# (default via the network gateway .1) is set by cloud-init on private-only
# hosts — see ../validator/cloud-init.yaml.tpl default_route_via.
resource "hcloud_network_route" "nat" {
  count = var.nat_gateway ? 1 : 0

  network_id  = var.network_id
  destination = "0.0.0.0/0"
  gateway     = var.private_ip
}

# The other cloud's private network is reachable through the WireGuard
# tunnel terminated on this host.
resource "hcloud_network_route" "remote" {
  for_each = var.remote_cidrs

  network_id  = var.network_id
  destination = each.value
  gateway     = var.private_ip
}
