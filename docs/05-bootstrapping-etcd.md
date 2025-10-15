# Bootstrapping etcd

Kubernetes components are stateless and store cluster state in [etcd](https://github.com/etcd-io/etcd). In this lab you will bootstrap a single-node etcd cluster and configure it for high availability and secure remote access.

## Prerequisites

The commands in this lab must be run on the control plane instance: `vm-control-plane`. Login to the control plane instance using SSH from the jumpbox.

```bash
# From the jumpbox, connect to the control plane
ssh azureuser@10.0.3.10
```

### Download and Install the etcd Binaries

Download the official etcd release binaries from the [etcd](https://github.com/etcd-io/etcd) GitHub project:

```bash
# Download etcd
wget -q --show-progress --https-only --timestamping \
  "https://github.com/etcd-io/etcd/releases/download/v3.5.9/etcd-v3.5.9-linux-amd64.tar.gz"

# Extract etcd
tar -xvf etcd-v3.5.9-linux-amd64.tar.gz

# Install etcd binaries
sudo mv etcd-v3.5.9-linux-amd64/etcd* /usr/local/bin/

# Verify installation
etcd --version
etcdctl version
```

### Configure the etcd Server

```bash
# Create etcd directories
sudo mkdir -p /etc/etcd /var/lib/etcd
sudo chmod 700 /var/lib/etcd

# Copy certificates
sudo cp ca.pem kubernetes-key.pem kubernetes.pem /etc/etcd/

# Get the internal IP address
INTERNAL_IP=$(ip addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
echo "Internal IP: $INTERNAL_IP"

# Set etcd name
ETCD_NAME=$(hostname -s)
echo "ETCD Name: $ETCD_NAME"
```

Create the `etcd.service` systemd unit file:

```bash
cat <<EOF | sudo tee /etc/systemd/system/etcd.service
[Unit]
Description=etcd
Documentation=https://github.com/etcd

[Service]
Type=notify
ExecStart=/usr/local/bin/etcd --name ${ETCD_NAME} --cert-file=/etc/etcd/kubernetes.pem --key-file=/etc/etcd/kubernetes-key.pem --peer-cert-file=/etc/etcd/kubernetes.pem --peer-key-file=/etc/etcd/kubernetes-key.pem --trusted-ca-file=/etc/etcd/ca.pem --peer-trusted-ca-file=/etc/etcd/ca.pem --peer-client-cert-auth --client-cert-auth --initial-advertise-peer-urls https://${INTERNAL_IP}:2380 --listen-peer-urls https://${INTERNAL_IP}:2380 --listen-client-urls https://${INTERNAL_IP}:2379,https://127.0.0.1:2379 --advertise-client-urls https://${INTERNAL_IP}:2379 --initial-cluster-token etcd-cluster-0 --initial-cluster ${ETCD_NAME}=https://${INTERNAL_IP}:2380 --initial-cluster-state new --data-dir=/var/lib/etcd
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

### Start the etcd Server

```bash
# Reload systemd and start etcd
sudo systemctl daemon-reload
sudo systemctl enable etcd
sudo systemctl start etcd
```

> Remember to run the above commands on the control plane instance: `vm-control-plane`.

## Verification

### Check etcd Service Status

Verify the etcd service is running:

```bash
# Check service status
sudo systemctl status etcd

# Check if etcd is listening on the correct ports
# Option 1: Using ss command (modern replacement for netstat)
sudo ss -tlnp | grep etcd

# Option 2: Using lsof (if ss not available)
sudo lsof -i :2379 -i :2380

# Option 3: Using netstat (install if needed)
# sudo apt-get update && sudo apt-get install -y net-tools
# sudo netstat -tlnp | grep etcd

# View etcd logs
sudo journalctl -u etcd
```

### Test etcd Functionality

List the etcd cluster members:

```bash
# Test etcd connectivity
sudo ETCDCTL_API=3 etcdctl member list --endpoints=https://127.0.0.1:2379 --cacert=/etc/etcd/ca.pem --cert=/etc/etcd/kubernetes.pem --key=/etc/etcd/kubernetes-key.pem
```

You should see output similar to:

```
3a57933972cb5131, started, vm-control-plane, https://10.0.3.10:2380, https://10.0.3.10:2379, false
```

#### Troubleshooting etcd Connection Issues

If you get authentication handshake errors or connection timeouts, try these troubleshooting steps:

```bash
# 1. Check if etcd is actually running
sudo systemctl status etcd

# 2. Check etcd logs for errors
sudo journalctl -u etcd --no-pager | tail -20

# 3. Verify certificates exist and have correct permissions
ls -la /etc/etcd/
sudo ls -la /etc/etcd/*.pem

# 4. Test etcd without TLS first (if configured)
# Note: This requires etcd to be configured for insecure connections
# sudo ETCDCTL_API=3 etcdctl --endpoints=http://127.0.0.1:2379 member list

# 5. Verify certificate validity
openssl x509 -in /etc/etcd/kubernetes.pem -text -noout | grep -A 2 "Subject:"
openssl x509 -in /etc/etcd/ca.pem -text -noout | grep -A 2 "Subject:"

# 6. Check if ports are actually listening
sudo ss -tlnp | grep -E ":2379|:2380"

# 7. Test basic connectivity to etcd ports
# First, check if etcd process is running
ps aux | grep etcd

# Test if port is reachable (should show connection success/failure)
timeout 5 bash -c 'cat < /dev/null > /dev/tcp/127.0.0.1/2379' && echo "Port 2379 is open" || echo "Port 2379 is closed"

# Try different curl approaches for health check
curl -k https://127.0.0.1:2379/health 2>&1
curl -k --connect-timeout 5 https://127.0.0.1:2379/version 2>&1
curl -k --connect-timeout 5 https://127.0.0.1:2379/metrics 2>&1

# If HTTPS fails, try HTTP (etcd might be running in insecure mode)
curl http://127.0.0.1:2379/health 2>&1
curl http://127.0.0.1:2379/version 2>&1

# If getting SSL errors, check etcd configuration
sudo cat /etc/systemd/system/etcd.service | grep -E "listen-client-urls|cert-file"

# 8. If still failing, restart etcd service
sudo systemctl restart etcd
sudo systemctl status etcd

# Check if etcd started successfully (wait for it to fully initialize)
sleep 10
sudo systemctl status etcd

# Check etcd logs for specific errors
sudo journalctl -u etcd --no-pager | tail -30

# 9. Wait a few seconds and try the member list command again
sleep 5
sudo ETCDCTL_API=3 etcdctl member list --endpoints=https://127.0.0.1:2379 --cacert=/etc/etcd/ca.pem --cert=/etc/etcd/kubernetes.pem --key=/etc/etcd/kubernetes-key.pem
```

#### Common Issues and Solutions

**Issue: "serving client traffic insecurely; this is strongly discouraged!"**
- etcd is running in HTTP mode instead of HTTPS
- Certificate configuration not properly applied
- etcd service file has incorrect parameters

**Solution:**
```bash
# Check current etcd service configuration
sudo cat /etc/systemd/system/etcd.service

# Look for the specific issue - check if variables are properly expanded
sudo systemctl cat etcd.service

# Check if INTERNAL_IP and ETCD_NAME variables were set during setup
echo "INTERNAL_IP should be: $(ip addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')"
echo "ETCD_NAME should be: $(hostname -s)"

# The etcd service file should show actual IP addresses, not variables
# If you see ${INTERNAL_IP} or ${ETCD_NAME} in the service file, they weren't expanded

# Fix by recreating the service file with proper variable expansion
INTERNAL_IP=$(ip addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
ETCD_NAME=$(hostname -s)

# Recreate the service file with actual values
cat <<EOF | sudo tee /etc/systemd/system/etcd.service
[Unit]
Description=etcd
Documentation=https://github.com/etcd

[Service]
Type=notify
ExecStart=/usr/local/bin/etcd --name ${ETCD_NAME} --cert-file=/etc/etcd/kubernetes.pem --key-file=/etc/etcd/kubernetes-key.pem --peer-cert-file=/etc/etcd/kubernetes.pem --peer-key-file=/etc/etcd/kubernetes-key.pem --trusted-ca-file=/etc/etcd/ca.pem --peer-trusted-ca-file=/etc/etcd/ca.pem --peer-client-cert-auth --client-cert-auth --initial-advertise-peer-urls https://${INTERNAL_IP}:2380 --listen-peer-urls https://${INTERNAL_IP}:2380 --listen-client-urls https://${INTERNAL_IP}:2379,https://127.0.0.1:2379 --advertise-client-urls https://${INTERNAL_IP}:2379 --initial-cluster-token etcd-cluster-0 --initial-cluster ${ETCD_NAME}=https://${INTERNAL_IP}:2380 --initial-cluster-state new --data-dir=/var/lib/etcd
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Reload and restart etcd
sudo systemctl daemon-reload
sudo systemctl restart etcd

# Wait for startup and check logs
sleep 10
sudo journalctl -u etcd --no-pager | tail -10

# Verify it's now running with TLS
sudo ss -tlnp | grep -E ":2379|:2380"
curl -k https://127.0.0.1:2379/health
```

**Issue: "curl: (35) error:0A000126:SSL routines::unexpected eof while reading"**
- etcd TLS/SSL configuration issue
- etcd process not fully started
- Certificate/TLS handshake failure

**Solution:**
```bash
# Check if etcd process is actually running
sudo systemctl status etcd
ps aux | grep etcd

# Check etcd logs for startup errors
sudo journalctl -u etcd --no-pager | tail -50

# Verify etcd is listening on the correct ports
sudo ss -tlnp | grep -E ":2379|:2380"

# Check if etcd started with correct certificates
sudo journalctl -u etcd | grep -i "certificate\|tls\|ssl\|error"

# Test port connectivity without SSL
nc -zv 127.0.0.1 2379

# If etcd is not starting properly, check the service file
sudo cat /etc/systemd/system/etcd.service

# Restart etcd and monitor startup
sudo systemctl stop etcd
sudo systemctl start etcd
sudo journalctl -u etcd -f &
# Press Ctrl+C to stop following logs

# Wait for etcd to fully initialize (can take 10-30 seconds)
sleep 15

# Then try the health check again
curl -k --connect-timeout 10 https://127.0.0.1:2379/health
```

**Issue: "x509: certificate is valid for 10.100.0.1, 10.0.3.10, not 127.0.0.1"**
- Certificate doesn't include localhost (127.0.0.1) in Subject Alternative Names
- The kubernetes certificate needs to be regenerated with 127.0.0.1

**Why localhost (127.0.0.1) is required:**
- etcd must listen on localhost for the Kubernetes API server connection
- kube-controller-manager and kube-scheduler connect to API server via localhost
- This is the standard Kubernetes security model

**Solution:**
```bash
# Check current certificate SANs
openssl x509 -in /etc/etcd/kubernetes.pem -text -noout | grep -A 1 "Subject Alternative Name"

# If 127.0.0.1 is missing, regenerate the certificate
# Go back to your certificate generation (docs/02-certificate-authority.md)
# and ensure the hostname parameter includes 127.0.0.1:
# -hostname=10.100.0.1,127.0.0.1,${CONTROL_PLANE_IP},...

# For immediate testing ONLY, you can use the actual IP instead of 127.0.0.1
# But note: This will NOT work for the full Kubernetes setup later
INTERNAL_IP=$(ip addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
sudo ETCDCTL_API=3 etcdctl member list --endpoints=https://${INTERNAL_IP}:2379 --cacert=/etc/etcd/ca.pem --cert=/etc/etcd/kubernetes.pem --key=/etc/etcd/kubernetes-key.pem
```

**Issue: "authentication handshake failed: EOF"**
- Certificate mismatch or invalid certificates
- etcd not properly started
- Wrong certificate paths

**Solution:**
```bash
# Verify certificate paths in etcd configuration
sudo cat /etc/systemd/system/etcd.service | grep -E "cert|key|ca"

# Ensure certificates have correct ownership and permissions
sudo chown root:root /etc/etcd/*.pem
sudo chmod 600 /etc/etcd/*-key.pem
sudo chmod 644 /etc/etcd/*.pem
```

**Issue: "connection error: desc = transport: authentication handshake failed"**
- Certificate CN (Common Name) doesn't match
- CA certificate doesn't match

**Solution:**
```bash
# Check certificate details
openssl x509 -in /etc/etcd/kubernetes.pem -text -noout | grep -A 5 "Subject Alternative Name"

# The certificate should include:
# - DNS:kubernetes
# - DNS:localhost  
# - IP:127.0.0.1
# - IP:10.0.3.10 (control plane IP)
```

### Test etcd Data Operations

Test basic etcd operations:

```bash
# Set a test key
sudo ETCDCTL_API=3 etcdctl put /test/key "test value" --endpoints=https://127.0.0.1:2379 --cacert=/etc/etcd/ca.pem --cert=/etc/etcd/kubernetes.pem --key=/etc/etcd/kubernetes-key.pem

# Get the test key
sudo ETCDCTL_API=3 etcdctl get /test/key --endpoints=https://127.0.0.1:2379 --cacert=/etc/etcd/ca.pem --cert=/etc/etcd/kubernetes.pem --key=/etc/etcd/kubernetes-key.pem

# Delete the test key
sudo ETCDCTL_API=3 etcdctl del /test/key --endpoints=https://127.0.0.1:2379 --cacert=/etc/etcd/ca.pem --cert=/etc/etcd/kubernetes.pem --key=/etc/etcd/kubernetes-key.pem
```

### Create etcd Helper Script

Create a helper script to make etcd commands easier:

```bash
cat > ~/etcd-helper.sh << 'EOF'
#!/bin/bash

# etcd Helper Script
# Usage: ./etcd-helper.sh [command]

ENDPOINTS="https://127.0.0.1:2379"
CACERT="/etc/etcd/ca.pem"
CERT="/etc/etcd/kubernetes.pem"
KEY="/etc/etcd/kubernetes-key.pem"

etcd_cmd() {
    sudo ETCDCTL_API=3 etcdctl --endpoints=$ENDPOINTS --cacert=$CACERT --cert=$CERT --key=$KEY "$@"
}

case "$1" in
    "members"|"member-list")
        etcd_cmd member list
        ;;
    "health"|"endpoint-health")
        etcd_cmd endpoint health
        ;;
    "status"|"endpoint-status")
        etcd_cmd endpoint status --write-out=table
        ;;
    "put")
        etcd_cmd put "$2" "$3"
        ;;
    "get")
        etcd_cmd get "$2"
        ;;
    "del"|"delete")
        etcd_cmd del "$2"
        ;;
    "backup")
        etcd_cmd snapshot save /tmp/etcd-backup-$(date +%Y%m%d-%H%M%S).db
        ;;
    *)
        echo "Usage: $0 {members|health|status|put|get|del|backup}"
        echo ""
        echo "Examples:"
        echo "  $0 members          - List cluster members"
        echo "  $0 health           - Check endpoint health"
        echo "  $0 status           - Show endpoint status"
        echo "  $0 put key value    - Set a key-value pair"
        echo "  $0 get key          - Get a value by key"
        echo "  $0 del key          - Delete a key"
        echo "  $0 backup           - Create a snapshot backup"
        ;;
esac
EOF

chmod +x ~/etcd-helper.sh
```

Test the helper script:

```bash
# Check cluster health
./etcd-helper.sh health

# Check cluster status
./etcd-helper.sh status

# List members
./etcd-helper.sh members
```

## etcd Configuration Details

### Security Configuration

The etcd cluster is configured with:

- **Client certificate authentication**: Requires valid certificates for API access
- **Peer certificate authentication**: Secures communication between etcd nodes
- **TLS encryption**: All communication is encrypted

### Network Configuration

- **Client URLs**: `https://10.0.3.10:2379` and `https://127.0.0.1:2379`
- **Peer URLs**: `https://10.0.3.10:2380`
- **Cluster Token**: `etcd-cluster-0`

### Data Directory

- **Data Directory**: `/var/lib/etcd`
- **Permissions**: `700` (owner read/write/execute only)

## Understanding etcd

### Key Concepts

- **Distributed**: etcd is a distributed key-value store
- **Consistent**: Uses Raft consensus algorithm
- **Available**: Designed for high availability
- **Partition-tolerant**: Can handle network partitions

### etcd in Kubernetes

etcd stores all Kubernetes cluster data:

- **Cluster state**: Node information, pod specifications
- **Configuration**: ConfigMaps, Secrets
- **Metadata**: Labels, annotations
- **RBAC**: Roles, bindings

### API Versions

- **API v2**: Legacy API (deprecated)
- **API v3**: Current API (what we're using)

## Monitoring and Maintenance

### Health Checks

Regular health checks:

```bash
# Check etcd health
./etcd-helper.sh health

# Check cluster status
./etcd-helper.sh status
```

### Backup Strategy

Create regular backups:

```bash
# Create a backup
./etcd-helper.sh backup

# List backups
ls -la /tmp/etcd-backup-*.db
```

### Log Analysis

Monitor etcd logs:

```bash
# View recent logs
sudo journalctl -u etcd --since "10 minutes ago"

# Follow logs in real-time
sudo journalctl -u etcd -f
```

## Troubleshooting

### Service Won't Start

If etcd fails to start:

1. Check the service status: `sudo systemctl status etcd`
2. View detailed logs: `sudo journalctl -u etcd --no-pager`
3. Verify certificate files: `ls -la /etc/etcd/`
4. Check port availability: `sudo netstat -tlnp | grep -E '2379|2380'`

### Connection Issues

If etcd connectivity fails:

1. Verify certificates: `openssl x509 -in /etc/etcd/kubernetes.pem -text -noout`
2. Test network connectivity: `telnet 127.0.0.1 2379`
3. Check firewall rules: `sudo ufw status`

### Performance Issues

If etcd is slow:

1. Check disk I/O: `iostat -x 1`
2. Monitor disk space: `df -h /var/lib/etcd`
3. Review logs for warnings: `sudo journalctl -u etcd | grep -i warn`

### Data Corruption

If data corruption occurs:

1. Stop etcd: `sudo systemctl stop etcd`
2. Remove data directory: `sudo rm -rf /var/lib/etcd/*`
3. Restore from backup: (restore procedure)
4. Start etcd: `sudo systemctl start etcd`

## High Availability Considerations

For production environments, consider:

- **Multiple etcd nodes**: Odd number (3, 5, 7)
- **Geographic distribution**: Spread across availability zones
- **Load balancing**: Use external load balancer
- **Monitoring**: Implement comprehensive monitoring
- **Backup automation**: Automated, regular backups

Next: [Bootstrapping the Kubernetes Control Plane](06-bootstrapping-kubernetes-controllers.md)