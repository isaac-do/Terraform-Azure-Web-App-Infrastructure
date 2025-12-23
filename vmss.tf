# Create 3 ubuntu servers, put them in the same subnet, and register them to the load balancer's backend pool
resource "azurerm_orchestrated_virtual_machine_scale_set" "vmss_tf" {
  name                        = "vmss-tf"
  location                    = azurerm_resource_group.rg_webapp.location
  resource_group_name         = azurerm_resource_group.rg_webapp.name
  sku_name                    = "Standard_D2s_v4"
  instances                   = 2
  platform_fault_domain_count = 1 # for zonal deployment, this must be set to 1
  zones                       = ["1"]

  user_data_base64 = base64encode(file("user-data.sh")) # startup script that runs when each VM first boots
  os_profile {
    linux_configuration {
      disable_password_authentication = true
      admin_username                  = "azureuser"
      admin_ssh_key {
        username   = "azureuser"
        public_key = file("~/.ssh/id_ed25519.pub")
      }
    }
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-LTS-gen2"
    version   = "latest"
  }

  os_disk {
    storage_account_type = "Premium_LRS"
    caching              = "ReadWrite"
  }

  network_interface {
    name                          = "nic"
    primary                       = true
    enable_accelerated_networking = false

    ip_configuration {
      name                                   = "ipconfig"
      primary                                = true
      subnet_id                              = azurerm_subnet.subnet.id
      load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.backend_pool.id]
    }
  }

  boot_diagnostics {
    storage_account_uri = ""
  }

  # Ignore changes to the instances property, so that the VMSS is not recreated when the number of instances is changed
  lifecycle {
    ignore_changes = [
      instances
    ]
  }
}