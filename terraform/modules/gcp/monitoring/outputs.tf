output "id" {
  value = google_compute_instance.this.id
}

output "private_ip" {
  value = google_compute_instance.this.network_interface[0].network_ip
}

output "data_volume_device" {
  value       = "/dev/disk/by-id/google-data"
  description = "GCP names the by-id path after attached_disk's device_name ('data'), so this is deterministic — pass to ansible/roles/node so it can format+mount without guessing."
}
