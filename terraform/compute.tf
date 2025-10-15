# Virtual Machines for Kubernetes Cluster

# Network Interfaces
resource "azurerm_network_interface" "jumpbox" {
  name                = "nic-jumpbox"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.jumpbox.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.2.10"
  }

  accelerated_networking_enabled = var.enable_accelerated_networking
}

resource "azurerm_network_interface" "control_plane" {
  name                = "nic-control-plane"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.kubernetes.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.3.10"
  }

  accelerated_networking_enabled = var.enable_accelerated_networking
  ip_forwarding_enabled          = true # Required for Kubernetes networking
}

resource "azurerm_network_interface" "worker" {
  count               = 2
  name                = "nic-worker-${count.index + 1}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.kubernetes.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.3.${20 + count.index}"
  }

  accelerated_networking_enabled = var.enable_accelerated_networking
  ip_forwarding_enabled          = true # Required for Kubernetes networking
}

# Virtual Machines
resource "azurerm_linux_virtual_machine" "jumpbox" {
  name                = "vm-jumpbox"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  size                = var.vm_size
  admin_username      = var.admin_username
  tags = merge(local.tags, {
    Role        = "Jumpbox"
    StudentName = var.student_name
  })

  # Disable password authentication
  disable_password_authentication = true

  network_interface_ids = [
    azurerm_network_interface.jumpbox.id,
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = local.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  # Install required tools
  custom_data = base64encode(templatefile("${path.module}/scripts/jumpbox-init.sh", {
    admin_username = var.admin_username
  }))
}

resource "azurerm_linux_virtual_machine" "control_plane" {
  name                = "vm-control-plane"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  size                = var.vm_size
  admin_username      = var.admin_username
  tags = merge(local.tags, {
    Role        = "ControlPlane"
    StudentName = var.student_name
  })

  # Disable password authentication
  disable_password_authentication = true

  network_interface_ids = [
    azurerm_network_interface.control_plane.id,
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = local.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  # Basic system preparation
  custom_data = base64encode(templatefile("${path.module}/scripts/k8s-node-init.sh", {
    admin_username = var.admin_username
    node_role      = "control-plane"
  }))
}

resource "azurerm_linux_virtual_machine" "worker" {
  count               = 2
  name                = "vm-worker-${count.index + 1}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  size                = var.vm_size
  admin_username      = var.admin_username
  tags = merge(local.tags, {
    Role        = "Worker"
    WorkerIndex = tostring(count.index + 1)
    StudentName = var.student_name
  })

  # Disable password authentication
  disable_password_authentication = true

  network_interface_ids = [
    azurerm_network_interface.worker[count.index].id,
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = local.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  # Basic system preparation
  custom_data = base64encode(templatefile("${path.module}/scripts/k8s-node-init.sh", {
    admin_username = var.admin_username
    node_role      = "worker"
  }))
}

# Auto-shutdown schedules for cost savings
resource "azurerm_dev_test_global_vm_shutdown_schedule" "jumpbox" {
  count              = var.auto_shutdown_enabled ? 1 : 0
  virtual_machine_id = azurerm_linux_virtual_machine.jumpbox.id
  location           = azurerm_resource_group.main.location
  enabled            = true

  daily_recurrence_time = var.auto_shutdown_time
  timezone              = var.auto_shutdown_timezone

  notification_settings {
    enabled = false
  }

  tags = local.tags
}

resource "azurerm_dev_test_global_vm_shutdown_schedule" "control_plane" {
  count              = var.auto_shutdown_enabled ? 1 : 0
  virtual_machine_id = azurerm_linux_virtual_machine.control_plane.id
  location           = azurerm_resource_group.main.location
  enabled            = true

  daily_recurrence_time = var.auto_shutdown_time
  timezone              = var.auto_shutdown_timezone

  notification_settings {
    enabled = false
  }

  tags = local.tags
}

resource "azurerm_dev_test_global_vm_shutdown_schedule" "worker" {
  count              = var.auto_shutdown_enabled ? 2 : 0
  virtual_machine_id = azurerm_linux_virtual_machine.worker[count.index].id
  location           = azurerm_resource_group.main.location
  enabled            = true

  daily_recurrence_time = var.auto_shutdown_time
  timezone              = var.auto_shutdown_timezone

  notification_settings {
    enabled = false
  }

  tags = local.tags
}
