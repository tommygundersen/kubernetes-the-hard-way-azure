#!/bin/bash
# Jumpbox initialization script
# This script prepares the jumpbox with required tools for Kubernetes cluster management

set -e

# Update system
apt-get update
apt-get upgrade -y

# Install essential packages
apt-get install -y \
    curl \
    wget \
    git \
    vim \
    htop \
    tree \
    jq \
    unzip \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release

# Install Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# Install kubectl
curl -LO "https://dl.k8s.io/release/v1.28.0/bin/linux/amd64/kubectl"
chmod +x kubectl
mv kubectl /usr/local/bin/

# Install cfssl and cfssljson for certificate management
curl -o /usr/local/bin/cfssl https://github.com/cloudflare/cfssl/releases/download/v1.6.4/cfssl_1.6.4_linux_amd64
curl -o /usr/local/bin/cfssljson https://github.com/cloudflare/cfssl/releases/download/v1.6.4/cfssljson_1.6.4_linux_amd64
chmod +x /usr/local/bin/cfssl /usr/local/bin/cfssljson

# Install Docker (for container image management)
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add admin user to docker group
usermod -aG docker ${admin_username}

# Install Helm
curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | tee /usr/share/keyrings/helm.gpg > /dev/null
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | tee /etc/apt/sources.list.d/helm-stable-debian.list
apt-get update
apt-get install -y helm

# Install yq for YAML processing
wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
chmod +x /usr/local/bin/yq

# Create workspace directory
mkdir -p /home/${admin_username}/k8s-the-hard-way
chown ${admin_username}:${admin_username} /home/${admin_username}/k8s-the-hard-way

# Create SSH config for easy access to cluster nodes
cat > /home/${admin_username}/.ssh/config << 'EOF'
Host control-plane
    HostName 10.0.3.10
    User ${admin_username}
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host worker-1
    HostName 10.0.3.20
    User ${admin_username}
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host worker-2
    HostName 10.0.3.21
    User ${admin_username}
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF

chown ${admin_username}:${admin_username} /home/${admin_username}/.ssh/config
chmod 600 /home/${admin_username}/.ssh/config

# Create helpful aliases
cat >> /home/${admin_username}/.bashrc << 'EOF'

# Kubernetes aliases
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get services'
alias kgn='kubectl get nodes'
alias kd='kubectl describe'
alias kl='kubectl logs'

# Navigation aliases
alias k8s='cd /home/${admin_username}/k8s-the-hard-way'

# Custom prompt with hostname
export PS1='\[\033[01;32m\]\u@jumpbox\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
EOF

# Set ownership
chown ${admin_username}:${admin_username} /home/${admin_username}/.bashrc

# Create welcome message
cat > /etc/motd << 'EOF'
╔═══════════════════════════════════════════════════════════════╗
║                   Kubernetes the Hard Way                    ║
║                      Azure Lab Environment                   ║
╠═══════════════════════════════════════════════════════════════╣
║                                                               ║
║  Welcome to your Kubernetes lab jumpbox!                     ║
║                                                               ║
║  Pre-installed tools:                                        ║
║  • kubectl (Kubernetes CLI)                                  ║
║  • cfssl/cfssljson (Certificate management)                  ║
║  • Docker (Container runtime)                                ║
║  • Helm (Package manager)                                    ║
║  • Azure CLI                                                 ║
║  • jq, yq (JSON/YAML processors)                            ║
║                                                               ║
║  Quick access commands:                                       ║
║  • ssh control-plane  (Connect to control plane)            ║
║  • ssh worker-1       (Connect to worker node 1)            ║
║  • ssh worker-2       (Connect to worker node 2)            ║
║  • k8s                (Change to workspace directory)        ║
║                                                               ║
║  Follow the documentation in the repository to build         ║
║  your Kubernetes cluster step by step.                       ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF

# Enable and start services
systemctl enable docker
systemctl start docker

# Final system update
apt-get autoremove -y
apt-get autoclean

echo "Jumpbox initialization completed successfully!"