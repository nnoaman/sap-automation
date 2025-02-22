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

resource "azurerm_app_configuration_key" "libraryStateFileName" {
  provider                             = azurerm.deployer
  configuration_store_id               = data.azurerm_app_configuration.app_config.id
  key                                  = format("%s_LibraryStateFileName", var.state_filename_prefix)
  label                                = var.state_filename_prefix
  value                                = format("%s-SAP_LIBRARY.terraform.tfstate",var.naming.prefix.LIBRARY)
  content_type                         = "text/plain"
  type                                 = "kv"
  tags                                 = {
                                           "source" = "SAPLibrary"
                                         }
  lifecycle {
              ignore_changes = [
                configuration_store_id,
                etag,
                id
              ]
            }
}


resource "azurerm_app_configuration_key" "terraformRemoteStateStorageAccountId" {
  provider                             = azurerm.deployer
  configuration_store_id               = data.azurerm_app_configuration.app_config.id
  key                                  = format("%s_TerraformRemoteStateStorageAccountId", var.state_filename_prefix)
  label                                = var.state_filename_prefix
  value                                = local.sa_tfstate_exists ? (
                                                            data.azurerm_storage_account.storage_tfstate[0].id) : (
                                                            try(azurerm_storage_account.storage_tfstate[0].id, "")
                                                          )
  content_type                         = "text/id"
  type                                 = "kv"
  tags                                 = {
                                           "source" = "SAPLibrary"
                                         }
  lifecycle {
              ignore_changes = [
                configuration_store_id,
                etag,
                id
              ]
            }
}


resource "azurerm_app_configuration_key" "SAPLibraryStorageAccountId" {
  provider                             = azurerm.deployer
  configuration_store_id               = data.azurerm_app_configuration.app_config.id
  key                                  = format("%s_SAPLibraryStorageAccountId", var.state_filename_prefix)
  label                                = var.state_filename_prefix
  value                                = local.sa_tfstate_exists ? (
                                                            data.azurerm_storage_account.storage_sapbits[0].id) : (
                                                            try(azurerm_storage_account.storage_sapbits[0].id, "")
                                                          )
  content_type                         = "text/id"
  type                                 = "kv"
  tags                                 = {
                                           "source" = "SAPLibrary"
                                         }
  lifecycle {
              ignore_changes = [
                configuration_store_id,
                etag,
                id
              ]
            }
}

resource "azurerm_app_configuration_key" "SAPMediaPath" {
  provider                             = azurerm.deployer
  configuration_store_id               = data.azurerm_app_configuration.app_config.id
  key                                  = format("%s_SAPMediaPath", var.state_filename_prefix)
  label                                = var.state_filename_prefix
  value                                = format("https://%s.blob.core.windows.net/%s", length(var.storage_account_sapbits.arm_id) > 0 ?
                                                             split("/", var.storage_account_sapbits.arm_id)[8] : local.sa_sapbits_name,
                                                             var.storage_account_sapbits.sapbits_blob_container.name)
  content_type                         = "text/plain"
  type                                 = "kv"
  tags                                 = {
                                           "source" = "SAPLibrary"
                                         }
  lifecycle {
              ignore_changes = [
                configuration_store_id,
                etag,
                id
              ]
            }
}

locals {

  parsed_id                            = provider::azurerm::parse_resource_id(coalesce(var.deployer.application_configuration_id,var.deployer_tfstate.deployer_app_config_id))
  app_config_name                      = local.parsed_id["resource_name"]
  app_config_resource_group_name       = local.parsed_id["resource_group_name"]
}
