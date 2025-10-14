# Kubernetes Configuration Files

In this lab you will generate [Kubernetes configuration files](https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/), also known as kubeconfigs, which enable Kubernetes clients to locate and authenticate to the Kubernetes API Servers.

## Client Authentication Configs

In this section you will generate kubeconfig files for the `controller manager`, `kubelet`, `kube-proxy`, `scheduler` clients and the `admin` user.

### Kubernetes Public IP Address

Each kubeconfig requires a Kubernetes API Server to connect to. To support high availability the IP address assigned to the external load balancer fronting the Kubernetes API Servers will be used.

In our setup, the control plane is accessible via its private IP address:

```bash
# Ensure environment variables are loaded
source ~/k8s-env.sh

# Set the Kubernetes API server address
KUBERNETES_PUBLIC_ADDRESS=${CONTROL_PLANE_IP}

echo "Kubernetes API Server: ${KUBERNETES_PUBLIC_ADDRESS}"
```

### The kubelet Kubernetes Configuration File

When generating kubeconfig files for Kubelets the client certificate matching the Kubelet's node name must be used. This will ensure Kubelets are properly authorized by the Kubernetes [Node Authorizer](https://kubernetes.io/docs/admin/authorization/node/).

Generate a kubeconfig file for each worker node:

```bash
# Ensure we're in the certificates directory
cd ~/kubernetes-the-hard-way-azure/certificates

# Generate kubeconfig for worker node 1
kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=ca.pem \
  --embed-certs=true \
  --server=https://${KUBERNETES_PUBLIC_ADDRESS}:6443 \
  --kubeconfig=${WORKER_1_HOSTNAME}.kubeconfig

kubectl config set-credentials system:node:${WORKER_1_HOSTNAME} \
  --client-certificate=${WORKER_1_HOSTNAME}.pem \
  --client-key=${WORKER_1_HOSTNAME}-key.pem \
  --embed-certs=true \
  --kubeconfig=${WORKER_1_HOSTNAME}.kubeconfig

kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=system:node:${WORKER_1_HOSTNAME} \
  --kubeconfig=${WORKER_1_HOSTNAME}.kubeconfig

kubectl config use-context default --kubeconfig=${WORKER_1_HOSTNAME}.kubeconfig

# Generate kubeconfig for worker node 2
kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=ca.pem \
  --embed-certs=true \
  --server=https://${KUBERNETES_PUBLIC_ADDRESS}:6443 \
  --kubeconfig=${WORKER_2_HOSTNAME}.kubeconfig

kubectl config set-credentials system:node:${WORKER_2_HOSTNAME} \
  --client-certificate=${WORKER_2_HOSTNAME}.pem \
  --client-key=${WORKER_2_HOSTNAME}-key.pem \
  --embed-certs=true \
  --kubeconfig=${WORKER_2_HOSTNAME}.kubeconfig

kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=system:node:${WORKER_2_HOSTNAME} \
  --kubeconfig=${WORKER_2_HOSTNAME}.kubeconfig

kubectl config use-context default --kubeconfig=${WORKER_2_HOSTNAME}.kubeconfig
```

Results:

```
vm-worker-1.kubeconfig
vm-worker-2.kubeconfig
```

### The kube-proxy Kubernetes Configuration File

Generate a kubeconfig file for the `kube-proxy` service:

```bash
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
```

Results:

```
kube-proxy.kubeconfig
```

### The kube-controller-manager Kubernetes Configuration File

Generate a kubeconfig file for the `kube-controller-manager` service:

```bash
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
```

Results:

```
kube-controller-manager.kubeconfig
```

### The kube-scheduler Kubernetes Configuration File

Generate a kubeconfig file for the `kube-scheduler` service:

```bash
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
```

Results:

```
kube-scheduler.kubeconfig
```

### The admin Kubernetes Configuration File

Generate a kubeconfig file for the `admin` user:

```bash
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
```

Results:

```
admin.kubeconfig
```

## Distribute the Kubernetes Configuration Files

Copy the appropriate `kubelet` and `kube-proxy` kubeconfig files to each worker instance:

```bash
# Copy kubeconfig files to worker nodes
scp ${WORKER_1_HOSTNAME}.kubeconfig kube-proxy.kubeconfig azureuser@${WORKER_1_IP}:~/
scp ${WORKER_2_HOSTNAME}.kubeconfig kube-proxy.kubeconfig azureuser@${WORKER_2_IP}:~/
```

Copy the appropriate `kube-controller-manager` and `kube-scheduler` kubeconfig files to the controller instance:

```bash
# Copy kubeconfig files to control plane
scp admin.kubeconfig kube-controller-manager.kubeconfig kube-scheduler.kubeconfig azureuser@${CONTROL_PLANE_IP}:~/
```

## Verification

### List Generated Kubeconfig Files

```bash
ls -la *.kubeconfig
```

You should see:

```
admin.kubeconfig
kube-controller-manager.kubeconfig
kube-proxy.kubeconfig
kube-scheduler.kubeconfig
vm-worker-1.kubeconfig
vm-worker-2.kubeconfig
```

### Verify Kubeconfig Content

Inspect the contents of a kubeconfig file:

```bash
# View the admin kubeconfig
kubectl config view --kubeconfig=admin.kubeconfig

# View the kube-proxy kubeconfig
kubectl config view --kubeconfig=kube-proxy.kubeconfig

# View a worker node kubeconfig
kubectl config view --kubeconfig=${WORKER_1_HOSTNAME}.kubeconfig
```

### Verify File Distribution

Check that kubeconfig files were copied to the VMs:

```bash
# Check control plane
ssh azureuser@${CONTROL_PLANE_IP} 'ls -la *.kubeconfig'

# Check worker nodes
ssh azureuser@${WORKER_1_IP} 'ls -la *.kubeconfig'
ssh azureuser@${WORKER_2_IP} 'ls -la *.kubeconfig'
```

### Test Kubeconfig Syntax

Validate the syntax of generated kubeconfig files:

```bash
# Test each kubeconfig file
for config in *.kubeconfig; do
  echo "Testing $config..."
  kubectl config view --kubeconfig=$config > /dev/null && echo "✓ $config is valid" || echo "✗ $config has errors"
done
```

## Understanding Kubeconfig Files

Each kubeconfig file contains three main sections:

1. **Clusters**: Defines the Kubernetes cluster and its API server endpoint
2. **Users**: Defines the client credentials for authentication
3. **Contexts**: Links a cluster with a user and optionally a namespace

### Example kubeconfig structure:

```yaml
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: <base64-encoded-ca-cert>
    server: https://10.0.3.10:6443
  name: kubernetes-the-hard-way
contexts:
- context:
    cluster: kubernetes-the-hard-way
    user: admin
  name: default
current-context: default
users:
- name: admin
  user:
    client-certificate-data: <base64-encoded-client-cert>
    client-key-data: <base64-encoded-client-key>
```

## Security Considerations

- Each component has its own certificate and kubeconfig for proper authentication
- The controller manager and scheduler connect to localhost (127.0.0.1) for security
- Worker nodes connect to the control plane's private IP address
- All certificates are embedded in the kubeconfig files for portability

## Troubleshooting

### Invalid Kubeconfig Files

If a kubeconfig file is invalid:

1. Check the certificate files exist: `ls -la *.pem`
2. Verify the JSON/YAML syntax: `kubectl config view --kubeconfig=filename.kubeconfig`
3. Regenerate the problematic kubeconfig file

### Copy Issues

If files aren't copying correctly:

1. Verify SSH connectivity: `ssh azureuser@${CONTROL_PLANE_IP} 'hostname'`
2. Check file permissions: `ls -la *.kubeconfig`
3. Try copying files individually to identify issues

### Certificate Issues

If certificates are not being embedded:

1. Verify certificate files exist and are readable
2. Check that the `--embed-certs=true` flag is used
3. Ensure you're using the correct certificate files for each component

Next: [Data Encryption Keys](04-data-encryption-keys.md)