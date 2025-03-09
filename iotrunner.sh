#!/bin/bash
#
# iotrunner.sh
#
# This script automates the creation of a DigitalOcean droplet for IoT services using Terraform.
# It handles SSH key generation and upload, prompts for user inputs, configures Terraform,
# and provides SSH instructions for connecting to the deployed droplet.
#
# Prerequisites:
# - A DigitalOcean account with a valid API token.
# - Bash shell environment with sudo privileges.

# -------------------------------------------------------------------
# Define Color Codes for Terminal Output
# -------------------------------------------------------------------
# Color codes enhance terminal output readability for user feedback.
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Starting IoT infrastructure setup...${NC}"

# -------------------------------------------------------------------
# Prompt User for Droplet Name
# -------------------------------------------------------------------
# Request the user to specify a unique name for the droplet.
echo -e "${YELLOW}Enter the name of the droplet you want to create:${NC}"
read DROPLET_NAME
echo ""

# -------------------------------------------------------------------
# Prompt User for DigitalOcean API Token
# -------------------------------------------------------------------
# Collect the DigitalOcean API token required for authentication.
echo -e "${YELLOW}Enter your DigitalOcean API token:${NC}"
read DIGITALOCEAN_TOKEN
echo ""

# -------------------------------------------------------------------
# Install or Update Terraform and jq
# -------------------------------------------------------------------
# Install Terraform for infrastructure management and jq for JSON parsing of API responses.
echo -e "${YELLOW}Installing/updating Terraform and jq...${NC}"
sudo apt-get update -y
sudo apt-get install -y gnupg software-properties-common curl jq

# Add HashiCorp GPG key and repository for Terraform installation.
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository \
  "deb [arch=amd64] https://apt.releases.hashicorp.com \
  $(lsb_release -cs) main"
sudo apt-get update -y
sudo apt-get install -y terraform

# -------------------------------------------------------------------
# Manage SSH Key for Droplet Access
# -------------------------------------------------------------------
# Set the file path for the SSH key pair.
KEY_PATH="$HOME/.ssh/iot_droplet_key"

# Generate a new SSH key pair if it doesn’t exist, with no passphrase.
if [ ! -f "$KEY_PATH" ]; then
  echo -e "${YELLOW}Generating new SSH key pair...${NC}"
  ssh-keygen -t rsa -b 4096 -f "$KEY_PATH" -N ""
  if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to generate SSH key.${NC}"
    exit 1
  fi
else
  echo -e "${YELLOW}Using existing SSH key: $KEY_PATH${NC}"
fi

# Retrieve the public key content.
PUBLIC_KEY=$(cat "${KEY_PATH}.pub")

# Check if the SSH key is already registered with DigitalOcean.
echo -e "${YELLOW}Checking if SSH key exists in DigitalOcean...${NC}"
EXISTING_KEYS=$(curl -X GET -H "Content-Type: application/json" -H "Authorization: Bearer $DIGITALOCEAN_TOKEN" "https://api.digitalocean.com/v2/account/keys")
FINGERPRINT=$(echo "$EXISTING_KEYS" | jq -r --arg pubkey "$PUBLIC_KEY" '.ssh_keys[] | select(.public_key == $pubkey) | .fingerprint')

# Upload the SSH key to DigitalOcean if it’s not already present.
if [ -z "$FINGERPRINT" ]; then
  echo -e "${YELLOW}Uploading SSH key to DigitalOcean...${NC}"
  API_RESPONSE=$(curl -X POST -H "Content-Type: application/json" -H "Authorization: Bearer $DIGITALOCEAN_TOKEN" -d "{\"name\":\"iot_droplet_key\",\"public_key\":\"$PUBLIC_KEY\"}" "https://api.digitalocean.com/v2/account/keys")
  FINGERPRINT=$(echo "$API_RESPONSE" | jq -r '.ssh_key.fingerprint')
  if [ -z "$FINGERPRINT" ]; then
    echo -e "${RED}Failed to upload SSH key to DigitalOcean.${NC}"
    exit 1
  fi
else
  echo -e "${GREEN}SSH key already exists in DigitalOcean.${NC}"
fi

# -------------------------------------------------------------------
# Create terraform.tfvars File with User-Provided Values
# -------------------------------------------------------------------
# Write user inputs to a Terraform variables file for configuration.
cat << EOF > terraform.tfvars
droplet_name     = "${DROPLET_NAME}"
do_token         = "${DIGITALOCEAN_TOKEN}"
ssh_public_keys  = ["$FINGERPRINT"]
EOF

echo -e "${GREEN}Created terraform.tfvars file with droplet name, DO token, and SSH fingerprint.${NC}"

# -------------------------------------------------------------------
# Initialize Terraform and Create Plan
# -------------------------------------------------------------------
# Initialize Terraform to download required providers and modules.
echo -e "${YELLOW}Initializing Terraform...${NC}"
terraform init

# Generate an execution plan and save it to a file.
echo -e "${YELLOW}Creating Terraform plan...${NC}"
terraform plan -out=tfplan

# -------------------------------------------------------------------
# Prompt User to Apply the Terraform Plan
# -------------------------------------------------------------------
# Ask for confirmation before applying infrastructure changes.
read -p "Do you want to apply the Terraform plan? (yes/no): " confirm
if [ "$confirm" = "yes" ] || [ "$confirm" = "y" ]; then
  echo -e "${YELLOW}Applying Terraform plan...${NC}"
  terraform apply tfplan

  if [ $? -eq 0 ]; then
    echo -e "${GREEN}Terraform apply completed successfully!${NC}"
    DROPLET_IP=$(terraform output -raw droplet_ip)
    echo -e "${GREEN}Droplet IP: $DROPLET_IP${NC}"
    echo -e "${GREEN}You can SSH into the droplet using the following command:${NC}"
    echo -e "${GREEN}ssh -i $KEY_PATH root@$DROPLET_IP${NC}"
    
    # Add instructions for real-time monitoring of user_data output
    echo -e "${YELLOW}To check the complete log later by running: ssh -i $KEY_PATH root@$DROPLET_IP \"cat /var/log/user-data.log\"${NC}"
    
    echo -e "${YELLOW}Docker is installed on the droplet. You can now SCP your Compose files"
    echo -e "and run 'docker compose up -d' remotely or however you wish to finalize.${NC}"
  else
    echo -e "${RED}Terraform apply failed. Please check the errors above.${NC}"
  fi
else
  echo -e "${RED}Terraform apply canceled.${NC}"
fi