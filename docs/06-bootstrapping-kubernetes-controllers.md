# Bootstrapping the Kubernetes Control Plane

In this lab you will bootstrap the Kubernetes control plane across a single compute instance and configure it for high availability. You will also create an external load balancer that exposes the Kubernetes API Servers to remote clients. The following components will be installed on the control plane node: Kubernetes API Server, Scheduler, and Controller Manager.

## Prerequisites

The commands in this lab must be run on the control plane instance: `vm-control-plane`. Login to the control plane instance using SSH from the jumpbox:

```bash
# From the jumpbox, connect to the control plane
ssh azureuser@10.0.3.10
```

## Provision the Kubernetes Control Plane

Create the Kubernetes configuration directory:

```bash
sudo mkdir -p /etc/kubernetes/config
```

### Download and Install the Kubernetes Controller Binaries

Download the official Kubernetes release binaries:

```bash
wget -q --show-progress --https-only --timestamping "https://storage.googleapis.com/kubernetes-release/release/v1.28.0/bin/linux/amd64/kube-apiserver" "https://storage.googleapis.com/kubernetes-release/release/v1.28.0/bin/linux/amd64/kube-controller-manager" "https://storage.googleapis.com/kubernetes-release/release/v1.28.0/bin/linux/amd64/kube-scheduler" "https://storage.googleapis.com/kubernetes-release/release/v1.28.0/bin/linux/amd64/kubectl"
```

Install the Kubernetes binaries:

```bash
chmod +x kube-apiserver kube-controller-manager kube-scheduler kubectl
sudo mv kube-apiserver kube-controller-manager kube-scheduler kubectl /usr/local/bin/
```

### Configure the Kubernetes API Server

```bash
sudo mkdir -p /var/lib/kubernetes/

sudo cp ca.pem ca-key.pem kubernetes-key.pem kubernetes.pem service-account-key.pem service-account.pem encryption-config.yaml /var/lib/kubernetes/
```

The instance internal IP address will be used to advertise the API Server to members of the cluster. Retrieve the internal IP address for the current compute instance:

```bash
INTERNAL_IP=$(ip addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
echo "Internal IP: $INTERNAL_IP"
```

**Important**: Ensure `INTERNAL_IP` is set correctly before creating the service file. If this variable is empty, the API server will fail to start with "failed to parse IP" errors.

Create the `kube-apiserver.service` systemd unit file:

```bash
cat <<EOF | sudo tee /etc/systemd/system/kube-apiserver.service
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-apiserver --advertise-address=${INTERNAL_IP} --allow-privileged=true --apiserver-count=1 --audit-log-maxage=30 --audit-log-maxbackup=3 --audit-log-maxsize=100 --audit-log-path=/var/log/audit.log --authorization-mode=Node,RBAC --bind-address=0.0.0.0 --client-ca-file=/var/lib/kubernetes/ca.pem --enable-admission-plugins=NamespaceLifecycle,NodeRestriction,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota --etcd-cafile=/var/lib/kubernetes/ca.pem --etcd-certfile=/var/lib/kubernetes/kubernetes.pem --etcd-keyfile=/var/lib/kubernetes/kubernetes-key.pem --etcd-servers=https://127.0.0.1:2379 --event-ttl=1h --encryption-provider-config=/var/lib/kubernetes/encryption-config.yaml --kubelet-certificate-authority=/var/lib/kubernetes/ca.pem --kubelet-client-certificate=/var/lib/kubernetes/kubernetes.pem --kubelet-client-key=/var/lib/kubernetes/kubernetes-key.pem --runtime-config='api/all=true' --service-account-key-file=/var/lib/kubernetes/service-account.pem --service-account-signing-key-file=/var/lib/kubernetes/service-account-key.pem --service-account-issuer=https://${INTERNAL_IP}:6443 --service-cluster-ip-range=10.100.0.0/16 --service-node-port-range=30000-32767 --tls-cert-file=/var/lib/kubernetes/kubernetes.pem --tls-private-key-file=/var/lib/kubernetes/kubernetes-key.pem --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

### Configure the Kubernetes Controller Manager

Move the `kube-controller-manager` kubeconfig into place:

```bash
sudo cp kube-controller-manager.kubeconfig /var/lib/kubernetes/
```

Create the `kube-controller-manager.service` systemd unit file:

```bash
cat <<EOF | sudo tee /etc/systemd/system/kube-controller-manager.service
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-controller-manager --bind-address=0.0.0.0 --cluster-cidr=10.200.0.0/16 --cluster-name=kubernetes --cluster-signing-cert-file=/var/lib/kubernetes/ca.pem --cluster-signing-key-file=/var/lib/kubernetes/ca-key.pem --kubeconfig=/var/lib/kubernetes/kube-controller-manager.kubeconfig --leader-elect=true --root-ca-file=/var/lib/kubernetes/ca.pem --service-account-private-key-file=/var/lib/kubernetes/service-account-key.pem --service-cluster-ip-range=10.100.0.0/16 --use-service-account-credentials=true --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

### Configure the Kubernetes Scheduler

Move the `kube-scheduler` kubeconfig into place:

```bash
sudo cp kube-scheduler.kubeconfig /var/lib/kubernetes/
```

Create the `kube-scheduler.yaml` configuration file:

```bash
cat <<EOF | sudo tee /etc/kubernetes/config/kube-scheduler.yaml
apiVersion: kubescheduler.config.k8s.io/v1beta3
kind: KubeSchedulerConfiguration
clientConnection:
  kubeconfig: "/var/lib/kubernetes/kube-scheduler.kubeconfig"
leaderElection:
  leaderElect: true
EOF
```

Create the `kube-scheduler.service` systemd unit file:

```bash
cat <<EOF | sudo tee /etc/systemd/system/kube-scheduler.service
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-scheduler --config=/etc/kubernetes/config/kube-scheduler.yaml --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

### Start the Controller Services

```bash
sudo systemctl daemon-reload
sudo systemctl enable kube-apiserver kube-controller-manager kube-scheduler
sudo systemctl start kube-apiserver kube-controller-manager kube-scheduler
```

> Allow up to 10 seconds for the Kubernetes API Server to fully initialize.

## Verification

### Check Service Status

```bash
# Check that all services are running
sudo systemctl status kube-apiserver kube-controller-manager kube-scheduler

# Check service logs
sudo journalctl -u kube-apiserver
sudo journalctl -u kube-controller-manager  
sudo journalctl -u kube-scheduler
```

### Test the Kubernetes API Server

```bash
# Test API server locally
curl --cacert /var/lib/kubernetes/ca.pem https://127.0.0.1:6443/version

# Test with kubectl (once configured)
kubectl cluster-info --kubeconfig admin.kubeconfig
```

### Troubleshooting Common Issues

**Issue: "invalid argument "" for "--advertise-address" flag: failed to parse IP: """**
- The `${INTERNAL_IP}` variable was not expanded in the service file
- Service file contains literal `${INTERNAL_IP}` instead of actual IP address
- This usually happens when the variable wasn't set before creating the service

**Common causes:**
- Didn't set `INTERNAL_IP` variable before creating service file
- Variable lost scope when using `sudo` commands
- Copy-pasted the service creation without setting the variable first

**Solution:**
```bash
# Check current service file for unexpanded variables
sudo cat /etc/systemd/system/kube-apiserver.service | grep advertise-address

# If you see ${INTERNAL_IP} instead of actual IP, recreate the service file
INTERNAL_IP=$(ip addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
echo "INTERNAL_IP should be: $INTERNAL_IP"

# Recreate the service file with actual IP values
cat <<EOF | sudo tee /etc/systemd/system/kube-apiserver.service
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-apiserver --advertise-address=${INTERNAL_IP} --allow-privileged=true --apiserver-count=1 --audit-log-maxage=30 --audit-log-maxbackup=3 --audit-log-maxsize=100 --audit-log-path=/var/log/audit.log --authorization-mode=Node,RBAC --bind-address=0.0.0.0 --client-ca-file=/var/lib/kubernetes/ca.pem --enable-admission-plugins=NamespaceLifecycle,NodeRestriction,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota --etcd-cafile=/var/lib/kubernetes/ca.pem --etcd-certfile=/var/lib/kubernetes/kubernetes.pem --etcd-keyfile=/var/lib/kubernetes/kubernetes-key.pem --etcd-servers=https://127.0.0.1:2379 --event-ttl=1h --encryption-provider-config=/var/lib/kubernetes/encryption-config.yaml --kubelet-certificate-authority=/var/lib/kubernetes/ca.pem --kubelet-client-certificate=/var/lib/kubernetes/kubernetes.pem --kubelet-client-key=/var/lib/kubernetes/kubernetes-key.pem --runtime-config='api/all=true' --service-account-key-file=/var/lib/kubernetes/service-account.pem --service-account-signing-key-file=/var/lib/kubernetes/service-account-key.pem --service-account-issuer=https://${INTERNAL_IP}:6443 --service-cluster-ip-range=10.100.0.0/16 --service-node-port-range=30000-32767 --tls-cert-file=/var/lib/kubernetes/kubernetes.pem --tls-private-key-file=/var/lib/kubernetes/kubernetes-key.pem --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Reload and restart the API server
sudo systemctl daemon-reload
sudo systemctl restart kube-apiserver

# Check if it's now working
sudo systemctl status kube-apiserver
sudo journalctl -u kube-apiserver --no-pager | tail -10
```

**Issue: "connection refused" when testing API server**
- API server may still be starting up
- Check if etcd is running and accessible

**Solution:**
```bash
# Verify etcd is running and accessible
sudo systemctl status etcd
curl -k https://127.0.0.1:2379/health

# Check API server logs for specific errors
sudo journalctl -u kube-apiserver --no-pager | tail -20

# Wait a bit more for startup (API server can take 30+ seconds)
sleep 30
curl --cacert /var/lib/kubernetes/ca.pem https://127.0.0.1:6443/version
```

## RBAC for Kubelet Authorization

In this section you will configure RBAC permissions to allow the Kubernetes API Server to access the Kubelet API on each worker node. Access to the Kubelet API is required for retrieving metrics, logs, and executing commands in pods.

> The commands in this section will effect the entire cluster and only need to be run once from one of the controller nodes.

From the jumpbox, create the `system:kube-apiserver-to-kubelet` [ClusterRole](https://kubernetes.io/docs/admin/authorization/rbac/#role-and-clusterrole) with permissions to access the Kubelet API and perform most common tasks associated with managing pods:

```bash
# From the jumpbox, configure kubectl to connect to the API server
cd ~/kubernetes-the-hard-way-azure/certificates

# Set up kubectl configuration
kubectl config set-cluster kubernetes-the-hard-way --certificate-authority=ca.pem --embed-certs=true --server=https://10.0.3.10:6443

kubectl config set-credentials admin --client-certificate=admin.pem --client-key=admin-key.pem

kubectl config set-context kubernetes-the-hard-way --cluster=kubernetes-the-hard-way --user=admin

kubectl config use-context kubernetes-the-hard-way

# Test connection
kubectl cluster-info
kubectl get componentstatuses
```

Create the ClusterRole and ClusterRoleBinding:

```bash
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
```

## Understanding the Control Plane Components

### API Server
- **Purpose**: Central management entity and communication hub
- **Functions**: Authentication, authorization, validation, and serving the API
- **Port**: 6443 (HTTPS)
- **Dependencies**: etcd for data storage

### Controller Manager
- **Purpose**: Runs controller processes (background threads)
- **Functions**: Node controller, Replication controller, Endpoints controller, Service Account & Token controllers
- **Communication**: Connects to API server
- **Dependencies**: API server availability

### Scheduler
- **Purpose**: Watches for newly created pods and assigns them to nodes
- **Functions**: Resource requirements, hardware constraints, affinity rules
- **Algorithm**: Filtering and scoring of nodes
- **Dependencies**: API server availability

## Security Considerations

### TLS Configuration
- All components communicate via TLS
- Mutual TLS (mTLS) between components
- Certificate-based authentication

### RBAC
- Role-Based Access Control enabled
- Principle of least privilege
- Service account automation

### Audit Logging
- API server actions are audited
- Logs stored in `/var/log/audit.log`
- Configurable audit policies

## Troubleshooting

### Service Won't Start

If a service fails to start:

1. Check systemd status: `sudo systemctl status [service-name]`
2. View logs: `sudo journalctl -u [service-name] --no-pager`
3. Check certificate files: `ls -la /var/lib/kubernetes/`
4. Verify port availability: `sudo netstat -tlnp | grep [port]`

### API Server Issues

Common API server problems:

```bash
# Check if API server is responding
curl -k https://127.0.0.1:6443/healthz

# Check certificate validity
openssl x509 -in /var/lib/kubernetes/kubernetes.pem -text -noout

# Check etcd connectivity
sudo ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/etcd/ca.pem --cert=/etc/etcd/kubernetes.pem --key=/etc/etcd/kubernetes-key.pem endpoint health
```

### Controller Manager Issues

```bash
# Check controller manager logs
sudo journalctl -u kube-controller-manager -f

# Verify kubeconfig
kubectl config view --kubeconfig=/var/lib/kubernetes/kube-controller-manager.kubeconfig
```

### Scheduler Issues

```bash
# Check scheduler logs
sudo journalctl -u kube-scheduler -f

# Test scheduler config
kubectl config view --kubeconfig=/var/lib/kubernetes/kube-scheduler.kubeconfig
```

## Monitoring and Maintenance

### Health Checks

Create a health check script:

```bash
cat > ~/check-control-plane.sh << 'EOF'
#!/bin/bash

echo "=== Control Plane Health Check ==="

# Check systemd services
echo "Service Status:"
for service in kube-apiserver kube-controller-manager kube-scheduler; do
    if systemctl is-active --quiet $service; then
        echo "✓ $service is running"
    else
        echo "✗ $service is not running"
    fi
done

# Check API server
echo -e "\nAPI Server:"
if curl -k -s https://127.0.0.1:6443/healthz | grep -q "ok"; then
    echo "✓ API server is healthy"
else
    echo "✗ API server is not responding"
fi

# Check component status
echo -e "\nComponent Status:"
kubectl get componentstatuses 2>/dev/null || echo "Unable to get component status"

echo -e "\nCheck complete."
EOF

chmod +x ~/check-control-plane.sh
```

### Performance Monitoring

Monitor key metrics:

```bash
# CPU and memory usage
top -p $(pgrep -f kube-apiserver) -p $(pgrep -f kube-controller-manager) -p $(pgrep -f kube-scheduler)

# API server metrics (if metrics are enabled)
curl -k https://127.0.0.1:6443/metrics

# Disk usage for etcd
df -h /var/lib/etcd
```

Next: [Bootstrapping the Kubernetes Worker Nodes](07-bootstrapping-kubernetes-workers.md)