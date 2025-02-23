
resource "azurerm_template_deployment" "sap_system" {
  provider                             = azurerm.main
  name                                 = format("SDAF-%s-%s-%s", var.platform, var.sid, var.environment, local.deployment_type)
  resource_group_name                  = local.resource_group_exists ? (
                                                           data.azurerm_resource_group.resource_group[0].name) : (
                                                           azurerm_resource_group.resource_group[0].name
                                                         )
  deployment_mode                      = "Incremental"

  template_body                        = file(format("%s%s", path.module, "/templates/deployment.json"))

}
