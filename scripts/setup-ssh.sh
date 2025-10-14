#!/bin/bash

# SSH Key Setup Script for Kubernetes the Hard Way
# This script helps set up SSH connectivity between jumpbox and Kubernetes VMs

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Configuration (should match bootstrap script)
RESOURCE_GROUP="rg-k8s-the-hard-way"
SSH_KEY_NAME="k8s-ssh-key"
SSH_KEY_PATH="$HOME/.ssh/${SSH_KEY_NAME}"
ADMIN_USERNAME="azureuser"

# VM IPs
JUMPBOX_IP="10.0.2.10"
CONTROL_PLANE_IP="10.0.3.10"
WORKER_1_IP="10.0.3.20"
WORKER_2_IP="10.0.3.21"

usage() {
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  generate    Generate SSH key pair"
    echo "  setup       Set up SSH keys on jumpbox (run from local machine)"
    echo "  test        Test SSH connectivity from jumpbox to all VMs"
    echo "  copy-files  Copy repository files to jumpbox"
    echo ""
}

generate_ssh_keys() {
    header "Generating SSH Keys"
    
    if [ -f "${SSH_KEY_PATH}" ]; then
        warn "SSH key already exists at ${SSH_KEY_PATH}"
        read -p "Overwrite? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Skipping SSH key generation"
            return 0
        fi
    fi
    
    log "Generating new SSH key pair..."
    ssh-keygen -t rsa -b 4096 -f "${SSH_KEY_PATH}" -N "" -C "k8s-the-hard-way"
    chmod 600 "${SSH_KEY_PATH}"
    chmod 644 "${SSH_KEY_PATH}.pub"
    log "SSH key generated at ${SSH_KEY_PATH}"
}

setup_ssh_on_jumpbox() {
    header "Setting up SSH on Jumpbox"
    
    if [ ! -f "${SSH_KEY_PATH}" ]; then
        error "SSH key not found at ${SSH_KEY_PATH}. Run 'generate' command first."
        exit 1
    fi
    
    log "This will help you copy the SSH private key to the jumpbox"
    log "You need to connect to the jumpbox via Azure Bastion first"
    echo
    warn "Manual steps required:"
    warn "1. Connect to jumpbox via Azure Bastion in Azure Portal"
    warn "2. Open terminal on jumpbox"
    warn "3. Run the following commands on the jumpbox:"
    echo
    echo "mkdir -p ~/.ssh"
    echo "chmod 700 ~/.ssh"
    echo "nano ~/.ssh/id_rsa"
    echo
    warn "4. Copy the content below into the file:"
    echo
    cat "${SSH_KEY_PATH}"
    echo
    warn "5. Set correct permissions:"
    echo "chmod 600 ~/.ssh/id_rsa"
    echo
    log "After completing these steps, you can test connectivity with: $0 test"
}

test_ssh_connectivity() {
    header "Testing SSH Connectivity"
    
    log "This script should be run FROM the jumpbox"
    log "Testing SSH connectivity to Kubernetes VMs..."
    
    # Test connectivity to control plane
    log "Testing connection to control plane (${CONTROL_PLANE_IP})..."
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 ${ADMIN_USERNAME}@${CONTROL_PLANE_IP} 'echo "Control plane connection successful"'; then
        log "✓ Control plane connection successful"
    else
        error "✗ Failed to connect to control plane"
    fi
    
    # Test connectivity to worker 1
    log "Testing connection to worker 1 (${WORKER_1_IP})..."
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 ${ADMIN_USERNAME}@${WORKER_1_IP} 'echo "Worker 1 connection successful"'; then
        log "✓ Worker 1 connection successful"
    else
        error "✗ Failed to connect to worker 1"
    fi
    
    # Test connectivity to worker 2
    log "Testing connection to worker 2 (${WORKER_2_IP})..."
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 ${ADMIN_USERNAME}@${WORKER_2_IP} 'echo "Worker 2 connection successful"'; then
        log "✓ Worker 2 connection successful"
    else
        error "✗ Failed to connect to worker 2"
    fi
    
    log "SSH connectivity test completed"
}

copy_files_to_jumpbox() {
    header "Copying Repository Files to Jumpbox"
    
    log "This will create scripts to help copy files to jumpbox"
    
    # Create a script that can be run on the jumpbox to download files
    cat > ./download-repo.sh << 'EOF'
#!/bin/bash
# Run this script on the jumpbox to download the repository

log() {
    echo -e "\033[0;32m[INFO]\033[0m $1"
}

log "Installing git if not present..."
sudo apt-get update
sudo apt-get install -y git

log "Cloning kubernetes-the-hard-way-azure repository..."
cd ~
if [ -d "kubernetes-the-hard-way-azure" ]; then
    log "Repository already exists, pulling latest changes..."
    cd kubernetes-the-hard-way-azure
    git pull
else
    git clone https://github.com/your-username/kubernetes-the-hard-way-azure.git
    cd kubernetes-the-hard-way-azure
fi

log "Making scripts executable..."
chmod +x scripts/*.sh

log "Repository setup complete!"
log "You can now follow the documentation in docs/ to set up Kubernetes"
EOF
    
    chmod +x ./download-repo.sh
    
    log "Created download-repo.sh"
    log "Copy this script to the jumpbox and run it to download the repository"
}

# Main script logic
case "${1:-}" in
    generate)
        generate_ssh_keys
        ;;
    setup)
        setup_ssh_on_jumpbox
        ;;
    test)
        test_ssh_connectivity
        ;;
    copy-files)
        copy_files_to_jumpbox
        ;;
    *)
        usage
        exit 1
        ;;
esac