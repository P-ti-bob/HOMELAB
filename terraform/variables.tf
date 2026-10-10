variable "zone_regex" {
  type = string
}

variable "template" {
  type = string
}

variable "service_offering_regex" {
  type = string
}

variable "network_id" {
  type = string
}

variable "project_name" {
  type = string
}

variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/id_rsa.pub"
}

variable "root_disk_size" {
  type    = number
  default = 30 # Go
}

variable "vm_count" {
  type = number
}
