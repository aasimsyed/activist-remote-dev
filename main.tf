terraform {
  required_version = "~> 1.10.5"
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
  backend "local" {
    # Remove invalid lock_timeout parameter
  }
}

output "droplet_ip" {
  value = digitalocean_droplet.activist.ipv4_address
}

provider "digitalocean" {
  token = var.do_token
}

data "digitalocean_ssh_key" "my_key" {
  name = "DigitalOcean"
}

resource "digitalocean_droplet" "activist" {
  name       = "activist-docker-nyc-${formatdate("YYYYMMDD-hhmmss", timestamp())}"
  size       = "s-4vcpu-16gb-amd"
  region     = "nyc2"
  image      = "ubuntu-24-04-x64"
  vpc_uuid   = "5f77068a-0c82-4bf6-ac14-87f052512fd4"
  backups    = false
  monitoring = true
  ssh_keys   = [data.digitalocean_ssh_key.my_key.id]

  lifecycle {
    prevent_destroy = false  # Explicitly allow destruction
    ignore_changes = [tags]  # Prevent conflicts with external changes
  }
}

variable "delete_all" {
  type    = bool
  default = false
}

variable "create_domain" {
  type    = bool
  default = true  # Set default based on your needs
}

# Try to fetch existing domain (will fail if not found)
data "digitalocean_domain" "existing" {
  count = var.manage_domain ? 0 : 1  # Only fetch when not managing domain
  name  = "dev-asyed.com"
}

# Create domain only when we're managing it and it doesn't exist
resource "digitalocean_domain" "main" {
  count      = var.manage_domain ? 1 : 0
  name       = "dev-asyed.com"
  ip_address = digitalocean_droplet.activist.ipv4_address

  lifecycle {
    prevent_destroy = false  # Allow domain deletion with delete-all
  }
}

# Always create/update the A record using either existing or new domain
resource "digitalocean_record" "activist_a_record" {
  domain = try(data.digitalocean_domain.existing[0].name, digitalocean_domain.main[0].name)
  type   = "A"
  name   = "activist"
  value  = digitalocean_droplet.activist.ipv4_address
  ttl    = 30
}

# Add IP check and SSH wait as separate resource
resource "null_resource" "wait_for_droplet" {
  depends_on = [digitalocean_droplet.activist]

  triggers = {
    droplet_ip = digitalocean_droplet.activist.ipv4_address
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      # Wait for IP to be assigned
      for i in {1..20}; do
        DROPLET_IP=$(doctl compute droplet get ${digitalocean_droplet.activist.id} --format PublicIPv4 --no-header)
        if [ ! -z "$DROPLET_IP" ]; then
          echo "Droplet IP assigned: $DROPLET_IP"
          break
        fi
        echo "Attempt $i: Waiting for IP assignment..."
        sleep 10
      done

      if [ -z "$DROPLET_IP" ]; then
        echo "Failed to get droplet IP after 20 attempts"
        exit 1
      fi

      # Wait for SSH
      sleep 30  # Initial wait for system boot
      for i in {1..20}; do
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes -i ~/.ssh/id_rsa root@$DROPLET_IP 'exit' 2>/dev/null; then
          echo "SSH connection established!"
          exit 0
        fi
        echo "Attempt $i: Waiting for SSH..."
        sleep 10
      done
      
      echo "Failed to establish SSH connection after 20 attempts"
      exit 1
    EOT
  }
}

# Ansible runs independently
resource "null_resource" "run_ansible" {
  depends_on = [null_resource.wait_for_droplet]

  triggers = {
    droplet_ip = digitalocean_droplet.activist.ipv4_address
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      DROPLET_IP="${digitalocean_droplet.activist.ipv4_address}"
      if [ -z "$${DROPLET_IP}" ]; then
        echo "Error: Empty droplet IP"
        exit 1
      fi
      sleep 10  # Extra buffer after SSH connection
      ANSIBLE_FORCE_COLOR=true ansible-playbook -u root -i "$DROPLET_IP," --private-key ~/.ssh/id_rsa deploy.yml
    EOT
  }
}

# Update the output to use the existing domain
output "droplet_fqdn" {
  value = digitalocean_record.activist_a_record.fqdn
}
