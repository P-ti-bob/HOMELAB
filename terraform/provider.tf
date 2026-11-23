terraform {
  required_providers {
    cloudstack = {
      source  = "cloudstack/cloudstack"
      version = "~> 0.6.0"
    }
    sops = {
      source = "carlpett/sops"
      version = ">= 1.4.0"
    }
  }
}

provider "cloudstack" {
  api_url    = data.sops_file.secrets.data["CLOUDSTACK_API_URL"]
  api_key    = data.sops_file.secrets.data["CLOUDSTACK_API_KEY"]
  secret_key = data.sops_file.secrets.data["CLOUDSTACK_SECRET_KEY"]
}

provider "sops" {}

data "sops_file" "secrets" {
  source_file = "secrets/api.yaml"
}

