output "id" {
  value = google_compute_instance.this.id
}

output "name" {
  value = google_compute_instance.this.name
}

output "public_ipv4" {
  value = google_compute_address.ipv4.address
}

output "private_ip" {
  value = google_compute_instance.this.network_interface[0].network_ip
}
