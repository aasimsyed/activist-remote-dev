terraform {
  required_providers {
    digitalocean = {
      source = "digitalocean/digitalocean"
    }
  }
}

provider "digitalocean" {
  token = var.do_token
}

module "droplet" {
  source = "../../modules/droplet"
  
  # Use values from config.yml
  size         = local.config.digitalocean.size
  region       = local.config.digitalocean.region
  image        = local.config.digitalocean.image
  vpc_uuid     = local.config.digitalocean.vpc_uuid
  ssh_key_name = local.config.digitalocean.ssh_key_name
  branch       = var.branch
}

output "droplet_ip" {
  value = module.droplet.droplet_ip
} 