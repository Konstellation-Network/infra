output "id" {
  value = hcloud_server.this.id
}

output "name" {
  value = hcloud_server.this.name
}

output "private_ip" {
  value = var.private_ip
}
