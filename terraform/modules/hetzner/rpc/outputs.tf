output "id" {
  value = hcloud_server.this.id
}

output "public_ipv4" {
  value = hcloud_server.this.ipv4_address
}
