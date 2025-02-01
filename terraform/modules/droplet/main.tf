terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
}

data "digitalocean_ssh_key" "my_key" {
  name = var.ssh_key_name
}

resource "digitalocean_droplet" "activist" {
  name       = "activist-docker-nyc-${formatdate("YYYYMMDD-hhmmss", timestamp())}"
  size       = var.size
  region     = var.region
  image      = var.image
  vpc_uuid   = var.vpc_uuid
  backups    = var.backups
  monitoring = var.monitoring
  ssh_keys   = [data.digitalocean_ssh_key.my_key.id]

  lifecycle {
    prevent_destroy = false
    ignore_changes = [tags]
  }
} 