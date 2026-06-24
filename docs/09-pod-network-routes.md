# Provisioning Pod Network Routes

In this lab you will explore the pod networking configuration and understand its current limitations.

**Important Understanding**: This "Kubernetes the Hard Way" setup uses a simplified pod networking approach where all worker nodes share the same pod CIDR (10.200.0.0/16). This means:
- ✅ Pods on the **same node** can communicate with each other
- ❌ Pods on **different nodes** cannot communicate directly
- ✅ Pods can reach the internet via NAT Gateway (TCP connectivity works)
- ✅ DNS resolution works (CoreDNS was deployed in chapter 07)
- ✅ Services work (kube-proxy creates iptables rules)

**Why this limitation exists**: To enable cross-node pod communication, you would need:
1. Unique pod CIDR per node (e.g., worker-1: 10.200.1.0/24, worker-2: 10.200.2.0/24)
2. Azure Route Table with routes directing each subnet to the correct worker node
3. Reconfiguration of kubelet and CNI on each node

**Production environments**: Use a CNI plugin (Calico, Flannel, Azure CNI, Cilium, etc.) that handles cross-node networking automatically using overlay networks or cloud-native routing. This lab focuses on understanding the core Kubernetes components rather than implementing full production networking.

## The Routing Table

In this section you will examine the current network configuration and understand why cross-node pod communication doesn't work.

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

**Expected result**: The pod CIDR will be **empty or undefined** because we configured the kubelet with a hardcoded pod CIDR (10.200.0.0/16) in the kubelet-config.yaml, rather than letting the API server assign unique subnets per node.

**What this means**: Both nodes think they own the entire 10.200.0.0/16 range, so when a pod on worker-1 tries to reach 10.200.0.x, it assumes that IP is local to its own bridge and never forwards the packet to worker-2.

## Network Architecture Overview

Our current network setup:

- **VM Network**: 10.0.3.0/24 (Kubernetes subnet)
- **Pod Network**: 10.200.0.0/16 (Shared/overlapping across all nodes) ⚠️
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
│  │               │  │ Pod Network:  │  │ Pod Network: ││
│  │               │  │ 10.200.0.0/16 │  │10.200.0.0/16 ││  ⚠️ SAME CIDR
│  │               │  │ (cnio0 bridge)│  │(cnio0 bridge)││
│  └───────────────┘  └───────────────┘  └──────────────┘│
└─────────────────────────────────────────────────────────┘

⚠️ Problem: Both worker nodes claim ownership of the entire 10.200.0.0/16 range.
   This causes cross-node pod traffic to be dropped (never leaves the source node).
```

## Understanding Why Cross-Node Routing Doesn't Work

**Why Azure Route Tables are needed (but not implemented here)**:

For cross-node pod communication to work, you would need:

### 1. Unique Pod CIDRs Per Node

Each node should have its own subnet:
- Worker-1: 10.200.1.0/24 (256 IPs for pods)
- Worker-2: 10.200.2.0/24 (256 IPs for pods)

This requires:
- Configuring the API server with `--allocate-node-cidrs=true` and `--cluster-cidr=10.200.0.0/16`
- Letting the controller manager assign unique /24 subnets to each node
- Updating kubelet configs to use the assigned CIDR instead of hardcoded values
- Restarting kubelets and recreating CNI configuration

### 2. Azure Route Table with Per-Node Routes

Once unique CIDRs are assigned, create Azure routes:

```bash
# Example of what you would need (NOT running this in the lab)

# Create a route table
az network route-table create \
  --resource-group rg-<student-name>-k8s-hard-way \
  --name rt-k8s-pods \
  --location swedencentral

# Create route for worker-1's pod subnet
az network route-table route create \
  --resource-group rg-<student-name>-k8s-hard-way \
  --route-table-name rt-k8s-pods \
  --name route-worker-1-pods \
  --address-prefix 10.200.1.0/24 \
  --next-hop-type VirtualAppliance \
  --next-hop-ip-address 10.0.3.20

# Create route for worker-2's pod subnet
az network route-table route create \
  --resource-group rg-<student-name>-k8s-hard-way \
  --route-table-name rt-k8s-pods \
  --name route-worker-2-pods \
  --address-prefix 10.200.2.0/24 \
  --next-hop-type VirtualAppliance \
  --next-hop-ip-address 10.0.3.21

# Associate route table with the Kubernetes subnet
az network vnet subnet update \
  --resource-group rg-<student-name>-k8s-hard-way \
  --vnet-name vnet-k8s \
  --name snet-k8s \
  --route-table rt-k8s-pods
```

**Why we're not doing this**: This lab focuses on understanding core Kubernetes components (API server, kubelet, kube-proxy, etc.) rather than cloud networking complexity. Implementing proper pod routing would require significant reconfiguration and cloud-specific knowledge that distracts from learning Kubernetes fundamentals.

**Production approach**: Use a CNI plugin that handles this automatically:
- **Calico**: Uses BGP or VXLAN overlays
- **Flannel**: Uses VXLAN overlays
- **Azure CNI**: Integrates directly with Azure networking
- **Cilium**: Uses eBPF and can work with or without overlays

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

**⚠️ Expected Result**: Cross-node pod connectivity **will NOT work** in this lab setup.

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

**Expected output**: `100% packet loss` - This is **normal and expected**.

**Why it fails**: Both nodes think they own the entire 10.200.0.0/16 range. When test-pod-1 tries to ping 10.200.0.4 (on worker-2), worker-1's routing table says "10.200.0.0/16 is local to cnio0 bridge", so it never forwards the packet off the node.

**What WOULD work**: If the pods were on the same node, they could communicate via the local bridge.

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

**Note**: CoreDNS was deployed in chapter 07, so DNS resolution should work. ICMP ping may be blocked by Azure (this is normal).

```bash
echo ""
echo "Testing Internet Connectivity:"
echo "============================="

# Check DNS configuration
echo "Pod DNS configuration:"
kubectl exec test-pod-1 -- cat /etc/resolv.conf

# Test DNS resolution to external domains
echo ""
echo "Testing external DNS resolution:"
kubectl exec test-pod-1 -- nslookup google.com
kubectl exec test-pod-2 -- nslookup google.com

# Test connectivity to external IP using TCP
echo ""
echo "Testing TCP connectivity to 8.8.8.8:53:"
kubectl exec test-pod-1 -- timeout 3 nc -zv 8.8.8.8 53

# OPTIONAL: Try ICMP ping (may fail - this is normal in Azure)
echo ""
echo "ICMP test (may fail - this is normal in Azure):"
kubectl exec test-pod-1 -- ping -c 2 8.8.8.8 || echo "ICMP blocked (expected in Azure)"
```

**Expected results**:
- ✅ DNS resolution works (google.com resolves to IP addresses)
- ✅ TCP connectivity to external IPs works
- ❌ ICMP ping may fail (Azure blocks outbound ICMP - this is normal)

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
- **Pod-to-Pod (different nodes)**: Routing via node network (not working in this lab - see Summary)
- **Pod-to-Service**: kube-proxy iptables rules
- **Pod-to-Internet**: NAT through Azure NAT Gateway (HTTP/DNS work; ICMP often blocked)

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

### What Works in This Lab Setup ✅

- ✅ **Pods can be scheduled** - Scheduler places pods on available worker nodes
- ✅ **Pods on the same node communicate** - Local bridge networking works
- ✅ **Pod-to-node connectivity** - Pods can reach worker nodes and control plane
- ✅ **Internet connectivity** - Pods can reach external IPs via NAT Gateway (TCP connectivity verified)
- ✅ **Service networking** - kube-proxy iptables rules enable ClusterIP services
- ✅ **Network isolation** - Each pod has its own network namespace
- ✅ **DNS resolution** - CoreDNS provides service discovery and external DNS

### What Doesn't Work ❌

- ❌ **Cross-node pod communication** - Pods on different nodes cannot communicate directly
  - **Why**: Both nodes use the same pod CIDR (10.200.0.0/16) without Azure routes
  - **Impact**: Multi-replica deployments may have issues if pods are on different nodes
  - **Workaround**: Services still work (kube-proxy handles routing via node IPs)

### Understanding the Limitation

This limitation is **intentional for this lab**. "Kubernetes the Hard Way" focuses on understanding core Kubernetes components, not cloud networking complexity.

**What you learned**:
- How CNI plugins configure pod networking
- How bridge networking works within a node
- How iptables provides NAT for pods
- Why unique pod CIDRs and route tables are needed for cross-node communication

**Production environments** solve this with CNI plugins:
- **Calico**: Layer 3 networking with BGP or VXLAN overlays
- **Flannel**: Simple VXLAN overlay network
- **Azure CNI**: Direct integration with Azure VNet (each pod gets an Azure IP)
- **Cilium**: eBPF-based networking with advanced features
- **Weave Net**: Mesh overlay network

These plugins automatically:
- Assign unique pod CIDRs per node
- Configure routing (via overlays or cloud routes)
- Handle network policies
- Provide network observability

### Next Steps

Your cluster can still run applications successfully:
- Services provide stable endpoints (work across nodes)
- Single-replica deployments work fine
- Multi-replica deployments work if you use services to communicate

Proceed to the smoke test to verify the cluster's functionality within these known limitations.

Next: [Smoke Test](10-smoke-test.md)