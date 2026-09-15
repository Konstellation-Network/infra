variable "name" {
  type = string
}

variable "zone" {
  type = string
}

variable "machine_type" {
  type    = string
  default = "n2-standard-8"
}

variable "network" {
  type = string
}

variable "subnetwork" {
  type = string
}

variable "private_ip" {
  type = string
}

variable "ssh_user" {
  type    = string
  default = "deploy"
}

variable "ssh_public_key" {
  type = string
}

variable "tags" {
  type    = list(string)
  default = ["konstellation", "rpc"]
}

variable "labels" {
  type    = map(string)
  default = {}
}
