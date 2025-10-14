# Input variables for the Kubernetes infrastructure

variable "location" {
  description = "The Azure region where resources will be created"
  type        = string
  default     = "West Europe"
  
  validation {
    condition = contains([
      "West Europe", "East US", "East US 2", "West US 2", "Central US",
      "North Europe", "Southeast Asia", "UK South", "Australia East",
      "swedencentral", "Sweden Central", "norwayeast", "Norway East",
      "westeurope", "northeurope", "eastus", "westus2", "centralus",
      "southeastasia", "uksouth", "australiaeast", "canadacentral",
      "japaneast", "koreacentral", "southcentralus", "brazilsouth",
      "francecentral", "germanywestcentral", "switzerlandnorth"
    ], var.location)
    error_message = "Location must be a valid Azure region. Common regions: West Europe, East US, Sweden Central, Norway East, etc."
  }
}

variable "vm_size" {
  description = "Size of the virtual machines"
  type        = string
  default     = "Standard_B2s"
  
  validation {
    condition = contains([
      "Standard_B1s", "Standard_B2s", "Standard_B2ms", "Standard_B4ms",
      "Standard_D2s_v3", "Standard_D4s_v3", "Standard_E2s_v3"
    ], var.vm_size)
    error_message = "VM size must be a valid Azure VM SKU suitable for labs."
  }
}

variable "admin_username" {
  description = "Administrator username for virtual machines"
  type        = string
  default     = "azureuser"
  
  validation {
    condition     = length(var.admin_username) >= 3 && length(var.admin_username) <= 20
    error_message = "Admin username must be between 3 and 20 characters."
  }
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key file (will be generated if not provided)"
  type        = string
  default     = ""
}

variable "kubernetes_version" {
  description = "Kubernetes version for reference (used in documentation)"
  type        = string
  default     = "1.28.0"
}

variable "enable_accelerated_networking" {
  description = "Enable accelerated networking on VMs (requires supported VM sizes)"
  type        = bool
  default     = false
}

variable "environment" {
  description = "Environment name for tagging"
  type        = string
  default     = "lab"
  
  validation {
    condition = contains([
      "dev", "test", "staging", "prod", "lab", "demo"
    ], var.environment)
    error_message = "Environment must be one of: dev, test, staging, prod, lab, demo."
  }
}

variable "student_name" {
  description = "Student name for resource tagging (optional)"
  type        = string
  default     = ""
}

variable "auto_shutdown_enabled" {
  description = "Enable auto-shutdown for VMs to save costs"
  type        = bool
  default     = true
}

variable "auto_shutdown_time" {
  description = "Time for auto-shutdown in HHMM format (24-hour)"
  type        = string
  default     = "1900"
  
  validation {
    condition     = can(regex("^([01][0-9]|2[0-3])[0-5][0-9]$", var.auto_shutdown_time))
    error_message = "Auto shutdown time must be in HHMM format (24-hour)."
  }
}

variable "auto_shutdown_timezone" {
  description = "Timezone for auto-shutdown"
  type        = string
  default     = "UTC"
}