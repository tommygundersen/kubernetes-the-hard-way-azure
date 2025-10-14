# Provisioning Pod Network Routes

In this lab you will create network routes for the Pod CIDR ranges. This will ensure that Pods running on different worker nodes can communicate with each other.

> In a production environment, you would typically use a CNI plugin like Calico, Flannel, or Azure CNI to handle pod networking automatically. This lab demonstrates the underlying networking concepts by configuring routes manually.

## The Routing Table

In this section you will gather the information required to create routes in the virtual network.

Print the internal IP address and Pod CIDR range for each worker instance:

```bash
# From the jumpbox, check the worker node configurations
echo "Worker Node Network Configuration:"
echo "=================================="

# Get worker node information
kubectl get nodes -o wide

# Check pod CIDR assignments
echo ""
echo "Pod CIDR Assignments:"
echo "===================="
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.podCIDR}{"\n"}{end}'
```

Since we're using a simple bridge network configuration, each node will use the same Pod CIDR (10.200.0.0/16). In a production setup, each node would typically get a unique subnet.

## Network Architecture Overview

Our current network setup:

- **VM Network**: 10.0.3.0/24 (Kubernetes subnet)
- **Pod Network**: 10.200.0.0/16 (Shared across all nodes)
- **Service Network**: 10.100.0.0/16 (Virtual network for services)

```
┌─────────────────────────────────────────────────────────┐
│              Azure Virtual Network                     │
│                   10.0.0.0/16                         │
├─────────────────────────────────────────────────────────┤
│  Kubernetes Subnet: 10.0.3.0/24                       │
│  ┌───────────────┐  ┌───────────────┐  ┌──────────────┐│
│  │ Control Plane │  │   Worker-1    │  │   Worker-2   ││
│  │  10.0.3.10    │  │  10.0.3.20    │  │  10.0.3.21   ││
│  │               │  │               │  │              ││
│  │  Pod Network: │  │  Pod Network: │  │ Pod Network: ││
│  │ 10.200.0.0/16 │  │ 10.200.0.0/16 │  │10.200.0.0/16││
│  └───────────────┘  └───────────────┘  └──────────────┘│
└─────────────────────────────────────────────────────────┘
```

## Configure Pod Network Routes

Since we're using a simple bridge network where all nodes share the same Pod CIDR, we need to ensure proper routing between nodes.

### Option 1: Using Azure Route Tables (Recommended for Production)

For a production environment, you would create Azure Route Tables:

```bash
# This is for demonstration - shows how you would configure Azure routes
# Note: This requires additional Azure permissions and is not needed for our lab

# Create a route table
az network route-table create \
  --resource-group rg-k8s-the-hard-way \
  --name rt-k8s-pods \
  --location westeurope

# Create routes for each worker node (example)
# In our simple setup, this isn't necessary as we're using a shared CIDR

# Associate route table with subnet
az network vnet subnet update \
  --resource-group rg-k8s-the-hard-way \
  --vnet-name vnet-k8s \
  --name snet-k8s \
  --route-table rt-k8s-pods
```

### Option 2: Node-level Routing (Our Lab Setup)

Since we're using a simple bridge configuration, routing is handled at the node level by the CNI bridge plugin and iptables.

Verify the current routing configuration on each worker node:

```bash
# Check routing on worker-1
ssh azureuser@10.0.3.20 << 'EOF'
echo "=== Worker-1 Routing Configuration ==="
echo "IP Addresses:"
ip addr show

echo -e "\nRouting Table:"
ip route show

echo -e "\nBridge Configuration:"
ip link show cnio0 2>/dev/null || echo "Bridge not yet created"

echo -e "\nIPTables NAT Rules:"
sudo iptables -t nat -L -n | grep -E "(MASQUERADE|10\.200)"
EOF

# Check routing on worker-2
ssh azureuser@10.0.3.21 << 'EOF'
echo "=== Worker-2 Routing Configuration ==="
echo "IP Addresses:"
ip addr show

echo -e "\nRouting Table:"
ip route show

echo -e "\nBridge Configuration:"
ip link show cnio0 2>/dev/null || echo "Bridge not yet created"

echo -e "\nIPTables NAT Rules:"
sudo iptables -t nat -L -n | grep -E "(MASQUERADE|10\.200)"
EOF
```

## Testing Pod Network Connectivity

Deploy test pods to verify network connectivity:

### Create Test Pods

```bash
# Create a test pod on worker-1
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: test-pod-1
  labels:
    app: network-test
spec:
  nodeSelector:
    kubernetes.io/hostname: vm-worker-1
  containers:
  - name: network-test
    image: busybox
    command: ["sleep", "3600"]
    imagePullPolicy: Always
EOF

# Create a test pod on worker-2
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: test-pod-2
  labels:
    app: network-test
spec:
  nodeSelector:
    kubernetes.io/hostname: vm-worker-2
  containers:
  - name: network-test
    image: busybox
    command: ["sleep", "3600"]
    imagePullPolicy: Always
EOF

# Wait for pods to be ready
kubectl wait --for=condition=Ready pod/test-pod-1 pod/test-pod-2 --timeout=300s
```

### Verify Pod IP Addresses

```bash
echo "Test Pod Network Information:"
echo "============================"
kubectl get pods -o wide -l app=network-test

# Get pod IPs for testing
POD1_IP=$(kubectl get pod test-pod-1 -o jsonpath='{.status.podIP}')
POD2_IP=$(kubectl get pod test-pod-2 -o jsonpath='{.status.podIP}')

echo ""
echo "Pod IP Addresses:"
echo "test-pod-1: $POD1_IP"
echo "test-pod-2: $POD2_IP"
```

### Test Pod-to-Pod Connectivity

```bash
echo ""
echo "Testing Pod-to-Pod Connectivity:"
echo "==============================="

# Test connectivity from pod-1 to pod-2
echo "Testing from test-pod-1 ($POD1_IP) to test-pod-2 ($POD2_IP):"
kubectl exec test-pod-1 -- ping -c 3 $POD2_IP

echo ""
echo "Testing from test-pod-2 ($POD2_IP) to test-pod-1 ($POD1_IP):"
kubectl exec test-pod-2 -- ping -c 3 $POD1_IP
```

### Test Pod-to-Node Connectivity

```bash
echo ""
echo "Testing Pod-to-Node Connectivity:"
echo "================================"

# Test connectivity from pods to worker nodes
echo "From test-pod-1 to worker-1 (10.0.3.20):"
kubectl exec test-pod-1 -- ping -c 2 10.0.3.20

echo ""
echo "From test-pod-1 to worker-2 (10.0.3.21):"
kubectl exec test-pod-1 -- ping -c 2 10.0.3.21

echo ""
echo "From test-pod-2 to worker-1 (10.0.3.20):"
kubectl exec test-pod-2 -- ping -c 2 10.0.3.20

echo ""
echo "From test-pod-2 to worker-2 (10.0.3.21):"
kubectl exec test-pod-2 -- ping -c 2 10.0.3.21
```

### Test Internet Connectivity

```bash
echo ""
echo "Testing Internet Connectivity:"
echo "============================="

# Test outbound internet access (should work through NAT Gateway)
echo "From test-pod-1 to google.com:"
kubectl exec test-pod-1 -- nslookup google.com
kubectl exec test-pod-1 -- ping -c 2 8.8.8.8

echo ""
echo "From test-pod-2 to google.com:"
kubectl exec test-pod-2 -- nslookup google.com
kubectl exec test-pod-2 -- ping -c 2 8.8.8.8
```

## Service Network Testing

Test the service network functionality:

### Create a Test Service

```bash
# Create a service for our test pods
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: network-test-service
spec:
  selector:
    app: network-test
  ports:
  - protocol: TCP
    port: 80
    targetPort: 8080
  type: ClusterIP
EOF

# Get service information
kubectl get service network-test-service
kubectl describe service network-test-service

# Get service cluster IP
SERVICE_IP=$(kubectl get service network-test-service -o jsonpath='{.spec.clusterIP}')
echo "Service Cluster IP: $SERVICE_IP"
```

### Test Service Discovery

```bash
echo ""
echo "Testing Service Discovery:"
echo "========================"

# Test DNS resolution
echo "DNS lookup for service:"
kubectl exec test-pod-1 -- nslookup network-test-service.default.svc.cluster.local

echo ""
echo "DNS lookup for kubernetes service:"
kubectl exec test-pod-1 -- nslookup kubernetes.default.svc.cluster.local
```

## Advanced Network Verification

### Check CNI Configuration

```bash
echo ""
echo "CNI Configuration Verification:"
echo "=============================="

# Check CNI configuration on worker nodes
for worker_ip in 10.0.3.20 10.0.3.21; do
    echo ""
    echo "CNI Config on worker $worker_ip:"
    ssh azureuser@$worker_ip 'sudo cat /etc/cni/net.d/*.conf' | head -20
done
```

### Monitor Network Traffic

```bash
echo ""
echo "Network Interface Status:"
echo "======================="

# Check network interfaces on worker nodes
for worker_ip in 10.0.3.20 10.0.3.21; do
    echo ""
    echo "Interfaces on worker $worker_ip:"
    ssh azureuser@$worker_ip 'ip link show | grep -E "(cnio0|eth0)"'
    ssh azureuser@$worker_ip 'ip addr show cnio0 2>/dev/null || echo "Bridge not active"'
done
```

### Troubleshoot Network Issues

Create a network troubleshooting script:

```bash
cat > ~/network-debug.sh << 'EOF'
#!/bin/bash

echo "=== Kubernetes Network Debugging ==="
echo ""

# Check node status
echo "Node Status:"
kubectl get nodes -o wide

echo ""
echo "Pod Status:"
kubectl get pods -o wide --all-namespaces

echo ""
echo "Service Status:"
kubectl get services --all-namespaces

echo ""
echo "Endpoints:"
kubectl get endpoints --all-namespaces

# Check kube-proxy status
echo ""
echo "Kube-proxy Pod Status:"
kubectl get pods -n kube-system -l k8s-app=kube-proxy

# Check DNS
echo ""
echo "DNS Pods:"
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Network policies (if any)
echo ""
echo "Network Policies:"
kubectl get networkpolicies --all-namespaces

echo ""
echo "=== Worker Node Network Status ==="

for worker_ip in 10.0.3.20 10.0.3.21; do
    echo ""
    echo "Worker $worker_ip:"
    echo "  CNI Bridge:"
    ssh azureuser@$worker_ip 'ip addr show cnio0 2>/dev/null | head -5'
    
    echo "  Routing:"
    ssh azureuser@$worker_ip 'ip route | grep 10.200 || echo "No pod routes found"'
    
    echo "  iptables rules:"
    ssh azureuser@$worker_ip 'sudo iptables -t nat -L | grep -c KUBE'
done

echo ""
echo "=== Debugging Complete ==="
EOF

chmod +x ~/network-debug.sh
```

Run the debugging script:

```bash
./network-debug.sh
```

## Understanding Pod Networking

### How Pod Networking Works

1. **CNI Plugin**: The bridge CNI plugin creates a bridge (cnio0) on each node
2. **Pod Interface**: Each pod gets a veth pair connected to the bridge
3. **IP Assignment**: IPAM (IP Address Management) assigns IPs from the pod CIDR
4. **Routing**: Routes are configured to direct pod traffic through the bridge
5. **NAT**: iptables rules provide NAT for external connectivity

### Network Flow Diagram

```
Pod-1 (10.200.0.x)     Pod-2 (10.200.0.y)
       |                       |
   veth-pair               veth-pair
       |                       |
    ┌──▼───────────────────────▼──┐
    │     cnio0 Bridge           │
    │    (Node Interface)        │
    └──┬─────────────────────────┘
       │
    eth0 (10.0.3.x)
       │
   ┌───▼────┐
   │ Router │ ──── Internet (via NAT Gateway)
   └────────┘
```

### Traffic Patterns

- **Pod-to-Pod (same node)**: Bridge forwarding
- **Pod-to-Pod (different nodes)**: Routing via node network
- **Pod-to-Service**: kube-proxy iptables rules
- **Pod-to-Internet**: NAT through Azure NAT Gateway

## Cleanup Test Resources

Clean up the test resources we created:

```bash
# Delete test pods and services
kubectl delete pod test-pod-1 test-pod-2
kubectl delete service network-test-service

# Verify cleanup
kubectl get pods -l app=network-test
kubectl get services network-test-service
```

## Production Considerations

### CNI Plugin Selection

For production environments, consider:

- **Azure CNI**: Native Azure networking integration
- **Calico**: Network policies and advanced routing
- **Flannel**: Simple overlay networking
- **Cilium**: eBPF-based networking with security features

### Network Policies

Implement network segmentation:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

### Monitoring and Observability

- **Network monitoring**: Use tools like Cilium Hubble or Calico monitoring
- **Traffic analysis**: Implement network flow monitoring
- **Security scanning**: Regular vulnerability assessments

### Performance Optimization

- **MTU settings**: Optimize for your network infrastructure
- **Buffer sizes**: Tune network buffer sizes for high throughput
- **CPU affinity**: Pin network-intensive pods to specific cores

## Summary

✅ **Pod networking configured** - Pods can communicate across nodes  
✅ **Service networking verified** - ClusterIP services work correctly  
✅ **DNS resolution working** - Service discovery is functional  
✅ **Internet connectivity** - Pods can reach external services  
✅ **Network troubleshooting** - Debug tools are available  

Your Kubernetes cluster now has fully functional pod networking! Pods can communicate with each other, resolve services via DNS, and access external resources through the Azure NAT Gateway.

The cluster is now ready for comprehensive testing and deployment of applications.

Next: [Smoke Test](10-smoke-test.md)