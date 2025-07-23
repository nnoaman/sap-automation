#######################################4#######################################8
#                                                                              #
#                                Role Assignments                              #
#                                                                              #
#######################################4#######################################8
resource "null_resource" "subscription_contributor_msi_fallback" {
  count = var.assign_subscription_permissions ? 1 : 0

  provisioner "local-exec" {
    command = <<EOT
      if [ -n "${var.deployer.user_assigned_identity_id}" ]; then
        PRINCIPAL_ID=$(az identity show --ids "${var.deployer.user_assigned_identity_id}" --query principalId -o tsv)
      elif [ "${length(azurerm_user_assigned_identity.deployer)}" -gt "0" ]; then
        PRINCIPAL_ID="${azurerm_user_assigned_identity.deployer[0].principal_id}"
      else
        echo "No user-assigned identity found. Skipping role assignment."
        exit 0
      fi

      output=$(az role assignment create \
        --assignee "$PRINCIPAL_ID" \
        --role "Contributor" \
        --scope "${data.azurerm_subscription.primary.id}" 2>&1) || status=$?

      if echo "$output" | grep -qiE "RoleAssignmentExists|already exists|The role assignment already exists"; then
        echo "Role assignment already exists. Skipping."
        exit 0
      elif echo "$output" | grep -qiE "403|Forbidden"; then
        echo "ERROR: Permission denied (403) - check service principal permissions"
        echo "$output"
        exit 1
      elif [ $${status:-0} -ne 0 ]; then
        echo "ERROR: Failed with status $${status:-0}."
        echo "$output"
        exit $${status:-1}
      else
        echo "$output"
        exit 0
      fi
    EOT
    interpreter = ["bash", "-c"]
  }

  triggers = {
    subscription_id = data.azurerm_subscription.primary.id
    principal_id = var.deployer.user_assigned_identity_id != "" ? var.deployer.user_assigned_identity_id : "new-identity"
  }
}

resource "null_resource" "deployer_msi_fallback" {
  count = var.assign_subscription_permissions ? 1 : 0

  provisioner "local-exec" {
    command = <<EOT
      if [ -n "${var.deployer.user_assigned_identity_id}" ]; then
        PRINCIPAL_ID=$(az identity show --ids "${var.deployer.user_assigned_identity_id}" --query principalId -o tsv)
      elif [ "${length(azurerm_user_assigned_identity.deployer)}" -gt "0" ]; then
        PRINCIPAL_ID="${azurerm_user_assigned_identity.deployer[0].principal_id}"
      else
        echo "No user-assigned identity found. Skipping role assignment."
        exit 0
      fi

      if [ -n "${var.deployer.deployer_diagnostics_account_arm_id}" ]; then
        SCOPE="${var.deployer.deployer_diagnostics_account_arm_id}"
      elif [ "${length(azurerm_storage_account.deployer)}" -gt "0" ]; then
        SCOPE="${azurerm_storage_account.deployer[0].id}"
      else
        echo "No storage account found. Skipping role assignment."
        exit 0
      fi

      output=$(az role assignment create \
        --assignee "$PRINCIPAL_ID" \
        --role "Storage Blob Data Contributor" \
        --scope "$SCOPE" 2>&1) || status=$?

      if echo "$output" | grep -qiE "RoleAssignmentExists|already exists|The role assignment already exists"; then
        echo "Role assignment already exists. Skipping."
        exit 0
      elif echo "$output" | grep -qiE "403|Forbidden"; then
        echo "ERROR: Permission denied (403) - check service principal permissions"
        echo "$output"
        exit 1
      elif [ $${status:-0} -ne 0 ]; then
        echo "ERROR: Failed with status $${status:-0}."
        echo "$output"
        exit $${status:-1}
      else
        echo "$output"
        exit 0
      fi
    EOT
    interpreter = ["bash", "-c"]
  }

  triggers = {
    storage_account_id = var.deployer.deployer_diagnostics_account_arm_id != "" ? var.deployer.deployer_diagnostics_account_arm_id : "new-storage"
    principal_id = var.deployer.user_assigned_identity_id != "" ? var.deployer.user_assigned_identity_id : "new-identity"
  }
}

resource "null_resource" "deployer_keyvault_msi_fallback" {
  count = var.assign_subscription_permissions && !var.key_vault.exists ? 1 : 0

  provisioner "local-exec" {
    command = <<EOT
      if [ -n "${var.deployer.user_assigned_identity_id}" ]; then
        PRINCIPAL_ID=$(az identity show --ids "${var.deployer.user_assigned_identity_id}" --query principalId -o tsv)
      elif [ "${length(azurerm_user_assigned_identity.deployer)}" -gt "0" ]; then
        PRINCIPAL_ID="${azurerm_user_assigned_identity.deployer[0].principal_id}"
      else
        echo "No user-assigned identity found. Skipping role assignment."
        exit 0
      fi

      if [ "${length(azurerm_key_vault.kv_user)}" -gt "0" ]; then
        KEY_VAULT_ID="${azurerm_key_vault.kv_user[0].id}"
      else
        echo "No Key Vault found. Skipping role assignment."
        exit 0
      fi

      output=$(az role assignment create \
        --assignee "$PRINCIPAL_ID" \
        --role "Key Vault Administrator" \
        --scope "$KEY_VAULT_ID" 2>&1) || status=$?

      if echo "$output" | grep -qiE "RoleAssignmentExists|already exists|The role assignment already exists"; then
        echo "Role assignment already exists. Skipping."
        exit 0
      elif echo "$output" | grep -qiE "403|Forbidden"; then
        echo "ERROR: Permission denied (403) - check service principal permissions"
        echo "$output"
        exit 1
      elif [ $${status:-0} -ne 0 ]; then
        echo "ERROR: Failed with status $${status:-0}."
        echo "$output"
        exit $${status:-1}
      else
        echo "$output"
        exit 0
      fi
    EOT
    interpreter = ["bash", "-c"]
  }

  triggers = {
    key_vault_exists = !var.key_vault.exists
    principal_id = var.deployer.user_assigned_identity_id != "" ? var.deployer.user_assigned_identity_id : "new-identity"
  }
}

resource "null_resource" "resource_group_contributor_msi_fallback" {
  count = var.assign_subscription_permissions ? 1 : 0

  provisioner "local-exec" {
    command = <<EOT
      if [ -n "${var.deployer.user_assigned_identity_id}" ]; then
        PRINCIPAL_ID=$(az identity show --ids "${var.deployer.user_assigned_identity_id}" --query principalId -o tsv)
      elif [ "${length(azurerm_user_assigned_identity.deployer)}" -gt "0" ]; then
        PRINCIPAL_ID="${azurerm_user_assigned_identity.deployer[0].principal_id}"
      else
        echo "No user-assigned identity found. Skipping role assignment."
        exit 0
      fi

      if [ "${var.infrastructure.resource_group.exists}" = "true" ]; then
        SCOPE="${var.infrastructure.resource_group.id}"
      elif [ "${length(azurerm_resource_group.deployer)}" -gt "0" ]; then
        SCOPE="${azurerm_resource_group.deployer[0].id}"
      else
        echo "No resource group found. Skipping role assignment."
        exit 0
      fi

      output=$(az role assignment create \
        --assignee "$PRINCIPAL_ID" \
        --role "Contributor" \
        --scope "$SCOPE" 2>&1) || status=$?

      if echo "$output" | grep -qiE "RoleAssignmentExists|already exists|The role assignment already exists"; then
        echo "Role assignment already exists. Skipping."
        exit 0
      elif echo "$output" | grep -qiE "403|Forbidden"; then
        echo "ERROR: Permission denied (403) - check service principal permissions"
        echo "$output"
        exit 1
      elif [ $${status:-0} -ne 0 ]; then
        echo "ERROR: Failed with status $${status:-0}."
        echo "$output"
        exit $${status:-1}
      else
        echo "$output"
        exit 0
      fi
    EOT
    interpreter = ["bash", "-c"]
  }

  triggers = {
    resource_group_id = var.infrastructure.resource_group.exists ? var.infrastructure.resource_group.id : "new-rg"
    principal_id = var.deployer.user_assigned_identity_id != "" ? var.deployer.user_assigned_identity_id : "new-identity"
  }
}

resource "null_resource" "keyvault_secrets_user_msi_fallback" {
  count = var.assign_subscription_permissions && !var.key_vault.exists ? 1 : 0

  provisioner "local-exec" {
    command = <<EOT
      if [ -n "${var.deployer.user_assigned_identity_id}" ]; then
        PRINCIPAL_ID=$(az identity show --ids "${var.deployer.user_assigned_identity_id}" --query principalId -o tsv)
      elif [ "${length(azurerm_user_assigned_identity.deployer)}" -gt "0" ]; then
        PRINCIPAL_ID="${azurerm_user_assigned_identity.deployer[0].principal_id}"
      else
        echo "No user-assigned identity found. Skipping role assignment."
        exit 0
      fi

      if [ "${length(azurerm_key_vault.kv_user)}" -gt "0" ]; then
        KEY_VAULT_ID="${azurerm_key_vault.kv_user[0].id}"
      else
        echo "No Key Vault found. Skipping role assignment."
        exit 0
      fi

      output=$(az role assignment create \
        --assignee "$PRINCIPAL_ID" \
        --role "Key Vault Secrets User" \
        --scope "$KEY_VAULT_ID" 2>&1) || status=$?

      if echo "$output" | grep -qiE "RoleAssignmentExists|already exists|The role assignment already exists"; then
        echo "Role assignment already exists. Skipping."
        exit 0
      elif echo "$output" | grep -qiE "403|Forbidden"; then
        echo "ERROR: Permission denied (403) - check service principal permissions"
        echo "$output"
        exit 1
      elif [ $${status:-0} -ne 0 ]; then
        echo "ERROR: Failed with status $${status:-0}."
        echo "$output"
        exit $${status:-1}
      else
        echo "$output"
        exit 0
      fi
    EOT
    interpreter = ["bash", "-c"]
  }

  triggers = {
    key_vault_exists = !var.key_vault.exists
    principal_id = var.deployer.user_assigned_identity_id != "" ? var.deployer.user_assigned_identity_id : "new-identity"
  }
}
