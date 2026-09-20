output "id" {
  value = hcloud_server.this.id
}

output "name" {
  value = hcloud_server.this.name
}

output "public_ipv4" {
  value = hcloud_server.this.ipv4_address
}

output "private_ip" {
  value = var.private_ip
}
