locals {
  role_assignment_creation_error_prefix = "You can ignore the following warning if the role assignment was already applied by another process"
}

resource "null_resource" "webapp_blob_role_assignment" {
  count = var.infrastructure.assign_permissions && var.deployer.use ? (
    length(try(var.deployer_tfstate.deployer_msi_id, "")) > 0 ? 1 : 0) : 0

  provisioner "local-exec" {
    command = <<EOT
      output=$(az role assignment create \
        --assignee ${var.deployer_tfstate.deployer_msi_id} \
        --role "Storage Blob Data Contributor" \
        --scope ${azurerm_storage_account.storage_tfstate[0].id} 2>&1) || status=$?

      if echo "$output" | grep -q "RoleAssignmentExists"; then
        echo "Role assignment already exists. Skipping."
        exit 0
      elif echo "$output" | grep -q "403\|Forbidden"; then
        echo "ERROR: Permission denied (403) - check service principal permissions"
        echo "$output"
        exit 1
      else
        echo "$output"
        exit $status
      fi
    EOT
    interpreter = ["bash", "-c"]
  }

  triggers = {
    always_run = timestamp()
  }
}

resource "null_resource" "webapp_table_role_assignment" {
  count = var.infrastructure.assign_permissions && var.deployer.use ? (
    length(try(var.deployer_tfstate.deployer_msi_id, "")) > 0 ? 1 : 0) : 0

  provisioner "local-exec" {
    command = <<EOT
      output=$(az role assignment create \
        --assignee ${var.deployer_tfstate.deployer_msi_id} \
        --role "Storage Table Data Contributor" \
        --scope ${azurerm_storage_account.storage_tfstate[0].id} 2>&1) || status=$?

      if echo "$output" | grep -q "RoleAssignmentExists"; then
        echo "Role assignment already exists. Skipping."
        exit 0
      elif echo "$output" | grep -q "403\|Forbidden"; then
        echo "ERROR: Permission denied (403) - check service principal permissions"
        echo "$output"
        exit 1
      else
        echo "$output"
        exit $status
      fi
    EOT
    interpreter = ["bash", "-c"]
  }

  triggers = {
    always_run = timestamp()
  }
}

resource "null_resource" "blob_msi_role_assignment" {
  count = var.infrastructure.assign_permissions && var.deployer.use ? (
    length(try(var.deployer_tfstate.deployer_msi_id, "")) > 0 ? 1 : 0) : 0

  provisioner "local-exec" {
    command = <<EOT
      output=$(az role assignment create \
        --assignee ${var.deployer_tfstate.deployer_msi_id} \
        --role "Storage Blob Data Owner" \
        --scope ${azurerm_storage_account.storage_tfstate[0].id} 2>&1) || status=$?

      if echo "$output" | grep -q "RoleAssignmentExists"; then
        echo "Role assignment already exists. Skipping."
        exit 0
      elif echo "$output" | grep -q "403\|Forbidden"; then
        echo "ERROR: Permission denied (403) - check service principal permissions"
        echo "$output"
        exit 1
      else
        echo "$output"
        exit $status
      fi
    EOT
    interpreter = ["bash", "-c"]
  }

  triggers = {
    always_run = timestamp()
  }
}

resource "null_resource" "dns_msi_role_assignment" {
  count = var.infrastructure.assign_permissions && var.deployer.use ? (
    length(try(var.deployer_tfstate.deployer_msi_id, "")) > 0 ? 1 : 0) : 0

  provisioner "local-exec" {
    command = <<EOT
      output=$(az role assignment create \
        --assignee ${var.deployer_tfstate.deployer_msi_id} \
        --role "Private DNS Zone Contributor" \
        --scope ${var.infrastructure.resource_group.exists ? data.azurerm_resource_group.library[0].id : azurerm_resource_group.library[0].id} 2>&1) || status=$?

      if echo "$output" | grep -q "RoleAssignmentExists"; then
        echo "Role assignment already exists. Skipping."
        exit 0
      elif echo "$output" | grep -q "403\|Forbidden"; then
        echo "ERROR: Permission denied (403) - check service principal permissions"
        echo "$output"
        exit 1
      else
        echo "$output"
        exit $status
      fi
    EOT
    interpreter = ["bash", "-c"]
  }

  triggers = {
    always_run = timestamp()
  }
}

resource "null_resource" "dns_spn_role_assignment" {
  count = var.infrastructure.assign_permissions && length(var.infrastructure.spn_id) > 0 ? 1 : 0

  provisioner "local-exec" {
    command = <<EOT
      output=$(az role assignment create \
        --assignee ${var.infrastructure.spn_id} \
        --role "Private DNS Zone Contributor" \
        --scope ${var.infrastructure.resource_group.exists ? data.azurerm_resource_group.library[0].id : azurerm_resource_group.library[0].id} 2>&1) || status=$?

      if echo "$output" | grep -q "RoleAssignmentExists"; then
        echo "Role assignment already exists. Skipping."
        exit 0
      elif echo "$output" | grep -q "403\|Forbidden"; then
        echo "ERROR: Permission denied (403) - check service principal permissions"
        echo "$output"
        exit 1
      else
        echo "$output"
        exit $status
      fi
    EOT
    interpreter = ["bash", "-c"]
  }

  triggers = {
    always_run = timestamp()
  }
}

resource "null_resource" "resource_group_contributor_msi_role_assignment" {
  count = var.infrastructure.assign_permissions && var.deployer.use ? (
    length(try(var.deployer_tfstate.deployer_msi_id, "")) > 0 ? 1 : 0) : 0

  provisioner "local-exec" {
    command = <<EOT
      output=$(az role assignment create \
        --assignee ${var.deployer_tfstate.deployer_msi_id} \
        --role "Contributor" \
        --scope ${var.infrastructure.resource_group.exists ? data.azurerm_resource_group.library[0].id : azurerm_resource_group.library[0].id} 2>&1) || status=$?

      if echo "$output" | grep -q "RoleAssignmentExists"; then
        echo "Role assignment already exists. Skipping."
        exit 0
      elif echo "$output" | grep -q "403\|Forbidden"; then
        echo "ERROR: Permission denied (403) - check service principal permissions"
        echo "$output"
        exit 1
      else
        echo "$output"
        exit $status
      fi
    EOT
    interpreter = ["bash", "-c"]
  }

  triggers = {
    always_run = timestamp()
  }
}

resource "null_resource" "resource_group_contributor_spn_role_assignment" {
  count = var.infrastructure.assign_permissions && length(var.infrastructure.spn_id) > 0 ? 1 : 0

  provisioner "local-exec" {
    command = <<EOT
      output=$(az role assignment create \
        --assignee ${var.infrastructure.spn_id} \
        --role "Contributor" \
        --scope ${var.infrastructure.resource_group.exists ? data.azurerm_resource_group.library[0].id : azurerm_resource_group.library[0].id} 2>&1) || status=$?

      if echo "$output" | grep -q "RoleAssignmentExists"; then
        echo "Role assignment already exists. Skipping."
        exit 0
      elif echo "$output" | grep -q "403\|Forbidden"; then
        echo "ERROR: Permission denied (403) - check service principal permissions"
        echo "$output"
        exit 1
      else
        echo "$output"
        exit $status
      fi
    EOT
    interpreter = ["bash", "-c"]
  }

  triggers = {
    always_run = timestamp()
  }
}

resource "null_resource" "storage_sapbits_role_assignment" {
  count = var.storage_account_sapbits.exists ? 0 : var.infrastructure.assign_permissions ? 1 : 0

  provisioner "local-exec" {
    command = <<EOT
      output=$(az role assignment create \
        --assignee ${data.azuread_client_config.current.object_id} \
        --role "Storage Blob Data Contributor" \
        --scope ${azurerm_storage_account.storage_sapbits[0].id} 2>&1) || status=$?

      if echo "$output" | grep -q "RoleAssignmentExists"; then
        echo "Role assignment already exists. Skipping."
        exit 0
      elif echo "$output" | grep -q "403\|Forbidden"; then
        echo "ERROR: Permission denied (403) - check service principal permissions"
        echo "$output"
        exit 1
      else
        echo "$output"
        exit $status
      fi
    EOT
    interpreter = ["bash", "-c"]
  }

  triggers = {
    always_run = timestamp()
  }
}
