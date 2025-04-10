# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

/*
  Description:
  Setup sap library
*/
module "sap_library" {
  source                            = "../../terraform-units/modules/sap_library"
  providers                         = {
                                       azurerm.main                     = azurerm.main
                                       azurerm.deployer                 = azurerm.deployer
                                       azurerm.dnsmanagement            = azurerm.dnsmanagement
                                       azurerm.privatelinkdnsmanagement = azurerm.privatelinkdnsmanagement
                                     }

  Agent_IP                             = var.add_Agent_IP ? var.Agent_IP : ""
  bootstrap                            = true
  deployer                             = local.deployer
  deployer_tfstate                     = var.use_deployer ? data.terraform_remote_state.deployer[0].outputs : []
  infrastructure                       = local.infrastructure
  key_vault                            = local.key_vault
  naming                               = length(var.name_override_file) > 0 ? local.custom_names : module.sap_namegenerator.naming
  place_delete_lock_on_resources       = var.place_delete_lock_on_resources
  short_named_endpoints_nics           = var.short_named_endpoints_nics
  storage_account_sapbits              = local.storage_account_sapbits
  storage_account_tfstate              = local.storage_account_tfstate
  use_private_endpoint                 = var.use_private_endpoint
  dns_settings                         = local.dns_settings
}

module "sap_namegenerator" {
  source                            = "../../terraform-units/modules/sap_namegenerator"
  codename                          = try(local.infrastructure.codename, "")
  deployer_environment              = try(split("-", var.control_plane_name)[0], var.environment)
  deployer_location                 = var.location
  environment                       = var.environment
  location                          = var.location
  management_vnet_name              = ""
  random_id                         = coalesce(var.custom_random_id, module.sap_library.random_id)
}
