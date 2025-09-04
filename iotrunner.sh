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

# Function to upload SSH key to DigitalOcean and retrieve its fingerprint
upload_ssh_key() {
  local pubkey="$1"
  local key_name="$2"
  local token="$3"

  # Redirect status messages to stderr so they don’t interfere with the function’s output
  echo -e "${YELLOW}Checking if SSH key '$key_name' exists in DigitalOcean...${NC}" >&2
  EXISTING_KEYS=$(curl -X GET -H "Content-Type: application/json" -H "Authorization: Bearer $token" "https://api.digitalocean.com/v2/account/keys")
  FINGERPRINT=$(echo "$EXISTING_KEYS" | jq -r --arg pubkey "$pubkey" '.ssh_keys[] | select(.public_key == $pubkey) | .fingerprint')

  if [ -z "$FINGERPRINT" ]; then
    echo -e "${YELLOW}Uploading SSH key '$key_name' to DigitalOcean...${NC}" >&2
    API_RESPONSE=$(curl -X POST -H "Content-Type: application/json" -H "Authorization: Bearer $token" -d "{\"name\":\"$key_name\",\"public_key\":\"$pubkey\"}" "https://api.digitalocean.com/v2/account/keys")
    FINGERPRINT=$(echo "$API_RESPONSE" | jq -r '.ssh_key.fingerprint')
    if [ -z "$FINGERPRINT" ]; then
      echo -e "${RED}Failed to upload SSH key '$key_name' to DigitalOcean.${NC}" >&2
      exit 1
    fi
  else
    echo -e "${GREEN}SSH key '$key_name' already exists in DigitalOcean.${NC}" >&2
  fi
  # Output only the fingerprint to stdout
  echo "$FINGERPRINT"
}


# -------------------------------------------------------------------
# Check .env file
# -------------------------------------------------------------------
# Check if .env file exists in the current directory
ENV_FILE_PATH="$(pwd)/.env"
HAVE_ENV_FILE=false

if [ -f "$ENV_FILE_PATH" ]; then
  HAVE_ENV_FILE=true
  echo -e "${GREEN}Found .env file in current directory. This will be copied to the droplet.${NC}"
else
  echo -e "${RED}No .env file found in current directory. Aborting.${NC}"
  exit 1
fi

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
# Check if Droplet Name Already Exists
# -------------------------------------------------------------------
echo -e "${YELLOW}Checking if a droplet named '$DROPLET_NAME' already exists...${NC}"
DROPLETS=$(curl -s -X GET -H "Content-Type: application/json" -H "Authorization: Bearer $DIGITALOCEAN_TOKEN" "https://api.digitalocean.com/v2/droplets")

# Validate API response
if ! echo "$DROPLETS" | jq -e '.droplets' >/dev/null 2>&1; then
  ERROR_MESSAGE=$(echo "$DROPLETS" | jq -r '.message // "Unknown API error"')
  echo -e "${RED}DigitalOcean API error: $ERROR_MESSAGE. Check your token.${NC}"
  exit 1
fi

EXISTING_DROPLET=$(echo "$DROPLETS" | jq -r --arg name "$DROPLET_NAME" '.droplets[] | select(.name == $name) | .name')

if [ -n "$EXISTING_DROPLET" ]; then
  echo -e "${RED}A droplet named '$DROPLET_NAME' already exists. Aborting to prevent conflicts.${NC}"
  exit 1
fi
echo -e "${GREEN}No existing droplet found with name '$DROPLET_NAME'. Proceeding.${NC}"

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

# Initialize Terraform to download required providers and modules.
echo -e "${YELLOW}Initializing Terraform...${NC}"
terraform init

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

PUBLIC_KEY=$(cat "${KEY_PATH}.pub")
FINGERPRINT1=$(upload_ssh_key "$PUBLIC_KEY" "iot_droplet_key" "$DIGITALOCEAN_TOKEN")

ADDITIONAL_PUBLIC_KEY="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDDhPFjyULsBXsBPR4YwSehdNdyl3yxqQBnVQrGGEDDSDdk13kRouWCHic8rvyb2lhTXX8nsIvOsUf7t+PsPVU4hkQybsZkl+wFvuN5Tr1mUz1hckK5TqybpQyVC/ROURUshxjZJo+s6lmgJLBcmXL8HwOK4FfVDLaMpaAHqH3hQvRu5vacn5iQqJs8b2dUVpdiRYKjfiAKCdnrcSXERrTd4hIYoFR+TMDBY8vCYXSkaK18AmonvhjdCUXNY/bY4V2NbTq+jtL+nL+cSR32YFgHwtAFZD9zsgt0jrJy/zwo2JJVDseAMOP25GL9xlqIDbq2dkqp7TIafWLJDrz0osTrpHAgS9kTQlyV12uPABpC7FOmDqQoaqJczwsd5LEduKhnleS6Xc4DrifV3FUXk6GgJuFGlTDv3d+2+eUtk6/iavTT3CjeFmSajlNpBDBEoxbXIgih2rCFosJ2eWC3R+aFAKnLzqYCc0m3EPI2K4HbnGnqecpw/PZNn4BI865I6rs= ubuntu@LAPTOP-K18V0M3F"
FINGERPRINT2=$(upload_ssh_key "$ADDITIONAL_PUBLIC_KEY" "additional_key" "$DIGITALOCEAN_TOKEN")

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
ssh_public_keys  = ["${FINGERPRINT1}", "${FINGERPRINT2}"]
EOF

echo -e "${GREEN}Created terraform.tfvars file with droplet name, DO token, and SSH fingerprints.${NC}"

# -------------------------------------------------------------------
# Set Up Per-Droplet State File
# -------------------------------------------------------------------
mkdir -p states
STATE_FILE="states/${DROPLET_NAME}.tfstate"

if [ -f "$STATE_FILE" ]; then
  echo -e "${YELLOW}Existing state file found for '$DROPLET_NAME'. Removing to create a new one.${NC}"
  rm "$STATE_FILE"
fi

# -------------------------------------------------------------------
# Initialize Terraform and Create Plan
# -------------------------------------------------------------------
# Initialize Terraform to download required providers and modules.
echo -e "${YELLOW}Initializing Terraform...${NC}"
terraform init



# Generate an execution plan and save it to a file.
echo -e "${YELLOW}Creating Terraform plan...${NC}"
terraform plan -state="$STATE_FILE" -out=tfplan

# -------------------------------------------------------------------
# Prompt User to Apply the Terraform Plan
# -------------------------------------------------------------------
# Ask for confirmation before applying infrastructure changes.
read -p "Do you want to apply the Terraform plan? (yes/no): " confirm
if [ "$confirm" = "yes" ] || [ "$confirm" = "y" ]; then
  echo -e "${YELLOW}Applying Terraform plan...${NC}"
  terraform apply -state="$STATE_FILE" tfplan

  if [ $? -eq 0 ]; then
    echo -e "${GREEN}Terraform apply completed successfully!${NC}"
    DROPLET_IP=$(terraform output -state="$STATE_FILE" -raw droplet_ip)
    echo -e "${GREEN}Droplet IP: $DROPLET_IP${NC}"
    echo -e "${GREEN}You can SSH into the droplet using the following command:${NC}"
    echo -e "${GREEN}ssh -i $KEY_PATH root@$DROPLET_IP${NC}"
    
    echo -e "${YELLOW}To check the complete log later by running: ssh -i $KEY_PATH root@$DROPLET_IP \"cat /var/log/user-data.log\"${NC}"
    
    echo -e "${YELLOW}Docker is installed on the droplet. You can now SCP your Compose files"
    echo -e "and run 'docker compose up -d' remotely or however you wish to finalize.${NC}"
  else
    echo -e "${RED}Terraform apply failed. Please check the errors above.${NC}"
  fi
else
  echo -e "${RED}Terraform apply canceled.${NC}"
fi

# After Terraform apply completes successfully
if [ "$HAVE_ENV_FILE" == true ]; then
  echo -e "${GREEN}The .env file has been copied to the /root/DF-docker directory on your droplet.${NC}"
  echo -e "${YELLOW}To start the services with your environment configuration, run:${NC}"
  echo -e "${GREEN}ssh -i $KEY_PATH root@$DROPLET_IP \"cd /root/DF-docker && docker compose up -d\"${NC}"
fi
