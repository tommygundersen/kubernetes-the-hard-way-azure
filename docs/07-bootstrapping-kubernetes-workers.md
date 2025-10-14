# Bootstrapping the Kubernetes Worker Nodes

In this lab you will bootstrap two Kubernetes worker nodes. The following components will be installed on each node: [runc](https://github.com/opencontainers/runc), [container networking plugins](https://github.com/containernetworking/cni), [containerd](https://github.com/containerd/containerd), [kubelet](https://kubernetes.io/docs/admin/kubelet), and [kube-proxy](https://kubernetes.io/docs/concepts/cluster-administration/proxies).

## Prerequisites

The commands in this lab must be run on each worker instance: `vm-worker-1` and `vm-worker-2`. Login to each worker instance using SSH from the jumpbox.

```bash
# From the jumpbox, connect to the first worker
ssh azureuser@10.0.3.20

# Open another terminal and connect to the second worker
ssh azureuser@10.0.3.21
```

> The following commands should be run on both worker nodes unless otherwise specified.

## Provisioning a Kubernetes Worker Node

Install the OS dependencies:

```bash
sudo apt-get update
sudo apt-get -y install socat conntrack ipset
```

> The socat binary enables support for the `kubectl port-forward` command.

### Download and Install Worker Binaries

```bash
wget -q --show-progress --https-only --timestamping \
  https://github.com/kubernetes-sigs/cri-tools/releases/download/v1.28.0/crictl-v1.28.0-linux-amd64.tar.gz \
  https://github.com/opencontainers/runc/releases/download/v1.1.8/runc.amd64 \
  https://github.com/containernetworking/plugins/releases/download/v1.3.0/cni-plugins-linux-amd64-v1.3.0.tgz \
  https://github.com/containerd/containerd/releases/download/v1.7.2/containerd-1.7.2-linux-amd64.tar.gz \
  https://storage.googleapis.com/kubernetes-release/release/v1.28.0/bin/linux/amd64/kubectl \
  https://storage.googleapis.com/kubernetes-release/release/v1.28.0/bin/linux/amd64/kube-proxy \
  https://storage.googleapis.com/kubernetes-release/release/v1.28.0/bin/linux/amd64/kubelet
```

Create the installation directories:

```bash
sudo mkdir -p \
  /etc/cni/net.d \
  /opt/cni/bin \
  /var/lib/kubelet \
  /var/lib/kube-proxy \
  /var/lib/kubernetes \
  /var/run/kubernetes
```

Install the worker binaries:

```bash
mkdir containerd
tar -xvf crictl-v1.28.0-linux-amd64.tar.gz
tar -xvf containerd-1.7.2-linux-amd64.tar.gz -C containerd
sudo tar -xvf cni-plugins-linux-amd64-v1.3.0.tgz -C /opt/cni/bin/
sudo mv runc.amd64 runc
chmod +x crictl kubectl kube-proxy kubelet runc 
sudo mv crictl kubectl kube-proxy kubelet runc /usr/local/bin/
sudo mv containerd/bin/* /usr/local/bin/
```

Configure crictl to use containerd:

```bash
# Method 1: Use crictl config command (recommended)
sudo crictl config --set runtime-endpoint=unix:///run/containerd/containerd.sock
sudo crictl config --set image-endpoint=unix:///run/containerd/containerd.sock

# Method 2: Create config file manually (alternative)
sudo mkdir -p /etc/crictl
cat <<EOF | sudo tee /etc/crictl/crictl.yaml
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 2
debug: false
pull-image-on-create: false
disable-pull-on-run: false
EOF
```

### Configure CNI Networking

Retrieve the Pod CIDR range for the current compute instance:

```bash
POD_CIDR="10.200.0.0/16"
echo "Pod CIDR: $POD_CIDR"
```

Create the `bridge` network configuration file:

```bash
cat <<EOF | sudo tee /etc/cni/net.d/10-bridge.conf
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
          [{"subnet": "${POD_CIDR}"}]
        ],
        "routes": [{"dst": "0.0.0.0/0"}]
    }
}
EOF
```

Create the `loopback` network configuration file:

```bash
cat <<EOF | sudo tee /etc/cni/net.d/99-loopback.conf
{
    "cniVersion": "1.0.0",
    "name": "lo",
    "type": "loopback"
}
EOF
```

### Configure containerd

Create the `containerd` configuration file:

```bash
sudo mkdir -p /etc/containerd/
```

```bash
cat << EOF | sudo tee /etc/containerd/config.toml
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
EOF
```

Create the `containerd.service` systemd unit file:

```bash
cat <<EOF | sudo tee /etc/systemd/system/containerd.service
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
EOF
```

### Configure the Kubelet

```bash
# Create required directories
sudo mkdir -p /var/lib/kubelet/
sudo mkdir -p /var/lib/kubernetes/
sudo mkdir -p /var/lib/kube-proxy/

WORKER_NAME=$(hostname -s)
echo "Worker name: $WORKER_NAME"

# Handle Azure hostname extensions (e.g., vm-worker-1-kkrcp4 vs vm-worker-1)
# Extract the base worker name (remove any suffix after the last dash if it matches a pattern)
if [[ $WORKER_NAME =~ ^(vm-worker-[0-9]+)-.+$ ]]; then
    BASE_WORKER_NAME="${BASH_REMATCH[1]}"
    echo "Detected Azure hostname extension. Using base name: $BASE_WORKER_NAME"
    CERT_NAME="$BASE_WORKER_NAME"
else
    CERT_NAME="$WORKER_NAME"
fi

# Copy certificates using the correct naming
sudo cp ${CERT_NAME}-key.pem ${CERT_NAME}.pem /var/lib/kubelet/
sudo cp ${CERT_NAME}.kubeconfig /var/lib/kubelet/kubeconfig
sudo cp ca.pem /var/lib/kubernetes/
```

Create the `kubelet-config.yaml` configuration file:

```bash
# Set required variables
POD_CIDR="10.200.0.0/16"

cat <<EOF | sudo tee /var/lib/kubelet/kubelet-config.yaml
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
cgroupDriver: cgroupfs
clusterDomain: "cluster.local"
clusterDNS:
  - "10.100.0.10"
containerRuntimeEndpoint: "unix:///var/run/containerd/containerd.sock"
nodeName: "${CERT_NAME}"
podCIDR: "${POD_CIDR}"
registerNode: true
resolvConf: "/run/systemd/resolve/resolv.conf"
runtimeRequestTimeout: "15m"
tlsCertFile: "/var/lib/kubelet/${CERT_NAME}.pem"
tlsPrivateKeyFile: "/var/lib/kubelet/${CERT_NAME}-key.pem"
EOF
```

Create the `kubelet.service` systemd unit file:

```bash
cat <<EOF | sudo tee /etc/systemd/system/kubelet.service
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/kubernetes/kubernetes
After=containerd.service
Requires=containerd.service

[Service]
ExecStart=/usr/local/bin/kubelet --config=/var/lib/kubelet/kubelet-config.yaml --kubeconfig=/var/lib/kubelet/kubeconfig --hostname-override=${CERT_NAME} --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

### Configure the Kubernetes Proxy

```bash
sudo cp kube-proxy.kubeconfig /var/lib/kube-proxy/kubeconfig
```

Create the `kube-proxy-config.yaml` configuration file:

```bash
cat <<EOF | sudo tee /var/lib/kube-proxy/kube-proxy-config.yaml
kind: KubeProxyConfiguration
apiVersion: kubeproxy.config.k8s.io/v1alpha1
clientConnection:
  kubeconfig: "/var/lib/kube-proxy/kubeconfig"
mode: "iptables"
clusterCIDR: "10.200.0.0/16"
EOF
```

Create the `kube-proxy.service` systemd unit file:

```bash
cat <<EOF | sudo tee /etc/systemd/system/kube-proxy.service
[Unit]
Description=Kubernetes Kube Proxy
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-proxy --config=/var/lib/kube-proxy/kube-proxy-config.yaml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

### Start the Worker Services

```bash
sudo systemctl daemon-reload
sudo systemctl enable containerd kubelet kube-proxy
sudo systemctl start containerd kubelet kube-proxy
```

> Remember to run the above commands on each worker node: `vm-worker-1` and `vm-worker-2`.

## Verification

### Check Service Status

On each worker node, verify that the services are running:

```bash
# Check service status
sudo systemctl status containerd kubelet kube-proxy

# Check service logs
sudo journalctl -u containerd
sudo journalctl -u kubelet
sudo journalctl -u kube-proxy
```

### Verify Node Registration

From the jumpbox, list the registered Kubernetes nodes:

```bash
# Ensure you have kubectl configured (from previous labs)
kubectl get nodes --kubeconfig certificates/admin.kubeconfig
```

You should see output similar to:

```
NAME           STATUS   ROLES    AGE   VERSION
vm-worker-1    Ready    <none>   30s   v1.28.0
vm-worker-2    Ready    <none>   30s   v1.28.0
```

> Note: It may take a few minutes for the nodes to appear as `Ready`.

### Check Node Details

Get detailed information about the nodes:

```bash
kubectl describe nodes --kubeconfig certificates/admin.kubeconfig
```

### Verify Container Runtime

On each worker node, test the container runtime:

```bash
# Check containerd status
sudo crictl version

# List running containers
sudo crictl ps

# List images
sudo crictl images
```

## Troubleshooting Common Issues

### Issue: "cannot stat 'vm-worker-1-kkrcp4-key.pem': No such file or directory"

**Problem**: Azure adds random extensions to hostnames (e.g., `vm-worker-1-kkrcp4`), but certificate files are named with the original hostname (`vm-worker-1`).

**Symptoms**:
```bash
WORKER_NAME=$(hostname -s)
echo $WORKER_NAME  # Shows: vm-worker-1-kkrcp4
ls *.pem           # Shows: vm-worker-1-key.pem, vm-worker-1.pem (without extension)
```

**Solution**: Use the corrected certificate copying logic:
```bash
WORKER_NAME=$(hostname -s)
echo "Full hostname: $WORKER_NAME"

# Handle Azure hostname extensions
if [[ $WORKER_NAME =~ ^(vm-worker-[0-9]+)-.+$ ]]; then
    BASE_WORKER_NAME="${BASH_REMATCH[1]}"
    echo "Using base name for certificates: $BASE_WORKER_NAME"
    CERT_NAME="$BASE_WORKER_NAME"
else
    CERT_NAME="$WORKER_NAME"
fi

# Verify files exist before copying
ls -la ${CERT_NAME}-key.pem ${CERT_NAME}.pem ${CERT_NAME}.kubeconfig

# Copy with correct names
sudo cp ${CERT_NAME}-key.pem ${CERT_NAME}.pem /var/lib/kubelet/
sudo cp ${CERT_NAME}.kubeconfig /var/lib/kubelet/kubeconfig
sudo cp ca.pem /var/lib/kubernetes/
```

### Issue: "unable to load client CA file /var/lib/kubernetes/ca.pem: no such file or directory"

**Problem**: The `/var/lib/kubernetes/` directory doesn't exist or the CA certificate wasn't copied.

**Solution**: Create the required directories and copy the CA certificate:
```bash
# Create the required directory
sudo mkdir -p /var/lib/kubernetes/

# Copy the CA certificate
sudo cp ca.pem /var/lib/kubernetes/

# Verify the file exists and has correct permissions
sudo ls -la /var/lib/kubernetes/ca.pem

# Restart kubelet
sudo systemctl restart kubelet
```

### Issue: kubelet fails to start with certificate errors

**Solution**: Verify certificate permissions and paths:
```bash
# Check certificate files exist and have correct permissions
sudo ls -la /var/lib/kubelet/
sudo ls -la /var/lib/kubernetes/

# Check kubelet logs for specific errors
sudo journalctl -u kubelet --no-pager | tail -20
```

### Issue: "No api server defined - no events will be sent to API server"

**Problem**: kubelet is running in standalone mode because it can't connect to the API server.

**Common causes:**
- kubeconfig file missing or incorrect
- API server endpoint not reachable
- Certificate issues preventing authentication

**Solution**:
```bash
# 1. Verify kubeconfig file exists and has correct content
sudo cat /var/lib/kubelet/kubeconfig

# Should show something like:
# server: https://10.0.3.10:6443

# 2. Test API server connectivity from worker node
curl -k https://10.0.3.10:6443/version

# 3. Verify the kubeconfig was copied correctly (after fixing hostname issue)
ls -la ${CERT_NAME}.kubeconfig
sudo cp ${CERT_NAME}.kubeconfig /var/lib/kubelet/kubeconfig

# 4. Check kubelet configuration references the kubeconfig
sudo cat /etc/systemd/system/kubelet.service | grep kubeconfig

# 5. Restart kubelet after fixing
sudo systemctl restart kubelet
sudo journalctl -u kubelet --no-pager | tail -20
```

### Issue: kubelet certificate path errors

**Problem**: Certificate paths in kubelet-config.yaml reference wrong worker name.

**Solution**:
```bash
# Recreate kubelet-config.yaml with correct certificate paths
POD_CIDR="10.200.0.0/16"

cat <<EOF | sudo tee /var/lib/kubelet/kubelet-config.yaml
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
clusterDomain: "cluster.local"
clusterDNS:
  - "10.100.0.10"
podCIDR: "${POD_CIDR}"
resolvConf: "/run/systemd/resolve/resolv.conf"
runtimeRequestTimeout: "15m"
tlsCertFile: "/var/lib/kubelet/${CERT_NAME}.pem"
tlsPrivateKeyFile: "/var/lib/kubelet/${CERT_NAME}-key.pem"
EOF

sudo systemctl restart kubelet
```

### Issue: "unknown flag: --container-runtime" or "--network-plugin"

**Problem**: Kubernetes v1.28.0 has deprecated and removed several kubelet flags.

**Deprecated flags in v1.28.0:**
- `--container-runtime=remote` (removed)
- `--network-plugin=cni` (removed, CNI is now default)
- `--image-pull-progress-deadline` (removed)

**Solution**: Use the updated kubelet service configuration:
```bash
cat <<EOF | sudo tee /etc/systemd/system/kubelet.service
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/kubernetes/kubernetes
After=containerd.service
Requires=containerd.service

[Service]
ExecStart=/usr/local/bin/kubelet --config=/var/lib/kubelet/kubelet-config.yaml --kubeconfig=/var/lib/kubelet/kubeconfig --hostname-override=${CERT_NAME} --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl restart kubelet
```

### Issue: Deprecation warnings in kubelet logs

**Problem**: Kubelet shows deprecation warnings for flags that should be in config file:

```
Flag --container-runtime-endpoint has been deprecated
Flag --register-node has been deprecated
```

**Solution**: Move these settings from command-line flags to the kubelet configuration file:

```bash
# Update kubelet config to include the deprecated flag settings
cat <<EOF | sudo tee /var/lib/kubelet/kubelet-config.yaml
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
clusterDomain: "cluster.local"
clusterDNS:
  - "10.100.0.10"
containerRuntimeEndpoint: "unix:///var/run/containerd/containerd.sock"
nodeName: "${CERT_NAME}"
podCIDR: "${POD_CIDR}"
registerNode: true
resolvConf: "/run/systemd/resolve/resolv.conf"
runtimeRequestTimeout: "15m"
tlsCertFile: "/var/lib/kubelet/${CERT_NAME}.pem"
tlsPrivateKeyFile: "/var/lib/kubelet/${CERT_NAME}-key.pem"
EOF

# Update kubelet service to remove deprecated flags
cat <<EOF | sudo tee /etc/systemd/system/kubelet.service
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/kubernetes/kubernetes
After=containerd.service
Requires=containerd.service

[Service]
ExecStart=/usr/local/bin/kubelet --config=/var/lib/kubelet/kubelet-config.yaml --kubeconfig=/var/lib/kubelet/kubeconfig --hostname-override=${CERT_NAME} --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl restart kubelet
```

### Test Pod Deployment

From the jumpbox, create a test deployment to verify the workers:

```bash
# Create a test deployment
kubectl create deployment test-nginx --image=nginx --kubeconfig certificates/admin.kubeconfig

# Check if pods are scheduled
kubectl get pods -o wide --kubeconfig certificates/admin.kubeconfig

# Wait for the pod to be ready
kubectl wait --for=condition=Ready pod -l app=test-nginx --kubeconfig certificates/admin.kubeconfig

# Clean up
kubectl delete deployment test-nginx --kubeconfig certificates/admin.kubeconfig
```

## Understanding Worker Node Components

### containerd
- **Purpose**: Container runtime for running containers
- **Responsibilities**: Container lifecycle management, image management
- **Configuration**: `/etc/containerd/config.toml`
- **Socket**: `/var/run/containerd/containerd.sock`

### kubelet
- **Purpose**: Primary node agent that manages pods and containers
- **Responsibilities**: Pod lifecycle, health checks, volume mounting, reporting to API server
- **Configuration**: `/var/lib/kubelet/kubelet-config.yaml`
- **Certificates**: Node-specific client certificates

### kube-proxy
- **Purpose**: Network proxy running on each node
- **Responsibilities**: Service load balancing, iptables rule management
- **Configuration**: `/var/lib/kube-proxy/kube-proxy-config.yaml`
- **Mode**: iptables (default)

### CNI (Container Network Interface)
- **Purpose**: Container networking specification and plugins
- **Configuration**: `/etc/cni/net.d/`
- **Plugins**: Bridge, loopback, and other networking plugins
- **CIDR**: Pod subnet allocation

## Security Considerations

### Certificate-based Authentication
- Each kubelet uses a unique certificate
- Node authorization ensures kubelets can only access their own resources
- Mutual TLS between all components

### Network Security
- CNI provides network isolation between pods
- iptables rules control traffic flow
- Service networking is separate from pod networking

### Runtime Security
- containerd runs containers in isolated namespaces
- runc provides low-level container runtime
- AppArmor/SELinux can provide additional security

## Troubleshooting

### Service Won't Start

If a service fails to start:

```bash
# Check service status
sudo systemctl status [service-name]

# View detailed logs
sudo journalctl -u [service-name] --no-pager

# Check configuration files
sudo kubelet --config=/var/lib/kubelet/kubelet-config.yaml --dry-run
```

### Node Not Registering

If nodes don't appear in kubectl:

```bash
# Check kubelet logs
sudo journalctl -u kubelet -f

# Verify kubeconfig
sudo cat /var/lib/kubelet/kubeconfig

# Test API server connectivity
curl -k https://10.0.3.10:6443/version
```

### Container Runtime Issues

**Issue**: `crictl: command not found`

**Problem**: The crictl tool wasn't installed during the worker setup.

**Solution**: Install crictl manually:
```bash
# Download crictl
wget -q --show-progress --https-only --timestamping \
  https://github.com/kubernetes-sigs/cri-tools/releases/download/v1.28.0/crictl-v1.28.0-linux-amd64.tar.gz

# Extract and install
tar -xvf crictl-v1.28.0-linux-amd64.tar.gz
chmod +x crictl
sudo mv crictl /usr/local/bin/

# Configure crictl to use containerd endpoint
sudo mkdir -p /etc/crictl
cat <<EOF | sudo tee /etc/crictl/crictl.yaml
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 2
debug: false
pull-image-on-create: false
disable-pull-on-run: false
EOF

# Verify installation
crictl version

# Clean up
rm crictl-v1.28.0-linux-amd64.tar.gz
```

**Issue**: `crictl version` shows permission denied or connection errors

**Problem**: containerd may not be running or crictl configuration is incorrect.

**Issue**: containerd fails to start with "No such file or directory"

**Problem**: containerd binary wasn't installed properly.

**Error message**:
```
Failed to locate executable /bin/containerd: No such file or directory
```

**Solution**: Reinstall containerd binaries:
```bash
# Check if containerd binary exists
ls -la /usr/local/bin/containerd

# If missing, reinstall containerd
cd ~
wget -q --show-progress --https-only --timestamping \
  https://github.com/containerd/containerd/releases/download/v1.7.2/containerd-1.7.2-linux-amd64.tar.gz

# Extract and install containerd
mkdir -p containerd
tar -xvf containerd-1.7.2-linux-amd64.tar.gz -C containerd
sudo mv containerd/bin/* /usr/local/bin/

# Verify installation
ls -la /usr/local/bin/containerd
which containerd

# Start containerd
sudo systemctl start containerd
sudo systemctl enable containerd
sudo systemctl status containerd

# Clean up
rm -rf containerd containerd-1.7.2-linux-amd64.tar.gz
```

**Issue**: containerd takes a long time to start or hangs

**Problem**: Configuration issues, dependency problems, or resource constraints.

**Solution**: Debug containerd startup:
```bash
# 1. Check systemd logs for containerd startup issues
sudo journalctl -u containerd --no-pager -f

# 2. Stop containerd and check configuration
sudo systemctl stop containerd

# 3. Test containerd configuration
sudo containerd config default > /tmp/containerd-default.conf
sudo containerd --config /tmp/containerd-default.conf &

# Kill the test process
sudo pkill containerd

# 4. Check if configuration file is causing issues
sudo mv /etc/containerd/config.toml /etc/containerd/config.toml.backup

# 5. Try starting containerd without custom config
sudo systemctl start containerd
sudo systemctl status containerd

# 6. If it starts without custom config, recreate a minimal config
cat <<EOF | sudo tee /etc/containerd/config.toml
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
EOF

# 7. Restart containerd with new config
sudo systemctl restart containerd
sudo systemctl status containerd
```

**Solution**: 
```bash
# 1. Check if containerd is running
sudo systemctl status containerd

# If not running, start it
sudo systemctl start containerd
sudo systemctl enable containerd

# 2. Verify the containerd socket exists and has correct permissions
ls -la /run/containerd/containerd.sock

# 3. Recreate crictl configuration (fix any heredoc issues)
sudo mkdir -p /etc/crictl
sudo tee /etc/crictl/crictl.yaml > /dev/null <<EOF
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 2
debug: false
pull-image-on-create: false
disable-pull-on-run: false
EOF

# 4. Alternative: Set crictl configuration via environment variable
export CONTAINER_RUNTIME_ENDPOINT=unix:///run/containerd/containerd.sock

# 5. Or use crictl config command
sudo crictl config --set runtime-endpoint=unix:///run/containerd/containerd.sock
sudo crictl config --set image-endpoint=unix:///run/containerd/containerd.sock

# 6. Verify the config file was created correctly
cat /etc/crictl/crictl.yaml

# 7. Test crictl (use sudo for permissions)
sudo crictl version
sudo crictl info
```

```bash
# Check containerd
sudo crictl info

# Test container creation
sudo crictl run --rm -it busybox sh

# Check CNI plugins
ls -la /opt/cni/bin/
```

### Networking Issues

```bash
# Check CNI configuration
cat /etc/cni/net.d/*.conf

# Check network interfaces
ip addr show

# Check routes
ip route show
```

### Cgroup Issues

**Issue**: "Failed to create pod sandbox" with cgroup path format errors

**Problem**: cgroup driver mismatch between kubelet and containerd/runc.

**Error message**:
```
expected cgroupsPath to be of format "slice:prefix:name" for systemd cgroups, got "/kubepods/besteffort/pod..." instead
```

**Root cause**: kubelet is using systemd cgroups but containerd/runc is configured for cgroupfs, or vice versa.

**Solution**: Ensure both kubelet and containerd use the same cgroup driver (cgroupfs):

```bash
# Step 1: Update containerd configuration
cat <<EOF | sudo tee /etc/containerd/config.toml
[plugins]
  [plugins.cri.containerd]
    snapshotter = "overlayfs"
    [plugins.cri.containerd.default_runtime]
      runtime_type = "io.containerd.runc.v2"
      runtime_engine = "/usr/local/bin/runc"
      runtime_root = ""
  [plugins.cri]
    [plugins.cri.containerd.runtimes.runc]
      runtime_type = "io.containerd.runc.v2"
      [plugins.cri.containerd.runtimes.runc.options]
        SystemdCgroup = false
EOF

# Step 2: Restart containerd
sudo systemctl restart containerd

# Step 3: Update kubelet configuration with correct cgroup driver

```bash
# Get certificate name for config
WORKER_NAME=$(hostname -s)
if [[ $WORKER_NAME =~ ^(vm-worker-[0-9]+)-.+$ ]]; then
    CERT_NAME="${BASH_REMATCH[1]}"
else
    CERT_NAME="$WORKER_NAME"
fi

POD_CIDR="10.200.0.0/16"

# Update kubelet config with correct cgroup driver
cat <<EOF | sudo tee /var/lib/kubelet/kubelet-config.yaml
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
cgroupDriver: cgroupfs
clusterDomain: "cluster.local"
clusterDNS:
  - "10.100.0.10"
containerRuntimeEndpoint: "unix:///var/run/containerd/containerd.sock"
nodeName: "${CERT_NAME}"
podCIDR: "${POD_CIDR}"
registerNode: true
resolvConf: "/run/systemd/resolve/resolv.conf"
runtimeRequestTimeout: "15m"
tlsCertFile: "/var/lib/kubelet/${CERT_NAME}.pem"
tlsPrivateKeyFile: "/var/lib/kubelet/${CERT_NAME}-key.pem"
EOF

# Restart kubelet
sudo systemctl restart kubelet

# Check kubelet status and get full error logs
sudo systemctl status kubelet
sudo journalctl -u kubelet --no-pager -l | tail -20

# Verify cgroup driver setting
grep cgroupDriver /var/lib/kubelet/kubelet-config.yaml

# Check containerd status
sudo systemctl status containerd

# Verify pods can now be created
kubectl get pods --kubeconfig /path/to/kubeconfig
```

### Certificate Issues

**Problem**: Node name mismatch with Azure hostname extensions.

When Azure VMs have hostname extensions (like `-kkrcp4`), the kubelet identifies itself with the certificate name but tries to register with the full system hostname, causing authentication errors:

```
csinodes.storage.k8s.io "vm-worker-1-kkrcp4" is forbidden: User "system:node:vm-worker-1" cannot get resource "csinodes"
```

**Root cause**: The kubelet certificate was generated for `vm-worker-1` but the system hostname is `vm-worker-1-kkrcp4`.

**Solution**: Force kubelet to use the logical hostname that matches the certificate:

```bash
# Get the certificate name (logical hostname)
WORKER_NAME=$(hostname -s)
if [[ $WORKER_NAME =~ ^(vm-worker-[0-9]+)-.+$ ]]; then
    CERT_NAME="${BASH_REMATCH[1]}"
else
    CERT_NAME="$WORKER_NAME"
fi

echo "Certificate name: $CERT_NAME"
echo "System hostname: $(hostname)"

# Update kubelet config to use the certificate name as nodeName
sudo sed -i "s/nodeName: .*/nodeName: $CERT_NAME/" /var/lib/kubelet/kubelet-config.yaml

# Restart kubelet
sudo systemctl restart kubelet

# Verify the fix
sudo journalctl -u kubelet --no-pager | tail -5
```

```bash
# Verify certificates
openssl x509 -in /var/lib/kubelet/vm-worker-1.pem -text -noout

# Check certificate expiration
openssl x509 -in /var/lib/kubelet/vm-worker-1.pem -noout -dates

# Verify CA chain
openssl verify -CAfile /var/lib/kubernetes/ca.pem /var/lib/kubelet/vm-worker-1.pem
```

## Performance Tuning

### kubelet Configuration

Optimize kubelet for your workload:

```yaml
# In kubelet-config.yaml
maxPods: 110                    # Default maximum pods per node
podPidsLimit: 2048              # PID limit per pod
registryPullQPS: 5              # Image pull rate limit
registryBurst: 10               # Image pull burst
eventRecordQPS: 5               # Event recording rate limit
```

### containerd Optimization

```toml
# In /etc/containerd/config.toml
[plugins."io.containerd.grpc.v1.cri"]
  max_concurrent_downloads = 3
  max_container_log_line_size = 16384
```

### Resource Monitoring

Monitor worker node resources:

```bash
# Node resource usage
kubectl top nodes

# Pod resource usage
kubectl top pods --all-namespaces

# System resources
free -h
df -h
iostat -x 1
```

Next: [Configuring kubectl for Remote Access](08-configuring-kubectl.md)