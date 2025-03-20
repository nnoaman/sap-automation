resource "azurerm_role_assignment" "webapp_blob" {
  provider                             = azurerm.main
  count                                = var.infrastructure.assign_permissions && length(var.deployer_tfstate.webapp_identity) > 0 && length(var.storage_account_tfstate.arm_id) == 0 ? 1 : 0
  scope                                = azurerm_storage_account.storage_tfstate[0].id
  role_definition_name                 = "Storage Blob Data Contributor"
  principal_id                         = var.deployer_tfstate.webapp_identity
}

resource "azurerm_role_assignment" "webapp_table" {
  provider                             = azurerm.main
  count                                = var.infrastructure.assign_permissions && length(var.deployer_tfstate.webapp_identity) > 0 && length(var.storage_account_tfstate.arm_id) == 0 ? 1 : 0
  scope                                = azurerm_storage_account.storage_tfstate[0].id
  role_definition_name                 = "Storage Table Data Contributor"
  principal_id                         = var.deployer_tfstate.webapp_identity
}

resource "azurerm_role_assignment" "blob_msi" {
  provider                             = azurerm.main
  count                                = var.infrastructure.assign_permissions && length(var.deployer_tfstate.deployer_msi_id) > 0 && length(var.storage_account_tfstate.arm_id) == 0 ? 1 : 0
  scope                                = azurerm_storage_account.storage_tfstate[0].id
  role_definition_name                 = "Storage Blob Data Owner"
  principal_id                         = var.deployer_tfstate.deployer_msi_id
}

resource "azurerm_role_assignment" "dns_msi" {
  provider                             = azurerm.main
  count                                = var.infrastructure.assign_permissions && length(var.deployer_tfstate.deployer_msi_id) > 0 && length(var.storage_account_tfstate.arm_id) == 0 ? 1 : 0
  scope                                = local.resource_group_exists ? (
                                                 data.azurerm_resource_group.library[0].id) : (
                                                 azurerm_resource_group.library[0].id
                                               )
  role_definition_name                 = "Private DNS Zone Contributor"
  principal_id                         = var.deployer_tfstate.deployer_msi_id
}

resource "azurerm_role_assignment" "resource_group_contributor_msi" {
  provider                             = azurerm.main
  count                                = var.infrastructure.assign_permissions && length(var.deployer_tfstate.deployer_msi_id) > 0 && length(var.storage_account_tfstate.arm_id) == 0 ? 1 : 0
  scope                                = local.resource_group_exists ? (
                                                 data.azurerm_resource_group.library[0].id) : (
                                                 azurerm_resource_group.library[0].id
                                               )
  role_definition_name                 = "Contributor"
  principal_id                         = var.deployer_tfstate.deployer_msi_id
}
