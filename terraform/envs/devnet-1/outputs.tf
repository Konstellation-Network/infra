locals {
  # Same host-var shape as envs/testnet-1/outputs.tf so the shared ansible
  # roles see the same facts; cloud is always "hetzner" and every host's
  # bastion is the one bastion. ansible_host is the PRIVATE IP for every
  # host except the bastion (Ansible always goes through it — ssh_config).
  host_common = {
    network_cidr       = var.hetzner_network_ip_range
    cloud              = "hetzner"
    bastion_private_ip = local.bastion_private_ip
  }

  inventory_validators = {
    v1 = merge(local.host_common, {
      hostname   = module.validator.name
      private_ip = module.validator.private_ip
    })
  }

  inventory_sentries = {
    for k, m in module.sentry : k => merge(local.host_common, {
      hostname    = m.name
      private_ip  = m.private_ip
      public_ipv4 = m.public_ipv4
    })
  }

  inventory_rpcs = {
    "1" = merge(local.host_common, {
      hostname    = "devnet-1-hetzner-rpc-1"
      private_ip  = module.rpc.private_ip
      public_ipv4 = module.rpc.public_ipv4
    })
  }

  inventory_archives = {
    "1" = merge(local.host_common, {
      hostname           = "devnet-1-hetzner-archive-1"
      private_ip         = module.archive.private_ip
      data_volume_device = module.archive.data_volume_device
    })
  }

  inventory_monitoring = {
    "1" = merge(local.host_common, {
      hostname           = "devnet-1-hetzner-monitoring-1"
      private_ip         = module.monitoring.private_ip
      data_volume_device = module.monitoring.data_volume_device
    })
  }

  inventory_bastion = {
    hostname           = module.bastion.name
    public_ipv4        = module.bastion.public_ipv4
    private_ip         = module.bastion.private_ip
    network_cidr       = var.hetzner_network_ip_range
    operator_ssh_cidrs = var.operator_ssh_cidrs
  }

  all_jumped_hosts = merge(
    { for k, v in local.inventory_validators : "validator-${k}" => v },
    { for k, v in local.inventory_sentries : "sentry-${k}" => v },
    { for k, v in local.inventory_rpcs : "rpc-${k}" => v },
    { for k, v in local.inventory_archives : "archive-${k}" => v },
    { for k, v in local.inventory_monitoring : "monitoring-${k}" => v },
  )
}

resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../../../ansible/inventories/devnet-1/hosts.yml"
  content = templatefile("${path.module}/inventory.tpl.yml", {
    validators                 = local.inventory_validators
    sentries                   = local.inventory_sentries
    rpcs                       = local.inventory_rpcs
    archives                   = local.inventory_archives
    monitoring                 = local.inventory_monitoring
    bastion                    = local.inventory_bastion
    fleet_cidrs                = local.fleet_cidrs
    monitoring_host_private_ip = local.monitoring_ip
  })
}

resource "local_file" "ssh_config" {
  filename = "${path.module}/../../../ansible/inventories/devnet-1/ssh_config"
  content = templatefile("${path.module}/ssh_config.tpl", {
    ssh_user     = var.ssh_user
    bastion      = local.inventory_bastion
    jumped_hosts = local.all_jumped_hosts
  })
}

# One validator holds 100 % of voting power: any outage of that host, its
# location or Hetzner stops block production. That is the accepted shape of
# a dev network (D18), not a placement mistake — stated in the plan so
# nobody reads devnet-1 uptime as a property of the design.
output "validator_placement_warning" {
  value = "NOTE: devnet-1 has ONE validator (100 % of voting power) in ${var.hetzner_location} on Hetzner — any outage of that host, location or provider halts devnet-1. By design (D18); never 'fix' it by starting a second node with the same key (ENGINEERING.md §2.7)."
}

output "validator_private_ip" {
  value = module.validator.private_ip
}

output "sentry_public_ips" {
  value = { for k, v in local.inventory_sentries : k => v.public_ipv4 }
}

output "rpc_public_ip" {
  description = "Point devnet-1 RPC DNS here: EVM JSON-RPC :8545 / WS :8546 (dapps, wallets, the faucet's RPC_URL), CometBFT RPC :26657, REST :1317."
  value       = module.rpc.public_ipv4
}

output "archive_private_ip" {
  description = "The explorer's Blockscout backend (debug JSON-RPC) — reachable only from var.explorer_cidrs."
  value       = module.archive.private_ip
}

output "bastion_public_ip" {
  value = module.bastion.public_ipv4
}

output "monitoring_private_ip" {
  value = local.monitoring_ip
}
