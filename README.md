# Kubernetes the Hard Way - Azure Edition

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

> Learn Kubernetes by building a cluster from scratch on Azure infrastructure

This repository contains a complete implementation of "Kubernetes the Hard Way" specifically designed for Azure, with a focus on **educational purposes** and **hands-on learning**. Perfect for classrooms, workshops, and anyone wanting to understand how Kubernetes works under the hood.

## 🎯 Project Goals

- **Educational Focus**: Learn Kubernetes internals by building everything manually
- **Azure Native**: Uses Azure services with private networking and security best practices
- **Infrastructure Automation**: Quick infrastructure provisioning so you can focus on Kubernetes
- **Step-by-Step Learning**: Detailed documentation for each component
- **Quick Testing**: Automated setup script for rapid validation

## 🚀 Quick Start Options

### Option 1: Terraform (Recommended)
Fast infrastructure deployment with cross-platform support:

```bash
cd terraform
# Copy and configure variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your preferences

# Deploy infrastructure
terraform init
terraform plan
terraform apply
```

[🔗 **Full Setup Instructions**](#-setup-instructions) | [🐳 **Terraform Guide**](terraform/README.md)

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                 Azure Resource Group                     │
├─────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────┐│
│  │           Virtual Network (10.0.0.0/16)            ││
│  │                                                     ││
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ││
│  │  │   Bastion   │  │   Jumpbox   │  │  K8s Nodes  │  ││
│  │  │   Subnet    │  │   Subnet    │  │   Subnet    │  ││
│  │  │10.0.1.0/24  │  │10.0.2.0/24  │  │10.0.3.0/24  │  ││
│  │  │             │  │             │  │             │  ││
│  │  │┌───────────┐│  │┌───────────┐│  │┌───────────┐│  ││
│  │  ││Azure      ││  ││Jumpbox VM ││  ││Control    ││  ││
│  │  ││Bastion    ││  ││10.0.2.10  ││  ││Plane      ││  ││
│  │  ││(Free Tier)││  ││           ││  ││10.0.3.10  ││  ││
│  │  │└───────────┘│  │└───────────┘│  │└───────────┘│  ││
│  │  └─────────────┘  └─────────────┘  │┌───────────┐│  ││
│  │                                     ││Worker-1   ││  ││
│  │        ┌─────────────────────────┐  ││10.0.3.20  ││  ││
│  │        │      NAT Gateway        │  │└───────────┘│  ││
│  │        │   (Internet Access)    │  │┌───────────┐│  ││
│  │        └─────────────────────────┘  ││Worker-2   ││  ││
│  │                                     ││10.0.3.21  ││  ││
│  │                                     │└───────────┘│  ││
│  │                                     └─────────────┘  ││
│  └─────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────┘
```

### 🔧 Infrastructure Components

- **Virtual Network**: `10.0.0.0/16` with NAT Gateway for secure outbound access
- **Azure Bastion**: Free Developer Edition for secure VM access
- **Jumpbox**: Ubuntu 22.04 LTS (B2s) - Your main access point
- **Control Plane**: Ubuntu 22.04 LTS (B2s) - Kubernetes master
- **Worker Nodes**: 2x Ubuntu 22.04 LTS (B2s) - Kubernetes workers

### 🌐 Network Configuration

- **Service CIDR**: `10.100.0.0/16`
- **Pod CIDR**: `10.200.0.0/16`
- **Cluster DNS**: `10.100.0.10`
- **Private Networking**: All VMs use private IPs only

## 🚀 Quick Start

### 1. Prerequisites

- Azure subscription with sufficient permissions
- Azure CLI installed and configured (`az login`)
- Git client
- SSH client

### 2. Provision Infrastructure

```bash
# Clone the repository
git clone https://github.com/your-username/kubernetes-the-hard-way-azure.git
cd kubernetes-the-hard-way-azure

# Deploy infrastructure using Terraform
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your preferences

terraform init
terraform plan
terraform apply
```

**⏱️ Infrastructure provisioning takes ~10-15 minutes**

### 3. Connect to Jumpbox

1. Open [Azure Portal](https://portal.azure.com)
2. Navigate to Resource Group: `rg-k8s-the-hard-way`
3. Click on `vm-jumpbox` → Connect → Bastion
4. Login with username: `azureuser` and SSH key

### 4. Setup SSH Access

SSH keys are automatically configured during Terraform deployment. Test connectivity from the jumpbox:

```bash
# Test connectivity to control plane
ssh azureuser@10.0.3.10

# Test connectivity to worker nodes  
ssh azureuser@10.0.3.20
ssh azureuser@10.0.3.21
```

### 5. Choose Your Path

#### 🎓 **Learning Path** (Recommended for education)
Follow the step-by-step labs to build Kubernetes manually:

```bash
# Clone repository on jumpbox (if not already done)
git clone https://github.com/your-username/kubernetes-the-hard-way-azure.git
cd kubernetes-the-hard-way-azure

# Follow the documentation
cd docs
# Start with: 01-prerequisites.md
```

#### ⚡ **Quick Setup** (For testing infrastructure)
Use the automated script to build the cluster quickly:

```bash
cd kubernetes-the-hard-way-azure
./scripts/automated-setup.sh
```

## 📚 Learning Labs

| Lab                                                   | Topic                          | Time   | Difficulty |
| ----------------------------------------------------- | ------------------------------ | ------ | ---------- |
| [01](docs/01-prerequisites.md)                        | Prerequisites & SSH Setup      | 15 min | ⭐          |
| [02](docs/02-certificate-authority.md)                | Certificate Authority & TLS    | 30 min | ⭐⭐         |
| [03](docs/03-kubernetes-configuration-files.md)       | Kubernetes Configuration Files | 20 min | ⭐⭐         |
| [04](docs/04-data-encryption-keys.md)                 | Data Encryption Keys           | 10 min | ⭐          |
| [05](docs/05-bootstrapping-etcd.md)                   | Bootstrapping etcd             | 25 min | ⭐⭐         |
| [06](docs/06-bootstrapping-kubernetes-controllers.md) | Control Plane Setup            | 35 min | ⭐⭐⭐        |
| [07](docs/07-bootstrapping-kubernetes-workers.md)     | Worker Nodes Setup             | 30 min | ⭐⭐⭐        |
| [08](docs/08-configuring-kubectl.md)                  | kubectl Configuration          | 15 min | ⭐⭐         |
| [09](docs/09-pod-network-routes.md)                   | Pod Network Routes             | 20 min | ⭐⭐         |
| [10](docs/10-smoke-test.md)                           | Smoke Test                     | 15 min | ⭐          |

**Total estimated time**: ~3-4 hours

## 🛠️ Project Structure

```
kubernetes-the-hard-way-azure/
├── terraform/                         # Terraform infrastructure
│   ├── main.tf                       # Core infrastructure
│   ├── variables.tf                  # Configuration variables
│   ├── outputs.tf                    # Deployment outputs
│   ├── cleanup.ps1                   # Resource cleanup
│   └── README.md                     # Terraform guide
├── scripts/
│   └── automated-setup.sh             # Automated K8s setup
├── docs/
│   ├── README.md                      # Lab overview
│   ├── 01-prerequisites.md            # Getting started
│   ├── 02-certificate-authority.md    # PKI setup
│   ├── 03-kubernetes-configuration-files.md
│   ├── 04-data-encryption-keys.md
│   ├── 05-bootstrapping-etcd.md
│   ├── 06-bootstrapping-kubernetes-controllers.md
│   ├── 07-bootstrapping-kubernetes-workers.md
│   ├── 08-configuring-kubectl.md
│   ├── 09-pod-network-routes.md
│   └── 10-smoke-test.md
├── infra/                             # Infrastructure as Code (future)
└── kubernetes/                        # Kubernetes manifests
```

## 🎯 Educational Features

### 🔐 **Security First**
- PKI certificate management
- TLS encryption everywhere
- RBAC configuration
- Private networking with NAT Gateway

### 🔍 **Deep Learning**
- Manual component installation
- Configuration file creation
- Service systemd unit files
- Network policy understanding

### 🧪 **Hands-On Testing**
- Component verification steps
- Troubleshooting guides
- Helper scripts for common tasks
- Comprehensive smoke testing

## 💰 Cost Optimization

This setup is designed to be cost-effective for educational use:

- **Azure Bastion**: Free Developer Edition
- **VMs**: Standard_B2s (burstable, cost-effective)
- **Storage**: Standard LRS (cheapest option)
- **NAT Gateway**: Pay-per-use model
- **Auto-shutdown**: VMs automatically shut down at 7 PM UTC

**Estimated cost**: ~$10-15/day with auto-shutdown, ~$30-50/month if left running

⚠️ **Remember to clean up resources when done!**

## 🧹 Cleanup

### Terraform Cleanup
```powershell
# Windows PowerShell
cd terraform
.\cleanup.ps1

# Linux/macOS
cd terraform
terraform destroy
```

### Bash Scripts Cleanup
```bash
# Delete all Azure resources
az group delete --name rg-k8s-the-hard-way --yes --no-wait
```

## 🤝 For Educators

### Classroom Setup

1. **Choose deployment method**:
   - **Terraform**: Better for Windows users, faster parallel deployment
   - **Bash scripts**: Traditional approach, more instructional
2. **Pre-provisioning**: Run infrastructure setup before class
3. **Student Access**: Provide Azure Portal access instructions
4. **Lab Time**: 3-4 hours for complete manual setup
5. **Quick Validation**: Use automated script to verify infrastructure

### Deployment Recommendations

| Student Environment | Recommended Method | Benefits                                       |
| ------------------- | ------------------ | ---------------------------------------------- |
| Windows laptops     | Terraform          | Native PowerShell, parallel deployment         |
| macOS/Linux         | Either method      | Bash scripts for learning, Terraform for speed |
| Mixed environment   | Terraform          | Consistent experience across platforms         |
| Educational focus   | Bash scripts       | More visibility into infrastructure steps      |

### Learning Objectives

Students will learn:
- ✅ PKI and certificate management
- ✅ Kubernetes component architecture
- ✅ Network security and policy
- ✅ Service discovery and DNS
- ✅ Container runtime integration
- ✅ Troubleshooting techniques

### Assessment Ideas

- Certificate chain validation
- Component health checking
- Network connectivity testing
- Pod scheduling and networking
- Security policy implementation

## 🔧 Advanced Usage

### Custom Configurations

Modify these environment variables in `k8s-env.sh`:

```bash
export SERVICE_CIDR="10.100.0.0/16"    # Kubernetes services
export POD_CIDR="10.200.0.0/16"        # Pod networking
export CLUSTER_DNS_IP="10.100.0.10"    # DNS service IP
```

### Multi-Master Setup

For high availability, the infrastructure can be extended to support multiple control plane nodes. See the infrastructure documentation for details.

### Custom Networking

The network architecture supports:
- Multiple availability zones
- Custom subnet configurations
- Additional security groups
- Load balancer integration

## 🐛 Troubleshooting

### Common Issues

| Issue                  | Solution                                       |
| ---------------------- | ---------------------------------------------- |
| SSH connectivity fails | Check Bastion connection and private key       |
| VM provisioning errors | Verify Azure quota and permissions             |
| Certificate errors     | Regenerate certificates with correct hostnames |
| etcd won't start       | Check certificate placement and permissions    |
| Pods won't schedule    | Verify kubelet and container runtime           |

### Getting Help

1. Check the troubleshooting section in each lab
2. Review the logs: `sudo journalctl -u [service-name]`
3. Verify network connectivity between components
4. Use the helper scripts for common operations

## 📖 Additional Resources

- [Original Kubernetes the Hard Way](https://github.com/kelseyhightower/kubernetes-the-hard-way)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Azure Kubernetes Service (AKS)](https://docs.microsoft.com/en-us/azure/aks/)
- [containerd Documentation](https://containerd.io/)
- [etcd Documentation](https://etcd.io/docs/)

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Test your changes thoroughly
4. Submit a pull request with detailed description

### Areas for Contribution

- Additional monitoring and observability
- Helm chart deployments
- CI/CD pipeline integration
- Multi-region setup
- Terraform/Bicep IaC templates

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [Kelsey Hightower](https://github.com/kelseyhightower) for the original "Kubernetes the Hard Way"
- The Kubernetes community for excellent documentation
- Azure team for the robust cloud platform

---

**Happy Learning! 🚀**

*"The best way to learn Kubernetes is to build it yourself"*