# Output values from the Terraform deployment

# Resource Group
output "resource_group_name" {
  description = "The name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "The location of the resource group"
  value       = azurerm_resource_group.main.location
}

# Network Information
output "virtual_network_name" {
  description = "The name of the virtual network"
  value       = azurerm_virtual_network.main.name
}

output "virtual_network_address_space" {
  description = "The address space of the virtual network"
  value       = azurerm_virtual_network.main.address_space
}

output "subnet_information" {
  description = "Information about all subnets"
  value = {
    bastion = {
      name          = azurerm_subnet.bastion.name
      address_prefix = azurerm_subnet.bastion.address_prefixes[0]
    }
    jumpbox = {
      name          = azurerm_subnet.jumpbox.name
      address_prefix = azurerm_subnet.jumpbox.address_prefixes[0]
    }
    kubernetes = {
      name          = azurerm_subnet.kubernetes.name
      address_prefix = azurerm_subnet.kubernetes.address_prefixes[0]
    }
  }
}

# NAT Gateway
output "nat_gateway_public_ip" {
  description = "The public IP address of the NAT Gateway"
  value       = azurerm_public_ip.nat_gateway.ip_address
}

# Azure Bastion (Developer Edition - No dedicated public IP)
output "bastion_info" {
  description = "Azure Bastion information"
  value = {
    name = azurerm_bastion_host.main.name
    sku  = "Developer (Free Tier)"
    note = "Connect via Azure Portal - no dedicated public IP required"
  }
}

# Virtual Machine Information
output "vm_information" {
  description = "Information about all virtual machines"
  value = {
    jumpbox = {
      name       = azurerm_linux_virtual_machine.jumpbox.name
      private_ip = azurerm_network_interface.jumpbox.private_ip_address
      size       = azurerm_linux_virtual_machine.jumpbox.size
    }
    control_plane = {
      name       = azurerm_linux_virtual_machine.control_plane.name
      private_ip = azurerm_network_interface.control_plane.private_ip_address
      size       = azurerm_linux_virtual_machine.control_plane.size
    }
    workers = [
      for i in range(2) : {
        name       = azurerm_linux_virtual_machine.worker[i].name
        private_ip = azurerm_network_interface.worker[i].private_ip_address
        size       = azurerm_linux_virtual_machine.worker[i].size
      }
    ]
  }
}

# SSH Information
output "ssh_key_information" {
  description = "SSH key information"
  value = {
    public_key_generated = var.ssh_public_key_path == "" ? true : false
    private_key_path     = var.ssh_public_key_path == "" ? "${path.module}/ssh-keys/k8s-lab-key" : "Using provided key"
    public_key_path      = var.ssh_public_key_path == "" ? "${path.module}/ssh-keys/k8s-lab-key.pub" : var.ssh_public_key_path
  }
}

# Connection Information
output "connection_instructions" {
  description = "Instructions for connecting to the environment"
  value = {
    bastion_connection = "Use Azure Bastion to connect to VMs via the Azure portal"
    jumpbox_ip        = azurerm_network_interface.jumpbox.private_ip_address
    control_plane_ip  = azurerm_network_interface.control_plane.private_ip_address
    worker_ips = [
      for i in range(2) : azurerm_network_interface.worker[i].private_ip_address
    ]
    ssh_command_from_jumpbox = "ssh azureuser@<target-ip>"
  }
}

# Configuration for Lab
output "lab_configuration" {
  description = "Configuration values needed for the lab"
  value = {
    cluster_cidr = "10.200.0.0/16"
    service_cidr = "10.100.0.0/16"
    dns_ip       = "10.100.0.10"
    pod_cidr     = "10.200.0.0/16"
    kubernetes_version = var.kubernetes_version
  }
}

# Cost Management
output "cost_management" {
  description = "Cost management features"
  value = {
    auto_shutdown_enabled = var.auto_shutdown_enabled
    auto_shutdown_time    = var.auto_shutdown_time
    auto_shutdown_timezone = var.auto_shutdown_timezone
    vm_size_used          = var.vm_size
  }
}

# Next Steps
output "next_steps" {
  description = "Next steps for setting up Kubernetes"
  value = [
    "1. Connect to the jumpbox using Azure Bastion",
    "2. Clone the kubernetes-the-hard-way-azure repository",
    "3. Follow the documentation starting with 01-prerequisites.md",
    "4. Use the SSH configuration to connect to cluster nodes",
    "5. Begin with certificate authority setup (02-certificate-authority.md)"
  ]
}

# Sensitive outputs (marked as sensitive to avoid showing in logs)
output "admin_username" {
  description = "The admin username for all VMs"
  value       = var.admin_username
  sensitive   = false
}

# Resource identifiers for automation scripts
output "resource_ids" {
  description = "Azure resource IDs for automation"
  value = {
    resource_group_id = azurerm_resource_group.main.id
    vnet_id          = azurerm_virtual_network.main.id
    jumpbox_vm_id    = azurerm_linux_virtual_machine.jumpbox.id
    control_plane_vm_id = azurerm_linux_virtual_machine.control_plane.id
    worker_vm_ids = [
      for vm in azurerm_linux_virtual_machine.worker : vm.id
    ]
  }
}