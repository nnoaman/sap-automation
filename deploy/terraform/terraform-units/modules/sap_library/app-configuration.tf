# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

#######################################4#######################################8
#                                                                              #
#                          Azure App Configuration                             #
#                                                                              #
#######################################4#######################################8

data  "azurerm_app_configuration" "app_config" {
  provider                             = azurerm.deployer
  name                                 = var.deployer_tfstate.deployer_app_config_name
  resource_group_name                  = var.deployer_tfstate.created_resource_group_name
}


resource "azurerm_app_configuration_key" "library_app_configuration_keys" {
  for_each               = local.configuration_values
  provider               = azurerm.deployer
  configuration_store_id = data.azurerm_app_configuration.app_config.id
  key                    = each.key
  label                  = each.value.label
  value                  = each.value.value
}

locals {

  key_prefix                           = replace(var.state_filename_prefix, format("-%s", var.deployer_tfstate.network_logical_name), "")
  configuration_values                 = {
                                          format("%s_LibraryStateFileName", local.key_prefix) = {
                                            label = local.resource_group_exists ? ( data.azurerm_resource_group.library[0].name) : ( azurerm_resource_group.library[0].name )
                                            value = format("%s-INFRASTRUCTURE.terraform.tfstate",var.state_filename_prefix)
                                          }
                                          format("%s_TerraformRemoteStateStorageAccountId", local.key_prefix) = {
                                            label = local.resource_group_exists ? ( data.azurerm_resource_group.library[0].name) : ( azurerm_resource_group.library[0].name )
                                            value = local.sa_tfstate_exists ? (
                                                     data.azurerm_storage_account.storage_tfstate[0].id) : (
                                                     try(azurerm_storage_account.storage_tfstate[0].id, "")
                                                   )
                                          }
                                          format("%s_SAPLibraryStorageAccountId", local.key_prefix) = {
                                            label = local.resource_group_exists ? ( data.azurerm_resource_group.library[0].name) : ( azurerm_resource_group.library[0].name )
                                            value = local.sa_sapbits_exists ? (
                                                     data.azurerm_storage_account.storage_sapbits[0].id) : (
                                                     try(azurerm_storage_account.storage_sapbits[0].id, "")
                                                   )
                                          }
                                        }
}
