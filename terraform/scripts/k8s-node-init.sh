#!/bin/bash
# Kubernetes node initialization script
# This script prepares Kubernetes nodes (control plane and workers)

set -e

# Update system
apt-get update
apt-get upgrade -y

# Install essential packages
apt-get install -y \
    curl \
    wget \
    vim \
    htop \
    socat \
    conntrack \
    ipset \
    nfs-common

# Disable swap (required for Kubernetes)
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Load required kernel modules
cat > /etc/modules-load.d/k8s.conf << 'EOF'
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# Set kernel parameters for Kubernetes
cat > /etc/sysctl.d/k8s.conf << 'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system

# Create directories that will be needed
mkdir -p /etc/kubernetes/{config,pki}
mkdir -p /var/lib/{etcd,kubernetes}
mkdir -p /var/run/kubernetes
mkdir -p /opt/cni/bin
mkdir -p /etc/cni/net.d

# Download CNI plugins
CNI_VERSION="v1.3.0"
curl -L "https://github.com/containernetworking/plugins/releases/download/$CNI_VERSION/cni-plugins-linux-amd64-$CNI_VERSION.tgz" | tar -C /opt/cni/bin -xz

# Install containerd
CONTAINERD_VERSION="1.7.2"
curl -L "https://github.com/containerd/containerd/releases/download/v$CONTAINERD_VERSION/containerd-$CONTAINERD_VERSION-linux-amd64.tar.gz" | tar -C /usr/local -xz

# Create containerd service file
cat > /etc/systemd/system/containerd.service << 'EOF'
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
LimitNPROC=infinity
LimitCORE=infinity
LimitNOFILE=infinity
TasksMax=infinity
OOMScoreAdjust=-999

[Install]
WantedBy=multi-user.target
EOF

# Configure containerd
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# Install runc
RUNC_VERSION="v1.1.7"
curl -L "https://github.com/opencontainers/runc/releases/download/$RUNC_VERSION/runc.amd64" -o /usr/local/sbin/runc
chmod 755 /usr/local/sbin/runc

# Download Kubernetes binaries
K8S_VERSION="v1.28.0"
cd /usr/local/bin

if [ "${node_role}" = "control-plane" ]; then
    # Control plane binaries
    curl -L --remote-name-all https://storage.googleapis.com/kubernetes-release/release/$K8S_VERSION/bin/linux/amd64/{kube-apiserver,kube-controller-manager,kube-scheduler,kubectl}
    chmod +x kube-apiserver kube-controller-manager kube-scheduler kubectl
    
    # etcd
    ETCD_VER="v3.5.9"
    curl -L "https://github.com/etcd-io/etcd/releases/download/$ETCD_VER/etcd-$ETCD_VER-linux-amd64.tar.gz" | tar -xz
    mv etcd-$ETCD_VER-linux-amd64/etcd* /usr/local/bin/
    rm -rf etcd-$ETCD_VER-linux-amd64
    
elif [ "${node_role}" = "worker" ]; then
    # Worker node binaries
    curl -L --remote-name-all https://storage.googleapis.com/kubernetes-release/release/$K8S_VERSION/bin/linux/amd64/{kubectl,kube-proxy,kubelet}
    chmod +x kubectl kube-proxy kubelet
fi

# Enable IP forwarding
echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf

# Create systemd unit files directories
mkdir -p /etc/systemd/system/{kubelet,kube-proxy}.service.d

# Set proper ownership and permissions
chown -R ${admin_username}:${admin_username} /home/${admin_username}

# Enable and start containerd
systemctl daemon-reload
systemctl enable containerd
systemctl start containerd

# Clean up
apt-get autoremove -y
apt-get autoclean

echo "Kubernetes ${node_role} node initialization completed successfully!"

# Create a status file
echo "Node Type: ${node_role}" > /etc/k8s-node-info
echo "Initialization Date: $(date)" >> /etc/k8s-node-info
echo "Containerd Version: $CONTAINERD_VERSION" >> /etc/k8s-node-info
echo "Kubernetes Version: $K8S_VERSION" >> /etc/k8s-node-info
echo "CNI Version: $CNI_VERSION" >> /etc/k8s-node-info