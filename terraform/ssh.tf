# SSH Key Generation and Management

# Generate SSH key pair if not provided
resource "tls_private_key" "ssh" {
  count     = var.ssh_public_key_path == "" ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Use provided SSH public key or generated one
locals {
  ssh_public_key = var.ssh_public_key_path != "" ? file(var.ssh_public_key_path) : tls_private_key.ssh[0].public_key_openssh
  ssh_private_key = var.ssh_public_key_path != "" ? null : tls_private_key.ssh[0].private_key_pem
}

# Save generated SSH keys to local files (if generated)
resource "local_file" "ssh_private_key" {
  count           = var.ssh_public_key_path == "" ? 1 : 0
  content         = tls_private_key.ssh[0].private_key_pem
  filename        = "${path.module}/ssh-keys/k8s-lab-key"
  file_permission = "0600"
  
  depends_on = [tls_private_key.ssh]
}

resource "local_file" "ssh_public_key" {
  count           = var.ssh_public_key_path == "" ? 1 : 0
  content         = tls_private_key.ssh[0].public_key_openssh
  filename        = "${path.module}/ssh-keys/k8s-lab-key.pub"
  file_permission = "0644"
  
  depends_on = [tls_private_key.ssh]
}

# Create directory for SSH keys
resource "null_resource" "ssh_keys_directory" {
  count = var.ssh_public_key_path == "" ? 1 : 0
  
  provisioner "local-exec" {
    command = "mkdir -p ${path.module}/ssh-keys"
    
    # Windows compatibility
    interpreter = ["powershell", "-Command"]
    when       = create
  }
}