terraform {
  required_version = "~> 1.10.5"
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
  backend "local" {
    lock_timeout = "5m"
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
  name       = "activist-docker-nyc-2"
  size       = "s-4vcpu-16gb-amd"
  region     = "nyc2"
  image      = "ubuntu-24-04-x64"
  vpc_uuid   = "5f77068a-0c82-4bf6-ac14-87f052512fd4"
  backups    = false
  monitoring = true
  ssh_keys   = [data.digitalocean_ssh_key.my_key.id]

  # Wait for droplet to be active and have an IP
  provisioner "local-exec" {
    command = <<-EOT
      until IP=$(doctl compute droplet get ${self.id} --format PublicIPv4 --no-header); do
        echo "Waiting for droplet IP..."
        sleep 5
      done
      echo "Droplet IP: $IP"
    EOT
  }
}

# Create domain (will fail silently if exists)
resource "digitalocean_domain" "activist_domain" {
  name = "dev-asyed.com"
  lifecycle {
    ignore_changes = [name]
  }
}

# DNS A record that points to the droplet
resource "digitalocean_record" "activist_a_record" {
  depends_on = [digitalocean_droplet.activist, digitalocean_domain.activist_domain]
  domain     = digitalocean_domain.activist_domain.name
  type       = "A"
  name       = "activist"
  value      = digitalocean_droplet.activist.ipv4_address
  ttl        = 30

  lifecycle {
    create_before_destroy = true
  }
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
      ANSIBLE_FORCE_COLOR=true bash run_ansible.sh "$${DROPLET_IP}"
    EOT
  }
}

# Output the consistent FQDN
output "droplet_fqdn" {
  value = digitalocean_record.activist_a_record.fqdn
}

# SSH tunnel depends on Ansible completing the app deployment
resource "null_resource" "ansible_provisioner" {
  triggers = {
    droplet_ip = digitalocean_droplet.activist.ipv4_address
  }

  provisioner "local-exec" {
    command = "ANSIBLE_FORCE_COLOR=1 ansible-playbook -u root -i '${digitalocean_droplet.activist.ipv4_address},' ansible/main.yml"
  }

  depends_on = [
    digitalocean_droplet.activist,
    null_resource.run_ansible
  ]
}
