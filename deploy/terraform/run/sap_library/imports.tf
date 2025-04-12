# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

/*
    Description:
      Import deployer resources
*/

data "terraform_remote_state" "deployer"          {
                                                    backend =    "azurerm"
                                                    count        = var.use_deployer && length(var.deployer_tfstate_key) > 0 ? 1 : 0
                                                    config       = {
                                                                     resource_group_name  = local.SAPLibrary_resource_group_name
                                                                     storage_account_name = local.tfstate_storage_account_name
                                                                     container_name       = local.tfstate_container_name
                                                                     key                  = local.deployer_tfstate_key
                                                                     subscription_id      = local.SAPLibrary_subscription_id
                                                                     use_msi              = true
                                                                   }
                                                  }

data "azurerm_app_configuration_key" "deployer_network" {
                                                          count                           = var.use_deployer ? length(coalesce(var.application_configuration_id, try(data.terraform_remote_state.deployer[0].outputs.deployer_app_config_id, ""))) > 0 ? 1 : 0 : 0
                                                          configuration_store_id          = coalesce(var.application_configuration_id, try(data.terraform_remote_state.deployer[0].outputs.deployer_app_config_id, ""))
                                                          key                             = format("%s_Deployer_network_id", var.control_plane_name)
                                                          label                           = var.control_plane_name
                                                        }

data "azurerm_key_vault_secret" "subscription_id" {
                                                    count        = length(local.key_vault.id) > 0 ? (var.use_deployer && var.use_spn ? 1 : 0) : 0
                                                    name         = format("%s-subscription-id", var.use_deployer ? upper(coalesce(try(data.terraform_remote_state.deployer[0].outputs.control_plane_name, ""), var.control_plane_name)) : upper(var.control_plane_name))
                                                    key_vault_id = local.key_vault.id
                                                  }


data "azurerm_key_vault_secret" "client_id"       {
                                                    count        = length(local.key_vault.id) > 0 ? (var.use_deployer && var.use_spn ? 1 : 0) : 0
                                                    name         = format("%s-client-id", var.use_deployer ? upper(coalesce(try(data.terraform_remote_state.deployer[0].outputs.control_plane_name, ""), var.control_plane_name)) : upper(var.control_plane_name))
                                                    key_vault_id = local.key_vault.id
                                                  }

ephemeral "azurerm_key_vault_secret" "client_secret"   {
                                                    count        = length(local.key_vault.id) > 0 ? (var.use_deployer && var.use_spn ? 1 : 0) : 0
                                                    name         = format("%s-client-secret", var.use_deployer ? upper(coalesce(try(data.terraform_remote_state.deployer[0].outputs.control_plane_name, ""), var.control_plane_name)) : upper(var.control_plane_name))
                                                    key_vault_id = local.key_vault.id
                                                  }

data "azurerm_key_vault_secret" "tenant_id"       {
                                                    count        = length(local.key_vault.id) > 0 ? (var.use_deployer && var.use_spn ? 1 : 0) : 0
                                                    name         = format("%s-tenant-id", var.use_deployer ? upper(coalesce(try(data.terraform_remote_state.deployer[0].outputs.control_plane_name, ""), var.control_plane_name)) : upper(var.control_plane_name))
                                                    key_vault_id = local.key_vault.id
                                                  }
// Import current service principal
data "azuread_service_principal" "sp"             {
                                                    count        = local.use_spn ? 1 : 0
                                                    client_id    = data.azurerm_key_vault_secret.client_id[0].value
                                                  }
