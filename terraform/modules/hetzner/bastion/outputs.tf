output "id" {
  value = hcloud_server.this.id
}

output "name" {
  value = hcloud_server.this.name
}

output "public_ipv4" {
  value = hcloud_primary_ip.ipv4.ip_address
}

output "private_ip" {
  value = var.private_ip
}
