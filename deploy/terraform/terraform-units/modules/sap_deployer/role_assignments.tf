data "azuread_service_principal" "spn" {
  count                                = var.options.use_spn ? 1 : 0
  client_id                            = data.azuread_service_principal.spn[0].id
}


#######################################4#######################################8
#                                                                              #
#                                Role Assignments                              #
#                                                                              #
#######################################4#######################################8

resource "azurerm_role_assignment" "deployer" {
  provider                             = azurerm.main
  count                                = var.assign_subscription_permissions && var.deployer.add_system_assigned_identity ? var.deployer_vm_count : 0
  scope                                = length(var.deployer.deployer_diagnostics_account_arm_id) > 0 ? var.deployer.deployer_diagnostics_account_arm_id : azurerm_storage_account.deployer[0].id
  role_definition_name                 = "Storage Blob Data Contributor"
  principal_id                         = azurerm_linux_virtual_machine.deployer[count.index].identity[0].principal_id
}

resource "azurerm_role_assignment" "deployer_msi" {
  provider                             = azurerm.main
  count                                = var.assign_subscription_permissions  ? 1 : 0
  scope                                = length(var.deployer.deployer_diagnostics_account_arm_id) > 0 ? var.deployer.deployer_diagnostics_account_arm_id : azurerm_storage_account.deployer[0].id
  role_definition_name                 = "Storage Blob Data Contributor"
  principal_id                         = length(var.deployer.user_assigned_identity_id) == 0 ? azurerm_user_assigned_identity.deployer[0].principal_id : data.azurerm_user_assigned_identity.deployer[0].principal_id
}


resource "azurerm_role_assignment" "resource_group_contributor" {
  provider                             = azurerm.main
  count                                = var.assign_subscription_permissions && var.deployer.add_system_assigned_identity ? var.deployer_vm_count : 0
  scope                                = local.resource_group_exists ? data.azurerm_resource_group.deployer[0].id : azurerm_resource_group.deployer[0].id
  role_definition_name                 = "Contributor"
  principal_id                         = azurerm_linux_virtual_machine.deployer[count.index].identity[0].principal_id
}

resource "azurerm_role_assignment" "resource_group_contributor_contributor_msi" {
  provider                             = azurerm.main
  count                                = var.assign_subscription_permissions ? 1 : 0
  scope                                = local.resource_group_exists ? data.azurerm_resource_group.deployer[0].id : azurerm_resource_group.deployer[0].id
  role_definition_name                 = "Contributor"
  principal_id                         = length(var.deployer.user_assigned_identity_id) == 0 ? azurerm_user_assigned_identity.deployer[0].principal_id : data.azurerm_user_assigned_identity.deployer[0].principal_id
}

resource "azurerm_role_assignment" "resource_group_contributor_spn" {
  count                                = var.assign_subscription_permissions && length(data.azuread_service_principal.spn[0].id) > 0 ? 1 : 0
  provider                             = azurerm.main
  scope                                = data.azurerm_subscription.primary.id
  role_definition_name                 = "Contributor"
  principal_type                       = "ServicePrincipal"
  principal_id                         = data.azuread_service_principal.spn[0].id
}


resource "azurerm_role_assignment" "resource_group_user_access_admin_msi" {
  provider                             = azurerm.main
  count                                = var.assign_subscription_permissions ? 1 : 0
  scope                                = local.resource_group_exists ? data.azurerm_resource_group.deployer[0].id : azurerm_resource_group.deployer[0].id
  role_definition_name                 = "User Access Administrator"
  principal_id                         = length(var.deployer.user_assigned_identity_id) == 0 ? azurerm_user_assigned_identity.deployer[0].principal_id : data.azurerm_user_assigned_identity.deployer[0].principal_id
}

resource "azurerm_role_assignment" "resource_group_user_access_admin_spn" {
  provider                             = azurerm.main
  count                                = var.assign_subscription_permissions ? 1 : 0
  scope                                = local.resource_group_exists ? data.azurerm_resource_group.deployer[0].id : azurerm_resource_group.deployer[0].id
  role_definition_name                 = "User Access Administrator"
  principal_type                       = "ServicePrincipal"
  principal_id                         = data.azuread_service_principal.spn[0].id
}



resource "azurerm_role_assignment" "appconf_dataowner" {
  provider                             = azurerm.main
  count                                = var.assign_subscription_permissions && var.bootstrap && var.infrastructure.application_configuration_deployment ? 1 : 0
  scope                                = length(var.infrastructure.application_configuration_id) == 0 ? azurerm_app_configuration.app_config[0].id : data.azurerm_app_configuration.app_config[0].id
  role_definition_name                 = "App Configuration Data Owner"
  principal_id                         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "appconf_dataowner_msi" {
  provider                             = azurerm.main
  count                                = var.assign_subscription_permissions && var.infrastructure.application_configuration_deployment ? 1 : 0
  scope                                = var.infrastructure.application_configuration_deployment ? (
                                          length(var.infrastructure.application_configuration_id) == 0 ? (
                                            azurerm_app_configuration.app_config[0].id) : (
                                            data.azurerm_app_configuration.app_config[0].id)) : (
                                          0
                                          )
  role_definition_name                 = "App Configuration Data Owner"
  principal_id                         = length(var.deployer.user_assigned_identity_id) == 0 ? azurerm_user_assigned_identity.deployer[0].principal_id : data.azurerm_user_assigned_identity.deployer[0].principal_id
}

resource "azurerm_role_assignment" "appconf_dataowner_spn" {
  provider                             = azurerm.main
  count                                = var.assign_subscription_permissions && var.infrastructure.application_configuration_deployment ? 1 : 0
  scope                                = length(var.infrastructure.application_configuration_id) == 0 ? azurerm_app_configuration.app_config[0].id : data.azurerm_app_configuration.app_config[0].id
  role_definition_name                 = "App Configuration Data Owner"
  principal_type                       = "ServicePrincipal"
  principal_id                         = data.azuread_service_principal.spn[0].id
}

resource "azurerm_role_assignment" "role_assignment_msi" {
  provider                             = azurerm.main
  count                                = var.assign_subscription_permissions && var.key_vault.enable_rbac_authorization ? 1 : 0
  scope                                = var.key_vault.exists ? data.azurerm_key_vault.kv_user[0].id : azurerm_key_vault.kv_user[0].id
  role_definition_name                 = "Key Vault Administrator"
  principal_id                         = length(var.deployer.user_assigned_identity_id) == 0 ? azurerm_user_assigned_identity.deployer[0].principal_id : data.azurerm_user_assigned_identity.deployer[0].principal_id
}

resource "azurerm_role_assignment" "role_assignment_spn" {
  provider                             = azurerm.main
  count                                = var.assign_subscription_permissions && var.key_vault.enable_rbac_authorization ? 1 : 0
  scope                                = var.key_vault.exists ? data.azurerm_key_vault.kv_user[0].id : azurerm_key_vault.kv_user[0].id
  role_definition_name                 = "Key Vault Administrator"
  principal_type                       = "ServicePrincipal"
  principal_id                         = data.azuread_service_principal.spn[0].id
}

resource "azurerm_role_assignment" "role_assignment_msi_officer" {
  provider                             = azurerm.main
  count                                = var.assign_subscription_permissions && var.key_vault.enable_rbac_authorization ? 1 : 0
  scope                                = var.key_vault.exists ? data.azurerm_key_vault.kv_user[0].id : azurerm_key_vault.kv_user[0].id
  role_definition_name                 = "Key Vault Secrets Officer"
  principal_id                         = length(var.deployer.user_assigned_identity_id) == 0 ? azurerm_user_assigned_identity.deployer[0].principal_id : data.azurerm_user_assigned_identity.deployer[0].principal_id

}

resource "azurerm_role_assignment" "role_assignment_system_identity" {
  provider                             = azurerm.main
  depends_on                           = [ azurerm_key_vault_secret.pk ]
  count                                = var.assign_subscription_permissions && var.deployer.add_system_assigned_identity && var.key_vault.enable_rbac_authorization ? var.deployer_vm_count : 0
  scope                                = var.key_vault.exists ? data.azurerm_key_vault.kv_user[0].id : azurerm_key_vault.kv_user[0].id
  role_definition_name                 = "Key Vault Secrets Officer"
  principal_id                         = azurerm_linux_virtual_machine.deployer[count.index].identity[0].principal_id
}

resource "azurerm_role_assignment" "role_assignment_additional_users" {
  provider                             = azurerm.main
  count                                = var.assign_subscription_permissions && !var.key_vault.exists && var.key_vault.enable_rbac_authorization && length(compact(var.additional_users_to_add_to_keyvault_policies)) > 0 ? (
                                           length(compact(var.additional_users_to_add_to_keyvault_policies))) : (
                                           0
                                         )

  scope                                = var.key_vault.exists ? data.azurerm_key_vault.kv_user[0].id : azurerm_key_vault.kv_user[0].id
  role_definition_name                 = "Key Vault Secrets Officer"
  principal_id                         = var.additional_users_to_add_to_keyvault_policies[count.index]
}

resource "azurerm_role_assignment" "role_assignment_webapp" {
  provider                             = azurerm.main
  count                                = var.assign_subscription_permissions && !var.key_vault.exists && !var.key_vault.enable_rbac_authorization && var.app_service.use ? 1 : 0
  scope                                = var.key_vault.exists ? data.azurerm_key_vault.kv_user[0].id : azurerm_key_vault.kv_user[0].id
  role_definition_name                 = "Key Vault Secrets User"
  principal_id                         = azurerm_windows_web_app.webapp[0].identity[0].principal_id
}



# // Add role to be able to deploy resources
resource "azurerm_role_assignment" "subscription_contributor_system_identity" {
  count                                = var.assign_subscription_permissions && var.deployer.add_system_assigned_identity ? var.deployer_vm_count : 0
  provider                             = azurerm.main
  scope                                = data.azurerm_subscription.primary.id
  role_definition_name                 = "Reader"
  principal_id                         = azurerm_linux_virtual_machine.deployer[count.index].identity[0].principal_id
}

resource "azurerm_role_assignment" "subscription_contributor_msi" {
  count                                = var.assign_subscription_permissions ? 1 : 0
  provider                             = azurerm.main
  scope                                = data.azurerm_subscription.primary.id
  role_definition_name                 = "Contributor"
  principal_id                         = length(var.deployer.user_assigned_identity_id) == 0 ? azurerm_user_assigned_identity.deployer[0].principal_id : data.azurerm_user_assigned_identity.deployer[0].principal_id
}

