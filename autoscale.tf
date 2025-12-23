# create autoscale resource that will decrease the number of instances if the azurerm_orchestrated_scale set cpu usaae is below 10% for 2 minutes
resource "azurerm_monitor_autoscale_setting" "autoscale" {
  name                = "autoscale"
  location            = azurerm_resource_group.rg_webapp.location
  resource_group_name = azurerm_resource_group.rg_webapp.name
  target_resource_id  = azurerm_orchestrated_virtual_machine_scale_set.vmss_tf.id
  enabled             = true
  profile {
    name = "autoscale"
    capacity {
      default = 3
      minimum = 1
      maximum = 10
    }
  }
}