terraform {
  required_version = "~> 1.10.5"
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
  backend "local" {
    path = ".terraform/terraform.tfstate"
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

  connection {
    type        = "ssh"
    user        = "root"
    host        = self.ipv4_address
    private_key = file("~/.ssh/id_rsa")
  }
}

# Create domain if it doesn't exist
resource "digitalocean_domain" "activist_domain" {
  name = "dev-asyed.com"
}

# DNS A record that points to the droplet
resource "digitalocean_record" "activist_a_record" {
  domain = digitalocean_domain.activist_domain.name
  type   = "A"
  name   = "activist"
  value  = digitalocean_droplet.activist.ipv4_address
  ttl    = 30
}

# SSH tunnel depends on Ansible completing the app deployment
resource "null_resource" "ssh_tunnel" {
  depends_on = [null_resource.run_ansible]

  triggers = {
    droplet_ip = digitalocean_droplet.activist.ipv4_address
  }

  provisioner "local-exec" {
    command = <<-EOT
      GREEN='\033[0;32m'
      BLUE='\033[0;34m'
      CYAN='\033[0;36m'
      YELLOW='\033[1;33m'
      RED='\033[0;31m'
      NC='\033[0m'
      
      echo -e "$${BLUE}Waiting for application services to be ready...$${NC}"
      
      # Wait for ports to be available on remote
      for i in {1..30}; do
        if ssh -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa root@${digitalocean_droplet.activist.ipv4_address} \
            'netstat -tuln | grep -E ":3000.*LISTEN|:8000.*LISTEN"' &>/dev/null; then
          echo -e "$${GREEN}Remote services are running!$${NC}"
          break
        fi
        echo -e "$${YELLOW}Waiting for services to start ($$i/30)...$${NC}"
        if [ $$i -eq 30 ]; then
          echo -e "$${RED}Timeout waiting for services to start$${NC}"
          exit 1
        fi
        sleep 10
      done
      
      echo -e "$${BLUE}Setting up SSH tunnels...$${NC}"
      
      # Clean up any existing tunnels
      pkill -f "ssh -L.*:3000.*:8000" || true
      
      # Set up new tunnel
      ssh -v -o StrictHostKeyChecking=no \
          -i ~/.ssh/id_rsa \
          -L 3000:localhost:3000 \
          -L 8000:localhost:8000 \
          -N -f \
          root@${digitalocean_droplet.activist.ipv4_address}
      
      sleep 2
      
      if pgrep -f "ssh -L.*:3000.*:8000" > /dev/null; then
        echo -e "$${GREEN}SSH tunnels established! Access the app at:$${NC}"
        echo -e "$${CYAN}Frontend: http://localhost:3000$${NC}"
        echo -e "$${CYAN}Backend: http://localhost:8000$${NC}"
        exit 0
      else
        echo -e "$${RED}Failed to establish SSH tunnels$${NC}"
        exit 1
      fi
    EOT
  }
}

# Ansible runs independently
resource "null_resource" "run_ansible" {
  depends_on = [digitalocean_droplet.activist]

  triggers = {
    droplet_ip        = digitalocean_droplet.activist.ipv4_address
    requirements_hash = filesha256("${path.module}/requirements.yml")
  }

  provisioner "local-exec" {
    command = "ANSIBLE_FORCE_COLOR=true bash run_ansible.sh ${digitalocean_droplet.activist.ipv4_address}"
  }
}

# Output the consistent FQDN
output "droplet_fqdn" {
  value = digitalocean_record.activist_a_record.fqdn
}
