# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

#######################################4#######################################8
#                                                                              #
#                          Azure App Configuration                             #
#                                                                              #
#######################################4#######################################8


resource "azurerm_app_configuration" "app_config" {
  provider                             = azurerm.main
  count                                = var.infrastructure.deploy_application_configuration ? length(var.infrastructure.application_configuration_id) > 0 ? 0 : 1 : 0
  name                                 = var.app_config_service_name
  resource_group_name                  = local.resource_group_exists ? (
                                           data.azurerm_resource_group.deployer[0].name) : (
                                           azurerm_resource_group.deployer[0].name
                                         )
  location                             = local.resource_group_exists ? (
                                           data.azurerm_resource_group.deployer[0].location) : (
                                           azurerm_resource_group.deployer[0].location
                                         )
  sku =                                "standard"
}

data "azurerm_app_configuration" "app_config" {
  provider                             = azurerm.main
  count                                = var.infrastructure.deploy_application_configuration ? length(var.infrastructure.application_configuration_id) > 0 ? 1 : 0 : 0
  name                                 = local.app_config_name
  resource_group_name                  = local.app_config_resource_group_name
}
resource "azurerm_role_assignment" "appconf_dataowner" {
  provider                             = azurerm.main
  count                                = var.bootstrap ? 1 : 0
  scope                                = length(var.infrastructure.application_configuration_id) == 0 ? azurerm_app_configuration.app_config[0].id : data.azurerm_app_configuration.app_config[0].id
  role_definition_name                 = "App Configuration Data Owner"
  principal_id                         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "appconf_dataowner_msi" {
  provider                             = azurerm.main
  scope                                = length(var.infrastructure.application_configuration_id) == 0 ? azurerm_app_configuration.app_config[0].id : data.azurerm_app_configuration.app_config[0].id
  role_definition_name                 = "App Configuration Data Owner"
  principal_id                         = length(var.deployer.user_assigned_identity_id) == 0 ? azurerm_user_assigned_identity.deployer[0].principal_id : data.azurerm_user_assigned_identity.deployer[0].principal_id

}

resource "time_sleep" "wait_for_appconf_dataowner_assignment" {
  create_duration                      = "60s"

  depends_on                           = [
                                           azurerm_role_assignment.appconf_dataowner_msi,
                                           azurerm_role_assignment.appconf_dataowner
                                         ]
}

resource "azurerm_app_configuration_key" "deployer_state_file_name" {
  provider                             = azurerm.main
  count                                = var.infrastructure.deploy_application_configuration ? 1 : 0
  depends_on                           = [
                                            time_sleep.wait_for_appconf_dataowner_assignment
                                         ]

  configuration_store_id               = length(var.infrastructure.application_configuration_id) == 0 ? azurerm_app_configuration.app_config[0].id : data.azurerm_app_configuration.app_config[0].id

  key                                  = format("%s_StateFileName", var.state_filename_prefix)
  label                                = var.state_filename_prefix
  value                                = format("%s-INFRASTRUCTURE.terraform.tfstate",var.state_filename_prefix)
  content_type                         = "text/plain"
  type                                 = "kv"
  tags                                 = {
                                           "source" = "Deployer"
                                         }
  lifecycle {
              ignore_changes = [
                configuration_store_id,
                etag,
                id
              ]
            }
}

resource "azurerm_app_configuration_key" "deployer_keyvault_name" {
  provider                             = azurerm.main
  count                                = var.infrastructure.deploy_application_configuration ? 1 : 0
  depends_on                           = [
                                            time_sleep.wait_for_appconf_dataowner_assignment
                                         ]

  configuration_store_id               = length(var.infrastructure.application_configuration_id) == 0 ? azurerm_app_configuration.app_config[0].id : data.azurerm_app_configuration.app_config[0].id

  key                                  = format("%s_KeyVaultName", var.state_filename_prefix)
  label                                = var.state_filename_prefix
  value                                = var.key_vault.exists ? data.azurerm_key_vault.kv_user[0].name : azurerm_key_vault.kv_user[0].name
  content_type                         = "text/plain"
  type                                 = "kv"
  tags                                 = {
                                           "source" = "Deployer"
                                         }
  lifecycle {
              ignore_changes = [
                configuration_store_id,
                etag,
                id
              ]
            }

}

resource "azurerm_app_configuration_key" "deployer_keyvault_id" {
  provider                             = azurerm.main
  count                                = var.infrastructure.deploy_application_configuration ? 1 : 0
  depends_on                           = [
                                            time_sleep.wait_for_appconf_dataowner_assignment
                                         ]

  configuration_store_id               = length(var.infrastructure.application_configuration_id) == 0 ? azurerm_app_configuration.app_config[0].id : data.azurerm_app_configuration.app_config[0].id
  key                                  = format("%s_KeyVaultResourceId", var.state_filename_prefix)
  label                                = var.state_filename_prefix
  value                                = var.key_vault.exists ? data.azurerm_key_vault.kv_user[0].id : azurerm_key_vault.kv_user[0].id
  content_type                         = "text/id"
  type                                 = "kv"
  tags                                 = {
                                           "source" = "Deployer"
                                         }
  lifecycle {
              ignore_changes = [
                configuration_store_id,
                etag,
                id
              ]
            }

}

resource "azurerm_app_configuration_key" "deployer_resourcegroup_name" {
  provider                             = azurerm.main
  count                                = var.infrastructure.deploy_application_configuration ? 1 : 0
  depends_on                           = [
                                            time_sleep.wait_for_appconf_dataowner_assignment
                                         ]

  configuration_store_id               = length(var.infrastructure.application_configuration_id) == 0 ? azurerm_app_configuration.app_config[0].id : data.azurerm_app_configuration.app_config[0].id
  key                                  = format("%s_ResourceGroupName", var.state_filename_prefix)
  label                                = var.state_filename_prefix
  value                                = local.resourcegroup_name
  content_type                         = "text/plain"
  type                                 = "kv"
  tags                                 = {
                                           "source" = "Deployer"
                                         }
  lifecycle {
              ignore_changes = [
                configuration_store_id,
                etag,
                id
              ]
            }
}

resource "azurerm_app_configuration_key" "deployer_subscription_id" {
  provider                             = azurerm.main
  count                                = var.infrastructure.deploy_application_configuration ? 1 : 0
  depends_on                           = [
                                            time_sleep.wait_for_appconf_dataowner_assignment
                                         ]

  configuration_store_id               = length(var.infrastructure.application_configuration_id) == 0 ? azurerm_app_configuration.app_config[0].id : data.azurerm_app_configuration.app_config[0].id
  key                                  = format("%s_SubscriptionId", var.state_filename_prefix)
  label                                = var.state_filename_prefix
  value                                = data.azurerm_subscription.primary.subscription_id
  content_type                         = "text/id"
  type                                 = "kv"
  tags                                 = {
                                           "source" = "Deployer"
                                         }
  lifecycle {
              ignore_changes = [
                configuration_store_id,
                etag,
                id
              ]
            }
}

resource "azurerm_app_configuration_key" "web_application_resource_id" {
  provider                             = azurerm.main
  count                                = var.infrastructure.deploy_application_configuration ? var.use_webapp ? 1 :0 : 0
  depends_on                           = [
                                            time_sleep.wait_for_appconf_dataowner_assignment
                                         ]

  configuration_store_id               = length(var.infrastructure.application_configuration_id) == 0 ? azurerm_app_configuration.app_config[0].id : data.azurerm_app_configuration.app_config[0].id
  key                                  = format("%s_AppServiceId", var.state_filename_prefix)
  label                                = var.state_filename_prefix
  value                                = try(azurerm_windows_web_app.webapp[0].id, "")
  content_type                         = "text/id"
  type                                 = "kv"
  tags                                 = {
                                           "source" = "Deployer"
                                         }
  lifecycle {
              ignore_changes = [
                configuration_store_id,
                etag,
                id
              ]
            }
}

resource "azurerm_app_configuration_key" "deployer_msi_id" {
  provider                             = azurerm.main
  count                                = var.infrastructure.deploy_application_configuration ? 1 : 0
  depends_on                           = [
                                            time_sleep.wait_for_appconf_dataowner_assignment
                                         ]

  configuration_store_id               = length(var.infrastructure.application_configuration_id) == 0 ? azurerm_app_configuration.app_config[0].id : data.azurerm_app_configuration.app_config[0].id
  key                                  = format("%s_Deployer_MSI_Id", var.state_filename_prefix)
  label                                = var.state_filename_prefix
  value                                = length(var.deployer.user_assigned_identity_id) == 0 ? azurerm_user_assigned_identity.deployer[0].principal_id : data.azurerm_user_assigned_identity.deployer[0].principal_id
  content_type                         = "text/id"
  type                                 = "kv"
  tags                                 = {
                                           "source" = "Deployer"
                                         }
  lifecycle {
              ignore_changes = [
                configuration_store_id,
                etag,
                id
              ]
            }
}

