
data "cloudstack_zone" "zone" {
  filter {
    name  = "name"
    value = var.zone_regex
  }
}

data "cloudstack_template" "tpl" {
  template_filter = "featured"
  filter {
    name  = "name"
    value = var.template
  }
}

data "cloudstack_service_offering" "offering" {
  filter {
    name  = "name"
    value = var.service_offering_regex
  }
}

resource "cloudstack_project" "project" {
  name        = var.project_name
  displaytext = var.project_name
}

resource "cloudstack_ssh_keypair" "ssh_key" {
  name       = "thinkpad"
  public_key = file(pathexpand(var.ssh_public_key_path))
  project    = cloudstack_project.project.name
}

resource "cloudstack_instance" "vm" {
  count            = var.vm_count
  name             = "homelab-${count.index}"
  service_offering = data.cloudstack_service_offering.offering.name
  template         = data.cloudstack_template.tpl.id
  zone             = data.cloudstack_zone.zone.name
  project          = cloudstack_project.project.name
  network_id       = var.network_id
  keypair          = cloudstack_ssh_keypair.ssh_key.name
  root_disk_size   = var.root_disk_size
  expunge          = true
}

output "vm_ips" {
  value = cloudstack_instance.vm[*].ip_address
}
