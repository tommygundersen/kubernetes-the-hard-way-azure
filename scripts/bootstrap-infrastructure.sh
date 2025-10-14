#!/bin/bash

# Kubernetes the Hard Way - Azure Infrastructure Bootstrap
# This script provisions the entire Azure infrastructure required for the Kubernetes cluster
# 
# Infrastructure includes:
# - Virtual Network with NAT Gateway
# - Azure Bastion (Developer Edition)
# - Jumpbox VM
# - Kubernetes VMs (1 control plane + 2 workers)
# - SSH keys for secure access

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

header() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
}

# Configuration
RESOURCE_GROUP="rg-k8s-the-hard-way"
LOCATION="westeurope"
VNET_NAME="vnet-k8s"
VNET_CIDR="10.0.0.0/16"

# Subnet configuration
BASTION_SUBNET_NAME="AzureBastionSubnet"
BASTION_SUBNET_CIDR="10.0.1.0/24"
JUMPBOX_SUBNET_NAME="snet-jumpbox"
JUMPBOX_SUBNET_CIDR="10.0.2.0/24"
K8S_SUBNET_NAME="snet-k8s"
K8S_SUBNET_CIDR="10.0.3.0/24"

# NAT Gateway
NAT_GATEWAY_NAME="nat-k8s"
PUBLIC_IP_NAT_NAME="pip-nat-k8s"

# Bastion
BASTION_NAME="bas-k8s"
BASTION_PUBLIC_IP_NAME="pip-bastion-k8s"

# Network Security Groups
NSG_JUMPBOX_NAME="nsg-jumpbox"
NSG_K8S_NAME="nsg-k8s"

# Virtual Machines
JUMPBOX_VM_NAME="vm-jumpbox"
CONTROL_PLANE_VM_NAME="vm-control-plane"
WORKER_1_VM_NAME="vm-worker-1"
WORKER_2_VM_NAME="vm-worker-2"

# VM Configuration
VM_SIZE="Standard_B2s"
VM_IMAGE="Ubuntu2204"
ADMIN_USERNAME="azureuser"

# Kubernetes Configuration
SERVICE_CIDR="10.100.0.0/16"
POD_CIDR="10.200.0.0/16"
CLUSTER_DNS_IP="10.100.0.10"

# SSH Key configuration
SSH_KEY_NAME="k8s-ssh-key"
SSH_KEY_PATH="$HOME/.ssh/${SSH_KEY_NAME}"

header "Starting Azure Infrastructure Bootstrap for Kubernetes the Hard Way"

# Check if user is logged in to Azure
if ! az account show > /dev/null 2>&1; then
    error "Please log in to Azure first using 'az login'"
    exit 1
fi

# Get current subscription
SUBSCRIPTION_ID=$(az account show --query id --output tsv)
log "Using subscription: $(az account show --query name --output tsv) ($SUBSCRIPTION_ID)"

header "Generating SSH Keys"

# Generate SSH key if it doesn't exist
if [ ! -f "${SSH_KEY_PATH}" ]; then
    log "Generating new SSH key pair..."
    ssh-keygen -t rsa -b 4096 -f "${SSH_KEY_PATH}" -N "" -C "k8s-the-hard-way"
    chmod 600 "${SSH_KEY_PATH}"
    chmod 644 "${SSH_KEY_PATH}.pub"
    log "SSH key generated at ${SSH_KEY_PATH}"
else
    log "SSH key already exists at ${SSH_KEY_PATH}"
fi

header "Creating Resource Group"

# Create resource group
if ! az group show --name "$RESOURCE_GROUP" > /dev/null 2>&1; then
    log "Creating resource group: $RESOURCE_GROUP"
    az group create --name "$RESOURCE_GROUP" --location "$LOCATION"
else
    log "Resource group $RESOURCE_GROUP already exists"
fi

header "Creating Virtual Network and Subnets"

# Create virtual network
log "Creating virtual network: $VNET_NAME"
az network vnet create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VNET_NAME" \
    --address-prefix "$VNET_CIDR" \
    --location "$LOCATION"

# Create subnets
log "Creating Bastion subnet"
az network vnet subnet create \
    --resource-group "$RESOURCE_GROUP" \
    --vnet-name "$VNET_NAME" \
    --name "$BASTION_SUBNET_NAME" \
    --address-prefix "$BASTION_SUBNET_CIDR"

log "Creating Jumpbox subnet"
az network vnet subnet create \
    --resource-group "$RESOURCE_GROUP" \
    --vnet-name "$VNET_NAME" \
    --name "$JUMPBOX_SUBNET_NAME" \
    --address-prefix "$JUMPBOX_SUBNET_CIDR"

log "Creating Kubernetes subnet"
az network vnet subnet create \
    --resource-group "$RESOURCE_GROUP" \
    --vnet-name "$VNET_NAME" \
    --name "$K8S_SUBNET_NAME" \
    --address-prefix "$K8S_SUBNET_CIDR"

header "Creating NAT Gateway"

# Create public IP for NAT Gateway
log "Creating public IP for NAT Gateway"
az network public-ip create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$PUBLIC_IP_NAT_NAME" \
    --sku Standard \
    --allocation-method Static

# Create NAT Gateway
log "Creating NAT Gateway"
az network nat gateway create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$NAT_GATEWAY_NAME" \
    --public-ip-addresses "$PUBLIC_IP_NAT_NAME" \
    --idle-timeout 10

# Associate NAT Gateway with subnets (excluding Bastion subnet)
log "Associating NAT Gateway with subnets"
az network vnet subnet update \
    --resource-group "$RESOURCE_GROUP" \
    --vnet-name "$VNET_NAME" \
    --name "$JUMPBOX_SUBNET_NAME" \
    --nat-gateway "$NAT_GATEWAY_NAME"

az network vnet subnet update \
    --resource-group "$RESOURCE_GROUP" \
    --vnet-name "$VNET_NAME" \
    --name "$K8S_SUBNET_NAME" \
    --nat-gateway "$NAT_GATEWAY_NAME"

header "Creating Network Security Groups"

# Create NSG for Jumpbox
log "Creating NSG for Jumpbox"
az network nsg create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$NSG_JUMPBOX_NAME"

# Create NSG rules for Jumpbox
az network nsg rule create \
    --resource-group "$RESOURCE_GROUP" \
    --nsg-name "$NSG_JUMPBOX_NAME" \
    --name "SSH" \
    --protocol tcp \
    --priority 1001 \
    --destination-port-range 22 \
    --source-address-prefixes "$BASTION_SUBNET_CIDR" \
    --access allow

# Create NSG for Kubernetes nodes
log "Creating NSG for Kubernetes nodes"
az network nsg create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$NSG_K8S_NAME"

# Create NSG rules for Kubernetes
# Allow SSH from jumpbox subnet
az network nsg rule create \
    --resource-group "$RESOURCE_GROUP" \
    --nsg-name "$NSG_K8S_NAME" \
    --name "SSH-from-jumpbox" \
    --protocol tcp \
    --priority 1001 \
    --destination-port-range 22 \
    --source-address-prefixes "$JUMPBOX_SUBNET_CIDR" \
    --access allow

# Allow Kubernetes API server
az network nsg rule create \
    --resource-group "$RESOURCE_GROUP" \
    --nsg-name "$NSG_K8S_NAME" \
    --name "K8s-API" \
    --protocol tcp \
    --priority 1002 \
    --destination-port-range 6443 \
    --source-address-prefixes "$K8S_SUBNET_CIDR" "$JUMPBOX_SUBNET_CIDR" \
    --access allow

# Allow etcd
az network nsg rule create \
    --resource-group "$RESOURCE_GROUP" \
    --nsg-name "$NSG_K8S_NAME" \
    --name "etcd" \
    --protocol tcp \
    --priority 1003 \
    --destination-port-range 2379-2380 \
    --source-address-prefixes "$K8S_SUBNET_CIDR" \
    --access allow

# Allow kubelet
az network nsg rule create \
    --resource-group "$RESOURCE_GROUP" \
    --nsg-name "$NSG_K8S_NAME" \
    --name "kubelet" \
    --protocol tcp \
    --priority 1004 \
    --destination-port-range 10250 \
    --source-address-prefixes "$K8S_SUBNET_CIDR" \
    --access allow

# Allow NodePort services
az network nsg rule create \
    --resource-group "$RESOURCE_GROUP" \
    --nsg-name "$NSG_K8S_NAME" \
    --name "NodePort" \
    --protocol tcp \
    --priority 1005 \
    --destination-port-range 30000-32767 \
    --source-address-prefixes "$K8S_SUBNET_CIDR" "$JUMPBOX_SUBNET_CIDR" \
    --access allow

# Associate NSGs with subnets
log "Associating NSGs with subnets"
az network vnet subnet update \
    --resource-group "$RESOURCE_GROUP" \
    --vnet-name "$VNET_NAME" \
    --name "$JUMPBOX_SUBNET_NAME" \
    --network-security-group "$NSG_JUMPBOX_NAME"

az network vnet subnet update \
    --resource-group "$RESOURCE_GROUP" \
    --vnet-name "$VNET_NAME" \
    --name "$K8S_SUBNET_NAME" \
    --network-security-group "$NSG_K8S_NAME"

header "Creating Azure Bastion"

# Create public IP for Bastion
log "Creating public IP for Bastion"
az network public-ip create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$BASTION_PUBLIC_IP_NAME" \
    --sku Standard \
    --allocation-method Static

# Create Bastion (Developer Edition - free tier)
log "Creating Azure Bastion (Developer Edition)"
az network bastion create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$BASTION_NAME" \
    --public-ip-address "$BASTION_PUBLIC_IP_NAME" \
    --vnet-name "$VNET_NAME" \
    --sku Developer

header "Creating Virtual Machines"

# Function to create VM
create_vm() {
    local vm_name=$1
    local subnet_name=$2
    local private_ip=$3
    
    log "Creating VM: $vm_name"
    az vm create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$vm_name" \
        --image "$VM_IMAGE" \
        --size "$VM_SIZE" \
        --admin-username "$ADMIN_USERNAME" \
        --ssh-key-values "${SSH_KEY_PATH}.pub" \
        --vnet-name "$VNET_NAME" \
        --subnet "$subnet_name" \
        --private-ip-address "$private_ip" \
        --public-ip-address "" \
        --accelerated-networking false \
        --storage-sku Standard_LRS
}

# Create VMs with static private IPs
create_vm "$JUMPBOX_VM_NAME" "$JUMPBOX_SUBNET_NAME" "10.0.2.10"
create_vm "$CONTROL_PLANE_VM_NAME" "$K8S_SUBNET_NAME" "10.0.3.10"
create_vm "$WORKER_1_VM_NAME" "$K8S_SUBNET_NAME" "10.0.3.20"
create_vm "$WORKER_2_VM_NAME" "$K8S_SUBNET_NAME" "10.0.3.21"

header "Configuring SSH Keys on VMs"

# Function to copy SSH private key to jumpbox
copy_ssh_key_to_jumpbox() {
    log "Copying SSH private key to jumpbox..."
    
    # Wait for VM to be ready
    sleep 30
    
    # Use Bastion to connect to jumpbox and copy the private key
    # Note: This requires the Azure CLI extension for Bastion
    local temp_key_file="/tmp/k8s-private-key"
    cp "${SSH_KEY_PATH}" "$temp_key_file"
    
    # Copy the private key to jumpbox using az network bastion ssh
    az network bastion ssh \
        --name "$BASTION_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --target-resource-id "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Compute/virtualMachines/$JUMPBOX_VM_NAME" \
        --auth-type ssh-key \
        --username "$ADMIN_USERNAME" \
        --ssh-key "${SSH_KEY_PATH}" \
        --command "mkdir -p ~/.ssh && chmod 700 ~/.ssh" || true
    
    # Create a script to transfer the private key
    cat > /tmp/setup_ssh.sh << 'EOF'
#!/bin/bash
# This script will be run on the jumpbox to set up SSH access
mkdir -p ~/.ssh
chmod 700 ~/.ssh
EOF
    
    log "SSH key configuration completed. You'll need to manually copy the private key to the jumpbox after connecting via Bastion."
}

copy_ssh_key_to_jumpbox

header "Creating Configuration Files"

# Create a configuration file with all the details
cat > "$HOME/k8s-hard-way-config.sh" << EOF
#!/bin/bash
# Kubernetes the Hard Way - Configuration

# Resource Group and Location
export RESOURCE_GROUP="$RESOURCE_GROUP"
export LOCATION="$LOCATION"

# Network Configuration
export VNET_NAME="$VNET_NAME"
export VNET_CIDR="$VNET_CIDR"
export SERVICE_CIDR="$SERVICE_CIDR"
export POD_CIDR="$POD_CIDR"
export CLUSTER_DNS_IP="$CLUSTER_DNS_IP"

# VM Information
export JUMPBOX_VM_NAME="$JUMPBOX_VM_NAME"
export CONTROL_PLANE_VM_NAME="$CONTROL_PLANE_VM_NAME"
export WORKER_1_VM_NAME="$WORKER_1_VM_NAME"
export WORKER_2_VM_NAME="$WORKER_2_VM_NAME"

# Private IP Addresses
export JUMPBOX_IP="10.0.2.10"
export CONTROL_PLANE_IP="10.0.3.10"
export WORKER_1_IP="10.0.3.20"
export WORKER_2_IP="10.0.3.21"

# SSH Configuration
export SSH_KEY_PATH="$SSH_KEY_PATH"
export ADMIN_USERNAME="$ADMIN_USERNAME"

# Bastion Information
export BASTION_NAME="$BASTION_NAME"
EOF

# Create a script to copy files to jumpbox
cat > "$HOME/copy-to-jumpbox.sh" << EOF
#!/bin/bash
# Script to copy necessary files to jumpbox

echo "Copying SSH private key to jumpbox..."
scp -i "${SSH_KEY_PATH}" "${SSH_KEY_PATH}" ${ADMIN_USERNAME}@10.0.2.10:~/.ssh/id_rsa

echo "Setting correct permissions..."
ssh -i "${SSH_KEY_PATH}" ${ADMIN_USERNAME}@10.0.2.10 "chmod 600 ~/.ssh/id_rsa"

echo "Testing SSH connectivity to Kubernetes nodes..."
ssh -i "${SSH_KEY_PATH}" ${ADMIN_USERNAME}@10.0.2.10 "ssh -o StrictHostKeyChecking=no ${ADMIN_USERNAME}@10.0.3.10 'hostname'"
ssh -i "${SSH_KEY_PATH}" ${ADMIN_USERNAME}@10.0.2.10 "ssh -o StrictHostKeyChecking=no ${ADMIN_USERNAME}@10.0.3.20 'hostname'"
ssh -i "${SSH_KEY_PATH}" ${ADMIN_USERNAME}@10.0.2.10 "ssh -o StrictHostKeyChecking=no ${ADMIN_USERNAME}@10.0.3.21 'hostname'"

echo "SSH setup completed!"
EOF

chmod +x "$HOME/copy-to-jumpbox.sh"

header "Installation Complete!"

echo
log "Azure infrastructure has been successfully provisioned!"
echo
log "Summary of created resources:"
log "  Resource Group: $RESOURCE_GROUP"
log "  Virtual Network: $VNET_NAME ($VNET_CIDR)"
log "  NAT Gateway: $NAT_GATEWAY_NAME"
log "  Azure Bastion: $BASTION_NAME"
echo
log "Virtual Machines:"
log "  Jumpbox: $JUMPBOX_VM_NAME (10.0.2.10)"
log "  Control Plane: $CONTROL_PLANE_VM_NAME (10.0.3.10)"
log "  Worker 1: $WORKER_1_VM_NAME (10.0.3.20)"
log "  Worker 2: $WORKER_2_VM_NAME (10.0.3.21)"
echo
log "SSH Key: ${SSH_KEY_PATH}"
log "Configuration file: $HOME/k8s-hard-way-config.sh"
echo
warn "Next steps:"
warn "1. Connect to the jumpbox using Azure Bastion in the Azure Portal"
warn "2. Clone this repository on the jumpbox"
warn "3. Copy the SSH private key to the jumpbox manually or run: $HOME/copy-to-jumpbox.sh"
warn "4. Follow the documentation in docs/ to set up Kubernetes manually"
echo
log "To connect to jumpbox via Bastion, go to:"
log "https://portal.azure.com/#@/resource/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Compute/virtualMachines/$JUMPBOX_VM_NAME/bastion"
echo
log "Infrastructure bootstrap completed successfully!"