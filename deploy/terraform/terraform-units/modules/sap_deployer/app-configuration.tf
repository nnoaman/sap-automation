# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

#######################################4#######################################8
#                                                                              #
#                          Azure App Configuration                             #
#                                                                              #
#######################################4#######################################8


resource "azurerm_app_configuration" "app_config" {
  provider                             = azurerm.main
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

resource "azurerm_role_assignment" "appconf_dataowner" {
  provider                             = azurerm.main
  scope                                = azurerm_app_configuration.app_config.id
  role_definition_name                 = "App Configuration Data Owner"
  principal_id                         = data.azurerm_client_config.current.object_id
}

resource "time_sleep" "wait_for_appconf_dataowner_assignment" {
  create_duration                      = "60s"

  depends_on                           = [
                                           azurerm_role_assignment.appconf_dataowner
                                         ]
}

resource "azurerm_app_configuration_key" "deployer_state_file_name" {
  provider                             = azurerm.main

  configuration_store_id               = azurerm_app_configuration.app_config.id
  key                                  = format("%s_StateFileName", var.state_filename_prefix)
  label                                = var.state_filename_prefix
  value                                = format("%s-INFRASTRUCTURE.terraform.tfstate",var.state_filename_prefix)
  content_type                         = "text/plain"
  type                                 = "kv"

  depends_on                          = [
                                          time_sleep.wait_for_appconf_dataowner_assignment
                                        ]

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

  configuration_store_id               = azurerm_app_configuration.app_config.id
  key                                  = format("%s_KeyVaultName", var.state_filename_prefix)
  label                                = var.state_filename_prefix
  value                                = var.key_vault.exists ? data.azurerm_key_vault.kv_user[0].name : azurerm_key_vault.kv_user[0].name
  content_type                         = "text/plain"
  type                                 = "kv"

  depends_on                          = [
                                          time_sleep.wait_for_appconf_dataowner_assignment
                                        ]

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

  configuration_store_id               = azurerm_app_configuration.app_config.id
  key                                  = format("%s_KeyVaultResourceId", var.state_filename_prefix)
  label                                = var.state_filename_prefix
  value                                = var.key_vault.exists ? data.azurerm_key_vault.kv_user[0].id : azurerm_key_vault.kv_user[0].id
  content_type                         = "text/id"
  type                                 = "kv"

  depends_on                          = [
                                          time_sleep.wait_for_appconf_dataowner_assignment
                                        ]

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

  configuration_store_id               = azurerm_app_configuration.app_config.id
  key                                  = format("%s_ResourceGroupName", var.state_filename_prefix)
  label                                = var.state_filename_prefix
  value                                = local.resourcegroup_name
  content_type                         = "text/plain"
  type                                 = "kv"

  depends_on                          = [
                                          time_sleep.wait_for_appconf_dataowner_assignment
                                        ]

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

  configuration_store_id               = azurerm_app_configuration.app_config.id
  key                                  = format("%s_SubscriptionId", var.state_filename_prefix)
  label                                = var.state_filename_prefix
  value                                = data.azurerm_subscription.primary.subscription_id
  content_type                         = "text/id"
  type                                 = "kv"

  depends_on                          = [
                                          time_sleep.wait_for_appconf_dataowner_assignment
                                        ]

  lifecycle {
    ignore_changes = [
      configuration_store_id,
      etag,
      id
    ]
  }
}
