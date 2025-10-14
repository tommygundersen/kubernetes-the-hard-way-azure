# Configuring kubectl for Remote Access

In this lab you will generate a kubeconfig file for the `kubectl` command line utility based on the `admin` user credentials.

> Run the commands in this lab from the jumpbox VM.

## The Admin Kubernetes Configuration File

Each kubeconfig requires a Kubernetes API Server to connect to. To support high availability the IP address assigned to the external load balancer fronting the Kubernetes API Servers will be used.

### Generate a kubeconfig file suitable for authenticating as the `admin` user

```bash
# Ensure we're in the certificates directory on the jumpbox
cd ~/kubernetes-the-hard-way-azure/certificates

# Set the Kubernetes API server address (control plane private IP)
KUBERNETES_PUBLIC_ADDRESS="10.0.3.10"
echo "Kubernetes API Server: ${KUBERNETES_PUBLIC_ADDRESS}"
```

Generate a kubeconfig file suitable for authenticating as the `admin` user:

```bash
kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=ca.pem \
  --embed-certs=true \
  --server=https://${KUBERNETES_PUBLIC_ADDRESS}:6443

kubectl config set-credentials admin \
  --client-certificate=admin.pem \
  --client-key=admin-key.pem

kubectl config set-context kubernetes-the-hard-way \
  --cluster=kubernetes-the-hard-way \
  --user=admin

kubectl config use-context kubernetes-the-hard-way
```

## Verification

Check the health of the remote Kubernetes cluster:

```bash
kubectl cluster-info
```

Output:

```
Kubernetes control plane is running at https://10.0.3.10:6443
```

List the nodes in the remote Kubernetes cluster:

```bash
kubectl get nodes
```

Output:

```
NAME           STATUS   ROLES    AGE   VERSION
vm-worker-1    Ready    <none>   2m    v1.28.0
vm-worker-2    Ready    <none>   2m    v1.28.0
```

## Setting Up kubectl on Your Local Machine

If you want to manage the cluster from your local machine (outside Azure), you'll need to set up kubectl with the appropriate configuration.

### Prerequisites for Local Access

For local access, you would need:

1. **Public IP or VPN access** to the control plane (not covered in this tutorial as we're using private IPs only)
2. **kubectl installed** on your local machine
3. **Admin certificates** copied to your local machine

### Alternative: Using Azure Bastion for kubectl Access

Since our setup uses private IPs only, the recommended approach is to use kubectl from the jumpbox through Azure Bastion:

#### Option 1: Direct Bastion SSH
1. Connect to jumpbox via Azure Bastion
2. Use kubectl directly from the jumpbox terminal

#### Option 2: Bastion Tunneling (Advanced)
You can create an SSH tunnel through Bastion to access the cluster from your local machine:

```bash
# This would require additional Azure CLI configuration
# Not recommended for this educational setup
```

## Managing Multiple Clusters

If you're managing multiple Kubernetes clusters, you can configure kubectl to switch between them:

### View Available Contexts

```bash
kubectl config get-contexts
```

### Switch Between Contexts

```bash
# Switch to a specific context
kubectl config use-context kubernetes-the-hard-way

# View current context
kubectl config current-context
```

### Merge Multiple Kubeconfig Files

```bash
# Set KUBECONFIG environment variable to merge configs
export KUBECONFIG=~/.kube/config:~/kubernetes-the-hard-way-azure/certificates/admin.kubeconfig

# View merged configuration
kubectl config view

# Make the merge permanent
kubectl config view --flatten > ~/.kube/config-merged
cp ~/.kube/config-merged ~/.kube/config
```

## Advanced kubectl Configuration

### Creating Namespace-Specific Contexts

Create contexts that default to specific namespaces:

```bash
# Create a context for development namespace
kubectl config set-context dev \
  --cluster=kubernetes-the-hard-way \
  --user=admin \
  --namespace=development

# Create a context for production namespace
kubectl config set-context prod \
  --cluster=kubernetes-the-hard-way \
  --user=admin \
  --namespace=production

# Create the namespaces
kubectl create namespace development
kubectl create namespace production

# Switch to development context
kubectl config use-context dev

# Verify you're in the development namespace
kubectl config get-contexts
```

### Setting Up kubectl Aliases

Create helpful aliases for common kubectl commands:

```bash
# Add to ~/.bashrc or ~/.zshrc
cat >> ~/.bashrc << 'EOF'

# Kubectl aliases
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get services'
alias kgn='kubectl get nodes'
alias kdf='kubectl delete --force --grace-period=0'
alias kdp='kubectl describe pod'
alias kds='kubectl describe service'
alias kdn='kubectl describe node'

# Context switching
alias kctx='kubectl config current-context'
alias kns='kubectl config set-context --current --namespace'

# Quick namespace switching
alias kcd='kubectl config use-context dev'
alias kcp='kubectl config use-context prod'
alias kcm='kubectl config use-context kubernetes-the-hard-way'
EOF

# Reload bash configuration
source ~/.bashrc
```

### Auto-completion

Enable kubectl auto-completion:

```bash
# For bash
echo 'source <(kubectl completion bash)' >> ~/.bashrc

# For zsh
echo 'source <(kubectl completion zsh)' >> ~/.zshrc

# If using alias 'k' for kubectl
echo 'complete -F __start_kubectl k' >> ~/.bashrc

# Reload shell
source ~/.bashrc
```

## Understanding kubeconfig Structure

### kubeconfig File Components

A kubeconfig file contains three main sections:

```yaml
apiVersion: v1
kind: Config
# Cluster definitions
clusters:
- cluster:
    certificate-authority-data: <base64-encoded-ca-cert>
    server: https://10.0.3.10:6443
  name: kubernetes-the-hard-way

# User credentials
users:
- name: admin
  user:
    client-certificate-data: <base64-encoded-client-cert>
    client-key-data: <base64-encoded-client-key>

# Context definitions (cluster + user + namespace)
contexts:
- context:
    cluster: kubernetes-the-hard-way
    user: admin
    namespace: default
  name: kubernetes-the-hard-way

# Current active context
current-context: kubernetes-the-hard-way
```

### Environment Variables

kubectl configuration can be influenced by environment variables:

```bash
# Override default kubeconfig location
export KUBECONFIG=~/my-custom-kubeconfig

# Set default namespace for all kubectl commands
export KUBECTL_NAMESPACE=development

# Enable debug logging
export KUBECTL_TRACE=1
```

## Security Best Practices

### Protecting kubeconfig Files

```bash
# Set appropriate permissions on kubeconfig files
chmod 600 ~/.kube/config
chmod 600 ~/kubernetes-the-hard-way-azure/certificates/admin.kubeconfig

# Verify permissions
ls -la ~/.kube/config
```

### Regular Certificate Rotation

```bash
# Check certificate expiration
openssl x509 -in ~/kubernetes-the-hard-way-azure/certificates/admin.pem -noout -dates

# Monitor certificate expiration (add to cron)
cat > ~/check-cert-expiry.sh << 'EOF'
#!/bin/bash
CERT_FILE="~/kubernetes-the-hard-way-azure/certificates/admin.pem"
EXPIRY_DATE=$(openssl x509 -in $CERT_FILE -noout -enddate | cut -d= -f2)
EXPIRY_EPOCH=$(date -d "$EXPIRY_DATE" +%s)
CURRENT_EPOCH=$(date +%s)
DAYS_UNTIL_EXPIRY=$(( ($EXPIRY_EPOCH - $CURRENT_EPOCH) / 86400 ))

if [ $DAYS_UNTIL_EXPIRY -lt 30 ]; then
    echo "WARNING: Certificate expires in $DAYS_UNTIL_EXPIRY days"
fi
EOF

chmod +x ~/check-cert-expiry.sh
```

### Audit kubectl Commands

Enable audit logging for kubectl commands:

```bash
# Set up command logging
export KUBECTL_COMMAND_HEADERS=true

# Log all kubectl commands
export KUBECTL_LOG_LEVEL=2

# Create a kubectl wrapper for logging
cat > ~/kubectl-wrapper.sh << 'EOF'
#!/bin/bash
echo "$(date): kubectl $*" >> ~/.kubectl-audit.log
kubectl "$@"
EOF

chmod +x ~/kubectl-wrapper.sh
alias kubectl='~/kubectl-wrapper.sh'
```

## Troubleshooting kubectl

### Connection Issues

```bash
# Test basic connectivity
kubectl cluster-info

# Get detailed connection info
kubectl cluster-info dump

# Check authentication
kubectl auth whoami

# Test API server access
curl -k https://10.0.3.10:6443/version
```

### Certificate Issues

```bash
# Verify certificate is valid
openssl x509 -in certificates/admin.pem -text -noout

# Check certificate chain
openssl verify -CAfile certificates/ca.pem certificates/admin.pem

# Debug TLS handshake
kubectl get nodes -v=8
```

### Configuration Issues

```bash
# View current configuration
kubectl config view

# Validate configuration
kubectl config validate

# Check current context
kubectl config current-context

# List all contexts
kubectl config get-contexts
```

### Common Error Messages

#### "Unable to connect to the server"
```bash
# Check if API server is running
ssh azureuser@10.0.3.10 'sudo systemctl status kube-apiserver'

# Check network connectivity
ping 10.0.3.10
telnet 10.0.3.10 6443
```

#### "error: You must be logged in to the server (Unauthorized)"
```bash
# Check certificate files exist
ls -la certificates/admin.pem certificates/admin-key.pem

# Verify certificate is not expired
openssl x509 -in certificates/admin.pem -noout -dates

# Check kubeconfig file
kubectl config view --raw
```

#### "The connection to the server was refused"
```bash
# Check API server is listening
ssh azureuser@10.0.3.10 'sudo netstat -tlnp | grep 6443'

# Check API server logs
ssh azureuser@10.0.3.10 'sudo journalctl -u kube-apiserver -f'
```

## kubectl Plugins and Extensions

### Installing kubectl plugins

```bash
# Install krew (kubectl plugin manager)
(
  set -x; cd "$(mktemp -d)" &&
  OS="$(uname | tr '[:upper:]' '[:lower:]')" &&
  ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')" &&
  KREW="krew-${OS}_${ARCH}" &&
  curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz" &&
  tar zxvf "${KREW}.tar.gz" &&
  ./"${KREW}" install krew
)

# Add krew to PATH
echo 'export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# Install useful plugins
kubectl krew install ctx    # Context switching
kubectl krew install ns     # Namespace switching
kubectl krew install tree   # Resource hierarchy
kubectl krew install tail   # Log tailing
```

### Useful kubectl Plugins

```bash
# Switch contexts easily
kubectl ctx kubernetes-the-hard-way

# Switch namespaces easily
kubectl ns development

# View resource trees
kubectl tree deployment nginx

# Tail logs from multiple pods
kubectl tail -l app=nginx
```

## Remote Access Summary

You now have kubectl configured to remotely manage your Kubernetes cluster from the jumpbox. Key points:

✅ **Admin access configured** - Full cluster administration capabilities  
✅ **Secure authentication** - Certificate-based authentication  
✅ **Context management** - Easy switching between clusters/namespaces  
✅ **Troubleshooting tools** - Debugging connection and auth issues  
✅ **Security practices** - Proper file permissions and audit trails  

The cluster is now ready for pod network configuration and testing!

Next: [Provisioning Pod Network Routes](09-pod-network-routes.md)