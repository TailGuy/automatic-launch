# Automatic DigitalOcean droplet launching
This documentation helps you set up an IoT droplet on DigitalOcean using the "Automatic Launch" script and TerraForm configuration. It’s designed to make the process smooth, handling everything from SSH keys to deploying your droplet.
- [Prerequisites](#prerequisites)
- [Getting Started](#getting-started)
- [About](#about)
  - [iotrunner.sh](#iotrunnersh)
  - [main.tf](#maintf)
    - [Droplet Configuration](#droplet-configuration)
    - [Firewall Rules](#firewall-rules)

## Prerequisites
Before proceeding, you must make sure that
- You have a DigitalOcean account with a valid API token.
- A Bash environment with sudo privileges.

## Getting Started
Clone the repository:
```bash
git clone https://github.com/TheGoodGamerGuy/automatic-launch.git
```
cd into the directory:
```bash
cd ./automatic-launch
```
> [!WARNING]
> Make sure to create a `.env` file by using the `.envtemplate`
> ```
> cp ./.envtemplate ./.env
> sudo nano .env
> ```
Ensure the iotrunner.sh script is executable by running:
```bash
sudo chmod +x ./iotrunner.sh
```
Then, run the script:
```bash
./iotrunner.sh
```
The script will now prompt you for a droplet name and your DigitalOcean API token.

It will then automatically create a DigitalOcean droplet and generate an ssh command to connect to the droplet.

---

## About
### `iotrunner.sh`
The `iotrunner.sh` script prepares the information for the terraform script.
- **Tool Installation**: Installs TerraForm and jq.
- **SSH Key Management**: Checks for an SSH key named iot_droplet_key at $HOME/.ssh/iot_droplet_key. If it doesn't exist, it generates a new key pair. The private key is saved locally for login (and must not be shared), while the public key is checked against DigitalOcean's API at https://api.digitalocean.com/v2/account/keys. If not present, it uploads the public key using a POST API call with JSON data like {"name":"iot_droplet_key","public_key":"$PUBLIC_KEY"}.
- **TerraForm Initialization**: Creates a terraform.tfvars file containing the user-provided droplet name, DigitalOcean API token, and the SSH key fingerprint.
- **TerraForm Execution**: Initializes TerraForm, creates an execution plan, and prompts the user to confirm before applying the plan. If confirmed, it provisions the DigitalOcean droplet and associated firewall, displaying the droplet's IP address and SSH connection instructions upon success.
- **Finally**: Displays the droplet IP address and generates an SSH command which you can use to connect to the server using SSH and check logs.

### `main.tf`
The `main.tf` Terraform script provisions the DigitalOcean droplet:
- **Terraform Configuration**: Specifies DigitalOcean provider and version.
- **Create DigitalOcean Droplet**: Creates a DigitalOcean Droplet with the set Droplet Configuration.
- **Copy environment variables**: Copies `.env` file to the newly created Droplet.
#### Droplet Configuration
| **Component**        | **Details**                                                                 |
|-----------------------|-----------------------------------------------------------------------------|
| Operating System      | Ubuntu 24.04 x64                                                           |
| Region                | Frankfurt 1 (fra1)                                                         |
| Droplet Size          | 2 vCPUs, 4 GB RAM (s-2vcpu-4gb)                                            |
| Monitoring            | True                                                                       |
| Logging Location      | `/var/log/user-data.log`                                                   |
| Pre-Installed Tools   | Docker, Docker Compose                                                     |
| Environment variables | Copies `.env` from main machine to Droplet                                 |
- **User Data**: Installs Docker packages and creates a non-root user. You have to use the -y argument for install commands because it is a non interactable environment.
### Firewall Rules
#### Inbound Rules
| Port | Service   |
|------|-----------|
| 22   | SSH       |
| 3000 | Grafana   |
| 1883 | MQTT      |
| 8086 | InfluxDB  |
| 9000 | Portainer |
##### For production remove all inbound rules except for SSH
#### Outbound Rules
All TCP and UDP traffic is allowed to any destination.

