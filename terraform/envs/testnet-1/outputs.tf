locals {
  # network_cidr / bastion_private_ip / cloud travel with each host because
  # Hetzner and GCP each have their own private network and bastion —
  # ansible/roles/firewall scopes SSH to the host's own bastion and "internal
  # only" ports to the fleet's CIDRs, and ssh_config ProxyJumps through the
  # right bastion per host.
  #
  # ansible_host is the PRIVATE IP for every host except the bastions —
  # Ansible always goes through a bastion (ssh_config), including to sentries
  # and the RPC node that do have public IPs. One SSH policy for the fleet.
  inventory_validators = merge(
    {
      for k, m in module.hetzner_validator : "hetzner-${k}" => {
        hostname           = m.name
        private_ip         = m.private_ip
        local_ssd_count    = 0
        network_cidr       = var.hetzner_network_ip_range
        cloud              = "hetzner"
        bastion_private_ip = local.hetzner_bastion_private_ip
      }
    },
    {
      for k, m in module.gcp_validator : "gcp-${k}" => {
        hostname           = m.name
        private_ip         = m.private_ip
        local_ssd_count    = local.gcp_validator_local_ssd_count
        network_cidr       = var.gcp_network_ip_range
        cloud              = "gcp"
        bastion_private_ip = local.gcp_bastion_private_ip
      }
    }
  )

  inventory_sentries = merge(
    {
      for k, m in module.hetzner_sentry : "hetzner-${k}" => {
        hostname           = m.name
        private_ip         = m.private_ip
        public_ipv4        = m.public_ipv4
        network_cidr       = var.hetzner_network_ip_range
        cloud              = "hetzner"
        bastion_private_ip = local.hetzner_bastion_private_ip
      }
    },
    {
      for k, m in module.gcp_sentry : "gcp-${k}" => {
        hostname           = m.name
        private_ip         = m.private_ip
        public_ipv4        = m.public_ipv4
        network_cidr       = var.gcp_network_ip_range
        cloud              = "gcp"
        bastion_private_ip = local.gcp_bastion_private_ip
      }
    }
  )

  inventory_archives = {
    "hetzner-1" = {
      hostname           = "testnet-1-hetzner-archive-1"
      private_ip         = module.hetzner_archive.private_ip
      data_volume_device = module.hetzner_archive.data_volume_device
      network_cidr       = var.hetzner_network_ip_range
      cloud              = "hetzner"
      bastion_private_ip = local.hetzner_bastion_private_ip
    }
    "gcp-1" = {
      hostname           = "testnet-1-gcp-archive-1"
      private_ip         = module.gcp_archive.private_ip
      data_volume_device = module.gcp_archive.data_volume_device
      network_cidr       = var.gcp_network_ip_range
      cloud              = "gcp"
      bastion_private_ip = local.gcp_bastion_private_ip
    }
  }

  inventory_rpcs = {
    "gcp-1" = {
      hostname           = "testnet-1-gcp-rpc-1"
      private_ip         = module.gcp_rpc.private_ip
      public_ipv4        = module.gcp_rpc.public_ipv4
      network_cidr       = var.gcp_network_ip_range
      cloud              = "gcp"
      bastion_private_ip = local.gcp_bastion_private_ip
    }
  }

  # Both bastions always exist (tunnel endpoints). ssh_entry says whether
  # operators may SSH to this one from the internet; ansible/roles/bastion
  # uses it to decide whether sshd listens publicly at all.
  inventory_bastions = {
    hetzner = {
      hostname           = module.hetzner_bastion.name
      public_ipv4        = module.hetzner_bastion.public_ipv4
      private_ip         = module.hetzner_bastion.private_ip
      network_cidr       = var.hetzner_network_ip_range
      cloud              = "hetzner"
      ssh_entry          = length(local.hetzner_bastion_ssh_cidrs) > 0
      operator_ssh_cidrs = local.hetzner_bastion_ssh_cidrs
      nat_gateway        = true
      wireguard_address  = local.hetzner_bastion_wg_ip
      wireguard_peer     = module.gcp_bastion.name
      wireguard_endpoint = module.gcp_bastion.public_ipv4
      remote_cidrs       = [var.gcp_network_ip_range]
    }
    gcp = {
      hostname           = module.gcp_bastion.name
      public_ipv4        = module.gcp_bastion.public_ipv4
      private_ip         = module.gcp_bastion.private_ip
      network_cidr       = var.gcp_network_ip_range
      cloud              = "gcp"
      ssh_entry          = length(local.gcp_bastion_ssh_cidrs) > 0
      operator_ssh_cidrs = local.gcp_bastion_ssh_cidrs
      nat_gateway        = false # Cloud NAT
      wireguard_address  = local.gcp_bastion_wg_ip
      wireguard_peer     = module.hetzner_bastion.name
      wireguard_endpoint = module.hetzner_bastion.public_ipv4
      remote_cidrs       = [var.hetzner_network_ip_range]
    }
  }

  # Exactly one of the two monitoring modules is instantiated.
  inventory_monitoring = merge(
    {
      for m in module.hetzner_monitoring : "hetzner-1" => {
        hostname           = "testnet-1-hetzner-monitoring-1"
        private_ip         = m.private_ip
        data_volume_device = m.data_volume_device
        network_cidr       = var.hetzner_network_ip_range
        cloud              = "hetzner"
        bastion_private_ip = local.hetzner_bastion_private_ip
      }
    },
    {
      for m in module.gcp_monitoring : "gcp-1" => {
        hostname           = "testnet-1-gcp-monitoring-1"
        private_ip         = m.private_ip
        data_volume_device = m.data_volume_device
        network_cidr       = var.gcp_network_ip_range
        cloud              = "gcp"
        bastion_private_ip = local.gcp_bastion_private_ip
      }
    }
  )

  # Empty in colocated mode. Keys c1..cN are the shard order.
  inventory_cosigners = merge(
    {
      for k, m in module.hetzner_cosigner : k => {
        hostname           = m.name
        private_ip         = m.private_ip
        shard_id           = local.cosigners[k].shard_id
        network_cidr       = var.hetzner_network_ip_range
        cloud              = "hetzner"
        bastion_private_ip = local.hetzner_bastion_private_ip
      }
    },
    {
      for k, m in module.gcp_cosigner : k => {
        hostname           = m.name
        private_ip         = m.private_ip
        shard_id           = local.cosigners[k].shard_id
        network_cidr       = var.gcp_network_ip_range
        cloud              = "gcp"
        bastion_private_ip = local.gcp_bastion_private_ip
      }
    }
  )

  # Single-entry topology: the far cloud's hosts also take SSH from the entry
  # bastion's private IP across the tunnel (ufw, ansible/roles/firewall).
  ssh_entry_bastion_private_ip = (
    var.bastion_ssh_entry == "hetzner" ? local.hetzner_bastion_private_ip :
    var.bastion_ssh_entry == "gcp" ? local.gcp_bastion_private_ip : ""
  )

  # Which bastion each cloud's hosts are ProxyJump'd through (ssh_config).
  ssh_jump_for = {
    hetzner = var.bastion_ssh_entry == "gcp" ? module.gcp_bastion.name : module.hetzner_bastion.name
    gcp     = var.bastion_ssh_entry == "hetzner" ? module.hetzner_bastion.name : module.gcp_bastion.name
  }

  all_jumped_hosts = merge(
    local.inventory_validators, local.inventory_sentries, local.inventory_archives,
    local.inventory_rpcs, local.inventory_monitoring, local.inventory_cosigners,
  )
}

resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../../../ansible/inventories/testnet-1/hosts.yml"
  content = templatefile("${path.module}/inventory.tpl.yml", {
    validators                   = local.inventory_validators
    sentries                     = local.inventory_sentries
    archives                     = local.inventory_archives
    rpcs                         = local.inventory_rpcs
    bastions                     = local.inventory_bastions
    monitoring                   = local.inventory_monitoring
    cosigners                    = local.inventory_cosigners
    fleet_cidrs                  = local.fleet_cidrs
    ssh_entry_bastion_private_ip = local.ssh_entry_bastion_private_ip
    monitoring_host_private_ip   = local.monitoring_host_private_ip
    horcrux_mode                 = var.horcrux_mode
    wireguard_cidr               = var.wireguard_cidr
    wireguard_port               = var.wireguard_port
  })
}

resource "local_file" "ssh_config" {
  filename = "${path.module}/../../../ansible/inventories/testnet-1/ssh_config"
  content = templatefile("${path.module}/ssh_config.tpl", {
    ssh_user     = var.ssh_user
    bastions     = local.inventory_bastions
    jumped_hosts = local.all_jumped_hosts
    jump_for     = local.ssh_jump_for
  })
}

# M4 (review, 2026-09-21): say it in the plan when a single provider holds
# two shards. Not an error — there is no third provider to place it on yet
# (STATUS §5a P16/P21).
output "cosigner_placement_warning" {
  value = (
    var.horcrux_mode == "dedicated" && (length(local.hetzner_cosigners) >= 2 || length(local.gcp_cosigners) >= 2)
    ? "WARNING: ${length(local.hetzner_cosigners)} shards on Hetzner, ${length(local.gcp_cosigners)} on GCP — one provider account holds a signing threshold (P21). Acceptable for testnet-1 only."
    : "ok"
  )
}

# D7 re-decided 2026-09-29: 4 validators in 4 separate failure domains, so
# losing one provider/region never halts the chain. CometBFT halts once
# more than 1/3 of voting power is offline; at equal power a provider
# holding n of N validators can halt the chain on its own when 3n >= N
# (2 of 4 = 50 %). Said in every plan, in the style of the P21 warning
# above. Not an error: which domains mainnet uses is still open (STATUS §5a
# P16), and the 2 + 2 default is accepted for testnet-1 only.
locals {
  validator_total = var.hetzner_validator_count + var.gcp_validator_count
  validators_per_provider = {
    hetzner = var.hetzner_validator_count
    gcp     = var.gcp_validator_count
  }
  halting_providers = [
    for p, n in local.validators_per_provider : "${p} holds ${n} of ${local.validator_total} validators"
    if n > 0 && n * 3 >= local.validator_total
  ]

  # Within a provider: a Hetzner location / GCP zone is the smaller domain.
  validator_domains = concat(
    [for v in local.hetzner_validators : "hetzner/${v.location}"],
    [for v in local.gcp_validators : "gcp/${v.zone}"],
  )
  shared_validator_domains = [
    for d in distinct(local.validator_domains) : d
    if length([for x in local.validator_domains : x if x == d]) > 1
  ]

  validator_placement_problems = compact([
    length(local.halting_providers) > 0 ? "${join("; ", local.halting_providers)} — each is >= 1/3 of voting power, so losing that one provider halts the chain." : "",
    var.gcp_validator_count >= 2 ? "The ${var.gcp_validator_count} GCP validators share region ${var.gcp_region} — a regional outage takes them together." : "",
    length(local.shared_validator_domains) > 0 ? "More than one validator in: ${join(", ", local.shared_validator_domains)}." : "",
  ])
}

output "validator_placement_warning" {
  value = (
    length(local.validator_placement_problems) > 0
    ? "WARNING: ${join(" ", local.validator_placement_problems)} Acceptable for testnet-1 only (4 separate failure domains is the rule; which ones is open — STATUS §5a P16)."
    : "ok"
  )
}

output "validator_private_ips" {
  value = { for k, v in local.inventory_validators : k => v.private_ip }
}

output "sentry_public_ips" {
  value = { for k, v in local.inventory_sentries : k => v.public_ipv4 }
}

output "rpc_public_ips" {
  value = { for k, v in local.inventory_rpcs : k => v.public_ipv4 }
}

output "archive_private_ips" {
  value = { for k, v in local.inventory_archives : k => v.private_ip }
}

output "bastion_public_ips" {
  value = { for k, v in local.inventory_bastions : k => v.public_ipv4 }
}

output "monitoring_private_ip" {
  value = local.monitoring_host_private_ip
}

output "cosigner_private_ips" {
  value = { for k, v in local.inventory_cosigners : k => v.private_ip }
}
