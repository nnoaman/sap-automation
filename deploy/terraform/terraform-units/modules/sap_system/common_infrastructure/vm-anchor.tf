# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.


# Create Anchor VM
resource "azurerm_network_interface" "anchor" {
  provider                             = azurerm.main
  count                                = local.deploy_anchor ? length(local.zones) : 0
  name                                 = format("%s%s%s%s%s",
                                           var.naming.resource_prefixes.nic,
                                           local.prefix,
                                           var.naming.separator,
                                           local.anchor_virtualmachine_names[count.index],
                                           local.resource_suffixes.nic
                                         )
  resource_group_name                  = local.resource_group_exists ? data.azurerm_resource_group.resource_group[0].name : azurerm_resource_group.resource_group[0].name
  location                             = local.resource_group_exists ? data.azurerm_resource_group.resource_group[0].location : azurerm_resource_group.resource_group[0].location
  accelerated_networking_enabled        = var.infrastructure.anchor_vms.accelerated_networking

  ip_configuration {
                     name      = "IPConfig1"
                     subnet_id = (var.infrastructure.virtual_networks.sap.subnet_db.exists || var.infrastructure.virtual_networks.sap.subnet_db.exists_in_workload ) ? data.azurerm_subnet.db[0].id : azurerm_subnet.db[0].id
                     private_ip_address = try(var.infrastructure.anchor_vms.use_DHCP, false) ? (
                       null) : (
                       try(var.infrastructure.anchor_vms.nic_ips[count.index],
                          cidrhost((var.infrastructure.virtual_networks.sap.subnet_db.exists || var.infrastructure.virtual_networks.sap.subnet_db.exists_in_workload ) ?
                            data.azurerm_subnet.db[0].address_prefixes[0] :
                            azurerm_subnet.db[0].address_prefixes[0], (count.index + 5)))
                     )
                     private_ip_address_allocation = try(var.infrastructure.anchor_vms.use_DHCP, false) ? "Dynamic" : "Static"
                   }
}

# Create the Linux Application VM(s)
resource "azurerm_linux_virtual_machine" "anchor" {
  provider                             = azurerm.main
  count                                = local.deploy_anchor && (local.anchor_ostype == "LINUX") ? length(local.zones) : 0
  name                                 = format("%s%s%s%s%s",
                                           var.naming.resource_prefixes.vm,
                                           local.prefix,
                                           var.naming.separator,
                                           local.anchor_virtualmachine_names[count.index],
                                           local.resource_suffixes.vm
                                         )
  computer_name                        = local.anchor_computer_names[count.index]
  resource_group_name                  = local.resource_group_exists ? data.azurerm_resource_group.resource_group[0].name : azurerm_resource_group.resource_group[0].name
  location                             = local.resource_group_exists ? data.azurerm_resource_group.resource_group[0].location : azurerm_resource_group.resource_group[0].location
  proximity_placement_group_id         = local.ppg_exists ? data.azurerm_proximity_placement_group.ppg[count.index].id : azurerm_proximity_placement_group.ppg[count.index].id

  patch_mode                                             = var.infrastructure.patch_mode

  patch_assessment_mode                                  = var.infrastructure.patch_assessment_mode
  bypass_platform_safety_checks_on_user_schedule_enabled = var.infrastructure.patch_mode != "AutomaticByPlatform" ? false : true

  zone                                 = local.zones[count.index]

  network_interface_ids                = [
                                          azurerm_network_interface.anchor[count.index].id
                                         ]
  size                                 = try(var.infrastructure.anchor_vms.sku, "")

  admin_username                       = local.sid_auth_username
  admin_password                       = local.enable_anchor_auth_key ? null : local.sid_auth_password
  disable_password_authentication      = !local.enable_anchor_auth_password

  custom_data                          = var.deployment == "new" ? local.cloudinit_growpart_config : null
  source_image_id                      = local.anchor_custom_image ? local.anchor_os.source_image_id : null
  license_type                         = length(var.license_type) > 0 ? var.license_type : null
  # ToDo Add back later
# patch_mode                           = var.infrastructure.patch_mode

  encryption_at_host_enabled           = var.infrastructure.encryption_at_host_enabled

  dynamic "admin_ssh_key" {
    for_each                           = range(var.deployment == "new" ? 1 : (local.enable_anchor_auth_password ? 0 : 1))
      content {
        username                       = local.sid_auth_username
        public_key                     = local.sid_public_key
      }
    }



  os_disk {
    name                               = format("%s%s%s%s%s",
                                           var.naming.resource_prefixes.osdisk,
                                           local.prefix,
                                           var.naming.separator,
                                           local.anchor_virtualmachine_names[count.index],
                                           local.resource_suffixes.osdisk
                                         )
    caching                            = "ReadWrite"
    storage_account_type               = "Premium_LRS"
    disk_encryption_set_id             = try(var.options.disk_encryption_set_id, null)
  }



  dynamic "source_image_reference" {
    for_each = range(local.anchor_custom_image ? 0 : 1)
    content {
      publisher = local.anchor_os.publisher
      offer     = local.anchor_os.offer
      sku       = local.anchor_os.sku
      version   = local.anchor_os.version
    }
  }

  dynamic "plan" {
    for_each = range(local.anchor_custom_image ? 1 : 0)
    content {
      name      = local.anchor_os.offer
      publisher = local.anchor_os.publisher
      product   = local.anchor_os.sku
    }
  }

  boot_diagnostics {
    storage_account_uri = data.azurerm_storage_account.storage_bootdiag.primary_blob_endpoint
  }

  additional_capabilities {
    ultra_ssd_enabled = local.enable_anchor_ultra[count.index]
  }

  lifecycle {
    ignore_changes = [
      source_image_id
    ]
  }

}

# Create the Windows Application VM(s)
resource "azurerm_windows_virtual_machine" "anchor" {
  provider                             = azurerm.main
  count                                = local.deploy_anchor && (local.anchor_ostype == "WINDOWS") ? length(local.zones) : 0
  name                                 = format("%s%s%s%s%s",
                                           var.naming.resource_prefixes.vm,
                                           local.prefix,
                                           var.naming.separator,
                                           local.anchor_virtualmachine_names[count.index],
                                           local.resource_suffixes.vm
                                         )
  computer_name                        = local.anchor_computer_names[count.index]
  resource_group_name                  = local.resource_group_exists ? data.azurerm_resource_group.resource_group[0].name : azurerm_resource_group.resource_group[0].name
  location                             = local.resource_group_exists ? data.azurerm_resource_group.resource_group[0].location : azurerm_resource_group.resource_group[0].location
  proximity_placement_group_id         = local.ppg_exists ? data.azurerm_proximity_placement_group.ppg[count.index].id : azurerm_proximity_placement_group.ppg[count.index].id
  zone                                 = local.zones[count.index]

  // ImageDefault = Manual on Windows
  // https://learn.microsoft.com/en-us/azure/virtual-machines/automatic-vm-guest-patching#patch-orchestration-modes
  patch_mode                                             = var.infrastructure.patch_mode == "ImageDefault" ? "Manual" : var.infrastructure.patch_mode
  patch_assessment_mode                                  = var.infrastructure.patch_assessment_mode
  bypass_platform_safety_checks_on_user_schedule_enabled = var.infrastructure.patch_mode != "AutomaticByPlatform" ? false : true

  network_interface_ids                = [
                                           azurerm_network_interface.anchor[count.index].id
                                         ]

  size                                 = try(var.infrastructure.anchor_vms.sku, "")
  admin_username                       = local.sid_auth_username
  admin_password                       = local.sid_auth_password

  encryption_at_host_enabled           = var.infrastructure.encryption_at_host_enabled

  os_disk {
    name                               = format("%s%s%s%s%s",
                                           var.naming.resource_prefixes.osdisk,
                                           local.prefix,
                                           var.naming.separator,
                                           local.anchor_virtualmachine_names[count.index],
                                           local.resource_suffixes.osdisk
                                         )
    caching                            = "ReadWrite"
    storage_account_type               = "Standard_LRS"
  }

  source_image_id                      = local.anchor_custom_image ? local.anchor_os.source_image_id : null

  dynamic "source_image_reference" {
    for_each = range(local.anchor_custom_image ? 0 : 1)
    content {
      publisher                        = local.anchor_os.publisher
      offer                            = local.anchor_os.offer
      sku                              = local.anchor_os.sku
      version                          = local.anchor_os.version
    }
  }

  boot_diagnostics {
    storage_account_uri = data.azurerm_storage_account.storage_bootdiag.primary_blob_endpoint
  }

  additional_capabilities {
    ultra_ssd_enabled = local.enable_anchor_ultra[count.index]
  }

  lifecycle {
    ignore_changes = [
      source_image_id
    ]
  }

  license_type                         = length(var.license_type) > 0 ? var.license_type : null
}
