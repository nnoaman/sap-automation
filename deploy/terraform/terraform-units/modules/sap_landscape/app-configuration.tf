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

resource "azurerm_app_configuration_key" "KeyVaultResourceId" {
  provider                             = azurerm.deployer
  configuration_store_id               = data.azurerm_app_configuration.app_config.id
  key                                  = format("%s_KeyVaultResourceId", var.naming.prefix.WORKLOAD_ZONE)
  label                                = var.naming.prefix.WORKLOAD_ZONE
  value                                = length(try(var.key_vault.keyvault_id_for_system_credentials, "")) > 0 ? (
                                              try(data.azurerm_key_vault.kv_user[0].id, "")) : (
                                              try(azurerm_key_vault.kv_user[0].id, "")
                                            )
  content_type                         = "text/id"
  type                                 = "kv"
  tags                                 = {
                                           "source" = "WorkloadZone"
                                         }
  lifecycle {
              ignore_changes = [
                configuration_store_id,
                etag,
                id
              ]
            }
}
resource "azurerm_app_configuration_key" "VirtualNetworkResourceId" {
  provider                             = azurerm.deployer
  configuration_store_id               = data.azurerm_app_configuration.app_config.id
  key                                  = format("%s_VirtualNetworkResourceId", var.naming.prefix.WORKLOAD_ZONE)
  label                                = var.naming.prefix.WORKLOAD_ZONE
  value                                = local.SAP_virtualnetwork_exists ? (
                                                try(data.azurerm_virtual_network.vnet_sap[0].id, "")) : (
                                                try(azurerm_virtual_network.vnet_sap[0].id, "")
                                              )
  content_type                         = "text/id"
  type                                 = "kv"
  tags                                 = {
                                           "source" = "WorkloadZone"
                                         }
  lifecycle {
              ignore_changes = [
                configuration_store_id,
                etag,
                id
              ]
            }
}

resource "azurerm_app_configuration_key" "witness_name" {
  provider                             = azurerm.deployer
  configuration_store_id               = data.azurerm_app_configuration.app_config.id
  key                                  = format("%s_WitnessStorageAccountName", var.naming.prefix.WORKLOAD_ZONE)
  label                                = var.naming.prefix.WORKLOAD_ZONE
  value                                = length(var.witness_storage_account.arm_id) > 0 ? (
                                           data.azurerm_storage_account.witness_storage[0].name) : (
                                           azurerm_storage_account.witness_storage[0].name
                                         )
  content_type                         = "text/plain"
  type                                 = "kv"
  tags                                 = {
                                           "source" = "WorkloadZone"
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

  parsed_id                           = provider::azurerm::parse_resource_id(coalesce(var.infrastructure.application_configuration_id, var.deployer_tfstate.deployer_app_config_id))
  app_config_name                     = local.parsed_id["resource_name"]
  app_config_resource_group_name      = local.parsed_id["resource_group_name"]
  }
