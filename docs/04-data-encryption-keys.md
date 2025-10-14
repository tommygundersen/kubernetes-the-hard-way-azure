# Data Encryption Keys

Kubernetes stores a variety of data including cluster state, application configurations, and secrets. Kubernetes supports the ability to [encrypt cluster data at rest](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data).

In this lab you will generate an encryption key and an [encryption config](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/#understanding-the-encryption-at-rest-configuration) suitable for encrypting Kubernetes Secrets.

## The Encryption Key

Generate an encryption key:

```bash
# Ensure we're in the certificates directory
cd ~/kubernetes-the-hard-way-azure/certificates

# Generate a random encryption key
ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)

echo "Generated encryption key: $ENCRYPTION_KEY"
```

## The Encryption Config File

Create the `encryption-config.yaml` encryption config file:

```bash
cat > encryption-config.yaml << EOF
kind: EncryptionConfig
apiVersion: v1
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${ENCRYPTION_KEY}
      - identity: {}
EOF
```

## Distribute the Encryption Config File

Copy the `encryption-config.yaml` encryption config file to the controller instance:

```bash
# Ensure environment variables are loaded
source ~/k8s-env.sh

# Copy encryption config to control plane
scp encryption-config.yaml azureuser@${CONTROL_PLANE_IP}:~/
```

## Verification

### Verify Encryption Config File

Check the contents of the encryption config file:

```bash
cat encryption-config.yaml
```

You should see output similar to:

```yaml
kind: EncryptionConfig
apiVersion: v1
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: <base64-encoded-key>
      - identity: {}
```

### Verify File Distribution

Confirm the encryption config file was copied to the control plane:

```bash
ssh azureuser@${CONTROL_PLANE_IP} 'ls -la encryption-config.yaml'
ssh azureuser@${CONTROL_PLANE_IP} 'cat encryption-config.yaml'
```

### Validate Encryption Key

Verify the encryption key is properly base64 encoded and has the correct length:

```bash
# Check the key length (should be 44 characters for a 32-byte key)
echo $ENCRYPTION_KEY | wc -c

# Verify it's valid base64
echo $ENCRYPTION_KEY | base64 -d > /dev/null && echo "✓ Valid base64" || echo "✗ Invalid base64"

# Check the decoded key length (should be 32 bytes)
echo $ENCRYPTION_KEY | base64 -d | wc -c
```

## Understanding Encryption at Rest

### How It Works

When encryption at rest is enabled:

1. **API Server**: Encrypts data before storing it in etcd
2. **etcd**: Stores encrypted data (cannot read the actual values)
3. **Decryption**: Only the API server with the encryption key can decrypt the data

### Provider Types

The encryption config supports multiple providers:

- **aescbc**: AES-CBC with PKCS#7 padding (what we're using)
- **secretbox**: XSalsa20 and Poly1305
- **aesgcm**: AES-GCM
- **identity**: No encryption (fallback)

### Resource Types

You can encrypt different types of Kubernetes resources:

- **secrets**: Sensitive data like passwords, tokens, keys
- **configmaps**: Configuration data
- **events**: Cluster events
- **all**: Encrypt all supported resources

### Provider Order

The order of providers matters:

1. **First provider**: Used for encryption of new data
2. **Subsequent providers**: Used for decryption of existing data
3. **identity provider**: Fallback for unencrypted data

## Security Best Practices

### Key Management

- **Rotation**: Regularly rotate encryption keys
- **Storage**: Store keys securely, separate from etcd data
- **Backup**: Backup encryption keys securely
- **Access**: Limit access to encryption keys

### Implementation

- **Multiple Keys**: Support key rotation by having multiple keys
- **Key Names**: Use descriptive names for keys
- **Monitoring**: Monitor encryption/decryption operations

## Advanced Configuration

### Multiple Keys for Rotation

You can configure multiple keys to support key rotation:

```yaml
kind: EncryptionConfig
apiVersion: v1
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key2
              secret: <new-base64-encoded-key>
            - name: key1
              secret: <old-base64-encoded-key>
      - identity: {}
```

### Encrypting Additional Resources

To encrypt more than just secrets:

```yaml
kind: EncryptionConfig
apiVersion: v1
resources:
  - resources:
      - secrets
      - configmaps
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${ENCRYPTION_KEY}
      - identity: {}
```

## Troubleshooting

### File Copy Issues

If the encryption config file doesn't copy:

1. Check SSH connectivity: `ssh azureuser@${CONTROL_PLANE_IP} 'hostname'`
2. Verify file exists locally: `ls -la encryption-config.yaml`
3. Check file permissions: `ls -la ~/.ssh/id_rsa`

### Invalid Configuration

If the encryption config is invalid:

1. Validate YAML syntax: `cat encryption-config.yaml | python3 -c "import sys, yaml; yaml.safe_load(sys.stdin)"`
2. Check the encryption key format: `echo $ENCRYPTION_KEY | base64 -d > /dev/null`
3. Verify the key length: `echo $ENCRYPTION_KEY | base64 -d | wc -c`

### Key Generation Issues

If encryption key generation fails:

1. Check /dev/urandom availability: `ls -la /dev/urandom`
2. Verify base64 command: `which base64`
3. Test manual generation: `head -c 32 /dev/urandom | base64`

## Testing Encryption

After the API server is configured with encryption (in later labs), you can test encryption:

```bash
# Create a secret
kubectl create secret generic test-secret --from-literal=key=value

# Check that it's encrypted in etcd (this will be covered in later labs)
# The data should not be readable in plain text
```

## Storage Considerations

- **etcd Backup**: Backup both etcd data AND encryption keys
- **Key Storage**: Store encryption keys separately from etcd
- **Recovery**: Ensure you can recover both data and keys
- **Migration**: Plan for migrating between encryption methods

Next: [Bootstrapping etcd](05-bootstrapping-etcd.md)