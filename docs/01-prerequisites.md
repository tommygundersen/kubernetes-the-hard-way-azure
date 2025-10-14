# Prerequisites

In this lab you will review the infrastructure requirements and set up the necessary tools.

## Infrastructure Overview

The infrastructure has been provisioned using the bootstrap script and consists of:

### Network Architecture
- **Virtual Network**: `vnet-k8s` with CIDR `10.0.0.0/16`
- **NAT Gateway**: Provides outbound internet access for all VMs
- **Azure Bastion**: Secure access to VMs without public IPs

### Virtual Machines
- **Jumpbox**: `vm-jumpbox` at `10.0.2.10` - Your main access point
- **Control Plane**: `vm-control-plane` at `10.0.3.10` - Kubernetes master node
- **Worker 1**: `vm-worker-1` at `10.0.3.20` - Kubernetes worker node
- **Worker 2**: `vm-worker-2` at `10.0.3.21` - Kubernetes worker node

All VMs run Ubuntu 22.04 LTS and use the `azureuser` account.

## Connecting to the Infrastructure

### Step 1: Connect to Jumpbox via Azure Bastion

1. Open the Azure Portal
2. Navigate to your resource group `rg-k8s-the-hard-way`
3. Click on the `vm-jumpbox` virtual machine
4. Click "Connect" and select "Bastion"
5. Use the username `azureuser` and SSH key authentication

### Step 2: Set Up the Jumpbox

Once connected to the jumpbox, install required tools:

```bash
# Update package lists
sudo apt-get update

# Install required packages
sudo apt-get install -y \
    curl \
    wget \
    git \
    vim \
    jq \
    openssl

# Install kubectl
curl -LO "https://dl.k8s.io/release/v1.28.0/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# Install cfssl and cfssljson for certificate generation
wget -q --show-progress --https-only --timestamping \
    https://github.com/cloudflare/cfssl/releases/download/v1.6.4/cfssl_1.6.4_linux_amd64 \
    https://github.com/cloudflare/cfssl/releases/download/v1.6.4/cfssljson_1.6.4_linux_amd64

chmod +x cfssl_1.6.4_linux_amd64 cfssljson_1.6.4_linux_amd64
sudo mv cfssl_1.6.4_linux_amd64 /usr/local/bin/cfssl
sudo mv cfssljson_1.6.4_linux_amd64 /usr/local/bin/cfssljson

# Verify installations
kubectl version --client
cfssl version
```

### Step 3: Clone the Repository

```bash
# Clone the repository
cd ~
git clone https://github.com/your-username/kubernetes-the-hard-way-azure.git
cd kubernetes-the-hard-way-azure

# Make scripts executable
chmod +x scripts/*.sh
```

### Step 4: Set Up SSH Access to Kubernetes VMs

You need to set up SSH access from the jumpbox to the Kubernetes VMs. The SSH private key should be available on the jumpbox.

1. Create the SSH directory and set permissions:
```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
```

2. Copy the SSH private key to the jumpbox. You can either:
   - Copy it manually through the Bastion session
   - Use the setup script provided

3. Set the correct permissions:
```bash
chmod 600 ~/.ssh/id_rsa
```

4. Test SSH connectivity:
```bash
# Test connection to control plane
ssh -o StrictHostKeyChecking=no azureuser@10.0.3.10 'hostname'

# Test connection to worker nodes
ssh -o StrictHostKeyChecking=no azureuser@10.0.3.20 'hostname'
ssh -o StrictHostKeyChecking=no azureuser@10.0.3.21 'hostname'
```

You should see the hostnames of each VM if the SSH connections are successful.

### Step 5: Verify VM Connectivity

Create a helper script to easily SSH into each VM:

```bash
cat > ~/ssh-vms.sh << 'EOF'
#!/bin/bash

case "$1" in
    control|control-plane|cp)
        ssh azureuser@10.0.3.10
        ;;
    worker1|w1)
        ssh azureuser@10.0.3.20
        ;;
    worker2|w2)
        ssh azureuser@10.0.3.21
        ;;
    *)
        echo "Usage: $0 {control|worker1|worker2}"
        echo "  control - Connect to control plane (10.0.3.10)"
        echo "  worker1 - Connect to worker node 1 (10.0.3.20)"
        echo "  worker2 - Connect to worker node 2 (10.0.3.21)"
        ;;
esac
EOF

chmod +x ~/ssh-vms.sh
```

Now you can easily connect to any VM:
```bash
# Connect to control plane
./ssh-vms.sh control

# Connect to worker nodes
./ssh-vms.sh worker1
./ssh-vms.sh worker2
```

## Network Configuration

Set up environment variables for the lab:

```bash
cat > ~/k8s-env.sh << 'EOF'
#!/bin/bash

# Kubernetes cluster configuration
export KUBERNETES_VERSION="v1.28.0"
export ETCD_VERSION="v3.5.9"
export CONTAINERD_VERSION="1.7.2"
export CNI_VERSION="v1.3.0"

# Network configuration
export SERVICE_CIDR="10.100.0.0/16"
export POD_CIDR="10.200.0.0/16"
export CLUSTER_DNS_IP="10.100.0.10"

# VM IP addresses
export CONTROL_PLANE_IP="10.0.3.10"
export WORKER_1_IP="10.0.3.20"
export WORKER_2_IP="10.0.3.21"

# VM hostnames
export CONTROL_PLANE_HOSTNAME="vm-control-plane"
export WORKER_1_HOSTNAME="vm-worker-1"
export WORKER_2_HOSTNAME="vm-worker-2"
EOF

# Source the environment variables
source ~/k8s-env.sh

# Add to .bashrc so it's always available
echo "source ~/k8s-env.sh" >> ~/.bashrc
```

## Verification

Verify that all prerequisites are met:

```bash
# Check tool versions
echo "=== Tool Versions ==="
kubectl version --client
cfssl version
echo ""

# Check SSH connectivity
echo "=== SSH Connectivity ==="
ssh -o StrictHostKeyChecking=no azureuser@$CONTROL_PLANE_IP 'echo "Control plane: $(hostname)"'
ssh -o StrictHostKeyChecking=no azureuser@$WORKER_1_IP 'echo "Worker 1: $(hostname)"'
ssh -o StrictHostKeyChecking=no azureuser@$WORKER_2_IP 'echo "Worker 2: $(hostname)"'
echo ""

# Check environment variables
echo "=== Environment Variables ==="
echo "Kubernetes Version: $KUBERNETES_VERSION"
echo "Service CIDR: $SERVICE_CIDR"
echo "Pod CIDR: $POD_CIDR"
echo "Control Plane IP: $CONTROL_PLANE_IP"
echo "Worker 1 IP: $WORKER_1_IP"
echo "Worker 2 IP: $WORKER_2_IP"
```

If all checks pass, you're ready to proceed to the next lab: [Certificate Authority](02-certificate-authority.md).

## Troubleshooting

### SSH Connection Issues

If you can't connect to the VMs:

1. Verify the SSH private key is correctly placed in `~/.ssh/id_rsa`
2. Check the key permissions: `ls -la ~/.ssh/`
3. Test with verbose output: `ssh -v azureuser@10.0.3.10`

### Tool Installation Issues

If tools fail to install:

1. Check internet connectivity: `curl -I https://google.com`
2. Verify the NAT Gateway is working
3. Try updating package lists: `sudo apt-get update`

### Environment Variables

If environment variables are not set:

```bash
source ~/k8s-env.sh
```

Next: [Certificate Authority](02-certificate-authority.md)