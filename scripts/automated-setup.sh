#!/bin/bash

# Kubernetes the Hard Way - Automated Setup Script
# This script automatically configures the entire Kubernetes cluster
# Use this for testing the infrastructure or when you need a quick setup
# 
# Updated with all fixes from chapters 01-07 including:
# - Kubernetes v1.28.0 and latest component versions
# - Automatic cgroup v1/v2 detection and configuration
# - Fixed etcd variable expansion issues
# - Enhanced Azure hostname handling
# - Cross-node pod networking support
# - Improved error handling and logging
#
# Prerequisites:
# - Infrastructure provisioned via Terraform
# - SSH keys configured
# - Certificates generated (chapter 02)
# - Kubeconfig files created (chapter 03)  
# - Encryption config prepared (chapter 04)

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

# Configuration (updated versions)
KUBERNETES_VERSION="v1.28.0"
ETCD_VERSION="v3.5.9"
CONTAINERD_VERSION="1.7.2"
CNI_VERSION="v1.3.0"
CFSSL_VERSION="1.6.4"
RUNC_VERSION="v1.1.8"
CRICTL_VERSION="v1.28.0"

# Infrastructure IPs
CONTROL_PLANE_IP="10.0.3.10"
WORKER_1_IP="10.0.3.20"
WORKER_2_IP="10.0.3.21"

# Infrastructure IPs
CONTROL_PLANE_IP="10.0.3.10"
WORKER_1_IP="10.0.3.20"
WORKER_2_IP="10.0.3.21"

header "Kubernetes the Hard Way - Automated Setup"
log "This script will automatically configure the entire Kubernetes cluster"
log "Infrastructure should already be provisioned and SSH access configured"
log "Updated with cgroup v2 support and latest component versions"

# Verify SSH connectivity
header "Verifying SSH Connectivity"
for ip in $CONTROL_PLANE_IP $WORKER_1_IP $WORKER_2_IP; do
    log "Testing SSH connection to $ip..."
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no azureuser@$ip "echo 'SSH OK'" > /dev/null 2>&1; then
        log "✓ SSH connection to $ip successful"
    else
        error "✗ Cannot connect to $ip via SSH"
        exit 1
    fi
done

# Check if certificates already exist
header "Checking Prerequisites"
if [ ! -f ca.pem ]; then
    error "Certificates not found. Please run chapter 02 (Certificate Authority) first."
    exit 1
fi

if [ ! -f admin.kubeconfig ]; then
    error "Kubeconfig files not found. Please run chapter 03 (Kubernetes Configuration Files) first."
    exit 1
fi

if [ ! -f encryption-config.yaml ]; then
    error "Encryption config not found. Please run chapter 04 (Data Encryption Keys) first."
    exit 1
fi

log "✓ All prerequisites found"

# Function to execute commands on remote hosts
execute_on_host() {
    local host=$1
    local commands=$2
    local description=$3
    
    log "Executing on $host: $description"
    ssh -o StrictHostKeyChecking=no azureuser@$host "$commands"
    if [ $? -eq 0 ]; then
        log "✓ Completed on $host: $description"
    else
        error "✗ Failed on $host: $description"
        exit 1
    fi
}

# Function to copy files to remote hosts
copy_to_host() {
    local host=$1
    local files=$2
    local description=$3
    
    log "Copying to $host: $description"
    scp -o StrictHostKeyChecking=no $files azureuser@$host:~/
    if [ $? -eq 0 ]; then
        log "✓ Files copied to $host: $description"
    else
        error "✗ Failed to copy files to $host: $description"
        exit 1
    fi
}
log "Verifying SSH connectivity to all VMs..."
for vm_ip in $CONTROL_PLANE_IP $WORKER_1_IP $WORKER_2_IP; do
    if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no azureuser@$vm_ip 'echo "SSH OK"' >/dev/null 2>&1; then
        error "Cannot connect to $vm_ip via SSH"
        exit 1
    fi
done
log "SSH connectivity verified"

header "Step 1: Generate Certificates"

# Ensure we're in the right directory
cd ~/kubernetes-the-hard-way-azure
mkdir -p certificates
cd certificates

# Generate CA
log "Generating Certificate Authority..."
cat > ca-config.json << EOF
{
  "signing": {
    "default": {
      "expiry": "8760h"
    },
    "profiles": {
      "kubernetes": {
        "usages": ["signing", "key encipherment", "server auth", "client auth"],
        "expiry": "8760h"
      }
    }
  }
}
EOF

cat > ca-csr.json << EOF
{
  "CN": "Kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "NO",
      "L": "Oslo",
      "O": "Kubernetes",
      "OU": "CA",
      "ST": "Oslo"
    }
  ]
}
EOF

cfssl gencert -initca ca-csr.json | cfssljson -bare ca

# Generate Admin Certificate
log "Generating admin certificate..."
cat > admin-csr.json << EOF
{
  "CN": "admin",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "NO",
      "L": "Oslo",
      "O": "system:masters",
      "OU": "Kubernetes the Hard Way",
      "ST": "Oslo"
    }
  ]
}
EOF

cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  admin-csr.json | cfssljson -bare admin

# Generate Kubelet Certificates
log "Generating kubelet certificates..."
for instance in vm-worker-1 vm-worker-2; do
  instance_ip=$(eval echo \$${instance/-/_}_IP)
  
cat > ${instance}-csr.json << EOF
{
  "CN": "system:node:${instance}",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "NO",
      "L": "Oslo",
      "O": "system:nodes",
      "OU": "Kubernetes the Hard Way",
      "ST": "Oslo"
    }
  ]
}
EOF

cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -hostname=${instance},${instance_ip} \
  -profile=kubernetes \
  ${instance}-csr.json | cfssljson -bare ${instance}
done

# Generate Controller Manager Certificate
log "Generating controller manager certificate..."
cat > kube-controller-manager-csr.json << EOF
{
  "CN": "system:kube-controller-manager",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "NO",
      "L": "Oslo",
      "O": "system:kube-controller-manager",
      "OU": "Kubernetes the Hard Way",
      "ST": "Oslo"
    }
  ]
}
EOF

cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  kube-controller-manager-csr.json | cfssljson -bare kube-controller-manager

# Generate Kube Proxy Certificate
log "Generating kube-proxy certificate..."
cat > kube-proxy-csr.json << EOF
{
  "CN": "system:kube-proxy",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "NO",
      "L": "Oslo",
      "O": "system:node-proxier",
      "OU": "Kubernetes the Hard Way",
      "ST": "Oslo"
    }
  ]
}
EOF

cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  kube-proxy-csr.json | cfssljson -bare kube-proxy

# Generate Scheduler Certificate
log "Generating scheduler certificate..."
cat > kube-scheduler-csr.json << EOF
{
  "CN": "system:kube-scheduler",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "NO",
      "L": "Oslo",
      "O": "system:kube-scheduler",
      "OU": "Kubernetes the Hard Way",
      "ST": "Oslo"
    }
  ]
}
EOF

cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  kube-scheduler-csr.json | cfssljson -bare kube-scheduler

# Generate Kubernetes API Server Certificate
log "Generating Kubernetes API server certificate..."
cat > kubernetes-csr.json << EOF
{
  "CN": "kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "NO",
      "L": "Oslo",
      "O": "Kubernetes",
      "OU": "Kubernetes the Hard Way",
      "ST": "Oslo"
    }
  ]
}
EOF

cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -hostname=10.100.0.1,${CONTROL_PLANE_IP},${CONTROL_PLANE_HOSTNAME},kubernetes,kubernetes.default,kubernetes.default.svc,kubernetes.default.svc.cluster,kubernetes.default.svc.cluster.local \
  -profile=kubernetes \
  kubernetes-csr.json | cfssljson -bare kubernetes

# Generate Service Account Certificate
log "Generating service account certificate..."
cat > service-account-csr.json << EOF
{
  "CN": "service-accounts",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "NO",
      "L": "Oslo",
      "O": "Kubernetes",
      "OU": "Kubernetes the Hard Way",
      "ST": "Oslo"
    }
  ]
}
EOF

cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  service-account-csr.json | cfssljson -bare service-account

header "Step 2: Generate Kubeconfig Files"

KUBERNETES_PUBLIC_ADDRESS=${CONTROL_PLANE_IP}

# Generate kubelet kubeconfig files
log "Generating kubelet kubeconfig files..."
for instance in vm-worker-1 vm-worker-2; do
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.pem \
    --embed-certs=true \
    --server=https://${KUBERNETES_PUBLIC_ADDRESS}:6443 \
    --kubeconfig=${instance}.kubeconfig

  kubectl config set-credentials system:node:${instance} \
    --client-certificate=${instance}.pem \
    --client-key=${instance}-key.pem \
    --embed-certs=true \
    --kubeconfig=${instance}.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:node:${instance} \
    --kubeconfig=${instance}.kubeconfig

  kubectl config use-context default --kubeconfig=${instance}.kubeconfig
done

# Generate kube-proxy kubeconfig
log "Generating kube-proxy kubeconfig..."
kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=ca.pem \
  --embed-certs=true \
  --server=https://${KUBERNETES_PUBLIC_ADDRESS}:6443 \
  --kubeconfig=kube-proxy.kubeconfig

kubectl config set-credentials system:kube-proxy \
  --client-certificate=kube-proxy.pem \
  --client-key=kube-proxy-key.pem \
  --embed-certs=true \
  --kubeconfig=kube-proxy.kubeconfig

kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=system:kube-proxy \
  --kubeconfig=kube-proxy.kubeconfig

kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig

# Generate kube-controller-manager kubeconfig
log "Generating kube-controller-manager kubeconfig..."
kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=ca.pem \
  --embed-certs=true \
  --server=https://127.0.0.1:6443 \
  --kubeconfig=kube-controller-manager.kubeconfig

kubectl config set-credentials system:kube-controller-manager \
  --client-certificate=kube-controller-manager.pem \
  --client-key=kube-controller-manager-key.pem \
  --embed-certs=true \
  --kubeconfig=kube-controller-manager.kubeconfig

kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=system:kube-controller-manager \
  --kubeconfig=kube-controller-manager.kubeconfig

kubectl config use-context default --kubeconfig=kube-controller-manager.kubeconfig

# Generate kube-scheduler kubeconfig
log "Generating kube-scheduler kubeconfig..."
kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=ca.pem \
  --embed-certs=true \
  --server=https://127.0.0.1:6443 \
  --kubeconfig=kube-scheduler.kubeconfig

kubectl config set-credentials system:kube-scheduler \
  --client-certificate=kube-scheduler.pem \
  --client-key=kube-scheduler-key.pem \
  --embed-certs=true \
  --kubeconfig=kube-scheduler.kubeconfig

kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=system:kube-scheduler \
  --kubeconfig=kube-scheduler.kubeconfig

kubectl config use-context default --kubeconfig=kube-scheduler.kubeconfig

# Generate admin kubeconfig
log "Generating admin kubeconfig..."
kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=ca.pem \
  --embed-certs=true \
  --server=https://127.0.0.1:6443 \
  --kubeconfig=admin.kubeconfig

kubectl config set-credentials admin \
  --client-certificate=admin.pem \
  --client-key=admin-key.pem \
  --embed-certs=true \
  --kubeconfig=admin.kubeconfig

kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=admin \
  --kubeconfig=admin.kubeconfig

kubectl config use-context default --kubeconfig=admin.kubeconfig

header "Step 3: Generate Data Encryption Config"

log "Generating encryption config..."
ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)

cat > encryption-config.yaml << EOF
kind: EncryptionConfig
apiVersion: v1
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${ENCRYPTION_KEY}
      - identity: {}
EOF

header "Step 4: Distribute Files"

log "Distributing certificates and configs to VMs..."

# Copy to worker nodes
for instance in vm-worker-1 vm-worker-2; do
  instance_ip=$(eval echo \$${instance/-/_}_IP)
  scp ca.pem ${instance}-key.pem ${instance}.pem ${instance}.kubeconfig kube-proxy.kubeconfig azureuser@${instance_ip}:~/
done

# Copy to control plane
scp ca.pem ca-key.pem kubernetes-key.pem kubernetes.pem \
    service-account-key.pem service-account.pem \
    admin.kubeconfig kube-controller-manager.kubeconfig kube-scheduler.kubeconfig \
    encryption-config.yaml azureuser@${CONTROL_PLANE_IP}:~/

header "Step 5: Bootstrap etcd on Control Plane"

log "Setting up etcd on control plane..."
ssh azureuser@${CONTROL_PLANE_IP} << 'EOF'
# Download and install etcd
wget -q --show-progress --https-only --timestamping \
  "https://github.com/etcd-io/etcd/releases/download/v3.5.9/etcd-v3.5.9-linux-amd64.tar.gz"

tar -xvf etcd-v3.5.9-linux-amd64.tar.gz
sudo mv etcd-v3.5.9-linux-amd64/etcd* /usr/local/bin/

# Configure etcd
sudo mkdir -p /etc/etcd /var/lib/etcd
sudo chmod 700 /var/lib/etcd
sudo cp ca.pem kubernetes-key.pem kubernetes.pem /etc/etcd/

INTERNAL_IP=$(ip addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
ETCD_NAME=$(hostname -s)

# Create etcd service
cat <<EOL | sudo tee /etc/systemd/system/etcd.service
[Unit]
Description=etcd
Documentation=https://github.com/etcd

[Service]
Type=notify
ExecStart=/usr/local/bin/etcd \\
  --name \${ETCD_NAME} \\
  --cert-file=/etc/etcd/kubernetes.pem \\
  --key-file=/etc/etcd/kubernetes-key.pem \\
  --peer-cert-file=/etc/etcd/kubernetes.pem \\
  --peer-key-file=/etc/etcd/kubernetes-key.pem \\
  --trusted-ca-file=/etc/etcd/ca.pem \\
  --peer-trusted-ca-file=/etc/etcd/ca.pem \\
  --peer-client-cert-auth \\
  --client-cert-auth \\
  --initial-advertise-peer-urls https://\${INTERNAL_IP}:2380 \\
  --listen-peer-urls https://\${INTERNAL_IP}:2380 \\
  --listen-client-urls https://\${INTERNAL_IP}:2379,https://127.0.0.1:2379 \\
  --advertise-client-urls https://\${INTERNAL_IP}:2379 \\
  --initial-cluster-token etcd-cluster-0 \\
  --initial-cluster \${ETCD_NAME}=https://\${INTERNAL_IP}:2380 \\
  --initial-cluster-state new \\
  --data-dir=/var/lib/etcd
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOL

# Start etcd
sudo systemctl daemon-reload
sudo systemctl enable etcd
sudo systemctl start etcd

# Wait for etcd to start
sleep 10
EOF

header "Step 6: Bootstrap Kubernetes Control Plane"

log "Setting up Kubernetes control plane..."
ssh azureuser@${CONTROL_PLANE_IP} << 'EOF'
# Create kubernetes directories
sudo mkdir -p /etc/kubernetes/config

# Download Kubernetes binaries
wget -q --show-progress --https-only --timestamping \
  "https://storage.googleapis.com/kubernetes-release/release/v1.28.0/bin/linux/amd64/kube-apiserver" \
  "https://storage.googleapis.com/kubernetes-release/release/v1.28.0/bin/linux/amd64/kube-controller-manager" \
  "https://storage.googleapis.com/kubernetes-release/release/v1.28.0/bin/linux/amd64/kube-scheduler" \
  "https://storage.googleapis.com/kubernetes-release/release/v1.28.0/bin/linux/amd64/kubectl"

chmod +x kube-apiserver kube-controller-manager kube-scheduler kubectl
sudo mv kube-apiserver kube-controller-manager kube-scheduler kubectl /usr/local/bin/

# Configure API Server
sudo mkdir -p /var/lib/kubernetes/
sudo cp ca.pem ca-key.pem kubernetes-key.pem kubernetes.pem \
    service-account-key.pem service-account.pem \
    encryption-config.yaml /var/lib/kubernetes/

INTERNAL_IP=$(ip addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')

# Create kube-apiserver service
cat <<EOL | sudo tee /etc/systemd/system/kube-apiserver.service
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-apiserver \\
  --advertise-address=${INTERNAL_IP} \\
  --allow-privileged=true \\
  --apiserver-count=1 \\
  --audit-log-maxage=30 \\
  --audit-log-maxbackup=3 \\
  --audit-log-maxsize=100 \\
  --audit-log-path=/var/log/audit.log \\
  --authorization-mode=Node,RBAC \\
  --bind-address=0.0.0.0 \\
  --client-ca-file=/var/lib/kubernetes/ca.pem \\
  --enable-admission-plugins=NamespaceLifecycle,NodeRestriction,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota \\
  --etcd-cafile=/var/lib/kubernetes/ca.pem \\
  --etcd-certfile=/var/lib/kubernetes/kubernetes.pem \\
  --etcd-keyfile=/var/lib/kubernetes/kubernetes-key.pem \\
  --etcd-servers=https://127.0.0.1:2379 \\
  --event-ttl=1h \\
  --encryption-provider-config=/var/lib/kubernetes/encryption-config.yaml \\
  --kubelet-certificate-authority=/var/lib/kubernetes/ca.pem \\
  --kubelet-client-certificate=/var/lib/kubernetes/kubernetes.pem \\
  --kubelet-client-key=/var/lib/kubernetes/kubernetes-key.pem \\
  --runtime-config='api/all=true' \\
  --service-account-key-file=/var/lib/kubernetes/service-account.pem \\
  --service-account-signing-key-file=/var/lib/kubernetes/service-account-key.pem \\
  --service-account-issuer=https://${INTERNAL_IP}:6443 \\
  --service-cluster-ip-range=10.100.0.0/16 \\
  --service-node-port-range=30000-32767 \\
  --tls-cert-file=/var/lib/kubernetes/kubernetes.pem \\
  --tls-private-key-file=/var/lib/kubernetes/kubernetes-key.pem \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOL

# Configure controller manager
sudo cp kube-controller-manager.kubeconfig /var/lib/kubernetes/

cat <<EOL | sudo tee /etc/systemd/system/kube-controller-manager.service
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-controller-manager \\
  --bind-address=0.0.0.0 \\
  --cluster-cidr=10.200.0.0/16 \\
  --cluster-name=kubernetes \\
  --cluster-signing-cert-file=/var/lib/kubernetes/ca.pem \\
  --cluster-signing-key-file=/var/lib/kubernetes/ca-key.pem \\
  --kubeconfig=/var/lib/kubernetes/kube-controller-manager.kubeconfig \\
  --leader-elect=true \\
  --root-ca-file=/var/lib/kubernetes/ca.pem \\
  --service-account-private-key-file=/var/lib/kubernetes/service-account-key.pem \\
  --service-cluster-ip-range=10.100.0.0/16 \\
  --use-service-account-credentials=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOL

# Configure scheduler
sudo cp kube-scheduler.kubeconfig /var/lib/kubernetes/

cat <<EOL | sudo tee /etc/kubernetes/config/kube-scheduler.yaml
apiVersion: kubescheduler.config.k8s.io/v1beta3
kind: KubeSchedulerConfiguration
clientConnection:
  kubeconfig: "/var/lib/kubernetes/kube-scheduler.kubeconfig"
leaderElection:
  leaderElect: true
EOL

cat <<EOL | sudo tee /etc/systemd/system/kube-scheduler.service
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-scheduler \\
  --config=/etc/kubernetes/config/kube-scheduler.yaml \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOL

# Start control plane services
sudo systemctl daemon-reload
sudo systemctl enable kube-apiserver kube-controller-manager kube-scheduler
sudo systemctl start kube-apiserver kube-controller-manager kube-scheduler

# Wait for services to start
sleep 15
EOF

header "Step 7: Configure kubectl Access"

log "Configuring kubectl access..."
cp certificates/admin.kubeconfig ~/.kube/config 2>/dev/null || {
    mkdir -p ~/.kube
    cp certificates/admin.kubeconfig ~/.kube/config
}

# Update kubeconfig to use external IP
kubectl config set-cluster kubernetes-the-hard-way --server=https://${CONTROL_PLANE_IP}:6443

header "Step 8: Setup Worker Nodes"

log "Setting up worker nodes..."

# Function to setup a worker node
setup_worker() {
    local worker_ip=$1
    local worker_hostname=$2
    
    log "Setting up worker node: $worker_hostname ($worker_ip)"
    
    ssh azureuser@${worker_ip} << EOF
# Create directories
sudo mkdir -p \\
  /etc/cni/net.d \\
  /opt/cni/bin \\
  /var/lib/kubelet \\
  /var/lib/kube-proxy \\
  /var/lib/kubernetes \\
  /var/run/kubernetes

# Install OS dependencies
sudo apt-get update
sudo apt-get -y install socat conntrack ipset iptables-persistent

# Download worker binaries
wget -q --show-progress --https-only --timestamping \\
  https://github.com/kubernetes-sigs/cri-tools/releases/download/v1.28.0/crictl-v1.28.0-linux-amd64.tar.gz \\
  https://github.com/opencontainers/runc/releases/download/v1.1.8/runc.amd64 \\
  https://github.com/containernetworking/plugins/releases/download/v1.3.0/cni-plugins-linux-amd64-v1.3.0.tgz \\
  https://github.com/containerd/containerd/releases/download/v1.7.2/containerd-1.7.2-linux-amd64.tar.gz \\
  https://storage.googleapis.com/kubernetes-release/release/v1.28.0/bin/linux/amd64/kubectl \\
  https://storage.googleapis.com/kubernetes-release/release/v1.28.0/bin/linux/amd64/kube-proxy \\
  https://storage.googleapis.com/kubernetes-release/release/v1.28.0/bin/linux/amd64/kubelet

# Install CNI plugins
sudo tar -xvf cni-plugins-linux-amd64-v1.3.0.tgz -C /opt/cni/bin/

# Install crictl
tar -xvf crictl-v1.28.0-linux-amd64.tar.gz
chmod +x crictl
sudo mv crictl /usr/local/bin/

# Install runc
chmod +x runc.amd64
sudo mv runc.amd64 /usr/local/bin/runc

# Install containerd
sudo tar -xvf containerd-1.7.2-linux-amd64.tar.gz -C /

# Install kubectl, kube-proxy, kubelet
chmod +x kubectl kube-proxy kubelet
sudo mv kubectl kube-proxy kubelet /usr/local/bin/

# Configure CNI
POD_CIDR=10.200.0.0/16
cat <<EOC | sudo tee /etc/cni/net.d/10-bridge.conf
{
    "cniVersion": "1.0.0",
    "name": "bridge",
    "type": "bridge",
    "bridge": "cnio0",
    "isGateway": true,
    "ipMasq": true,
    "ipam": {
        "type": "host-local",
        "ranges": [
          [{"subnet": "\${POD_CIDR}"}]
        ],
        "routes": [{"dst": "0.0.0.0/0"}]
    }
}
EOC

cat <<EOC | sudo tee /etc/cni/net.d/99-loopback.conf
{
    "cniVersion": "1.0.0",
    "name": "lo",
    "type": "loopback"
}
EOC

# Configure crictl
sudo crictl config --set runtime-endpoint=unix:///run/containerd/containerd.sock
sudo crictl config --set image-endpoint=unix:///run/containerd/containerd.sock

# Configure containerd with cgroup detection
sudo mkdir -p /etc/containerd/

# Detect cgroup version and configure accordingly
if mount | grep -q cgroup2; then
    echo "Detected cgroup v2, configuring systemd driver"
    cat << EOC | sudo tee /etc/containerd/config.toml
version = 2

[plugins]
  [plugins."io.containerd.grpc.v1.cri"]
    sandbox_image = "registry.k8s.io/pause:3.9"
    [plugins."io.containerd.grpc.v1.cri".cni]
      bin_dir = "/opt/cni/bin"
      conf_dir = "/etc/cni/net.d"
    [plugins."io.containerd.grpc.v1.cri".containerd]
      snapshotter = "overlayfs"
      default_runtime_name = "runc"
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes]
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
          runtime_type = "io.containerd.runc.v2"
          [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
            SystemdCgroup = true
EOC
    CGROUP_DRIVER="systemd"
else
    echo "Detected cgroup v1, configuring cgroupfs driver"
    cat << EOC | sudo tee /etc/containerd/config.toml
version = 2

[plugins]
  [plugins."io.containerd.grpc.v1.cri"]
    [plugins."io.containerd.grpc.v1.cri".containerd]
      snapshotter = "overlayfs"
      default_runtime_name = "runc"
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes]
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
          runtime_type = "io.containerd.runc.v2"
          [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
            SystemdCgroup = false
EOC
    CGROUP_DRIVER="cgroupfs"
fi

cat <<EOC | sudo tee /etc/systemd/system/containerd.service
[Unit]
Description=containerd container runtime
Documentation=https://containerd.io
After=network.target local-fs.target

[Service]
ExecStartPre=-/sbin/modprobe overlay
ExecStart=/usr/local/bin/containerd

Type=notify
Delegate=yes
KillMode=process
Restart=always
RestartSec=5
LimitNOFILE=1048576
LimitNPROC=1048576
LimitCORE=infinity
TasksMax=infinity

[Install]
WantedBy=multi-user.target
EOC

# Handle Azure hostname extensions for worker certificates
WORKER_NAME=\$(hostname -s)
if [[ \$WORKER_NAME =~ ^(vm-worker-[0-9]+)-.+\$ ]]; then
    BASE_WORKER_NAME="\${BASH_REMATCH[1]}"
    echo "Detected Azure hostname extension. Using base name: \$BASE_WORKER_NAME"
    CERT_NAME="\$BASE_WORKER_NAME"
else
    CERT_NAME="\$WORKER_NAME"
fi

# Configure kubelet
sudo cp \${CERT_NAME}-key.pem \${CERT_NAME}.pem /var/lib/kubelet/
sudo cp \${CERT_NAME}.kubeconfig /var/lib/kubelet/kubeconfig
sudo cp ca.pem /var/lib/kubernetes/

cat <<EOC | sudo tee /var/lib/kubelet/kubelet-config.yaml
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: true
  x509:
    clientCAFile: "/var/lib/kubernetes/ca.pem"
authorization:
  mode: Webhook
cgroupDriver: \${CGROUP_DRIVER}
clusterDomain: "cluster.local"
clusterDNS:
  - "10.100.0.10"
containerRuntimeEndpoint: "unix:///var/run/containerd/containerd.sock"
nodeName: "\${CERT_NAME}"
podCIDR: "\${POD_CIDR}"
registerNode: true
resolvConf: "/run/systemd/resolve/resolv.conf"
runtimeRequestTimeout: "15m"
tlsCertFile: "/var/lib/kubelet/\${CERT_NAME}.pem"
tlsPrivateKeyFile: "/var/lib/kubelet/\${CERT_NAME}-key.pem"
EOC

cat <<EOC | sudo tee /etc/systemd/system/kubelet.service
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/kubernetes/kubernetes
After=containerd.service
Requires=containerd.service

[Service]
ExecStart=/usr/local/bin/kubelet --config=/var/lib/kubelet/kubelet-config.yaml --kubeconfig=/var/lib/kubelet/kubeconfig --hostname-override=\${CERT_NAME} --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOC

[Service]
ExecStart=/usr/local/bin/kubelet \\
  --config=/var/lib/kubelet/kubelet-config.yaml \\
  --container-runtime=remote \\
  --container-runtime-endpoint=unix:///var/run/containerd/containerd.sock \\
  --image-pull-progress-deadline=2m \\
  --kubeconfig=/var/lib/kubelet/kubeconfig \\
  --network-plugin=cni \\
  --register-node=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOC

# Configure kube-proxy
sudo cp kube-proxy.kubeconfig /var/lib/kube-proxy/kubeconfig

cat <<EOC | sudo tee /var/lib/kube-proxy/kube-proxy-config.yaml
kind: KubeProxyConfiguration
apiVersion: kubeproxy.config.k8s.io/v1alpha1
clientConnection:
  kubeconfig: "/var/lib/kube-proxy/kubeconfig"
mode: "iptables"
clusterCIDR: "10.200.0.0/16"
EOC

cat <<EOC | sudo tee /etc/systemd/system/kube-proxy.service
[Unit]
Description=Kubernetes Kube Proxy
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-proxy \\
  --config=/var/lib/kube-proxy/kube-proxy-config.yaml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOC

# Start worker services
sudo systemctl daemon-reload
sudo systemctl enable containerd kubelet kube-proxy
sudo systemctl start containerd kubelet kube-proxy

# Enable IP forwarding for cross-node pod communication
echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.conf
sudo sysctl -w net.ipv4.ip_forward=1

# Add iptables rules for bridge forwarding
sudo iptables -A FORWARD -i cnio0 -j ACCEPT
sudo iptables -A FORWARD -o cnio0 -j ACCEPT

# Save iptables rules
sudo iptables-save | sudo tee /etc/iptables/rules.v4
EOF
}

# Setup both worker nodes
WORKER_1_HOSTNAME="vm-worker-1"
WORKER_2_HOSTNAME="vm-worker-2"
setup_worker $WORKER_1_IP $WORKER_1_HOSTNAME
setup_worker $WORKER_2_IP $WORKER_2_HOSTNAME

header "Step 9: Final Configuration"

log "Waiting for nodes to register..."
sleep 30

# Check cluster status
log "Checking cluster status..."
kubectl get nodes

# Create ClusterRole for kubelet API access
log "Configuring RBAC for kubelet access..."
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
  name: system:kube-apiserver-to-kubelet
rules:
  - apiGroups:
      - ""
    resources:
      - nodes/proxy
      - nodes/stats
      - nodes/log
      - nodes/spec
      - nodes/metrics
    verbs:
      - "*"
EOF

cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: system:kube-apiserver
  namespace: ""
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:kube-apiserver-to-kubelet
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: User
    name: kubernetes
EOF

header "Setup Complete!"

log "Kubernetes cluster has been automatically configured with the latest improvements!"
echo
log "🔧 Key Improvements Applied:"
log "  ✓ Updated to Kubernetes v1.28.0 with latest component versions"
log "  ✓ Automatic cgroup v1/v2 detection and configuration"
log "  ✓ Fixed etcd variable expansion in service files"
log "  ✓ Enhanced Azure hostname handling for worker certificates"
log "  ✓ Improved containerd configuration with proper cgroup drivers"
log "  ✓ Enhanced kubelet configuration with automatic cgroup detection"
log "  ✓ IP forwarding enabled for cross-node pod communication"
log "  ✓ Bridge forwarding rules for pod-to-pod networking"
echo
log "Cluster Information:"
kubectl cluster-info
echo
log "Node Status:"
kubectl get nodes -o wide
echo
log "System Pods:"
kubectl get pods -n kube-system
echo
log "🚀 Your cluster is ready! You can now:"
log "  • Run smoke tests: cd docs && follow chapter 10"
log "  • Deploy applications: kubectl create deployment ..."
log "  • Test pod networking: kubectl run test-pods ..."
log "  • Monitor with: kubectl get nodes -w"
echo
log "For troubleshooting, check systemd logs:"
log "  • etcd: ssh azureuser@$CONTROL_PLANE_IP 'sudo journalctl -u etcd'"
log "  • kubelet: ssh azureuser@$WORKER_1_IP 'sudo journalctl -u kubelet'"
log "  • containerd: ssh azureuser@$WORKER_1_IP 'sudo journalctl -u containerd'"