# Assign the load balancer a random name
resource "random_pet" "lb_hostname" {
}

# Web App resource group
# Keeps everything for the web app environment together
resource "azurerm_resource_group" "rg_webapp" {
  name     = "rg-web-app"
  location = "centralus"
}

# Create a network security group
# Define the network security group with rules for HTTP, HTTPS, and SSH access
resource "azurerm_network_security_group" "nsg" {
  name                = "nsg-webapp-dev"
  location            = azurerm_resource_group.rg_webapp.location
  resource_group_name = azurerm_resource_group.rg_webapp.name

  security_rule {
    name                       = "allow-http"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-https"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-ssh"
    priority                   = 102
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = {
    environment = "Webapp-Dev"
  }
}

# Create a virtual network (like a private office LAN)
# Serves as the network infrastructure for servers and internal services to talk privately
# without exposing everything to the internet.
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-webapp-dev"
  location            = azurerm_resource_group.rg_webapp.location
  resource_group_name = azurerm_resource_group.rg_webapp.name
  address_space       = ["10.0.0.0/16"]
  dns_servers         = ["8.8.8.8", "1.1.1.1"]

  tags = {
    environment = "Webapp-Dev"
  }
}

# Create a subnet within the virtual network
# Place resources in here like VMs, VM scale sets, etc..
resource "azurerm_subnet" "subnet" {
  name                 = "subnet-webapp-dev"
  resource_group_name  = azurerm_resource_group.rg_webapp.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.0.0/20"]
}

# Make the subnet obey the NSG rules
resource "azurerm_subnet_network_security_group_association" "nsg-webapp" {
  subnet_id                 = azurerm_subnet.subnet.id
  network_security_group_id = azurerm_network_security_group.nsg.id

  depends_on = [azurerm_orchestrated_virtual_machine_scale_set.vmss_tf]
}

# A public IP reachable from the internet
# load balancer's public "front door"
resource "azurerm_public_ip" "publicIP" {
  name                = "lb-publicIP"
  resource_group_name = azurerm_resource_group.rg_webapp.name
  location            = azurerm_resource_group.rg_webapp.location
  allocation_method   = "Static"
  sku                 = "Standard"      # supports zone redundancy
  zones               = ["1", "2", "3"] # aim for resiliency across availability zones
  domain_name_label   = "${azurerm_resource_group.rg_webapp.name}-${random_pet.lb_hostname.id}"

  tags = {
    environment = "Webapp-Dev"
  }
}

# Create a load balancer
# Clients hit the public IP, and the load balancer forwards traffic to the backend servers
# Helps to distribute traffic, keep sites up when one server is unhealthy, avoid exposing each server directly to the internet
resource "azurerm_lb" "lb_webapp" {
  name                = "lb-webapp-dev"
  location            = azurerm_resource_group.rg_webapp.location
  resource_group_name = azurerm_resource_group.rg_webapp.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.publicIP.id
  }
}

# List of servers behind the load balancer
resource "azurerm_lb_backend_address_pool" "backend_pool" {
  loadbalancer_id = azurerm_lb.lb_webapp.id
  name            = "backend-pool"
}

# Create a health probe for the load balancer
# LB should only send users to servers taht are responding properly
resource "azurerm_lb_probe" "lb_probe" {
  loadbalancer_id = azurerm_lb.lb_webapp.id
  name            = "http-running-probe"
  protocol        = "Http"
  port            = 80
  request_path    = "/"
}

# Traffic for port 80 at the public IP should be forwarded to port 80 on healthy backend servers
resource "azurerm_lb_rule" "lb_rules" {
  loadbalancer_id                = azurerm_lb.lb_webapp.id
  name                           = "http"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "PublicIPAddress"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.backend_pool.id]
  probe_id                       = azurerm_lb_probe.lb_probe.id
}

# SSH to backend servers through the load balancer's public IP using high ports that mapps to port 22 on individual server
# Aims to avoid having each VM its own public IP
resource "azurerm_lb_nat_rule" "ssh" {
  resource_group_name            = azurerm_resource_group.rg_webapp.name
  loadbalancer_id                = azurerm_lb.lb_webapp.id
  name                           = "ssh"
  protocol                       = "Tcp"
  frontend_port_start            = 50000
  frontend_port_end              = 50119
  backend_port                   = 22
  frontend_ip_configuration_name = "PublicIPAddress"
  backend_address_pool_id        = azurerm_lb_backend_address_pool.backend_pool.id
}

# Create a NAT gateway
resource "azurerm_nat_gateway" "nat_gw" {
  name                    = "nat-gateway"
  location                = azurerm_resource_group.rg_webapp.location
  resource_group_name     = azurerm_resource_group.rg_webapp.name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10
  zones                   = ["1"]
}

# Create a public IP address for the NAT gateway
# Public IP address that will be used only for outbound traffic.
# This public IP becomes the single visible source IP for all outbound traffic from the subnet
resource "azurerm_public_ip" "nat_gw_ip" {
  name                = "natgw-publicIP"
  resource_group_name = azurerm_resource_group.rg_webapp.name
  location            = azurerm_resource_group.rg_webapp.location
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1"] # must match NAT gateway zones
}

# Associate the subnet with the NAT gateway
# Any resource inside this subnet must send outbound internet traffic through this NAT gateway
resource "azurerm_subnet_nat_gateway_association" "nat_gw_assoc" {
  subnet_id      = azurerm_subnet.subnet.id
  nat_gateway_id = azurerm_nat_gateway.nat_gw.id

  depends_on = [azurerm_orchestrated_virtual_machine_scale_set.vmss_tf]
}

# Attach the public IP to the NAT gateway
resource "azurerm_nat_gateway_public_ip_association" "nat_gw_ip_assoc" {
  public_ip_address_id = azurerm_public_ip.nat_gw_ip.id
  nat_gateway_id       = azurerm_nat_gateway.nat_gw.id
}