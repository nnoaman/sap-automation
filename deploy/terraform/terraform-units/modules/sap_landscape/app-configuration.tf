# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

#######################################4#######################################8
#                                                                              #
#                          Azure App Configuration                             #
#                                                                              #
#######################################4#######################################8

data  "azurerm_app_configuration" "app_config" {
  provider                             = azurerm.deployer
  count                                = local.application_configuration_deployed ? 1 : 0
  name                                 = local.app_config_name
  resource_group_name                  = local.app_config_resource_group_name
}

data "azurerm_app_configuration_key" "deployer_network_id" {
  count                                = local.application_configuration_deployed ? 1 : 0
  configuration_store_id               = data.azurerm_app_configuration.app_config[0].id
  key                                  = format("%s_Deployer_network_id", var.infrastructure.control_plane_name)
  label                                = var.infrastructure.control_plane_name
}

data "azurerm_app_configuration_key" "deployer_subnet_id" {
  count                                = local.application_configuration_deployed ? 1 : 0
  configuration_store_id               = data.azurerm_app_configuration.app_config[0].id
  key                                  = format("%s_Deployer_subnet_id", var.infrastructure.control_plane_name)
  label                                = var.infrastructure.control_plane_name
}

resource "azurerm_app_configuration_key" "KeyVaultResourceId" {
  provider                             = azurerm.deployer
  count                                = local.application_configuration_deployed ? 1 : 0
  configuration_store_id               = data.azurerm_app_configuration.app_config[0].id
  key                                  = format("%s_KeyVaultResourceId", var.naming.prefix.WORKLOAD_ZONE)
  label                                = var.naming.prefix.WORKLOAD_ZONE
  value                                = var.key_vault.user.exists ? (
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
  count                                = local.application_configuration_deployed ? 1 : 0
  configuration_store_id               = data.azurerm_app_configuration.app_config[0].id
  key                                  = format("%s_VirtualNetworkResourceId", var.naming.prefix.WORKLOAD_ZONE)
  label                                = var.naming.prefix.WORKLOAD_ZONE
  value                                = var.infrastructure.virtual_networks.sap.exists ? (
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
  count                                = local.application_configuration_deployed ? 1 : 0
  configuration_store_id               = data.azurerm_app_configuration.app_config[0].id
  key                                  = format("%s_WitnessStorageAccountName", var.naming.prefix.WORKLOAD_ZONE)
  label                                = var.naming.prefix.WORKLOAD_ZONE
  value                                = length(var.witness_storage_account.id) > 0 ? (
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

  application_configuration_deployed  = length(trimspace(coalesce(var.infrastructure.application_configuration_id, try(var.deployer_tfstate.deployer_app_config_id, " "), " "))) > 0
  parsed_id                           = local.application_configuration_deployed ? provider::azurerm::parse_resource_id(coalesce(var.infrastructure.application_configuration_id, try(var.deployer_tfstate.deployer_app_config_id, ""))) : null
  app_config_name                     = local.application_configuration_deployed ? local.parsed_id["resource_name"] : ""
  app_config_resource_group_name      = local.application_configuration_deployed ? local.parsed_id["resource_group_name"] : ""
  }
