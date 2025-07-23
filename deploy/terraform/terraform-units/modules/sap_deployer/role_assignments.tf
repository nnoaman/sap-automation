
#######################################4#######################################8
#                                                                              #
#                                Role Assignments                              #
#                                                                              #
#######################################4#######################################8
resource "null_resource" "subscription_contributor_msi_fallback" {
  count = var.assign_subscription_permissions ? 1 : 0

  provisioner "local-exec" {
    command = <<EOT
      # Determine the correct principal ID
      if [ -z "${var.deployer.user_assigned_identity_id}" ]; then
        PRINCIPAL_ID="${azurerm_user_assigned_identity.deployer[0].principal_id}"
      else
        PRINCIPAL_ID="${data.azurerm_user_assigned_identity.deployer[0].principal_id}"
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
      else
        echo "$output"
        exit 1
      fi
    EOT
    interpreter = ["bash", "-c"]
  }

  triggers = {
    always_run = timestamp()
  }

  depends_on = [
    azurerm_user_assigned_identity.deployer
  ]
}

resource "null_resource" "deployer_msi_fallback" {
  count = var.assign_subscription_permissions ? 1 : 0

  provisioner "local-exec" {
    command = <<EOT
      # Determine the correct principal ID
      if [ -z "${var.deployer.user_assigned_identity_id}" ]; then
        PRINCIPAL_ID="${azurerm_user_assigned_identity.deployer[0].principal_id}"
      else
        PRINCIPAL_ID="${data.azurerm_user_assigned_identity.deployer[0].principal_id}"
      fi

      # Determine the correct scope
      if [ -n "${var.deployer.deployer_diagnostics_account_arm_id}" ]; then
        SCOPE="${var.deployer.deployer_diagnostics_account_arm_id}"
      else
        SCOPE="${azurerm_storage_account.deployer[0].id}"
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
      else
        echo "$output"
        exit 1
      fi
    EOT
    interpreter = ["bash", "-c"]
  }

  triggers = {
    always_run = timestamp()
  }

  depends_on = [
    azurerm_user_assigned_identity.deployer,
    azurerm_storage_account.deployer
  ]
}

resource "null_resource" "deployer_keyvault_msi_fallback" {
  count = var.assign_subscription_permissions && !var.key_vault.exists ? 1 : 0

  provisioner "local-exec" {
    command = <<EOT
      # Determine the correct principal ID
      if [ -z "${var.deployer.user_assigned_identity_id}" ]; then
        PRINCIPAL_ID="${azurerm_user_assigned_identity.deployer[0].principal_id}"
      else
        PRINCIPAL_ID="${data.azurerm_user_assigned_identity.deployer[0].principal_id}"
      fi

      output=$(az role assignment create \
        --assignee "$PRINCIPAL_ID" \
        --role "Key Vault Administrator" \
        --scope "${azurerm_key_vault.kv_user[0].id}" 2>&1) || status=$?

      if echo "$output" | grep -qiE "RoleAssignmentExists|already exists|The role assignment already exists"; then
        echo "Role assignment already exists. Skipping."
        exit 0
      elif echo "$output" | grep -qiE "403|Forbidden"; then
        echo "ERROR: Permission denied (403) - check service principal permissions"
        echo "$output"
        exit 1
      else
        echo "$output"
        exit 1
      fi
    EOT
    interpreter = ["bash", "-c"]
  }

  triggers = {
    always_run = timestamp()
  }

  depends_on = [
    azurerm_user_assigned_identity.deployer,
    azurerm_key_vault.kv_user
  ]
}

resource "null_resource" "resource_group_contributor_msi_fallback" {
  count = var.assign_subscription_permissions ? 1 : 0

  provisioner "local-exec" {
    command = <<EOT
      # Determine the correct principal ID
      if [ -z "${var.deployer.user_assigned_identity_id}" ]; then
        PRINCIPAL_ID="${azurerm_user_assigned_identity.deployer[0].principal_id}"
      else
        PRINCIPAL_ID="${data.azurerm_user_assigned_identity.deployer[0].principal_id}"
      fi

      output=$(az role assignment create \
        --assignee "$PRINCIPAL_ID" \
        --role "Contributor" \
        --scope "${azurerm_resource_group.deployer.id}" 2>&1) || status=$?

      if echo "$output" | grep -qiE "RoleAssignmentExists|already exists|The role assignment already exists"; then
        echo "Role assignment already exists. Skipping."
        exit 0
      elif echo "$output" | grep -qiE "403|Forbidden"; then
        echo "ERROR: Permission denied (403) - check service principal permissions"
        echo "$output"
        exit 1
      else
        echo "$output"
        exit 1
      fi
    EOT
    interpreter = ["bash", "-c"]
  }

  triggers = {
    always_run = timestamp()
  }

  depends_on = [
    azurerm_user_assigned_identity.deployer,
    azurerm_resource_group.deployer
  ]
}

resource "null_resource" "keyvault_secrets_user_msi_fallback" {
  count = var.assign_subscription_permissions && !var.key_vault.exists ? 1 : 0

  provisioner "local-exec" {
    command = <<EOT
      # Determine the correct principal ID
      if [ -z "${var.deployer.user_assigned_identity_id}" ]; then
        PRINCIPAL_ID="${azurerm_user_assigned_identity.deployer[0].principal_id}"
      else
        PRINCIPAL_ID="${data.azurerm_user_assigned_identity.deployer[0].principal_id}"
      fi

      output=$(az role assignment create \
        --assignee "$PRINCIPAL_ID" \
        --role "Key Vault Secrets User" \
        --scope "${azurerm_key_vault.kv_user[0].id}" 2>&1) || status=$?

      if echo "$output" | grep -qiE "RoleAssignmentExists|already exists|The role assignment already exists"; then
        echo "Role assignment already exists. Skipping."
        exit 0
      elif echo "$output" | grep -qiE "403|Forbidden"; then
        echo "ERROR: Permission denied (403) - check service principal permissions"
        echo "$output"
        exit 1
      else
        echo "$output"
        exit 1
      fi
    EOT
    interpreter = ["bash", "-c"]
  }

  triggers = {
    always_run = timestamp()
  }

  depends_on = [
    azurerm_user_assigned_identity.deployer,
    azurerm_key_vault.kv_user
  ]
}
