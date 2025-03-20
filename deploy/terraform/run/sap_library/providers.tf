# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

/*
Description:

  Constraining provider versions
    =    (or no operator): exact version equality
    !=   version not equal
    >    greater than version number
    >=   greater than or equal to version number
    <    less than version number
    <=   less than or equal to version number
    ~>   pessimistic constraint operator, constraining both the oldest and newest version allowed.
           For example, ~> 0.9   is equivalent to >= 0.9,   < 1.0
                        ~> 0.8.4 is equivalent to >= 0.8.4, < 0.9
*/

data "azurerm_client_config" "current" {
                                         provider                   = azurerm.main
                                       }

provider "azurerm"                     {
                                         features {
                                                  }

                                         use_msi                    = true
                                         storage_use_azuread        = !var.shared_access_key_enabled

                                       }

provider "azurerm"                     {
                                         features {
                                                    resource_group {
                                                                     prevent_deletion_if_contains_resources = var.prevent_deletion_if_contains_resources
                                                                   }
                                                    storage        {
                                                                        data_plane_available = var.data_plane_available
                                                                   }

                                                  }
                                         subscription_id            = try(data.azurerm_key_vault_secret.subscription_id[0].value, null)
                                         client_id                  = try(data.azurerm_key_vault_secret.client_id[0].value, null)
                                         client_secret              = try(ephemeral.azurerm_key_vault_secret.client_secret[0].value, null)
                                         tenant_id                  = try(ephemeral.azurerm_key_vault_secret.tenant_id[0].value, null)
                                         partner_id                 = "140c3bc9-c937-4139-874f-88288bab08bb"
                                         storage_use_azuread        = !var.shared_access_key_enabled
                                         use_msi                    = var.use_spn ? false : true

                                         alias = "main"
                                       }

provider "azurerm"                     {
                                         features {
                                                  }
                                         alias                      = "deployer"
                                         storage_use_azuread        = !var.shared_access_key_enabled
                                         use_msi                    = true
                                         subscription_id            = local.SAPLibrary_subscription_id
                                       }

provider "azurerm"                     {
                                         features {
                                                  }
                                         alias                      = "dnsmanagement"
                                         subscription_id            = try(coalesce(var.management_dns_subscription_id, data.azurerm_key_vault_secret.subscription_id[0].value), null)
                                         client_id                  = try(data.azurerm_key_vault_secret.client_id[0].value, null)
                                         client_secret              = try(ephemeral.azurerm_key_vault_secret.client_secret[0].value, null)
                                         tenant_id                  = try(ephemeral.azurerm_key_vault_secret.tenant_id[0].value, null)
                                         storage_use_azuread        = !var.shared_access_key_enabled
                                         use_msi                    = var.use_spn ? false : true
                                       }

provider "azurerm"                     {
                                         features {}
                                         subscription_id            = try(coalesce(var.management_dns_subscription_id, data.azurerm_key_vault_secret.subscription_id[0].value), null)
                                         client_id                  = try(data.azurerm_key_vault_secret.client_id[0].value, null)
                                         client_secret              = try(ephemeral.azurerm_key_vault_secret.client_secret[0].value, null)
                                         tenant_id                  = try(ephemeral.azurerm_key_vault_secret.tenant_id[0].value, null)
                                         alias                      = "privatelinkdnsmanagement"
                                         storage_use_azuread        = !var.shared_access_key_enabled
                                         use_msi                    = var.use_spn ? false : true
                                       }


provider "azuread"                     {
                                         client_id                  = try(data.azurerm_key_vault_secret.client_id[0].value, null)
                                         client_secret              = try(ephemeral.azurerm_key_vault_secret.client_secret[0].value, null)
                                         tenant_id                  = try(ephemeral.azurerm_key_vault_secret.tenant_id[0].value, null)
                                         use_msi                    = var.use_spn ? false : true
                                       }

terraform                              {
                                         required_version = ">= 1.0"
                                         required_providers {
                                                              external = {
                                                                           source = "hashicorp/external"
                                                                         }
                                                              local    = {
                                                                           source = "hashicorp/local"
                                                                         }
                                                              random   = {
                                                                           source = "hashicorp/random"
                                                                         }
                                                              null =     {
                                                                           source = "hashicorp/null"
                                                                         }
                                                              azuread =  {
                                                                           source  = "hashicorp/azuread"
                                                                           version = "3.0.2"
                                                                         }
                                                              azurerm =  {
                                                                           source  = "hashicorp/azurerm"
                                                                           version = "4.22.0"
                                                                         }
                                                            }
                                       }

