output "id" {
  value = google_compute_instance.this.id
}

output "name" {
  value = google_compute_instance.this.name
}

output "private_ip" {
  value = google_compute_instance.this.network_interface[0].network_ip
}
