resource "azurerm_role_assignment" "resource_group_user_access_admin" {
  provider                             = azurerm.deployer
  count                                = 0
  scope                                = local.resource_group_exists ? (
                                                                   data.azurerm_resource_group.resource_group[0].id) : (
                                                                   try(azurerm_resource_group.resource_group[0].id, "")
                                                                 )
  role_definition_name                 = "Role Based Access Control Administrator"
  principal_id                         = var.deployer_tfstate.deployer_uai.principal_id
  condition_version                    = "2.0"
  condition                            = <<-EOT
                                            (
                                             (
                                              !(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})
                                             )
                                             OR
                                             (
                                              @Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidNotEquals {8e3af657-a8ff-443c-a75c-2fe8c4bcb635, 18d7d88d-d35e-4fb5-a5c3-7773c20a72d9, f58310d9-a9f6-439a-9e8d-f62e7b41a168}
                                             )
                                            )
                                            AND
                                            (
                                             (
                                              !(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})
                                             )
                                             OR
                                             (
                                              @Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidNotEquals {8e3af657-a8ff-443c-a75c-2fe8c4bcb635, 18d7d88d-d35e-4fb5-a5c3-7773c20a72d9, f58310d9-a9f6-439a-9e8d-f62e7b41a168}
                                             )
                                            )
                                            EOT
}
