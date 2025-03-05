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


resource "azurerm_private_endpoint" "app_config" {
  provider                             = azurerm.deployer
  count                                = var.deployer.use && var.use_private_endpoint ? 1 : 0
  name                                 = format("%s%s%s",
                                          var.naming.resource_prefixes.appconfig_private_link,
                                          local.prefix,
                                          var.naming.resource_suffixes.appconfig_private_link
                                        )
  resource_group_name                  = var.deployer_tfstate.created_resource_group_name
  location                             = var.deployer_tfstate.created_resource_group_location
  subnet_id                            = var.deployer_tfstate.subnet_mgmt_id
  custom_network_interface_name        = format("%s%s%s%s",
                                           var.naming.resource_prefixes.appconfig_private_link,
                                           local.prefix,
                                           var.naming.resource_suffixes.appconfig_private_link,
                                           var.naming.resource_suffixes.nic
                                         )

  private_service_connection {
                               name                           = format("%s%s%s",
                                                                  var.naming.resource_prefixes.appconfig_private_svc,
                                                                  local.prefix,
                                                                  var.naming.resource_suffixes.appconfig_private_svc
                                                                )
                               is_manual_connection           = false
                               private_connection_resource_id = var.deployer_tfstate.deployer_app_config_id
                               subresource_names              = [
                                                                  "configurationStores"
                                                                ]
                             }

  dynamic "private_dns_zone_group" {
                                     for_each = range(var.dns_settings.register_storage_accounts_keyvaults_with_dns ? 1 : 0)
                                     content {
                                               name                 = var.dns_settings.dns_zone_names.appconfig_dns_zone_name
                                               private_dns_zone_ids = [local.use_local_privatelink_dns ? azurerm_private_dns_zone.appconfig[0].id : data.azurerm_private_dns_zone.appconfig[0].id]
                                             }
                                   }

}


locals {

  parsed_id                            = provider::azurerm::parse_resource_id(coalesce(var.deployer.application_configuration_id,var.deployer_tfstate.deployer_app_config_id))
  app_config_name                      = local.parsed_id["resource_name"]
  app_config_resource_group_name       = local.parsed_id["resource_group_name"]
}
