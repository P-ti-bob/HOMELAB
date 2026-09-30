
# ---- Découverte automatique via l'API ----
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

# ---- Projet ----
resource "cloudstack_project" "project" {
  name        = var.project_name
  displaytext = var.project_name
}

# Les keypairs CloudStack sont liées à un compte ou à un projet :
# celle du compte n'est pas utilisable dans le projet, on l'y enregistre.
resource "cloudstack_ssh_keypair" "ssh_key" {
  name       = "thinkpad"
  public_key = file(pathexpand(var.ssh_public_key_path))
  project    = cloudstack_project.project.name
}

# ---- VMs ----
resource "cloudstack_instance" "vm" {
  count            = var.vm_count
  name             = "tf-vm-${count.index + 1}"
  service_offering = data.cloudstack_service_offering.offering.name
  template         = data.cloudstack_template.tpl.id
  zone             = data.cloudstack_zone.zone.name
  project          = cloudstack_project.project.name
  # Réseau partagé "Oteria" (pas de data source cloudstack_network dans le provider)
  network_id       = var.network_id
  keypair          = cloudstack_ssh_keypair.ssh_key.name
  expunge          = true
}

output "vm_ips" {
  value = cloudstack_instance.vm[*].ip_address
}
