output "id" {
  value = google_compute_instance.this.id
}

output "public_ipv4" {
  value = google_compute_instance.this.network_interface[0].access_config[0].nat_ip
}

output "private_ip" {
  value = google_compute_instance.this.network_interface[0].network_ip
}
