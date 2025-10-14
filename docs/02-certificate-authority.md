# Certificate Authority

In this lab you will provision a [PKI Infrastructure](https://en.wikipedia.org/wiki/Public_key_infrastructure) using CloudFlare's PKI toolkit, [cfssl](https://github.com/cloudflare/cfssl), then use it to bootstrap a Certificate Authority, and generate TLS certificates for the following components: etcd, kube-apiserver, kube-controller-manager, kube-scheduler, kubelet, and kube-proxy.

## Certificate Authority

In this section you will provision a Certificate Authority that can be used to generate additional TLS certificates.

Generate the CA configuration file, certificate, and private key:

```bash
# Ensure you're in the repository directory and have sourced environment variables
cd ~/kubernetes-the-hard-way-azure
source ~/k8s-env.sh

# Create certificates directory
mkdir -p certificates
cd certificates
```

### Create the CA Configuration File

```bash
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
```

### Create the CA Certificate Signing Request

```bash
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
```

### Generate the CA Certificate and Private Key

```bash
cfssl gencert -initca ca-csr.json | cfssljson -bare ca
```

Results:

```
ca-key.pem
ca.pem
```

## Client and Server Certificates

In this section you will generate client and server certificates for each Kubernetes component and a client certificate for the Kubernetes `admin` user.

### The Admin Client Certificate

Generate the `admin` client certificate and private key:

```bash
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
```

Results:

```
admin-key.pem
admin.pem
```

### The Kubelet Client Certificates

Kubernetes uses a [special-purpose authorization mode](https://kubernetes.io/docs/admin/authorization/node/) called Node Authorizer, that specifically authorizes API requests made by [Kubelets](https://kubernetes.io/docs/concepts/overview/components/#kubelet). In order to be authorized by the Node Authorizer, Kubelets must use a credential that identifies them as being in the `system:nodes` group, with a username of `system:node:<nodeName>`. In this section you will create a certificate for each Kubernetes worker node that meets the Node Authorizer requirements.

Generate a certificate and private key for each Kubernetes worker node:

```bash
# Worker 1
cat > ${WORKER_1_HOSTNAME}-csr.json << EOF
{
  "CN": "system:node:${WORKER_1_HOSTNAME}",
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
  -hostname=${WORKER_1_HOSTNAME},${WORKER_1_IP} \
  -profile=kubernetes \
  ${WORKER_1_HOSTNAME}-csr.json | cfssljson -bare ${WORKER_1_HOSTNAME}

# Worker 2
cat > ${WORKER_2_HOSTNAME}-csr.json << EOF
{
  "CN": "system:node:${WORKER_2_HOSTNAME}",
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
  -hostname=${WORKER_2_HOSTNAME},${WORKER_2_IP} \
  -profile=kubernetes \
  ${WORKER_2_HOSTNAME}-csr.json | cfssljson -bare ${WORKER_2_HOSTNAME}
```

Results:

```
vm-worker-1-key.pem
vm-worker-1.pem
vm-worker-2-key.pem
vm-worker-2.pem
```

### The Controller Manager Client Certificate

Generate the `kube-controller-manager` client certificate and private key:

```bash
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
```

Results:

```
kube-controller-manager-key.pem
kube-controller-manager.pem
```

### The Kube Proxy Client Certificate

Generate the `kube-proxy` client certificate and private key:

```bash
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
```

Results:

```
kube-proxy-key.pem
kube-proxy.pem
```

### The Scheduler Client Certificate

Generate the `kube-scheduler` client certificate and private key:

```bash
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
```

Results:

```
kube-scheduler-key.pem
kube-scheduler.pem
```

### The Kubernetes API Server Certificate

The `kubernetes-api-server` certificate requires all names that various components may reach it to be part of the alternate names. These include the different DNS names, and IP addresses such as the master servers IP address, the load balancers IP address, the kube-api service IP address etc.

The IP `10.100.0.1` is designated as the first IP in the services subnet and will be assigned to the `kubernetes` service which is created by default.

**Important**: `127.0.0.1` is required because:
- The API server connects to etcd on localhost (`https://127.0.0.1:2379`)
- kube-controller-manager and kube-scheduler connect to API server on localhost (`https://127.0.0.1:6443`)
- etcd listens on both external IP and localhost for different purposes

Generate the Kubernetes API Server certificate and private key:

```bash
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
  -hostname=10.100.0.1,127.0.0.1,${CONTROL_PLANE_IP},${CONTROL_PLANE_HOSTNAME},kubernetes,kubernetes.default,kubernetes.default.svc,kubernetes.default.svc.cluster,kubernetes.default.svc.cluster.local \
  -profile=kubernetes \
  kubernetes-csr.json | cfssljson -bare kubernetes
```

Results:

```
kubernetes-key.pem
kubernetes.pem
```

## The Service Account Key Pair

The Kubernetes Controller Manager leverages a key pair to generate and sign service account tokens as described in the [managing service accounts](https://kubernetes.io/docs/admin/service-accounts-admin/) documentation.

Generate the `service-account` certificate and private key:

```bash
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
```

Results:

```
service-account-key.pem
service-account.pem
```

## Distribute the Client and Server Certificates

Copy the appropriate certificates and private keys to each worker instance:

```bash
# Copy certificates to worker nodes
scp ca.pem vm-worker-1-key.pem vm-worker-1.pem azureuser@${WORKER_1_IP}:~/
scp ca.pem vm-worker-2-key.pem vm-worker-2.pem azureuser@${WORKER_2_IP}:~/
```

Copy the appropriate certificates and private keys to the controller instance:

```bash
# Copy certificates to control plane
scp ca.pem ca-key.pem kubernetes-key.pem kubernetes.pem \
    service-account-key.pem service-account.pem azureuser@${CONTROL_PLANE_IP}:~/
```

> The `kube-proxy`, `kube-controller-manager`, `kube-scheduler`, and `kubelet` client certificates will be used to generate client authentication configuration files in the next lab.

## Verification

List the generated certificates:

```bash
ls -la *.pem
```

You should see the following files:

```
admin-key.pem
admin.pem
ca-key.pem
ca.pem
kube-controller-manager-key.pem
kube-controller-manager.pem
kube-proxy-key.pem
kube-proxy.pem
kube-scheduler-key.pem
kube-scheduler.pem
kubernetes-key.pem
kubernetes.pem
service-account-key.pem
service-account.pem
vm-worker-1-key.pem
vm-worker-1.pem
vm-worker-2-key.pem
vm-worker-2.pem
```

### Verify Certificate Information

You can inspect any certificate to verify its information:

```bash
# Check the CA certificate
openssl x509 -in ca.pem -text -noout

# Check the Kubernetes API server certificate
openssl x509 -in kubernetes.pem -text -noout

# Check a worker node certificate
openssl x509 -in vm-worker-1.pem -text -noout
```

### Test Certificate Distribution

Verify that certificates were copied to the VMs:

```bash
# Check control plane
ssh azureuser@${CONTROL_PLANE_IP} 'ls -la *.pem'

# Check worker nodes
ssh azureuser@${WORKER_1_IP} 'ls -la *.pem'
ssh azureuser@${WORKER_2_IP} 'ls -la *.pem'
```

## Troubleshooting

### Certificate Generation Issues

If certificate generation fails:

1. Verify cfssl is installed: `cfssl version`
2. Check the JSON syntax in CSR files: `cat filename.json | jq .`
3. Ensure the CA files exist: `ls -la ca.pem ca-key.pem`

### File Copy Issues

If scp fails:

1. Test SSH connectivity: `ssh azureuser@${CONTROL_PLANE_IP} 'hostname'`
2. Check SSH key permissions: `ls -la ~/.ssh/id_rsa`
3. Try copying files one by one to identify the issue

### Certificate Verification

To verify a certificate was signed by the CA:

```bash
openssl verify -CAfile ca.pem kubernetes.pem
```

Next: [Kubernetes Configuration Files](03-kubernetes-configuration-files.md)