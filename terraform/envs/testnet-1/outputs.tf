locals {
  # network_cidr travels with each host because Hetzner and GCP each have
  # their own private network — ansible/roles/firewall scopes "internal only"
  # ports to whichever CIDR the host actually shares with its own sentry/
  # monitoring traffic, not a single fleet-wide value.
  inventory_validators = merge(
    {
      for k, m in module.hetzner_validator : "hetzner-${k}" => {
        hostname        = m.name
        private_ip      = m.private_ip
        local_ssd_count = 0
        network_cidr    = var.hetzner_network_ip_range
      }
    },
    {
      for k, m in module.gcp_validator : "gcp-${k}" => {
        hostname        = m.name
        private_ip      = m.private_ip
        local_ssd_count = local.gcp_validator_local_ssd_count
        network_cidr    = var.gcp_network_ip_range
      }
    }
  )

  inventory_sentries = merge(
    {
      for k, m in module.hetzner_sentry : "hetzner-${k}" => {
        hostname     = m.name
        public_ipv4  = m.public_ipv4
        network_cidr = var.hetzner_network_ip_range
      }
    },
    {
      for k, m in module.gcp_sentry : "gcp-${k}" => {
        hostname     = m.name
        public_ipv4  = m.public_ipv4
        network_cidr = var.gcp_network_ip_range
      }
    }
  )

  inventory_archives = {
    "hetzner-1" = {
      hostname           = "testnet-1-hetzner-archive-1"
      private_ip         = module.hetzner_archive.private_ip
      data_volume_device = module.hetzner_archive.data_volume_device
      network_cidr       = var.hetzner_network_ip_range
    }
    "gcp-1" = {
      hostname           = "testnet-1-gcp-archive-1"
      private_ip         = module.gcp_archive.private_ip
      data_volume_device = module.gcp_archive.data_volume_device
      network_cidr       = var.gcp_network_ip_range
    }
  }

  inventory_rpcs = {
    "gcp-1" = {
      hostname     = "testnet-1-gcp-rpc-1"
      public_ipv4  = module.gcp_rpc.public_ipv4
      network_cidr = var.gcp_network_ip_range
    }
  }
}

resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../../../ansible/inventories/testnet-1/hosts.yml"
  content = templatefile("${path.module}/inventory.tpl.yml", {
    validators = local.inventory_validators
    sentries   = local.inventory_sentries
    archives   = local.inventory_archives
    rpcs       = local.inventory_rpcs
  })
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
