# Kubernetes the Hard Way - Azure Infrastructure
# This Terraform configuration provisions the required Azure infrastructure
# for a Kubernetes cluster using private IPs only with NAT Gateway

terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {}
}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for configuration
locals {
  location            = var.location
  resource_group_name = "rg-k8s-the-hard-way-${random_string.suffix.result}"
  
  # Network configuration
  vnet_cidr = "10.0.0.0/16"
  subnets = {
    bastion = {
      name    = "AzureBastionSubnet"  # Required name for Azure Bastion
      cidr    = "10.0.1.0/24"
    }
    jumpbox = {
      name    = "snet-jumpbox"
      cidr    = "10.0.2.0/24"
    }
    kubernetes = {
      name    = "snet-k8s"
      cidr    = "10.0.3.0/24"
    }
  }
  
  # VM configuration
  vm_size = "Standard_B2s"
  admin_username = "azureuser"
  
  # Common tags
  tags = {
    Environment = "Lab"
    Project     = "Kubernetes-The-Hard-Way"
    CreatedBy   = "Terraform"
    Purpose     = "Education"
  }
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = local.location
  tags     = local.tags
}

# Virtual Network
resource "azurerm_virtual_network" "main" {
  name                = "vnet-k8s-${random_string.suffix.result}"
  address_space       = [local.vnet_cidr]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.tags
}

# Subnets
resource "azurerm_subnet" "bastion" {
  name                 = local.subnets.bastion.name
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [local.subnets.bastion.cidr]
}

resource "azurerm_subnet" "jumpbox" {
  name                 = local.subnets.jumpbox.name
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [local.subnets.jumpbox.cidr]
}

resource "azurerm_subnet" "kubernetes" {
  name                 = local.subnets.kubernetes.name
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [local.subnets.kubernetes.cidr]
}

# Public IP for NAT Gateway
resource "azurerm_public_ip" "nat_gateway" {
  name                = "pip-nat-gateway-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1"]
  tags                = local.tags
}

# NAT Gateway
resource "azurerm_nat_gateway" "main" {
  name                    = "nat-gateway-${random_string.suffix.result}"
  location                = azurerm_resource_group.main.location
  resource_group_name     = azurerm_resource_group.main.name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10
  zones                   = ["1"]
  tags                    = local.tags
}

# Associate Public IP to NAT Gateway
resource "azurerm_nat_gateway_public_ip_association" "main" {
  nat_gateway_id       = azurerm_nat_gateway.main.id
  public_ip_address_id = azurerm_public_ip.nat_gateway.id
}

# Associate NAT Gateway to subnets
resource "azurerm_subnet_nat_gateway_association" "jumpbox" {
  subnet_id      = azurerm_subnet.jumpbox.id
  nat_gateway_id = azurerm_nat_gateway.main.id
}

resource "azurerm_subnet_nat_gateway_association" "kubernetes" {
  subnet_id      = azurerm_subnet.kubernetes.id
  nat_gateway_id = azurerm_nat_gateway.main.id
}

# Note: Azure Bastion Developer Edition (free tier) doesn't require a dedicated subnet or public IP
# It uses shared infrastructure. For production workloads, consider using Standard SKU.

# Azure Bastion Host (Developer Edition - Free)
resource "azurerm_bastion_host" "main" {
  name                   = "bastion-${random_string.suffix.result}"
  location               = azurerm_resource_group.main.location
  resource_group_name    = azurerm_resource_group.main.name
  sku                    = "Developer"  # Free tier
  virtual_network_id     = azurerm_virtual_network.main.id
  tags                   = local.tags
}