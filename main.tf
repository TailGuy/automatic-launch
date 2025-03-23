# -------------------------------------------------------------------
# Terraform Configuration
# -------------------------------------------------------------------
# Specify required providers and their versions for the configuration.
terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
}

# -------------------------------------------------------------------
# Variables
# -------------------------------------------------------------------
# Define input variables for DigitalOcean authentication and droplet configuration.
variable "do_token" {
  description = "DigitalOcean API token"
  type        = string
}

variable "droplet_name" {
  description = "Name of the IoT droplet"
  type        = string
}

variable "ssh_public_keys" {
  description = "List of SSH key fingerprints to allow"
  type        = list(string)
}

# -------------------------------------------------------------------
# DigitalOcean Provider
# -------------------------------------------------------------------
# Configure the DigitalOcean provider with the API token.
provider "digitalocean" {
  token = var.do_token
}

# -------------------------------------------------------------------
# Create DigitalOcean Droplet
# -------------------------------------------------------------------
# Provision a droplet with specified image, size, and SSH access.
resource "digitalocean_droplet" "droplet" {
  name       = var.droplet_name
  image      = "ubuntu-24-04-x64"
  region     = "fra1"
  size       = "s-2vcpu-4gb"
  monitoring = true
  ssh_keys   = var.ssh_public_keys

  # Minimal user_data script to set up Docker and a non-root user.
  # YOU HAVE TO USE -y ARGUMENTS FOR INSTALL COMMANDS!!! The installation is non-interactive
  user_data = <<-EOF
    #!/bin/bash
    # Redirect all output to a log file for troubleshooting
    exec > /var/log/user-data.log 2>&1
    set -x  # Enable command tracing for debugging

    # Update package list
    apt-get update -y

    # Install prerequisites
    apt-get install -y ca-certificates curl git

    # Create directory for Docker's GPG key
    install -m 0755 -d /etc/apt/keyrings

    # Download and add Docker's GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    # Add Docker repository to APT sources
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(source /etc/os-release && echo $UBUNTU_CODENAME) stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Update package list again with Docker repository
    apt-get update -y

    # Install Docker packages
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Verify Docker is running
    systemctl enable docker
    systemctl start docker

    # Clone the GitHub repository
    git clone https://github.com/TheGoodGamerGuy/DF-docker.git /root/DF-docker

    # Navigate to the repository directory
    cd /root/DF-docker

    # Run Docker Compose to start the services
    # docker compose up -d # TODO: add the environment variables for the docker compose
  EOF 
}

# -------------------------------------------------------------------
# Configure Firewall Rules
# -------------------------------------------------------------------
# Define firewall rules to control inbound and outbound traffic for the droplet.
resource "digitalocean_firewall" "services_firewall" {
  name       = var.droplet_name
  droplet_ids = [digitalocean_droplet.droplet.id]

  # Allow SSH access from any IP.
  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Allow Grafana traffic on port 3000.
  inbound_rule {
    protocol         = "tcp"
    port_range       = "3000"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Allow MQTT traffic on port 1883.
  inbound_rule {
    protocol         = "tcp"
    port_range       = "1883"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Allow InfluxDB traffic on port 8086.
  inbound_rule {
    protocol         = "tcp"
    port_range       = "8086"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Allow Portainer traffic on port 9000.
  inbound_rule {
    protocol         = "tcp"
    port_range       = "9000"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Allow Loki traffic on port 3100
  inbound_rule {
    protocol         = "tcp"
    port_range       = "3100"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Allow the fastapi app traffic on port 7080
  inbound_rule {
    protocol         = "tcp"
    port_range       = "7080"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Allow all outbound TCP traffic.
  outbound_rule {
    protocol              = "tcp"
    port_range            = "all"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Allow all outbound UDP traffic.
  outbound_rule {
    protocol              = "udp"
    port_range            = "all"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}

# -------------------------------------------------------------------
# Output Droplet IP Address
# -------------------------------------------------------------------
# Expose the droplet’s public IP address for user access.
output "droplet_ip" {
  description = "Public IPv4 address of the IoT droplet"
  value       = digitalocean_droplet.droplet.ipv4_address
}