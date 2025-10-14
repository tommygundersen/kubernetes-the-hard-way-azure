# Smoke Test

In this lab you will complete a series of tasks to ensure your Kubernetes cluster is functioning correctly.

## Data Encryption

In this section you will verify the ability to [encrypt secret data at rest](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/#verifying-that-data-is-encrypted).

Create a generic secret:

```bash
kubectl create secret generic kubernetes-the-hard-way \
  --from-literal="mykey=mydata"
```

Print a hexdump of the `kubernetes-the-hard-way` secret stored in etcd:

```bash
# SSH to the control plane to check etcd
ssh azureuser@10.0.3.10

# Query etcd for the secret
sudo ETCDCTL_API=3 etcdctl get \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/ca.pem \
  --cert=/etc/etcd/kubernetes.pem \
  --key=/etc/etcd/kubernetes-key.pem\
  /registry/secrets/default/kubernetes-the-hard-way | hexdump -C
```

The etcd key should be prefixed with `k8s:enc:aescbc:v1:key1`, which indicates the `aescbc` provider was used to encrypt the data with the `key1` encryption key.

## Deployments

In this section you will verify the ability to create and manage [Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/).

Create a deployment for the [nginx](https://nginx.org/) web server:

```bash
kubectl create deployment nginx --image=nginx
```

List the pod created by the `nginx` deployment:

```bash
kubectl get pods -l app=nginx
```

### Port Forwarding

In this section you will verify the ability to access applications remotely using [port forwarding](https://kubernetes.io/docs/tasks/access-application-cluster/port-forward-access-application-cluster/).

Retrieve the full name of the `nginx` pod:

```bash
POD_NAME=$(kubectl get pods -l app=nginx -o jsonpath="{.items[0].metadata.name}")
echo $POD_NAME
```

Forward port `8080` on your local machine to port `80` of the `nginx` pod:

```bash
kubectl port-forward $POD_NAME 8080:80
```

In a new terminal make an HTTP request using the forwarding address:

```bash
curl --head http://127.0.0.1:8080
```

Switch back to the previous terminal and stop the port forwarding to the `nginx` pod:

```
Forwarding from 127.0.0.1:8080 -> 80
Forwarding from [::1]:8080 -> 80
Handling connection for 8080
^C
```

### Logs

In this section you will verify the ability to [retrieve container logs](https://kubernetes.io/docs/concepts/cluster-administration/logging/).

Print the `nginx` pod logs:

```bash
kubectl logs $POD_NAME
```

### Exec

In this section you will verify the ability to [execute commands in a container](https://kubernetes.io/docs/tasks/debug-application-cluster/get-shell-running-container/).

Print the nginx version by executing the `nginx -v` command in the `nginx` container:

```bash
kubectl exec -ti $POD_NAME -- nginx -v
```

## Services

In this section you will verify the ability to expose applications using a [Service](https://kubernetes.io/docs/concepts/services-networking/service/).

Expose the `nginx` deployment using a [NodePort](https://kubernetes.io/docs/concepts/services-networking/service/#type-nodeport) service:

```bash
kubectl expose deployment nginx --port 80 --type NodePort
```

> The LoadBalancer service type can not be used because your cluster is not configured with [cloud provider integration](https://kubernetes.io/docs/getting-started-guides/scratch/#cloud-provider). Setting up cloud provider integration is out of scope for this tutorial.

Retrieve the node port assigned to the `nginx` service:

```bash
NODE_PORT=$(kubectl get svc nginx \
  --output=jsonpath='{range .spec.ports[0]}{.nodePort}')
echo $NODE_PORT
```

Create a firewall rule that allows remote access to the `nginx` node port:

```bash
# From the jumpbox, update the security group to allow the NodePort
# This is already configured in our infrastructure, but you can verify:
az network nsg rule create \
  --resource-group rg-k8s-the-hard-way \
  --nsg-name nsg-k8s \
  --name nginx-nodeport \
  --protocol tcp \
  --priority 1100 \
  --destination-port-range $NODE_PORT \
  --source-address-prefixes 10.0.2.0/24 \
  --access allow || echo "Rule may already exist"
```

Test external access to the nginx service from the jumpbox:

```bash
# Test from jumpbox to worker nodes
curl -I http://10.0.3.20:$NODE_PORT
curl -I http://10.0.3.21:$NODE_PORT
```

You should see HTTP/1.1 200 OK response.

## Untrusted Workloads

This section will verify the ability to run untrusted workloads using [gVisor](https://github.com/google/gvisor).

> Note: gVisor is not installed in this basic setup. This section demonstrates how you would test it if it were configured.

Create the `untrusted` pod:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: untrusted
  annotations:
    io.kubernetes.cri.untrusted-workload: "true"
spec:
  containers:
    - name: webserver
      image: gcr.io/hightowerlabs/helloworld:2.0.0
EOF
```

### Verification

In this section you will verify the `untrusted` pod is running under gVisor (runsc) by inspecting the assigned worker node.

Verify the `untrusted` pod is running:

```bash
kubectl get pods -o wide
```

Get the node name where the `untrusted` pod is running:

```bash
INSTANCE_NAME=$(kubectl get pod untrusted --output=jsonpath='{.spec.nodeName}')
echo $INSTANCE_NAME
```

SSH to the worker node:

```bash
# Get the worker node IP
if [ "$INSTANCE_NAME" = "vm-worker-1" ]; then
    WORKER_IP="10.0.3.20"
else
    WORKER_IP="10.0.3.21"
fi

ssh azureuser@$WORKER_IP
```

List the containers running under gVisor:

```bash
# On the worker node
sudo runsc --root /run/containerd/runsc/k8s.io list
```

Get the process ID of the `helloworld` container:

```bash
# This would show gVisor processes if configured
sudo runsc --root /run/containerd/runsc/k8s.io ps <container-id>
```

## Additional Verification Tests

### Cluster Info

Verify basic cluster information:

```bash
kubectl cluster-info
kubectl get nodes -o wide
kubectl get pods --all-namespaces -o wide
```

### DNS Resolution

Test DNS resolution within the cluster:

```bash
# Create a test pod for DNS testing
kubectl run test-dns --image=busybox --rm -it -- nslookup kubernetes.default.svc.cluster.local
```

### Resource Creation and Management

Test various Kubernetes resources:

```bash
# Create a namespace
kubectl create namespace smoke-test

# Create a ConfigMap
kubectl create configmap test-config \
  --from-literal=key1=value1 \
  --from-literal=key2=value2 \
  -n smoke-test

# Create a Secret
kubectl create secret generic test-secret \
  --from-literal=username=admin \
  --from-literal=password=secretpassword \
  -n smoke-test

# Verify resources
kubectl get all,configmap,secret -n smoke-test
```

### Network Connectivity

Test pod-to-pod networking:

```bash
# Create two test pods
kubectl run pod1 --image=busybox --restart=Never -- sleep 3600
kubectl run pod2 --image=busybox --restart=Never -- sleep 3600

# Wait for pods to be ready
kubectl wait --for=condition=Ready pod/pod1 pod/pod2

# Get pod IPs
POD1_IP=$(kubectl get pod pod1 -o jsonpath='{.status.podIP}')
POD2_IP=$(kubectl get pod pod2 -o jsonpath='{.status.podIP}')

echo "Pod1 IP: $POD1_IP"
echo "Pod2 IP: $POD2_IP"

# Test connectivity from pod1 to pod2
kubectl exec pod1 -- ping -c 3 $POD2_IP

# Test connectivity from pod2 to pod1
kubectl exec pod2 -- ping -c 3 $POD1_IP
```

### Storage

Test persistent storage:

```bash
# Create a PersistentVolume and PersistentVolumeClaim
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: test-pv
spec:
  capacity:
    storage: 1Gi
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: /tmp/test-pv
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF

# Create a pod that uses the PVC
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: storage-test
spec:
  containers:
  - name: storage-container
    image: busybox
    command: ["/bin/sh", "-c", "echo 'Hello Storage' > /data/test.txt && sleep 3600"]
    volumeMounts:
    - name: storage
      mountPath: /data
  volumes:
  - name: storage
    persistentVolumeClaim:
      claimName: test-pvc
EOF

# Verify storage
kubectl wait --for=condition=Ready pod/storage-test
kubectl exec storage-test -- cat /data/test.txt
```

## Performance Tests

### Basic Load Test

Test basic cluster performance:

```bash
# Create multiple replicas
kubectl create deployment load-test --image=nginx --replicas=10

# Scale the deployment
kubectl scale deployment load-test --replicas=20

# Check status
kubectl get pods -l app=load-test
kubectl top nodes
kubectl top pods
```

### Resource Limits

Test resource constraints:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: resource-test
spec:
  containers:
  - name: resource-container
    image: busybox
    command: ["/bin/sh", "-c", "while true; do echo 'Resource test running'; sleep 10; done"]
    resources:
      requests:
        memory: "64Mi"
        cpu: "250m"
      limits:
        memory: "128Mi"
        cpu: "500m"
EOF

# Monitor resource usage
kubectl top pod resource-test
```

## Cleanup Test Resources

Clean up the test resources:

```bash
# Delete test deployments and pods
kubectl delete deployment nginx load-test
kubectl delete pod untrusted pod1 pod2 storage-test resource-test test-dns
kubectl delete secret kubernetes-the-hard-way test-secret
kubectl delete configmap test-config
kubectl delete pvc test-pvc
kubectl delete pv test-pv
kubectl delete service nginx
kubectl delete namespace smoke-test
```

## Summary

If all tests pass, your Kubernetes cluster is working correctly! The cluster can:

✅ **Encrypt data at rest** - Secrets are encrypted in etcd  
✅ **Run deployments** - Pods can be created and managed  
✅ **Port forwarding** - Applications can be accessed remotely  
✅ **Container logs** - Log retrieval works properly  
✅ **Exec into containers** - Command execution works  
✅ **Services** - Network services and NodePorts work  
✅ **DNS resolution** - Internal DNS is functional  
✅ **Pod networking** - Pods can communicate with each other  
✅ **Resource management** - CPU and memory limits work  
✅ **Storage** - Persistent volumes can be mounted  

## Troubleshooting Failed Tests

### DNS Issues
```bash
# Check CoreDNS pods
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Check DNS service
kubectl get svc -n kube-system kube-dns
```

### Networking Issues
```bash
# Check CNI configuration
ls -la /etc/cni/net.d/

# Check network routes
ip route show

# Check iptables rules
sudo iptables -L -n
```

### Storage Issues
```bash
# Check if directories exist on nodes
ls -la /tmp/test-pv

# Check volume mounts
kubectl describe pod storage-test
```

### Performance Issues
```bash
# Check node resources
kubectl describe nodes

# Check system resources
free -h
df -h
```

Congratulations! You have completed the Kubernetes the Hard Way tutorial. Your cluster is ready for production workloads (with appropriate additional security and monitoring configurations).

## Next Steps

Consider implementing:

1. **Monitoring**: Set up Prometheus and Grafana
2. **Logging**: Configure centralized logging with ELK stack
3. **Ingress**: Install an ingress controller
4. **Helm**: Install Helm for package management
5. **Security**: Implement Pod Security Standards
6. **Backup**: Set up etcd backup automation
7. **High Availability**: Add additional control plane nodes