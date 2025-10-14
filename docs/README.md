# Kubernetes the Hard Way - Azure Edition

This guide walks you through setting up a Kubernetes cluster the hard way on Azure. This is a great way to learn what happens under the hood of a Kubernetes cluster.

> **Note**: This guide is for educational purposes and is not meant for production use.

## Overview

Kubernetes the Hard Way guides you through bootstrapping a highly available Kubernetes cluster with end-to-end encryption between components and RBAC authentication.

## Target Audience

The target audience for this tutorial is someone planning to support a production Kubernetes cluster and wants to understand how everything fits together.

## Cluster Details

Kubernetes the Hard Way guides you through bootstrapping a highly available Kubernetes cluster with the following components:

* [Kubernetes](https://github.com/kubernetes/kubernetes) 1.28.0
* [containerd](https://github.com/containerd/containerd) Container Runtime 1.7.2
* [CNI Container Networking](https://github.com/containernetworking/cni) 1.3.0
* [etcd](https://github.com/etcd-io/etcd) v3.5.9

## Labs

This tutorial assumes you have access to Azure and have provisioned the infrastructure using the provided scripts.

### Prerequisites

- Access to Azure with sufficient permissions
- Azure CLI installed and configured
- SSH client
- Git

### Infrastructure

The infrastructure consists of:

- **Virtual Network**: `10.0.0.0/16`
- **Azure Bastion**: For secure access to VMs
- **NAT Gateway**: For outbound internet access
- **Jumpbox VM**: `10.0.2.10` - Ubuntu 22.04 LTS
- **Control Plane VM**: `10.0.3.10` - Ubuntu 22.04 LTS  
- **Worker Node 1**: `10.0.3.20` - Ubuntu 22.04 LTS
- **Worker Node 2**: `10.0.3.21` - Ubuntu 22.04 LTS

### Network Configuration

- **Service CIDR**: `10.100.0.0/16`
- **Pod CIDR**: `10.200.0.0/16`
- **Cluster DNS IP**: `10.100.0.10`

## Labs

1. [Prerequisites](01-prerequisites.md)
2. [Certificate Authority](02-certificate-authority.md)
3. [Kubernetes Configuration Files](03-kubernetes-configuration-files.md)
4. [Data Encryption Keys](04-data-encryption-keys.md)
5. [Bootstrapping etcd](05-bootstrapping-etcd.md)
6. [Bootstrapping the Kubernetes Control Plane](06-bootstrapping-kubernetes-controllers.md)
7. [Bootstrapping the Kubernetes Worker Nodes](07-bootstrapping-kubernetes-workers.md)
8. [Configuring kubectl for Remote Access](08-configuring-kubectl.md)
9. [Provisioning Pod Network Routes](09-pod-network-routes.md)
10. [Smoke Test](10-smoke-test.md)

## Getting Started

1. **Provision Infrastructure**: Run the infrastructure bootstrap script from your local machine
2. **Connect to Jumpbox**: Use Azure Bastion to connect to the jumpbox
3. **Clone Repository**: Clone this repository on the jumpbox
4. **Follow Labs**: Work through each lab in order

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────┐
│                    Azure Subscription                    │
├─────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────┐│
│  │              Virtual Network 10.0.0.0/16           ││
│  │                                                     ││
│  │  ┌──────────────┐  ┌──────────────┐  ┌───────────┐  ││
│  │  │   Bastion    │  │   Jumpbox    │  │ K8s Nodes │  ││
│  │  │  Subnet      │  │   Subnet     │  │  Subnet   │  ││
│  │  │ 10.0.1.0/24  │  │ 10.0.2.0/24  │  │10.0.3.0/24│  ││
│  │  │              │  │              │  │           │  ││
│  │  │ ┌──────────┐ │  │ ┌──────────┐ │  │┌─────────┐│  ││
│  │  │ │ Bastion  │ │  │ │ Jumpbox  │ │  ││Control  ││  ││
│  │  │ │ Service  │ │  │ │    VM    │ │  ││ Plane   ││  ││
│  │  │ └──────────┘ │  │ │10.0.2.10 │ │  ││10.0.3.10││  ││
│  │  └──────────────┘  │ └──────────┘ │  │└─────────┘│  ││
│  │                    └──────────────┘  │┌─────────┐│  ││
│  │                                      ││Worker-1 ││  ││
│  │                                      ││10.0.3.20││  ││
│  │                                      │└─────────┘│  ││
│  │                                      │┌─────────┐│  ││
│  │                                      ││Worker-2 ││  ││
│  │                                      ││10.0.3.21││  ││
│  │                                      │└─────────┘│  ││
│  │                                      └───────────┘  ││
│  └─────────────────────────────────────────────────────┘│
│  ┌─────────────────────────────────────────────────────┐│
│  │                  NAT Gateway                        ││
│  │              (Internet Access)                     ││
│  └─────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────┘
```

## Quick Test

To quickly test your setup without going through all the manual steps, you can use the automated setup script:

```bash
cd kubernetes-the-hard-way-azure
./scripts/automated-setup.sh
```

This will automatically configure the entire Kubernetes cluster, which is useful for testing your infrastructure or when you need a quick cluster setup.

## Cleanup

When you're done with the tutorial, you can clean up all Azure resources:

```bash
az group delete --name rg-k8s-the-hard-way --yes --no-wait
```

## Credits

This tutorial is inspired by and based on [Kubernetes the Hard Way](https://github.com/kelseyhightower/kubernetes-the-hard-way) by Kelsey Hightower, adapted for Azure infrastructure.