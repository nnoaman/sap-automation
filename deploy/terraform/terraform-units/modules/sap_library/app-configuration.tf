# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

#######################################4#######################################8
#                                                                              #
#                          Azure App Configuration                             #
#                                                                              #
#######################################4#######################################8

data  "azurerm_app_configuration" "app_config" {
  provider                             = azurerm.deployer
  name                                 = local.app_config_name
  resource_group_name                  = local.app_config_resource_group_name
}


resource "azurerm_app_configuration_key" "library_app_configuration_keys" {
  for_each                             = local.configuration_values
  provider                             = azurerm.deployer
  configuration_store_id               = data.azurerm_app_configuration.app_config.id
  key                                  = each.key
  label                                = each.value.label
  value                                = each.value.value
  content_type                         = each.value.content_type
}

locals {

  parsed_id                            = provider::azurerm::parse_resource_id(coalesce(var.deployer.application_configuration_id,var.deployer_tfstate.deployer_app_config_id))
  app_config_name                      = local.parsed_id["resource_name"]
  app_config_resource_group_name       = local.parsed_id["resource_group_name"]
  configuration_values                 = {
                                          format("%s_LibraryStateFileName", var.state_filename_prefix) = {
                                            label        = var.state_filename_prefix
                                            value        = format("%s-SAP_LIBRARY.terraform.tfstate",var.naming.prefix.LIBRARY)
                                            content_type = "text/plain"
                                          }
                                          format("%s_TerraformRemoteStateStorageAccountId", var.state_filename_prefix) = {
                                            label        = var.state_filename_prefix
                                            value        = local.sa_tfstate_exists ? (
                                                            data.azurerm_storage_account.storage_tfstate[0].id) : (
                                                            try(azurerm_storage_account.storage_tfstate[0].id, "")
                                                          )
                                            content_type = "text/id"
                                          }
                                          format("%s_SAPLibraryStorageAccountId", var.state_filename_prefix) = {
                                            label        = var.state_filename_prefix
                                            value        = local.sa_sapbits_exists ? (
                                                            data.azurerm_storage_account.storage_sapbits[0].id) : (
                                                            try(azurerm_storage_account.storage_sapbits[0].id, "")
                                                          )
                                            content_type = "text/id"
                                          }
                                        }
}
