# Network Security Groups and Rules

# Network Security Group for Jumpbox
resource "azurerm_network_security_group" "jumpbox" {
  name                = "nsg-jumpbox-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.tags

  # Allow SSH from anywhere (Bastion will be the secure entry point)
  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Allow outbound internet access
  security_rule {
    name                       = "AllowInternetOutbound"
    priority                   = 1000
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "Internet"
  }
}

# Network Security Group for Kubernetes nodes
resource "azurerm_network_security_group" "kubernetes" {
  name                = "nsg-k8s-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.tags

  # Allow SSH from jumpbox subnet
  security_rule {
    name                       = "SSH-from-jumpbox"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = local.subnets.jumpbox.cidr
    destination_address_prefix = "*"
  }

  # Allow Kubernetes API server (6443)
  security_rule {
    name                       = "Kubernetes-API"
    priority                   = 1010
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "6443"
    source_address_prefix      = local.subnets.kubernetes.cidr
    destination_address_prefix = "*"
  }

  # Allow etcd communication (2379-2380)
  security_rule {
    name                       = "etcd"
    priority                   = 1020
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["2379", "2380"]
    source_address_prefix      = local.subnets.kubernetes.cidr
    destination_address_prefix = "*"
  }

  # Allow kubelet API (10250)
  security_rule {
    name                       = "kubelet-API"
    priority                   = 1030
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "10250"
    source_address_prefix      = local.subnets.kubernetes.cidr
    destination_address_prefix = "*"
  }

  # Allow kube-scheduler (10251)
  security_rule {
    name                       = "kube-scheduler"
    priority                   = 1040
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "10251"
    source_address_prefix      = local.subnets.kubernetes.cidr
    destination_address_prefix = "*"
  }

  # Allow kube-controller-manager (10252)
  security_rule {
    name                       = "kube-controller-manager"
    priority                   = 1050
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "10252"
    source_address_prefix      = local.subnets.kubernetes.cidr
    destination_address_prefix = "*"
  }

  # Allow NodePort Services (30000-32767)
  security_rule {
    name                       = "NodePort-Services"
    priority                   = 1060
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "30000-32767"
    source_address_prefix      = local.subnets.kubernetes.cidr
    destination_address_prefix = "*"
  }

  # Allow Pod-to-Pod communication (CNI bridge)
  security_rule {
    name                       = "Pod-Network"
    priority                   = 1070
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "10.200.0.0/16"  # Pod CIDR
    destination_address_prefix = "10.200.0.0/16"
  }

  # Allow internal cluster communication
  security_rule {
    name                       = "Internal-Cluster"
    priority                   = 1080
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = local.subnets.kubernetes.cidr
    destination_address_prefix = local.subnets.kubernetes.cidr
  }

  # Allow outbound internet access
  security_rule {
    name                       = "AllowInternetOutbound"
    priority                   = 1000
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "Internet"
  }
}

# Associate NSG with jumpbox subnet
resource "azurerm_subnet_network_security_group_association" "jumpbox" {
  subnet_id                 = azurerm_subnet.jumpbox.id
  network_security_group_id = azurerm_network_security_group.jumpbox.id
}

# Associate NSG with kubernetes subnet
resource "azurerm_subnet_network_security_group_association" "kubernetes" {
  subnet_id                 = azurerm_subnet.kubernetes.id
  network_security_group_id = azurerm_network_security_group.kubernetes.id
}