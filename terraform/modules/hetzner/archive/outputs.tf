output "id" {
  value = hcloud_server.this.id
}

output "private_ip" {
  value = var.private_ip
}

output "data_volume_device" {
  value       = hcloud_volume.data.linux_device
  description = "Pass to ansible/roles/node so it can format+mount without guessing the device path"
}
